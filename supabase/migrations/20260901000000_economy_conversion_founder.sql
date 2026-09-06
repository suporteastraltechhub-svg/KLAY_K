-- ============================================================================
-- KLAY K — CONVERSÃO/RESGATE DE MOEDAS + CRÉDITOS ILIMITADOS DO FUNDADOR
-- (v2 — SEgurança corrigida)  Autossuficiente e idempotente.
--
-- Correções de segurança desta versão:
--   1) RLS em currency_conversion_requests: usuário vê SOMENTE os próprios
--      pedidos; admin/fundador vê tudo via validação server-side
--      (economy_has_admin). Nada de `for select using (true)`.
--   2) founder_unlimited_currency é IMUTÁVEL em prática: um trigger de guarda
--      força a flag sempre igual a "é a conta oficial do fundador
--      (ceo.arh.tech@gmail.com)". NÃO existe RPC para alterá-la; mesmo um
--      admin tentando setar true em outro usuário é revertido pelo trigger.
--   3) Conversão reserva o saldo na hora (debito na criacao do pedido, com
--      FOR UPDATE + economy_adjust atômico): impossível converter mais do que
--      o saldo real. Aprovacao credita a moeda destino; rejeicao/cancelamento
--      reembolsa a origem. Tudo no backend, uma transação por operacao.
--
-- Nenhuma funcao existente tem o RETURNS alterado -> sem erro 42P13.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Flag de creditos ilimitados do fundador (imutavel) + selo verificado
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists founder_unlimited_currency boolean not null default false;

-- Guarda de seguranca: force a flag SEMPRE conforme o e-mail oficial do
-- fundador, em qualquer INSERT/UPDATE em profiles. Assim:
--   * o fundador sempre fica true;
--   * qualquer outro usuario fica false (mesmo que um admin tente setar true);
--   * o cliente jamais consegue alterar (coluna nao e editavel por authenticated).
create or replace function public.tg_founder_unlimited_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner boolean;
begin
  select exists (
    select 1 from auth.users u
    where u.id = NEW.id
      and lower(u.email) = 'ceo.arh.tech@gmail.com'
  ) into v_owner;
  NEW.founder_unlimited_currency := coalesce(v_owner, false);
  return NEW;
end;
$$;

drop trigger if exists tg_founder_unlimited_guard on public.profiles;
create trigger tg_founder_unlimited_guard
  before insert or update on public.profiles
  for each row execute function public.tg_founder_unlimited_guard();

-- Selo + role do dono: is_verified=true no servidor para o e-mail oficial.
update public.profiles p
   set is_verified = true
  from auth.users u
 where u.id = p.id
   and lower(u.email) = 'ceo.arh.tech@gmail.com';

-- Marcação dinâmica: quando o perfil do dono for criado/atualizado, o trigger
-- também liga role/is_admin/is_verified. Recreate = idempotente.
create or replace function public.tg_mark_founder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from auth.users u
    where u.id = NEW.id
      and lower(u.email) = 'ceo.arh.tech@gmail.com'
  ) then
    NEW.role := 'founder';
    NEW.is_admin := true;
    NEW.is_verified := true;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_mark_founder on public.profiles;
create trigger tg_mark_founder
  before insert or update of id, role on public.profiles
  for each row execute function public.tg_mark_founder();

-- ---------------------------------------------------------------------------
-- 2) conversion_settings: regras de conversao/resgate por moeda-alvo
--    (catálogo: leitura publica; escrita apenas via RPC admin/owner)
-- ---------------------------------------------------------------------------
create table if not exists public.conversion_settings (
  id text primary key,
  name text not null,
  from_currency text not null,
  to_currency text not null,
  rate numeric not null default 1 check (rate > 0),
  min_amount bigint not null default 1 check (min_amount >= 1),
  max_amount bigint not null default 1e6 check (max_amount >= 1),
  fee_percent numeric not null default 0 check (fee_percent >= 0 and fee_percent < 100),
  status text not null default 'active' check (status in ('active','paused')),
  method text not null default 'wallet' check (method in ('wallet','rescue')),
  sort_order int not null default 0,
  description text default '',
  created_at timestamptz not null default now()
);

alter table public.conversion_settings enable row level security;
drop policy if exists "conversion_settings_select" on public.conversion_settings;
create policy "conversion_settings_select" on public.conversion_settings
  for select using (true);

-- ---------------------------------------------------------------------------
-- 3) currency_conversion_requests: pedidos de conversao/resgate (com RLS)
--    * usuario comum: apenas os proprios (user_id = auth.uid())
--    * admin/fundador: todos, via validacao server-side (economy_has_admin)
--    Nenhum usuario comum le dados financeiros de terceiros.
-- ---------------------------------------------------------------------------
create table if not exists public.currency_conversion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  setting_id text not null references public.conversion_settings(id),
  from_currency text not null,
  to_currency text not null,
  amount bigint not null check (amount >= 1),
  rate numeric not null default 1,
  fee numeric not null default 0,
  received numeric not null default 0,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled','executed')),
  note text default '',
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null
);

