-- ============================================================================
-- KLAY K — SISTEMA DE CONVITES (migration AUTOSSUFICIENTE)
-- Tudo no backend: cada usuário tem um `invite_code` único; convites são
-- registrados no momento do cadastro (via redeem_invite) e recompensas são
-- liberadas por RPC (claim_invite_rewards) com limites anti-abuso.
-- O cliente NUNCA insere diretamente na tabela `invites` (sem RLS de INSERT).
--
-- NÃO depende de migrations anteriores de economia: garante aqui a base mínima
-- de cristais (user_wallets.crystals + ledger credit_transactions + função
-- segura) com CREATE IF NOT EXISTS. Se já existir um sistema inteiro de
-- economia (currencies/6 moedas/economy_adjust), esta migration é compatível:
-- usa a MESMA tabela user_wallets, o MESMO ledger credit_transactions e apenas
-- credita cristais via função própria security definer.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) BOOTSTRAP DE ECONOMIA (só cria o que ainda não existe)
-- ---------------------------------------------------------------------------
-- user_wallets: saldo de créditos (fonte de verdade). Se o gifts/economy já
-- criaram, mantém tudo; apenas garante a coluna crystals (com CHECK >= 0).
create table if not exists public.user_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  credits bigint not null default 0 check (credits >= 0),
  updated_at timestamptz not null default now()
);

alter table public.user_wallets
  add column if not exists crystals bigint not null default 0 check (crystals >= 0);

-- credit_transactions: livro-caixa de movimentações (todas as moedas).
-- Se já existe, só ganha a coluna currency e o kind `reward`.
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

-- Amplia o CHECK de kind mantendo os originais (idempotente; mesmo nome do
-- economy_wallet, então não conflita se ambas as migrations rodarem).
alter table public.credit_transactions drop constraint if exists credit_transactions_kind_check;
alter table public.credit_transactions add constraint credit_transactions_kind_check
  check (kind in ('grant','spend','refund','admin','reward','chest','mission'));

create index if not exists credit_tx_currency_idx
  on public.credit_transactions (user_id, currency, created_at desc);

-- RLS: leitura somente do próprio usuário; NENHUM policy de insert/update/delete
-- para o cliente. Saldos/ledger só mudam dentro de funções security definer.
alter table public.user_wallets enable row level security;
drop policy if exists "user_wallets_select" on public.user_wallets;
create policy "user_wallets_select" on public.user_wallets
  for select using (user_id = auth.uid());

alter table public.credit_transactions enable row level security;
drop policy if exists "credit_transactions_select" on public.credit_transactions;
create policy "credit_transactions_select" on public.credit_transactions
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 0b) klayk_invite_credit: operação atômica de CRÉDITO de cristais (ledger).
--     - Só credita (amount > 0); nunca permite saldo negativo (CHECK coluna).
--     - Sempre grava o ledger com balance_after e currency='crystals'.
--     - EXECUTE apenas para service_role/security definer — nunca um cliente.
-- ---------------------------------------------------------------------------
create or replace function public.klayk_invite_credit(
  p_user_id uuid,
  p_amount bigint,
  p_invite_id uuid,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance bigint;
begin
  if p_user_id is null then raise exception 'bad_user'; end if;
  if p_amount <= 0 then raise exception 'bad_amount'; end if;

  insert into public.user_wallets (user_id) values (p_user_id)
    on conflict (user_id) do nothing;

  update public.user_wallets
     set crystals = crystals + p_amount, updated_at = now()
   where user_id = p_user_id
     and crystals + p_amount >= 0
   returning crystals into v_balance;

  if v_balance is null then raise exception 'insufficient_funds'; end if;

  insert into public.credit_transactions
    (user_id, delta, balance_after, kind, ref_type, ref_id, note, currency)
  values
    (p_user_id, p_amount, v_balance, 'reward', 'invite', p_invite_id::text, p_note, 'crystals');

  return jsonb_build_object('balance', v_balance, 'ok', true);
end;
$$;

revoke all on function public.klayk_invite_credit(uuid, bigint, uuid, text) from public;
revoke execute on function public.klayk_invite_credit(uuid, bigint, uuid, text) from anon, authenticated;
grant execute on function public.klayk_invite_credit(uuid, bigint, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 1) invite_code em profiles (gerado pelo backend, único, formato KLAYK-XXXXXX)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists invite_code text;

create unique index if not exists profiles_invite_code_uidx
  on public.profiles (invite_code);

-- ---------------------------------------------------------------------------
-- 2) Tabela invites
-- ---------------------------------------------------------------------------
create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invited_user_id uuid references auth.users(id) on delete cascade,
  invite_code text,
  status text not null default 'pending'
    check (status in ('pending', 'validated', 'rewarded', 'blocked')),
  created_at timestamptz not null default now(),
  validated_at timestamptz,
  rewarded_at timestamptz,
  unique (invite_code, invited_user_id)
);

