-- ============================================================================
-- KLAY K — ECONOMIA VIRTUAL MULTI-MOEDA
-- Base: (1) currencys catalog; (2) wallet com 6 saldos; (3) ledger unificado.
-- A moeda-base "moedas" == credits existente (100% compatível com gift/send).
-- As outras: diamantes, cristais, rubis, esmeraldas e cristal raro.
-- Escrita de saldo SOMENTE via backend (Edge Function/service role) ou RPC
-- security definer com cap 'economy' (painel). O cliente jamais altera saldo.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- currencies: catálogo/config das moedas (id estável usado no código).
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
  ('crystal_rare', 'Cristal Raro',  '',  '📿', '#D4AF37', 6, true,  'Moeda ultra-rara (exclusivos A.R.H TECH).')
on conflict (id) do update set
  name = excluded.name, emoji = excluded.emoji, color = excluded.color,
  sort_order = excluded.sort_order, is_premium = excluded.is_premium,
  description = excluded.description;

alter table public.currencies enable row level security;
drop policy if exists "currencies_select" on public.currencies;
create policy "currencies_select" on public.currencies for select using (true);

-- ---------------------------------------------------------------------------
-- user_wallets: 6 saldos. credits se mantém (compat), novos saldos default 0.
-- ---------------------------------------------------------------------------
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
-- credit_transactions: ganha coluna currency (default 'credits' → compat total
-- com as transações existentes). É o ledger unificado de todas as moedas.
-- ---------------------------------------------------------------------------
alter table public.credit_transactions
  add column if not exists currency text not null default 'credits';

-- Estende o CHECK de kind para os kinds introduzidos pela economia virtual
-- (chest/mission/reward) mantendo os originais (grant/spend/refund/admin).
alter table public.credit_transactions drop constraint if exists credit_transactions_kind_check;
alter table public.credit_transactions add constraint credit_transactions_kind_check
  check (kind in ('grant','spend','refund','admin','reward','chest','mission'));

create index if not exists credit_tx_currency_idx on public.credit_transactions (user_id, currency, created_at desc);

-- ---------------------------------------------------------------------------
-- economy_adjust: operação atômica de crédito/débito por moeda.
-- - Delta > 0  → credita (sem limite).
-- - Delta < 0  → debita (exige saldo suficiente; senão falha).
-- - Nunca permite saldo negativo.
-- - Sempre grava o ledger com balance_after e audit oportunista.
-- - SOMENTE service_role (Edge Functions) chama: revogado para clientes.
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
  v_ok boolean;
begin
  insert into public.user_wallets (user_id) values (p_user_id)
    on conflict (user_id) do nothing;

  if p_delta = 0 then
    raise exception 'zero_delta';
  end if;
  if p_kind not in ('grant','spend','refund','admin','reward','chest','mission') then
    raise exception 'bad_kind';
  end if;

  -- tabela de colunas permitidas (whitelist rígida contra injection).
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

  if p_audit_action is not null then
    perform public.write_audit(p_audit_action, 'wallet', p_user_id::text,
      jsonb_build_object('currency', p_currency, 'delta', p_delta, 'balance', v_balance, 'note', p_note));
  end if;

  v_ok := true;
  return jsonb_build_object('balance', v_balance, 'ok', v_ok);
end;
$$;

revoke all on function public.economy_adjust(uuid, text, bigint, text, text, text, text, text) from public;
revoke execute on function public.economy_adjust(uuid, text, bigint, text, text, text, text, text) from anon, authenticated;
grant execute on function public.economy_adjust(uuid, text, bigint, text, text, text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- my_wallet: visão consolidada (saldos + configuração de moedas ativas).
-- Legítima leitura pelo cliente (RLS) — nenhuma escrita aqui.
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
-- Histórico financeiro completo do usuário (todas as moedas) — RLS owner.
-- ---------------------------------------------------------------------------
drop policy if exists "credit_transactions_select" on public.credit_transactions;
create policy "credit_transactions_select" on public.credit_transactions
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- RPC admin (cap 'economy'): concede/adjusta saldo com trilha de auditoria.
-- Só admin/super/founder (cap economy) — NUNCA um usuário comum.
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
  if not public.has_perm('economy') then
    raise exception 'not_admin';
  end if;
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  r := public.economy_adjust(p_user_id, p_currency, p_amount, 'admin',
       'admin','', p_note, 'economy.grant');
  return r;
end;
$$;

revoke all on function public.admin_grant_currency(uuid, text, bigint, text) from public;
grant execute on function public.admin_grant_currency(uuid, text, bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_economy_stats: somatório por moeda (cap 'economy') para o painel.
-- ---------------------------------------------------------------------------
create or replace function public.admin_economy_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb;
begin
  if not public.has_perm('economy') then
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