alter table public.currency_conversion_requests enable row level security;

-- Select: somente do proprio usuario.
drop policy if exists "currency_conversion_requests_select_own" on public.currency_conversion_requests;
create policy "currency_conversion_requests_select_own" on public.currency_conversion_requests
  for select using (user_id = auth.uid());

-- Select: admin/fundador ve todos (validacao no backend via economy_has_admin).
drop policy if exists "currency_conversion_requests_select_admin" on public.currency_conversion_requests;
create policy "currency_conversion_requests_select_admin" on public.currency_conversion_requests
  for select using (public.economy_has_admin());

-- Sem policies de escrita: somente as RPCs security definer abaixo gravam.
create index if not exists conversion_req_user_idx
  on public.currency_conversion_requests (user_id, created_at desc);
create index if not exists conversion_req_status_idx
  on public.currency_conversion_requests (status);

-- ---------------------------------------------------------------------------
-- 4) Consulta das regras ativas (leitura publica das configs ativas)
-- ---------------------------------------------------------------------------
create or replace function public.my_conversion_settings()
returns setof public.conversion_settings
language sql
security definer
set search_path = public
as $$
  select * from public.conversion_settings
   where status = 'active'
   order by sort_order, id;
$$;

revoke all on function public.my_conversion_settings() from public;
grant execute on function public.my_conversion_settings() to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Criacao de pedido de conversao/resgate — RESERVA o saldo de forma
--    atomica (FOR UPDATE + economy_adjust) na hora do pedido. Assim o mesmo
--    saldo nao pode ser usado em varios pedidos pendentes.
--    * o debito da origem acontece aqui (vira reserva);
--    * aprovacao credita a moeda destino;
--    * rejeicao/cancelamento reembolsa a origem.
-- ---------------------------------------------------------------------------
create or replace function public.currency_conversion_request(
  p_setting_id text,
  p_amount bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  s public.conversion_settings;
  v_wallet record;
  v_from_balance bigint;
  v_fee numeric;
  v_received numeric;
  v_req_id uuid;
  v_lock uuid;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_amount is null or p_amount < 1 then raise exception 'bad_amount'; end if;

  select * into s from public.conversion_settings
   where id = p_setting_id and status = 'active';
  if s.id is null then raise exception 'setting_not_active'; end if;

  if p_amount < s.min_amount or p_amount > s.max_amount then
    raise exception 'amount_out_of_range';
  end if;

  -- Locka a linha da carteira do usuário para serializar operações e impedir
  -- gasto duplo concorrente.
  select user_id into v_lock
    from public.user_wallets
   where user_id = u
   for update;

  select * into v_wallet from public.user_wallets where user_id = u;
  case s.from_currency
    when 'credits' then v_from_balance := v_wallet.credits;
    when 'diamonds' then v_from_balance := v_wallet.diamonds;
    when 'crystals' then v_from_balance := v_wallet.crystals;
    when 'rubies' then v_from_balance := v_wallet.rubies;
    when 'emeralds' then v_from_balance := v_wallet.emeralds;
    when 'crystal_rare' then v_from_balance := v_wallet.crystal_rare;
    else raise exception 'bad_from_currency';
  end case;

  if v_from_balance < p_amount then
    raise exception 'insufficient_funds';
  end if;

  v_fee := round(p_amount * s.fee_percent / 100.0);
  v_received := round(p_amount * s.rate - v_fee);
  if v_received < 1 then raise exception 'received_zero'; end if;

  -- Reserva: debita a origem de forma atomica (economy_adjust grava o ledger).
  perform public.economy_adjust(
    u, s.from_currency, -p_amount,
    'spend', 'conversion', p_setting_id,
    'Reserva para conversao -> ' || s.to_currency
  );

  insert into public.currency_conversion_requests
    (user_id, setting_id, from_currency, to_currency, amount, rate, fee, received, status)
  values
    (u, s.id, s.from_currency, s.to_currency, p_amount, s.rate, v_fee, v_received, 'pending')
  returning id into v_req_id;

  return jsonb_build_object(
    'ok', true, 'request_id', v_req_id,
    'from_currency', s.from_currency,
    'to_currency', s.to_currency,
    'amount', p_amount,
    'fee', v_fee,
    'received', v_received,
    'rate', s.rate,
    'status', 'pending',
    'reserved', true
  );
end;
$$;

revoke all on function public.currency_conversion_request(text, bigint) from public;
grant execute on function public.currency_conversion_request(text, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Cancelamento pelo proprio usuario (somente pedido proprio e pendente) —
--    REFUND da reserva na origem.
-- ---------------------------------------------------------------------------
create or replace function public.cancel_conversion_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  r public.currency_conversion_requests;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  select * into r from public.currency_conversion_requests
    where id = p_request_id and user_id = u and status = 'pending';
  if r.id is null then raise exception 'not_found_or_not_pending'; end if;

  -- Reembolsa a reserva inteira.
  perform public.economy_adjust(
    u, r.from_currency, r.amount,
    'refund', 'conversion', r.id::text,
    'Reembolso por cancelamento de conversao'
  );

  update public.currency_conversion_requests
     set status = 'cancelled', decided_at = now()
   where id = p_request_id;

  return jsonb_build_object('ok', true, 'status', 'cancelled', 'refunded', r.amount);
end;
$$;

revoke all on function public.cancel_conversion_request(uuid) from public;
grant execute on function public.cancel_conversion_request(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Aprovar/rejeitar (admin/fundador). A reserva já foi debitada na origem:
--    * aprovar  -> credita a moeda destino (processo em uma transação);
--    * rejeitar -> reembolsa a origem.
--    Se o credito do destino falhar, a EXCEÇÃO aborta a transação inteira:
--    o pedido continua 'pending' e a reserva segue na origem (sem perda e sem
--    double-spend), podendo ser rejeitado/retentado depois.
-- ---------------------------------------------------------------------------
create or replace function public.admin_conversion_decision(
  p_request_id uuid,
  p_approve boolean,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  r public.currency_conversion_requests;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if not public.economy_has_admin() then
    raise exception 'not_admin';
  end if;

  select * into r from public.currency_conversion_requests where id = p_request_id;
  if r.id is null then raise exception 'request_not_found'; end if;
  if r.status <> 'pending' then raise exception 'request_already_decided'; end if;

  if not p_approve then
    -- Reembolsa a reserva na origem.
    perform public.economy_adjust(
      r.user_id, r.from_currency, r.amount,
      'refund', 'conversion', r.id::text,
      'Reembolso por rejeicao de conversao'
    );
    update public.currency_conversion_requests
       set status = 'rejected', decided_at = now(), decided_by = u, note = p_note
     where id = p_request_id;
    return jsonb_build_object('ok', true, 'status', 'rejected', 'refunded', r.amount);
  end if;

  -- Aprova: credita a moeda destino (mesma transação; falha aborta tudo).
  perform public.economy_adjust(
    r.user_id, r.to_currency, round(r.received),
    'grant', 'conversion', r.id::text,
    'Recebido de conversao (origem ja reservada)'
  );

  update public.currency_conversion_requests
     set status = 'executed', decided_at = now(), decided_by = u, note = p_note
   where id = p_request_id;

  return jsonb_build_object('ok', true, 'status', 'executed', 'received', round(r.received));
end;
$$;

revoke all on function public.admin_conversion_decision(uuid, boolean, text) from public;
grant execute on function public.admin_conversion_decision(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8) Config admin das regras de conversao (gate economy_has_admin)
-- ---------------------------------------------------------------------------
create or replace function public.admin_conversion_settings(
  p_id text,
  p_name text,
  p_from_currency text,
  p_to_currency text,
  p_rate numeric,
  p_min bigint,
  p_max bigint,
  p_fee_percent numeric,
  p_status text,
  p_method text,
  p_description text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.economy_has_admin() then
    raise exception 'not_admin';
  end if;
  if p_to_currency = p_from_currency then raise exception 'same_currency'; end if;
  insert into public.conversion_settings
    (id, name, from_currency, to_currency, rate, min_amount, max_amount,
     fee_percent, status, method, description, sort_order)
  values
    (p_id, p_name, p_from_currency, p_to_currency, p_rate, p_min, p_max,
     p_fee_percent, p_status, p_method, p_description, 0)
  on conflict (id) do update set
    name = excluded.name,
    from_currency = excluded.from_currency,
    to_currency = excluded.to_currency,
    rate = excluded.rate,
    min_amount = excluded.min_amount,
    max_amount = excluded.max_amount,
    fee_percent = excluded.fee_percent,
    status = excluded.status,
    method = excluded.method,
    description = excluded.description;
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

revoke all on function public.admin_conversion_settings(text, text, text, text, numeric, bigint, bigint, numeric, text, text, text) from public;
grant execute on function public.admin_conversion_settings(text, text, text, text, numeric, bigint, bigint, numeric, text, text, text) to authenticated;

-- Historico de pedidos do proprio usuario (admins leem via policy + select direto).
create or replace function public.my_conversion_requests(p_limit int default 30)
returns setof public.currency_conversion_requests
language sql
security definer
set search_path = public
as $$
  select * from public.currency_conversion_requests
   where user_id = auth.uid()
   order by created_at desc
   limit p_limit;
$$;

revoke all on function public.my_conversion_requests(int) from public;
grant execute on function public.my_conversion_requests(int) to authenticated;