create index if not exists invites_inviter_idx on public.invites (inviter_id, created_at desc);
create index if not exists invites_invited_idx on public.invites (invited_user_id);

-- ---------------------------------------------------------------------------
-- 3) handle_new_user: agora também persiste o invite_code do metadata no perfil
--    (o novo usuário já nasce com código próprio e reutilizável).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  v_code := nullif(new.raw_user_meta_data->>'invite_code', '');

  insert into public.profiles (id, username, display_name, avatar_url, invite_code)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'username', ''), 'user-' || left(new.id::text, 8)),
    coalesce(
      nullif(new.raw_user_meta_data->>'full_name', ''),
      coalesce(nullif(new.raw_user_meta_data->>'name', ''), 'Participante')
    ),
    null,
    v_code
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Geração de código único (security definer; cada usuário so tem o seu)
-- ---------------------------------------------------------------------------
create or replace function public.ensure_invite_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_code text;
  v_try int := 0;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select invite_code into v_code from public.profiles where id = u;
  if v_code is not null then
    return v_code;
  end if;

  -- Gera código único do tipo KLAYK-AB12CD (6 chars de um alfabeto sem ambiguidade).
  -- gen_random_uuid() é CORE do Postgres 13+ (não depende de pgcrypto, que no
  -- Supabase vive no schema `extensions` e some atrás de `set search_path`).
  loop
    v_try := v_try + 1;
    if v_try > 20 then raise exception 'code_generation_failed'; end if;
    v_code := 'KLAYK-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 6));
    exit when not exists (
      select 1 from public.profiles where invite_code = v_code
    );
  end loop;

  update public.profiles set invite_code = v_code where id = u;
  return v_code;
end;
$$;

revoke all on function public.ensure_invite_code() from public;
grant execute on function public.ensure_invite_code() to authenticated;

-- Fallback em lote para usuários existentes sem código (executado manualmente,
-- não bloqueia a migration). Código = KLAYK-{6 hex} via gen_random_uuid().
do $$
declare
  r record;
begin
  for r in
    select p.id
    from public.profiles p
    where p.invite_code is null
  loop
    update public.profiles
       set invite_code = 'KLAYK-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 6))
     where id = r.id
       and invite_code is null;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Validação pública do código (permite conferência ANTES do cadastro)
-- ---------------------------------------------------------------------------
create or replace function public.validate_invite_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
begin
  if p_code is null or length(trim(p_code)) < 6 then
    return null;
  end if;
  select pr.id, pr.display_name, pr.username, pr.avatar_url
    into p
    from public.profiles pr
   where pr.invite_code = upper(trim(p_code));
  if p is null or p.id is null then
    return null;
  end if;
  return jsonb_build_object(
    'inviter_id', p.id,
    'display_name', p.display_name,
    'username', p.username,
    'avatar_url', p.avatar_url,
    'code', upper(trim(p_code))
  );
end;
$$;

revoke all on function public.validate_invite_code(text) from public;
grant execute on function public.validate_invite_code(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) Redeem: registra o convite quando o novo usuário confirma sessão.
--    Quem usa o CÓDIGO de outrem = convidado. Impede auto-convite, código
--    inválido, duplicidade por usuário e excesso de convites pendentes.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_inviter_id uuid;
  v_pending_count int;
  v_existing public.invites%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_code is null or length(trim(p_code)) < 6 then
    raise exception 'invalid_code';
  end if;

  select id into v_inviter_id
    from public.profiles
   where invite_code = upper(trim(p_code))
     and id is distinct from u;

  if v_inviter_id is null then
    raise exception 'invalid_code';
  end if;

  -- Já redeimiu? Devolve o estado atual sem erro (idempotente).
  select * into v_existing from public.invites
   where invited_user_id = u order by created_at desc limit 1;
  if v_existing.invited_user_id is not null then
    return public.invite_summary();
  end if;

  -- Limite de convites pendentes do convidante (anti mass-signup).
  select count(*) into v_pending_count from public.invites
   where inviter_id = v_inviter_id
     and status in ('pending', 'validated');
  if v_pending_count >= 50 then
    raise exception 'inviter_saturated';
  end if;

  insert into public.invites (inviter_id, invited_user_id, invite_code, status, validated_at)
  values (v_inviter_id, u, upper(trim(p_code)), 'validated', now());

  return public.invite_summary();
