-- ============================================================================
-- KLAY K — ECONOMIA COMPLETA (migration AUTOSSUFICIENTE)
-- Sistema multi-moeda por usuário com trilha (ledger) e regras 100% no backend.
-- Esta migration NÃO depende de nenhuma migration anterior:
--   * cria currencies, user_wallets (6 moedas), credit_transactions (ledger);
--   * economy_adjust: função security definer que credita/debita com proteção
--     contra saldo negativo e sempre grava o ledger;
--   * auditoria (write_audit) e permissões (has_perm) são usadas de forma
--     DINÂMICA — se não existirem, a economia funciona do mesmo jeito;
--   * RLS select-only no wallet/ledger: o cliente NUNCA escreve saldo;
--   * apenas funções security definer / service_role mudam saldo.
-- Tudo idempotente (if not exists / create or replace).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) currencies: catálogo/config das moedas (ids estáveis usados no código)
-- ---------------------------------------------------------------------------
create table if not exists public.currencies (
  id text primary key,
  name text not null,
  symbol text default '',
  emoji text default '',
  color text default '#8B5CF6',
  sort_order int not null default 0,
  active boolean not null default true,
  is_premium boolean not null default false,
  description text default '',
  created_at timestamptz not null default now()
);

insert into public.currencies (id, name, symbol, emoji, color, sort_order, is_premium, description) values
  ('credits',      'Moedas',        '',  '🪙', '#F59E0B', 1, false, 'Moeda-base do KLAY K (presentes, loja, missões).'),
  ('diamonds',     'Diamantes',     '💎', '💎', '#22D3EE', 2, false, 'Moeda premium comum (baús, eventos).'),
  ('crystals',     'Cristais',      '',  '🔮', '#8B5CF6', 3, false, 'Moeda mística (eventos, recompensas).'),
  ('rubies',       'Rubis',         '',  '🔴', '#F43F5E', 4, false, 'Moeda rara (baús raros, conquistas).'),
  ('emeralds',     'Esmeraldas',    '',  '💚', '#34D399', 5, false, 'Moeda rara (eventos sazonais).'),
  ('crystal_rare', 'Cristal Raro',  '',  '📿', '#D4AF37', 6, true,  'Moeda ultra-rara (exclusivos).')
on conflict (id) do update set
  name = excluded.name, emoji = excluded.emoji, color = excluded.color,
  sort_order = excluded.sort_order, is_premium = excluded.is_premium,
  description = excluded.description;

alter table public.currencies enable row level security;
drop policy if exists "currencies_select" on public.currencies;
create policy "currencies_select" on public.currencies for select using (true);

-- ---------------------------------------------------------------------------
-- 2) user_wallets: saldo fonte de verdade. 6 moedas, CHECK >= 0.
-- ---------------------------------------------------------------------------
create table if not exists public.user_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  credits bigint not null default 0 check (credits >= 0),
  updated_at timestamptz not null default now()
);

alter table public.user_wallets
  add column if not exists diamonds bigint not null default 0 check (diamonds >= 0);
alter table public.user_wallets
  add column if not exists crystals bigint not null default 0 check (crystals >= 0);
alter table public.user_wallets
  add column if not exists rubies bigint not null default 0 check (rubies >= 0);
alter table public.user_wallets
  add column if not exists emeralds bigint not null default 0 check (emeralds >= 0);
alter table public.user_wallets
  add column if not exists crystal_rare bigint not null default 0 check (crystal_rare >= 0);

-- ---------------------------------------------------------------------------
-- 3) credit_transactions: livro-caixa unificado (todas as moedas).
-- ---------------------------------------------------------------------------
create table if not exists public.credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta bigint not null,
  balance_after bigint not null,
  kind text not null default 'spend' check (kind in ('grant','spend','refund','admin')),
  ref_type text,
  ref_id text,
  note text default '',
  created_at timestamptz not null default now()
);