end;
$$;

-- Redeem usa a RPC de resumo (criada abaixo) — garante existência prévia.
create or replace function public.invite_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_invited int := 0;
  v_validated int := 0;
  v_rewarded int := 0;
  v_pending_rewards int := 0;
  v_code text;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select invite_code into v_code from public.profiles where id = u;
  if v_code is null then
    v_code := public.ensure_invite_code();
  end if;

  select count(*) into v_invited from public.invites where inviter_id = u;
  select count(*) into v_validated from public.invites where inviter_id = u and status = 'validated';
  select count(*) into v_rewarded from public.invites where inviter_id = u and status = 'rewarded';
  select count(*) into v_pending_rewards from public.invites where inviter_id = u and status = 'validated';

  return jsonb_build_object(
    'code', v_code,
    'invited', v_invited,
    'validated', v_validated,
    'rewarded', v_rewarded,
    'pending_rewards', v_pending_rewards
  );
end;
$$;

revoke all on function public.redeem_invite(text) from public;
grant execute on function public.redeem_invite(text) to authenticated;
revoke all on function public.invite_summary() from public;
grant execute on function public.invite_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Recompensas: quem convidou libera cristais ao atingir patamar validado.
--    Regras 100% no backend; só usuários do próprio invite podem reivindicar.
--    Limite diário anti-fraude (30/ dia) e anti auto-convite.
--    Pagamento usa klayk_invite_credit (função própria desta migration) — não
--    depende de economy_adjust de outra migration. Idempotente: cada convite
--    paga UMA vez (transição validated -> rewarded com guard).
-- ---------------------------------------------------------------------------
create or replace function public.claim_invite_rewards()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_claimed int := 0;
  v_crystals bigint := 0;
  v_today date := current_date;
  v_today_claims int;
  v_invite public.invites%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  -- Limite diário de reivindicações.
  select count(*) into v_today_claims
    from public.credit_transactions
   where user_id = u and kind = 'reward' and created_at::date = v_today;
  if v_today_claims >= 30 then
    raise exception 'daily_limit_reached';
  end if;

  for v_invite in
    select * from public.invites
     where inviter_id = u and status = 'validated'
     order by validated_at asc
  loop
    -- 5 cristais por convidado validado (recompensa fixa, backend decide).
    perform public.klayk_invite_credit(
      u, 5, v_invite.id, 'Convidou um amigo'
    );
    -- Guarda idempotência: só paga quem ainda está 'validated'.
    update public.invites
       set status = 'rewarded', rewarded_at = now()
     where id = v_invite.id and status = 'validated';
    if found then
      v_claimed := v_claimed + 1;
      v_crystals := v_crystals + 5;
    end if;
  end loop;

  return jsonb_build_object('claimed', v_claimed, 'crystals', v_crystals);
end;
$$;

revoke all on function public.claim_invite_rewards() from public;
grant execute on function public.claim_invite_rewards() to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Lista de convites do usuário (auto) com perfil do convidado
-- ---------------------------------------------------------------------------
create or replace function public.my_invites()
returns table (
  id uuid,
  invited_user_id uuid,
  invite_code text,
  status text,
  validated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select inv.id, inv.invited_user_id, inv.invite_code, inv.status, inv.validated_at
      from public.invites inv
     where inv.inviter_id = auth.uid()
     order by inv.created_at desc;
end;
$$;

revoke all on function public.my_invites() from public;
grant execute on function public.my_invites() to authenticated;

-- ---------------------------------------------------------------------------
-- 8) RLS
-- ---------------------------------------------------------------------------
alter table public.invites enable row level security;

drop policy if exists "invites_select_own" on public.invites;
create policy "invites_select_own" on public.invites
  for select using (inviter_id = auth.uid() or invited_user_id = auth.uid());

-- Sem INSERT/UPDATE/DELETE direto pelo cliente: a integridade é garantida
-- exclusivamente pelas RPCs security definer acima.

-- ---------------------------------------------------------------------------
-- 9) Leitura segura do saldo (se ainda não existir um my_wallet global).
--    Opcional e compatível com economia completa: se o objetivo é só mostrar
--    cristais de convites, my_wallet_crystals() já basta e não conflita.
-- ---------------------------------------------------------------------------
create or replace function public.my_wallet_crystals()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_balance bigint;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  select crystals into v_balance from public.user_wallets where user_id = u;
  return coalesce(v_balance, 0);
end;
$$;

revoke all on function public.my_wallet_crystals() from public;
grant execute on function public.my_wallet_crystals() to authenticated;