alter table public.credit_transactions
  add column if not exists currency text not null default 'credits';

-- Amplia o CHECK de kind mantendo os originais e os kinds de recompensa.
alter table public.credit_transactions drop constraint if exists credit_transactions_kind_check;
alter table public.credit_transactions add constraint credit_transactions_kind_check
  check (kind in ('grant','spend','refund','admin','reward','chest','mission'));

create index if not exists credit_tx_user_idx
  on public.credit_transactions (user_id, created_at desc);
create index if not exists credit_tx_currency_idx
  on public.credit_transactions (user_id, currency, created_at desc);

-- RLS: SELECT somente do próprio usuário. SEM políticas de escrita para o
-- cliente — saldo/ledger só mudam dentro de funções security definer abaixo.
alter table public.user_wallets enable row level security;
drop policy if exists "user_wallets_select" on public.user_wallets;
create policy "user_wallets_select" on public.user_wallets
  for select using (user_id = auth.uid());

alter table public.credit_transactions enable row level security;
drop policy if exists "credit_transactions_select" on public.credit_transactions;
create policy "credit_transactions_select" on public.credit_transactions
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4) economy_has_admin: gate administrativo de economia.
--    Usa has_perm('economy') se staff_roles estiver aplicado; senão cai para
--    profiles.is_admin (flag de compatibilidade existente desde a init/gift).
--    Garantimos a coluna is_admin para nunca depender de outra migration.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

create or replace function public.economy_has_admin()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_perm boolean;
begin
  if coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false) then
    return true;
  end if;
  -- Compat: se o framework de roles (has_perm) existe, respeita a cap 'economy'.
  if to_regprocedure('public.has_perm(text)') is not null then
    execute 'select public.has_perm($1)' into v_has_perm using 'economy';
  end if;
  return coalesce(v_has_perm, false);
end;
$$;

revoke all on function public.economy_has_admin() from public;
grant execute on function public.economy_has_admin() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) economy_adjust: operação atômica de crédito/débito por moeda.
--    - Delta > 0 → credita; Delta < 0 → debita (exige saldo; nunca negativo).
--    - Whitelist rígida de moedas; sempre grava o ledger com balance_after.
--    - Auditoria DINÂMICA via write_audit (se existir); sem dependência.
--    - EXECUTE apenas service_role / security definer (nunca o cliente).
--    Assinatura = (uuid, text, bigint, text, text, text, text, text) para
--    compatibilidade com baús/missões/jogos que a chamam internamente.
-- ---------------------------------------------------------------------------
create or replace function public.economy_adjust(
  p_user_id uuid,
  p_currency text,
  p_delta bigint,
  p_kind text default 'grant',
  p_ref_type text default '',
  p_ref_id text default '',
  p_note text default '',
  p_audit_action text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance bigint;
  v_act text;
begin
  insert into public.user_wallets (user_id) values (p_user_id)
    on conflict (user_id) do nothing;

  if p_delta = 0 then raise exception 'zero_delta'; end if;
  if p_kind not in ('grant','spend','refund','admin','reward','chest','mission') then
    raise exception 'bad_kind';
  end if;

  case p_currency
    when 'credits' then
      update public.user_wallets
         set credits = credits + p_delta, updated_at = now()
       where user_id = p_user_id and credits + p_delta >= 0
       returning credits into v_balance;
    when 'diamonds' then
      update public.user_wallets
         set diamonds = diamonds + p_delta, updated_at = now()
       where user_id = p_user_id and diamonds + p_delta >= 0
       returning diamonds into v_balance;
    when 'crystals' then
      update public.user_wallets
         set crystals = crystals + p_delta, updated_at = now()
       where user_id = p_user_id and crystals + p_delta >= 0
       returning crystals into v_balance;
    when 'rubies' then
      update public.user_wallets
         set rubies = rubies + p_delta, updated_at = now()
       where user_id = p_user_id and rubies + p_delta >= 0
       returning rubies into v_balance;
    when 'emeralds' then
      update public.user_wallets
         set emeralds = emeralds + p_delta, updated_at = now()
       where user_id = p_user_id and emeralds + p_delta >= 0
       returning emeralds into v_balance;
    when 'crystal_rare' then
      update public.user_wallets
         set crystal_rare = crystal_rare + p_delta, updated_at = now()
       where user_id = p_user_id and crystal_rare + p_delta >= 0
       returning crystal_rare into v_balance;
    else
      raise exception 'bad_currency';
  end case;

  if v_balance is null then
    raise exception 'insufficient_funds';
  end if;

  insert into public.credit_transactions
    (user_id, delta, balance_after, kind, ref_type, ref_id, note, currency)
  values
    (p_user_id, p_delta, v_balance, p_kind, p_ref_type, p_ref_id, p_note, p_currency);

  -- Auditoria opcional (dinâmica): funciona com ou sem o framework de roles.
  if p_audit_action is not null then
    v_act := p_audit_action;
    if to_regprocedure('public.write_audit(text,text,text,jsonb)') is not null then
      execute 'select public.write_audit($1,$2,$3,$4)'
        using v_act, 'wallet', p_user_id::text,
             jsonb_build_object('currency', p_currency, 'delta', p_delta,
                                'balance', v_balance, 'note', p_note);
    end if;
  end if;

  return jsonb_build_object('balance', v_balance, 'ok', true);
end;
$$;

revoke all on function public.economy_adjust(uuid, text, bigint, text, text, text, text, text) from public;
revoke execute on function public.economy_adjust(uuid, text, bigint, text, text, text, text, text) from anon, authenticated;
grant execute on function public.economy_adjust(uuid, text, bigint, text, text, text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 6) my_wallet: leitura consolidada (saldos). Sem escrita.
-- ---------------------------------------------------------------------------
create or replace function public.my_wallet()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  w record;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.user_wallets (user_id) values (u)
    on conflict (user_id) do nothing;
  select * into w from public.user_wallets where user_id = u;
  return jsonb_build_object(
    'credits', w.credits,
    'diamonds', w.diamonds,
    'crystals', w.crystals,
    'rubies', w.rubies,
    'emeralds', w.emeralds,
    'crystal_rare', w.crystal_rare
  );
end;
$$;

revoke all on function public.my_wallet() from public;
grant execute on function public.my_wallet() to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Admin de economia (gate economy_has_admin):
--    admin_grant_currency — conceder/ajustar saldo com auditoria.
--    admin_economy_stats — somatório por moeda para o painel.
-- ---------------------------------------------------------------------------
create or replace function public.admin_grant_currency(
  p_user_id uuid,
  p_currency text,
  p_amount bigint,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb;
begin
  if not public.economy_has_admin() then
    raise exception 'not_admin';
  end if;
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  r := public.economy_adjust(p_user_id, p_currency, p_amount, 'admin',
       'admin', '', p_note, 'economy.grant');
  return r;
end;
$$;

revoke all on function public.admin_grant_currency(uuid, text, bigint, text) from public;
grant execute on function public.admin_grant_currency(uuid, text, bigint, text) to authenticated;

create or replace function public.admin_economy_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb;
begin
  if not public.economy_has_admin() then
    raise exception 'not_admin';
  end if;
  select jsonb_build_object(
    'credits', coalesce(sum(w.credits), 0),
    'diamonds', coalesce(sum(w.diamonds), 0),
    'crystals', coalesce(sum(w.crystals), 0),
    'rubies', coalesce(sum(w.rubies), 0),
    'emeralds', coalesce(sum(w.emeralds), 0),
    'crystal_rare', coalesce(sum(w.crystal_rare), 0)
  ) into r from public.user_wallets w;
  return r;
end;
$$;

revoke all on function public.admin_economy_stats() from public;
grant execute on function public.admin_economy_stats() to authenticated;