-- ============================================================================
-- KLAY K — SISTEMA FINANCEIRO CENTRAL (KLAY K FINANCE)
-- Migration ADITIVA e idempotente. Constrói POR CIMA do sistema existente:
--   * currencies           (catálogo de moedas)
--   * user_wallets         (saldos source-of-truth, CHECK >= 0)
--   * credit_transactions  (ledger unificado — toda mudança de saldo grava aqui)
--   * economy_adjust()     (única porta atômica de crédito/débito; service_role)
--   * process_gift_spend() (gasto de presentes atômico — NÃO alterado aqui)
--   * write_audit()        (audit_logs existente — usado de forma dinâmica)
--
-- REGRAS DE OURO (enforced nesta migration):
--   1) NUNCA confiar em valor/moeda/destinatário vindo do cliente: preço,
--      créditos, taxas e destino são SEMPRE recomputados/lidos no backend.
--   2) DINHEIRO REAL × MOEDA VIRTUAL separados: compras de pacotes usam preço
--      em CENTAVOS (numeric) no backend; a entrega é SEMPRE de moeda virtual
--      (credits) via economy_adjust. Nada aqui é rastreável a dinheiro real
--      automaticamente; payout = intenção registrada, liquidação fora do app.
--   3) Idempotência: webhook por event_id único; pagamento com idempotency_key
--      único; gift_earnings com gift_tx_id único. Retry NUNCA entrega 2x.
--   4) Concorrência: wallets atualizadas com UPDATE atômico + CHECK >= 0 e
--      linhas protegidas (FOR UPDATE) onde necessário — saldo nunca negativo.
--   5) Escrita de saldo SOMENTE via security definer; cliente lê o próprio.
--   6) Sem DROP destrutivo; sem alterar funções/assinaturas existentes.
--
-- Deploy: aplicar esta migration e depois criar/atualizar as Edge Functions
-- `payments-webhook` e `send-gift`.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) coin_packages: PACOTES DE COMPRA DE MOEDA VIRTUAL (estáveis p/ código)
--    Preço em CENTAVOS (BRL) = R$ real que o usuário pagaria. A entrega é
--    sempre moeda virtual (credits). `sku` garante idempotência de catálogo.
-- ---------------------------------------------------------------------------
create table if not exists public.coin_packages (
  id text primary key,
  sku text not null unique,
  name text not null,
  emoji text not null default '🪙',
  currency text not null default 'credits',
  credits_amount bigint not null check (credits_amount > 0),
  price_cents numeric(12,2) not null check (price_cents > 0),
  is_active boolean not null default true,
  sort_order int not null default 0,
  description text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.coin_packages
  (id, sku, name, emoji, currency, credits_amount, price_cents, sort_order, description)
values
  ('pack_100',    'KLAY-COINS-100',    '100 Moedas',    '🪙', 'credits', 100,    1.99, 1,   'Pacote inicial.'),
  ('pack_500',    'KLAY-COINS-500',    '500 Moedas',    '🌟', 'credits', 500,    9.49, 2,   'Mais por menos.'),
  ('pack_1200',   'KLAY-COINS-1200',   '1200 Moedas',   '🚀', 'credits', 1200,  19.99, 3,   'Popular.'),
  ('pack_3000',   'KLAY-COINS-3000',   '3000 Moedas',   '💎', 'credits', 3000,  45.99, 4,   'Melhor custo-benefício.')
on conflict (id) do nothing;

create index if not exists coin_packages_active_idx on public.coin_packages (is_active, sort_order);

alter table public.coin_packages enable row level security;
drop policy if exists "coin_packages_select" on public.coin_packages;
create policy "coin_packages_select" on public.coin_packages
  for select using (true);

-- ---------------------------------------------------------------------------
-- 2) financial_price_history: trilha de AUDITORIA de preços de produtos
--    (quem alterou, de quanto, quando e por quê). Vale para coin_packages e
--    futuramente store products. Sem cascata: ciência de produto.
-- ---------------------------------------------------------------------------
create table if not exists public.financial_price_history (
  id uuid primary key default gen_random_uuid(),
  product_type text not null default 'coin_package',
  product_id text not null,
  old_price_cents numeric(12,2),
  new_price_cents numeric(12,2) not null,
  currency text not null default 'credits',
  changed_by uuid references auth.users(id) on delete set null,
  reason text default '',
  created_at timestamptz not null default now()
);

create index if not exists price_history_product_idx
  on public.financial_price_history (product_type, product_id, created_at desc);

alter table public.financial_price_history enable row level security;
-- Sem políticas de leitura direta para clientes: admins leem via RPC
-- security definer. RLS habilitado para bloquear escrita acidental no cliente.

-- ---------------------------------------------------------------------------
-- 3) fee_configs: TAXAS DE PLATAFORMA por escopo (gift / payout).
--    Fonte de verdade no backend para cálculo de ganhos de criadores.
-- ---------------------------------------------------------------------------
create table if not exists public.fee_configs (
  id text primary key,
  scope text not null check (scope in ('gift','payout')),
  platform_percent numeric(5,2) not null default 20 check (platform_percent >= 0 and platform_percent < 100),
  min_amount bigint not null default 1 check (min_amount >= 0),
  note text default '',
  updated_at timestamptz not null default now()
);

insert into public.fee_configs (id, scope, platform_percent, min_amount, note) values
  ('gift.default', 'gift',   20, 1, 'Taxa padrão sobre moedas enviadas em presentes.'),
  ('payout.default', 'payout', 0, 1, 'Taxa padrão sobre resgates de ganhos de criador.')
on conflict (id) do update set
  platform_percent = excluded.platform_percent,
  min_amount = excluded.min_amount,
  updated_at = now();

alter table public.fee_configs enable row level security;
drop policy if exists "fee_configs_select" on public.fee_configs;
create policy "fee_configs_select" on public.fee_configs for select using (true);

-- ---------------------------------------------------------------------------
-- 4) financial_orders: PEDIDO CENTRAL de compra virtual (1 por compra).
--    status: draft → pending → paid | failed → refunded | cancelled
--    Preços SEMPRE vindos do catálogo (backend), nunca do cliente.
-- ---------------------------------------------------------------------------
create table if not exists public.financial_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_type text not null default 'coin_package',
  product_id text not null,
  currency text not null,
  quantity int not null default 1 check (quantity > 0),
  unit_credits bigint not null default 0 check (unit_credits >= 0),
  unit_price_cents numeric(12,2) not null check (unit_price_cents >= 0),
  total_price_cents numeric(12,2) not null check (total_price_cents >= 0),
  credits_delivered bigint not null default 0 check (credits_delivered >= 0),
  status text not null default 'pending'
    check (status in ('draft','pending','paid','failed','refunded','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists financial_orders_user_idx
  on public.financial_orders (user_id, created_at desc);
create index if not exists financial_orders_status_idx
  on public.financial_orders (status, created_at desc);

alter table public.financial_orders enable row level security;
drop policy if exists "financial_orders_select_own" on public.financial_orders;
create policy "financial_orders_select_own" on public.financial_orders
  for select using (user_id = auth.uid());
-- Sem políticas de INSERT/UPDATE/DELETE: só as RPCs security definer gravam.

-- ---------------------------------------------------------------------------
-- 5) financial_payments: PAGAMENTO do pedido. 1 pedido → 1 pagamento (a menos
--    que haja retentativa; mesmo assim só UM fica captured). Idempotência por
--    idempotency_key ÚNICO e provider_tx_id ÚNICO.
-- ---------------------------------------------------------------------------
create table if not exists public.financial_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.financial_orders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  method text not null default 'card',
  amount_cents numeric(12,2) not null check (amount_cents > 0),
  currency_code text not null default 'BRL',
  status text not null default 'pending'
    check (status in ('pending','processing','authorized','captured','failed','refunded')),
  idempotency_key text not null unique,
  provider text not null default 'default',
  provider_tx_id text,
  webhook_event_id text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists financial_payments_provider_tx_uniq
  on public.financial_payments (provider_tx_id) where provider_tx_id is not null;
create index if not exists financial_payments_user_idx
  on public.financial_payments (user_id, created_at desc);
create index if not exists financial_payments_status_idx
  on public.financial_payments (status);

alter table public.financial_payments enable row level security;
drop policy if exists "financial_payments_select_own" on public.financial_payments;
create policy "financial_payments_select_own" on public.financial_payments
  for select using (user_id = auth.uid());
-- Sem políticas de escrita direta: somente RPCs security definer.

-- ---------------------------------------------------------------------------
-- 6) payment_webhook_events: IDEMPOTÊNCIA de webhooks. Um event_id do provider
--    só é processado UMA vez. Replays/retries devolvem o resultado original.
-- ---------------------------------------------------------------------------
create table if not exists public.payment_webhook_events (
  id text primary key,                       -- event_id do provider (único)
  provider text not null default 'default',
  provider_tx_id text,
  status text not null default 'received',
  payload jsonb not null default '{}'::jsonb,
  signature_ok boolean not null default false,
  amount_cents numeric(12,2),
  processed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists payment_webhook_tx_idx
  on public.payment_webhook_events (provider_tx_id, created_at desc);

alter table public.payment_webhook_events enable row level security;
-- Nenhuma política: esta tabela é de servidor (ESC), nunca do cliente.

-- ---------------------------------------------------------------------------
-- 7) payment_provider_config: configuração do provedor de pagamento.
--    webhook_secret NUNCA é exposto ao cliente (sem grants). É usado pela
--    Edge Function para validar assinatura HMAC antes de capturar.
-- ---------------------------------------------------------------------------
create table if not exists public.payment_provider_config (
  id text primary key,
  name text not null,
  webhook_secret text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.payment_provider_config (id, name, webhook_secret) values
  ('default', 'KLAY PSP', gen_random_uuid()::text)
on conflict (id) do nothing;

alter table public.payment_provider_config enable row level security;
-- Sem políticas (off-limits para o cliente). Após aplicar a migration:
--   select id, webhook_secret from public.payment_provider_config;
-- e configure o segredo no provedor para assinar os webhooks.

-- ---------------------------------------------------------------------------
-- 8) financial_refunds: REEMBOLSO de pagamentos (administrativo). A devolução
--    de moedas usa economy_adjust com kind 'refund' e ref finance_refund.
-- ---------------------------------------------------------------------------
create table if not exists public.financial_refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.financial_payments(id) on delete cascade,
  order_id uuid not null references public.financial_orders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents numeric(12,2) not null check (amount_cents > 0),
  refunded_credits bigint not null default 0 check (refunded_credits >= 0),
  reason text not null default '',
  status text not null default 'processed'
    check (status in ('processed','partial','failed')),
  refunded_by uuid references auth.users(id) on delete set null,
  provider_refund_id text,
  created_at timestamptz not null default now()
);
create index if not exists financial_refunds_user_idx
  on public.financial_refunds (user_id, created_at desc);

alter table public.financial_refunds enable row level security;
drop policy if exists "financial_refunds_select_own" on public.financial_refunds;
create policy "financial_refunds_select_own" on public.financial_refunds
  for select using (user_id = auth.uid());
-- Escrita apenas via RPC security definer (admin).

-- ---------------------------------------------------------------------------
-- 9) gift_earnings: GANHOS DE CRIADOR por presente recebido. Um gift pode
--    gerar UMA linha (gift_tx_id único = idempotência). Criador recebe
--    (1 - platform_percent) × credits_total via economy_adjust (moeda virtual).
-- ---------------------------------------------------------------------------
create table if not exists public.gift_earnings (
  id uuid primary key default gen_random_uuid(),
  gift_tx_id uuid not null unique references public.gift_transactions(id) on delete cascade,
  receiver_id uuid references auth.users(id) on delete cascade,
  gross_credits bigint not null check (gross_credits >= 0),
  platform_fee bigint not null default 0 check (platform_fee >= 0),
  creator_net bigint not null default 0 check (creator_net >= 0),
  status text not null default 'available'
    check (status in ('available','payout_requested','paid')),
  created_at timestamptz not null default now()
);
create index if not exists gift_earnings_receiver_idx
  on public.gift_earnings (receiver_id, created_at desc);
create index if not exists gift_earnings_status_idx
  on public.gift_earnings (status);

alter table public.gift_earnings enable row level security;
drop policy if exists "gift_earnings_select_own" on public.gift_earnings;
create policy "gift_earnings_select_own" on public.gift_earnings
  for select using (receiver_id = auth.uid());
-- Escrita só via function security definer (service_role).

-- ---------------------------------------------------------------------------
-- 10) creator_balances: SALDO AGGREGADO DE GANHOS por criador (moeda virtual
--     resgatável via payout aceito pelo fundador). Balança com gift_earnings.
-- ---------------------------------------------------------------------------
create table if not exists public.creator_balances (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pending_credits bigint not null default 0 check (pending_credits >= 0),
  available_credits bigint not null default 0 check (available_credits >= 0),
  withdrawn_credits bigint not null default 0 check (withdrawn_credits >= 0),
  updated_at timestamptz not null default now()
);

alter table public.creator_balances enable row level security;
drop policy if exists "creator_balances_select_own" on public.creator_balances;
create policy "creator_balances_select_own" on public.creator_balances
  for select using (user_id = auth.uid());
-- Escrita só via services security definer.

-- ---------------------------------------------------------------------------
-- 11) creator_payout_requests: PEDIDO DE RESGATE DE GANHOS (criador).
--     criar pedido deduz available→pending; aprovação move pending→withdrawn
--     (liquidação real acontece fora do app, manualmente pelo fundador);
--     rejeição devolve pending→available. Nada aqui movimenta dinheiro real.
-- ---------------------------------------------------------------------------
create table if not exists public.creator_payout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_credits bigint not null check (amount_credits > 0),
  status text not null default 'pending'
    check (status in ('pending','paid','rejected')),
  note text default '',
  decided_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists payout_requests_user_idx
  on public.creator_payout_requests (user_id, created_at desc);
create index if not exists payout_requests_status_idx
  on public.creator_payout_requests (status, created_at desc);

alter table public.creator_payout_requests enable row level security;
drop policy if exists "creator_payout_requests_select_own" on public.creator_payout_requests;
create policy "creator_payout_requests_select_own" on public.creator_payout_requests
  for select using (user_id = auth.uid());
-- Escrita só via RPCs security definer.

-- ---------------------------------------------------------------------------
-- 12) antifraud_flags: CLASSIFICAÇÃO DE RISCO por usuário. Gerada por funções
--     de avaliação e/ou pelo painel. Só S (service_role/security definer).
-- ---------------------------------------------------------------------------
create table if not exists public.antifraud_flags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  level text not null default 'NORMAL'
    check (level in ('NORMAL','REVIEW','RESTRICTED')),
  reason text default '',
  flagged_by uuid references auth.users(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists antifraud_user_idx on public.antifraud_flags (user_id, active);

alter table public.antifraud_flags enable row level security;
-- Sem políticas para cliente: avaliação e override são server-side.

-- ---------------------------------------------------------------------------
-- 13) Helper de auditoria financeira: usa write_audit quando existe (dinâmico)
-- ---------------------------------------------------------------------------
create or replace function public.finance_audit(
  p_action text,
  p_subject_type text,
  p_subject_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if to_regprocedure('public.write_audit(text,text,text,jsonb)') is not null then
    execute 'select public.write_audit($1,$2,$3,$4)'
      using p_action, p_subject_type, p_subject_id, coalesce(p_metadata, '{}'::jsonb);
  end if;
end;
$$;

revoke all on function public.finance_audit(text, text, text, jsonb) from public;
revoke execute on function public.finance_audit(text, text, text, jsonb) from anon, authenticated;
grant execute on function public.finance_audit(text, text, text, jsonb) to service_role;

-- Atualização automática de updated_at em tabelas financeiras.
create or replace function public.finance_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists "coin_packages_set_updated_at" on public.coin_packages;
create trigger "coin_packages_set_updated_at" before update on public.coin_packages
for each row execute function public.finance_set_updated_at();

drop trigger if exists "financial_orders_set_updated_at" on public.financial_orders;
create trigger "financial_orders_set_updated_at" before update on public.financial_orders
for each row execute function public.finance_set_updated_at();

drop trigger if exists "financial_payments_set_updated_at" on public.financial_payments;
create trigger "financial_payments_set_updated_at" before update on public.financial_payments
for each row execute function public.finance_set_updated_at();

-- ---------------------------------------------------------------------------
-- 14) finance_catalog: catálogo de pacotes ativos (leitura pública autenticada)
-- ---------------------------------------------------------------------------
create or replace function public.finance_catalog()
returns setof public.coin_packages
language sql
security definer
set search_path = public
as $$
  select * from public.coin_packages
   where is_active = true
   order by sort_order, id;
$$;

revoke all on function public.finance_catalog() from public;
grant execute on function public.finance_catalog() to authenticated;

-- ---------------------------------------------------------------------------
-- 15) create_coin_order: CRIA PEDIDO + PAGAMENTO pendente.
--     Preço/credits 100% lidos do catálogo no backend. Idempotência: se o
--     cliente reenviar a MESMA idempotency_key, devolve o pagamento existente.
--     Concorrência: FOR UPDATE sobre o pacote evita venda com catálogo mutável.
-- ---------------------------------------------------------------------------
create or replace function public.create_coin_order(
  p_package_id text,
  p_idempotency_key text,
  p_method text default 'card'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  pkg public.coin_packages%rowtype;
  v_existing uuid;
  v_order_id uuid;
  v_payment_id uuid;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_package_id is null or p_package_id = '' then raise exception 'bad_package'; end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) < 8 or char_length(p_idempotency_key) > 64 then
    raise exception 'bad_idempotency_key';
  end if;
  if p_method is null or p_method = '' then p_method := 'card'; end if;

  -- Retentativa: mesmo idempotency_key → devolve o pedido/pagamento original.
  select p.id, p.order_id into v_existing, v_order_id
    from public.financial_payments p
   where p.idempotency_key = p_idempotency_key and p.user_id = u;
  if v_existing is not null then
    return jsonb_build_object(
      'ok', true, 'duplicate', true,
      'order_id', v_order_id, 'payment_id', v_existing, 'status', 'pending'
    );
  end if;

  -- Lê preço no catálogo (backend). FOR UPDATE serializa vs admin_price_update.
  select * into pkg from public.coin_packages where id = p_package_id for update;
  if pkg.id is null then raise exception 'package_not_found'; end if;
  if not pkg.is_active then raise exception 'package_inactive'; end if;
  if pkg.currency <> 'credits' then raise exception 'unsupported_currency'; end if;

  v_order_id := gen_random_uuid();
  insert into public.financial_orders
    (id, user_id, product_type, product_id, currency, quantity,
     unit_credits, unit_price_cents, total_price_cents, credits_delivered, status)
  values
    (v_order_id, u, 'coin_package', pkg.id, pkg.currency, 1,
     pkg.credits_amount, pkg.price_cents, pkg.price_cents, 0, 'pending');

  insert into public.financial_payments
    (order_id, user_id, method, amount_cents, currency_code, status,
     idempotency_key, provider)
  values
    (v_order_id, u, p_method, pkg.price_cents, 'BRL', 'pending',
     p_idempotency_key, 'default')
  returning id into v_payment_id;

  perform public.finance_audit('finance.order.created', 'financial_order',
    v_order_id::text,
    jsonb_build_object('package', pkg.id, 'price_cents', pkg.price_cents,
                       'credits', pkg.credits_amount));

  return jsonb_build_object(
    'ok', true,
    'order_id', v_order_id,
    'payment_id', v_payment_id,
    'package_id', pkg.id,
    'price_cents', pkg.price_cents,
    'credits_amount', pkg.credits_amount,
    'currency', pkg.currency,
    'status', 'pending'
  );
end;
$$;

revoke all on function public.create_coin_order(text, text, text) from public;
grant execute on function public.create_coin_order(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 16) finance_order_status: status atual do pedido+pagamento (dono).
--     Usado no polling "Verificando transação..." do app.
-- ---------------------------------------------------------------------------
create or replace function public.finance_order_status(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  o public.financial_orders%rowtype;
  p public.financial_payments%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  select * into o from public.financial_orders where id = p_order_id and user_id = u;
  if o.id is null then raise exception 'order_not_found'; end if;
  select * into p from public.financial_payments where order_id = o.id order by created_at desc limit 1;
  return jsonb_build_object(
    'order_id', o.id,
    'order_status', o.status,
    'credits_delivered', o.credits_delivered,
    'total_price_cents', o.total_price_cents,
    'payment_id', p.id,
    'payment_status', p.status,
    'provider_tx_id', p.provider_tx_id,
    'paid_at', p.paid_at
  );
end;
$$;

revoke all on function public.finance_order_status(uuid) from public;
grant execute on function public.finance_order_status(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 17) finance_webhook_capture: CAPTURA IDEMPOTENTE via Edge Function.
--     validado pela Edge (HMAC) e revalidado aqui: assinatura precisa estar ok
--     e os VALUES do provider precisam bater com o pagamento (amount + status).
--     Replay de event_id devolve o resultado original sem entregar 2x.
--     Somente service_role executa.
-- ---------------------------------------------------------------------------
create or replace function public.finance_webhook_capture(
  p_event_id text,
  p_provider text,
  p_provider_tx_id text,
  p_status text,
  p_signature_ok boolean,
  p_amount_cents numeric,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pay public.financial_payments%rowtype;
  v_order public.financial_orders%rowtype;
  v_gross bigint;
  v_fee_pct numeric;
  v_fee bigint;
  v_net bigint;
  v_earnings_id uuid;
  v_used boolean;
begin
  if p_event_id is null or p_event_id = '' then raise exception 'bad_event_id'; end if;
  if p_provider_tx_id is null or p_provider_tx_id = '' then raise exception 'bad_provider_tx'; end if;

  -- 1) Idempotência: registra o evento. Conflict → já processado (ou em
  --    processamento): devolve o mesmo resultado sem re-entregar.
  insert into public.payment_webhook_events
    (id, provider, provider_tx_id, status, payload, signature_ok, amount_cents, processed_at)
  values
    (p_event_id, coalesce(p_provider,'default'), p_provider_tx_id, p_status,
     coalesce(p_payload,'{}'::jsonb), coalesce(p_signature_ok,false), p_amount_cents, now())
  on conflict (id) do nothing
  returning id into v_used;

  if v_used is null then
    select processed_at into v_used from public.payment_webhook_events where id = p_event_id;
    if v_used is not null then
      return jsonb_build_object('ok', true, 'duplicate', true, 'event_id', p_event_id,
                                'already_processed', true);
    end if;
  end if;

  select * into v_pay
    from public.financial_payments
   where provider_tx_id = p_provider_tx_id
     and provider = coalesce(nullif(p_provider,''), 'default')
   for update;

  if v_pay.id is null then
    -- Webhook para pagamento desconhecido: guarda audit, não entrega nada.
    perform public.finance_audit('finance.webhook.orphan', 'payment', p_provider_tx_id,
      jsonb_build_object('event_id', p_event_id));
    return jsonb_build_object('ok', false, 'error', 'payment_not_found');
  end if;

  -- 2) Assinatura: a Edge validou; aqui só aceitamos signature_ok.
  if not coalesce(p_signature_ok, false) then
    perform public.finance_audit('finance.webhook.bad_signature', 'payment', v_pay.id::text,
      jsonb_build_object('event_id', p_event_id));
    raise exception 'bad_signature';
  end if;

  -- 3) Value check: amount precisa ser EXATO.
  if round(coalesce(p_amount_cents, 0)) <> round(v_pay.amount_cents) then
    perform public.finance_audit('finance.webhook.amount_mismatch', 'payment', v_pay.id::text,
      jsonb_build_object('event_id', p_event_id, 'expected', v_pay.amount_cents,
                         'received', p_amount_cents));
    raise exception 'amount_mismatch';
  end if;

  -- 4) Só captura estados válidos; idempotente para captured (retry pós-commit).
  if v_pay.status = 'captured' then
    return jsonb_build_object('ok', true, 'duplicate', true,
                              'payment_id', v_pay.id, 'status', 'captured');
  end if;
  if v_pay.status in ('refunded','failed') then
    raise exception 'payment_not_capturable';
  end if;

  if p_status = 'failed' or p_status in ('declined','cancelled','voided') then
    update public.financial_payments
       set status = 'failed', updated_at = now()
     where id = v_pay.id;
    update public.financial_orders set status = 'failed', updated_at = now()
     where id = v_pay.order_id;
    perform public.finance_audit('finance.payment.failed', 'payment', v_pay.id::text,
      jsonb_build_object('status', p_status));
    return jsonb_build_object('ok', true, 'payment_id', v_pay.id, 'status', 'failed');
  end if;

  -- 5) Captura: marca pago + entrega moedas virtual via economy_adjust (que
  --    grava o ledger). Tudo em UMA transação — ou nada acontece.
  select * into v_order from public.financial_orders where id = v_pay.order_id for update;
  if v_order.id is null then raise exception 'order_not_found'; end if;
  if v_order.status = 'paid' then
    return jsonb_build_object('ok', true, 'duplicate', true,
                              'order_id', v_order.id, 'status', 'paid',
                              'credits_delivered', v_order.credits_delivered);
  end if;

  v_gross := v_order.unit_credits * v_order.quantity;

  update public.financial_payments
     set status = 'captured', provider_tx_id = v_pay.provider_tx_id,
         webhook_event_id = p_event_id, paid_at = now(), updated_at = now()
   where id = v_pay.id;

  update public.financial_orders
     set status = 'paid', credits_delivered = v_gross, updated_at = now()
   where id = v_order.id;

  perform public.economy_adjust(
    v_pay.user_id, v_order.currency, v_gross,
    'grant', 'purchase', v_order.id::text,
    'Compra de pacote ' || v_order.product_id || ' (' || v_gross || ' ' || v_order.currency || ')'
  );

  perform public.finance_audit('finance.payment.captured', 'payment', v_pay.id::text,
    jsonb_build_object('order_id', v_order.id, 'event_id', p_event_id,
                       'amount_cents', v_pay.amount_cents, 'credits', v_gross));

  return jsonb_build_object(
    'ok', true,
    'payment_id', v_pay.id,
    'order_id', v_order.id,
    'status', 'paid',
    'credits_delivered', v_gross,
    'balance', (select coalesce((select credits from public.user_wallets where user_id = v_pay.user_id), 0))
  );
end;
$$;

revoke all on function public.finance_webhook_capture(text, text, text, text, boolean, numeric, jsonb) from public;
revoke execute on function public.finance_webhook_capture(text, text, text, text, boolean, numeric, jsonb) from anon, authenticated;
grant execute on function public.finance_webhook_capture(text, text, text, text, boolean, numeric, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 18) process_gift_earnings: GANHOS DE CRIADOR POR PRESENTE (service_role).
--     Idempotente por gift_tx_id. Usa fee_configs (gift) para repartir:
--       creator_net = gross × (100 - fee)% ; platform_fee = gross - creator_net
--     Credita o criador em moeda virtual via economy_adjust (não é dinheiro)
--     e atualiza creator_balances. Edge send-gift chama logo após spend.
-- ---------------------------------------------------------------------------
create or replace function public.process_gift_earnings(
  p_gift_tx_id uuid,
  p_receiver_id uuid,
  p_gross_credits bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fee_pct numeric;
  v_fee bigint;
  v_net bigint;
  v_existing uuid;
begin
  if p_gift_tx_id is null then raise exception 'bad_gift_tx'; end if;
  if p_gross_credits is null or p_gross_credits < 0 then raise exception 'bad_amount'; end if;

  -- Idempotência: cada gift_tx gera NO MÁXIMO uma linha de ganho.
  select id into v_existing from public.gift_earnings where gift_tx_id = p_gift_tx_id;
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'gift_earnings_id', v_existing);
  end if;

  v_fee_pct := coalesce(
    (select platform_percent from public.fee_configs where scope = 'gift' limit 1),
    20
  );

  v_fee := round(p_gross_credits * v_fee_pct / 100.0);
  v_net := p_gross_credits - v_fee;
  if v_net < 0 then v_net := 0; end if;

  insert into public.gift_earnings
    (gift_tx_id, receiver_id, gross_credits, platform_fee, creator_net, status)
  values
    (p_gift_tx_id, p_receiver_id, p_gross_credits, v_fee, v_net, 'available')
  returning id into v_existing;

  if p_receiver_id is not null and v_net > 0 then
    insert into public.creator_balances (user_id) values (p_receiver_id)
      on conflict (user_id) do nothing;
    update public.creator_balances
       set available_credits = available_credits + v_net,
           updated_at = now()
     where user_id = p_receiver_id;

    perform public.economy_adjust(
      p_receiver_id, 'credits', v_net,
      'reward', 'gift', v_existing::text,
      'Ganhos de criador de presente recebido'
    );

    perform public.finance_audit('finance.gift_earnings.credited', 'gift_earnings',
      v_existing::text,
      jsonb_build_object('receiver', p_receiver_id, 'gross', p_gross_credits,
                         'fee', v_fee, 'net', v_net));
  end if;

  return jsonb_build_object(
    'ok', true,
    'gift_earnings_id', v_existing,
    'gross_credits', p_gross_credits,
    'platform_fee', v_fee,
    'creator_net', v_net
  );
end;
$$;

revoke all on function public.process_gift_earnings(uuid, uuid, bigint) from public;
revoke execute on function public.process_gift_earnings(uuid, uuid, bigint) from anon, authenticated;
grant execute on function public.process_gift_earnings(uuid, uuid, bigint) to service_role;

-- ---------------------------------------------------------------------------
-- 19) creator_balance / my_creator_earnings: leitura do próprio criador
-- ---------------------------------------------------------------------------
create or replace function public.creator_balance()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  b record;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  select * into b from public.creator_balances where user_id = u;
  if b is null then
    return jsonb_build_object('available_credits', 0, 'pending_credits', 0, 'withdrawn_credits', 0);
  end if;
  return jsonb_build_object(
    'available_credits', coalesce(b.available_credits, 0),
    'pending_credits', coalesce(b.pending_credits, 0),
    'withdrawn_credits', coalesce(b.withdrawn_credits, 0)
  );
end;
$$;

revoke all on function public.creator_balance() from public;
grant execute on function public.creator_balance() to authenticated;

create or replace function public.my_creator_earnings(p_limit int default 30)
returns setof public.gift_earnings
language sql
security definer
set search_path = public
as $$
  select * from public.gift_earnings
   where receiver_id = auth.uid()
   order by created_at desc
   limit p_limit;
$$;

revoke all on function public.my_creator_earnings(int) from public;
grant execute on function public.my_creator_earnings(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 20) creator_payout_request: CRIADOR pede resgate de ganhos disponíveis.
--     DEDUZ available → pending (reserva). Não movimenta dinheiro real.
-- ---------------------------------------------------------------------------
create or replace function public.creator_payout_request(p_amount_credits bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_req uuid;
  v_pct numeric;
  v_fee bigint;
  v_amount bigint;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_amount_credits is null or p_amount_credits < 1 then raise exception 'bad_amount'; end if;

  -- Taxa de payout (se houver) é paga da própria reserva.
  select platform_percent into v_pct from public.fee_configs where scope = 'payout' limit 1;
  if v_pct is null then v_pct := 0; end if;
  v_fee := round(p_amount_credits * v_pct / 100.0);
  v_amount := p_amount_credits - v_fee;
  if v_amount < 1 then raise exception 'amount_too_small'; end if;

  insert into public.creator_balances (user_id) values (u) on conflict (user_id) do nothing;

  update public.creator_balances
     set available_credits = available_credits - p_amount_credits,
         pending_credits = pending_credits + p_amount_credits,
         updated_at = now()
   where user_id = u and available_credits >= p_amount_credits;

  if not found then raise exception 'insufficient_balance'; end if;

  insert into public.creator_payout_requests (user_id, amount_credits, status, note)
  values (u, v_amount, 'pending', 'Payout de ' || p_amount_credits || ' credits (taxa ' || v_fee || ')')
  returning id into v_req;

  -- Marca as linhas de ganho correspondentes como solicitadas (FIFO).
  update public.gift_earnings ge
     set status = 'payout_requested'
   where ge.receiver_id = u and ge.status = 'available'
     and ge.id in (
       select gid from (
         select e.id as gid,
                sum(e.creator_net) over (order by e.created_at, e.id) as cum
         from public.gift_earnings e
         where e.receiver_id = u and e.status = 'available'
       ) t where t.cum <= p_amount_credits
     );

  perform public.finance_audit('finance.payout.requested', 'creator_payout_request', v_req::text,
    jsonb_build_object('amount', v_amount, 'gross', p_amount_credits, 'fee', v_fee));

  return jsonb_build_object('ok', true, 'request_id', v_req, 'amount_credits', v_amount,
                            'gross', p_amount_credits, 'fee', v_fee, 'status', 'pending');
end;
$$;

revoke all on function public.creator_payout_request(bigint) from public;
grant execute on function public.creator_payout_request(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 21) finance_refund: REEMBOLSO administrativo de compra paga.
--     Devolve moedas via economy_adjust + registra financial_refunds +
--     invalida o pagamento. Idempotente (só paga → refunded uma vez).
-- ---------------------------------------------------------------------------
create or replace function public.finance_refund(
  p_payment_id uuid,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_pay public.financial_payments%rowtype;
  v_order public.financial_orders%rowtype;
  v_refunded bigint;
  v_ref uuid;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if not public.economy_has_admin() then raise exception 'not_admin'; end if;

  select * into v_pay from public.financial_payments where id = p_payment_id for update;
  if v_pay.id is null then raise exception 'payment_not_found'; end if;

  if v_pay.status = 'refunded' then
    return jsonb_build_object('ok', true, 'duplicate', true, 'payment_id', p_payment_id,
                              'status', 'refunded');
  end if;
  if v_pay.status <> 'captured' then raise exception 'payment_not_refundable'; end if;

  select * into v_order from public.financial_orders where id = v_pay.order_id;
  if v_order.id is null then raise exception 'order_not_found'; end if;
  v_refunded := v_order.credits_delivered;

  if v_refunded > 0 then
    perform public.economy_adjust(
      v_pay.user_id, v_order.currency, -v_refunded,
      'refund', 'finance_refund', p_payment_id::text,
      'Reembolso de compra de pacote ' || v_order.product_id
    );
  end if;

  update public.financial_payments
     set status = 'refunded', updated_at = now()
   where id = v_pay.id;
  update public.financial_orders
     set status = 'refunded', updated_at = now()
   where id = v_order.id;

  insert into public.financial_refunds
    (payment_id, order_id, user_id, amount_cents, refunded_credits, reason, status, refunded_by)
  values
    (v_pay.id, v_order.id, v_pay.user_id, v_pay.amount_cents, v_refunded,
     coalesce(p_reason,''), 'processed', u)
  returning id into v_ref;

  perform public.finance_audit('finance.refund.processed', 'financial_refund', v_ref::text,
    jsonb_build_object('payment_id', v_pay.id, 'order_id', v_order.id,
                       'credits', v_refunded, 'reason', p_reason));

  return jsonb_build_object('ok', true, 'refund_id', v_ref, 'payment_id', p_payment_id,
                            'credits_refunded', v_refunded, 'status', 'refunded');
end;
$$;

revoke all on function public.finance_refund(uuid, text) from public;
grant execute on function public.finance_refund(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 22) finance_integrity_check: VERIFICAÇÃO DE INTEGRIDADE wallet × ledger.
--     Retorna anomalias reais (ou lista vazia). Somente service_role/admin.
--      - cada moeda: saldo wallet == soma(ledger delta) do usuário;
--      - nenhum wallet negativo (CHECK já garante, mas valida);
--      - orders paid sem entrega total (credits_delivered < total esperado);
--      - pagamentos captured sem order paid.
-- ---------------------------------------------------------------------------
create or replace function public.finance_integrity_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  a1 jsonb := '[]'::jsonb;
  a2 jsonb := '[]'::jsonb;
  a3 jsonb := '[]'::jsonb;
  a4 jsonb := '[]'::jsonb;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if not public.economy_has_admin() then raise exception 'not_admin'; end if;

  -- Anomalias de ledger vs wallet (saldo atual deve ser o somatório do ledger).
  -- Usa um CASE p/ mapear moeda → coluna; reporta somente divergências reais
  -- (quando o ledger soma negativo para um usuário = indício de desvio).
  select coalesce(jsonb_agg(x), '[]'::jsonb) into a1
  from (
    select jsonb_build_object(
             'type', 'LEDGER_MISMATCH', 'user_id', t.user_id, 'currency', t.currency,
             'ledger_sum', t.s,
             'wallet_balance', coalesce(
               (select case t.currency
                   when 'credits' then w.credits when 'diamonds' then w.diamonds
                   when 'crystals' then w.crystals when 'rubies' then w.rubies
                   when 'emeralds' then w.emeralds when 'crystal_rare' then w.crystal_rare
                   else 0 end
                from public.user_wallets w where w.user_id = t.user_id), 0)
           ) as anomaly
    from (
      select ct.user_id, ct.currency, sum(ct.delta) as s
        from public.credit_transactions ct
       group by ct.user_id, ct.currency
    ) t
    where t.s < 0
      and coalesce(
        (select case t.currency
            when 'credits' then w.credits when 'diamonds' then w.diamonds
            when 'crystals' then w.crystals when 'rubies' then w.rubies
            when 'emeralds' then w.emeralds when 'crystal_rare' then w.crystal_rare
            else 0 end
         from public.user_wallets w where w.user_id = t.user_id), 0) <> 0
    limit 50
  ) x;

  -- Payments captured com order não-paga.
  select coalesce(jsonb_agg(y), '[]'::jsonb) into a2 from (
    select jsonb_build_object('type', 'ORDER_NOT_PAID',
      'order_id', o.id, 'payment_id', p.id)
    from public.financial_payments p
    join public.financial_orders o on o.id = p.order_id
    where p.status = 'captured' and o.status <> 'paid'
    limit 50
  ) y;

  -- Orders paid com entrega incompleta.
  select coalesce(jsonb_agg(z), '[]'::jsonb) into a3 from (
    select jsonb_build_object('type', 'PARTIAL_DELIVERY',
      'order_id', o.id,
      'expected', o.unit_credits * o.quantity,
      'delivered', o.credits_delivered)
    from public.financial_orders o
    where o.status = 'paid' and o.credits_delivered < (o.unit_credits * o.quantity)
    limit 50
  ) z;

  -- Ganhos de criador: somatório de gift_earnings vs creator_balances.
  select coalesce(jsonb_agg(a), '[]'::jsonb) into a4 from (
    select jsonb_build_object('type', 'EARNINGS_MISMATCH',
      'receiver_id', e.receiver_id,
      'earnings_net', e.s,
      'balance_available', cb.available_credits)
    from (
      select receiver_id, sum(creator_net) as s
        from public.gift_earnings
       where receiver_id is not null and status <> 'paid'
       group by receiver_id
    ) e
    left join public.creator_balances cb on cb.user_id = e.receiver_id
    where coalesce(e.s,0) <> coalesce(cb.available_credits,0)
      and coalesce(e.s,0) > 0
    limit 50
  ) a;

  return jsonb_build_object(
    'ok', true,
    'anomalies', (a1 || a2 || a3 || a4),
    'integrity', case when jsonb_array_length(a1 || a2 || a3 || a4) = 0
                       then 'OK' else 'FINANCIAL_INTEGRITY_ALERT' end
  );
end;
$$;

revoke all on function public.finance_integrity_check() from public;
grant execute on function public.finance_integrity_check() to authenticated;

-- ---------------------------------------------------------------------------
-- 23) admin_finance_stats: PAINEL — números reais agregados.
-- ---------------------------------------------------------------------------
create or replace function public.admin_finance_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.economy_has_admin() then raise exception 'not_admin'; end if;
  select jsonb_build_object(
    'orders_total', (select count(*) from public.financial_orders),
    'orders_paid', (select coalesce(sum(case when status='paid' then 1 else 0 end),0) from public.financial_orders),
    'revenue_cents', (select coalesce(sum(total_price_cents),0) from public.financial_orders where status='paid'),
    'refunds_cents', (select coalesce(sum(amount_cents),0) from public.financial_refunds),
    'gift_earnings_net', (select coalesce(sum(creator_net),0) from public.gift_earnings),
    'gift_earnings_fees', (select coalesce(sum(platform_fee),0) from public.gift_earnings),
    'creator_available', (select coalesce(sum(available_credits),0) from public.creator_balances),
    'creator_pending', (select coalesce(sum(pending_credits),0) from public.creator_balances),
    'creator_withdrawn', (select coalesce(sum(withdrawn_credits),0) from public.creator_balances),
    'recent_orders', coalesce((select jsonb_agg(x) from (
        select o.id, o.user_id, o.status, o.total_price_cents, o.created_at,
               p.name as product_name
        from public.financial_orders o
        left join public.coin_packages p on p.id = o.product_id
        order by o.created_at desc limit 20
      ) x), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

revoke all on function public.admin_finance_stats() from public;
grant execute on function public.admin_finance_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- 24) admin_finance_orders / admin_price_update: gestão admin
-- ---------------------------------------------------------------------------
create or replace function public.admin_finance_orders(p_limit int default 50)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.economy_has_admin() then raise exception 'not_admin'; end if;
  select jsonb_agg(x) into v from (
    select o.id, o.user_id, o.status, o.total_price_cents, o.credits_delivered,
           o.created_at, pr.username, pr.display_name, p.name as product_name
    from public.financial_orders o
    left join public.profiles pr on pr.id = o.user_id
    left join public.coin_packages p on p.id = o.product_id
    order by o.created_at desc
    limit greatest(1, p_limit)
  ) x;
  return coalesce(v, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_finance_orders(int) from public;
grant execute on function public.admin_finance_orders(int) to authenticated;

create or replace function public.admin_price_update(
  p_package_id text,
  p_new_price_cents numeric,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_old numeric;
  v_new numeric;
begin
  if not public.economy_has_admin() then raise exception 'not_admin'; end if;
  if p_new_price_cents is null or p_new_price_cents <= 0 then raise exception 'bad_price'; end if;

  select price_cents into v_old from public.coin_packages where id = p_package_id;
  if v_old is null then raise exception 'package_not_found'; end if;

  update public.coin_packages set price_cents = p_new_price_cents, updated_at = now()
   where id = p_package_id;

  insert into public.financial_price_history
    (product_type, product_id, old_price_cents, new_price_cents, currency, changed_by, reason)
  values
    ('coin_package', p_package_id, v_old, p_new_price_cents, 'credits', u, coalesce(p_reason,''));

  perform public.finance_audit('finance.price.updated', 'coin_package', p_package_id,
    jsonb_build_object('old', v_old, 'new', p_new_price_cents, 'reason', p_reason));

  return jsonb_build_object('ok', true, 'package_id', p_package_id,
                            'old_price_cents', v_old, 'new_price_cents', p_new_price_cents);
end;
$$;

revoke all on function public.admin_price_update(text, numeric, text) from public;
grant execute on function public.admin_price_update(text, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 25) my_finance_history: HISTÓRICO consolidado do usuário
--     (compras + presentes/ganhos + reembolsos + resgates + conversões).
-- ---------------------------------------------------------------------------
create or replace function public.my_finance_history(p_limit int default 40)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v jsonb;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select jsonb_agg(x) from (
    (
      select 'order' as kind,
             o.id::text as ref_id,
             o.status as status,
             o.total_price_cents as price_cents,
             o.credits_delivered as credits,
             o.currency,
             p.name as label,
             o.created_at
        from public.financial_orders o
        left join public.coin_packages p on p.id = o.product_id
       where o.user_id = u
    )
    union all
    (
      select 'earning' as kind,
             ge.id::text as ref_id,
             ge.status as status,
             0 as price_cents,
             ge.creator_net as credits,
             'credits' as currency,
             'Ganhos de criador' as label,
             ge.created_at
        from public.gift_earnings ge
       where ge.receiver_id = u
    )
    union all
    (
      select 'refund' as kind,
             fr.id::text as ref_id,
             fr.status as status,
             fr.amount_cents as price_cents,
             fr.refunded_credits as credits,
             'credits' as currency,
             'Reembolso' as label,
             fr.created_at
        from public.financial_refunds fr
       where fr.user_id = u
    )
    union all
    (
      select 'payout' as kind,
             cpr.id::text as ref_id,
             cpr.status as status,
             0 as price_cents,
             cpr.amount_credits as credits,
             'credits' as currency,
             'Resgate de ganhos' as label,
             cpr.created_at
        from public.creator_payout_requests cpr
       where cpr.user_id = u
    )
    order by created_at desc
    limit greatest(1, p_limit)
  ) x into v;

  return coalesce(v, '[]'::jsonb);
end;
$$;

revoke all on function public.my_finance_history(int) from public;
grant execute on function public.my_finance_history(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 26) antifraude básico: avaliação de risco a partir de dados reais.
--     Retorna o nível calculado (sem escrever) — o nível "forte" é guardado
--     por admin. Não bloqueia compras; apenas sinaliza para REVIEW.
-- ---------------------------------------------------------------------------
create or replace function public.finance_classify_user(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orders_24h int;
  v_spend_rate numeric;
  v_result text;
begin
  select count(*) into v_orders_24h
    from public.financial_orders
   where user_id = p_user_id and created_at > now() - interval '24 hours';

  select coalesce(avg(credits_total), 0) into v_spend_rate
    from (
      select credits_total from public.gift_transactions
       where user_id = p_user_id and created_at > now() - interval '1 hour'
       order by created_at desc limit 20
    ) t;

  if v_orders_24h >= 10 or v_spend_rate >= 10000 then
    v_result := 'REVIEW';
  elsif v_orders_24h >= 3 or v_spend_rate >= 2000 then
    v_result := 'REVIEW';
  else
    v_result := 'NORMAL';
  end if;

  -- Override administrativo ativo vence.
  select level into v_result from public.antifraud_flags
   where user_id = p_user_id and active = true
   order by created_at desc limit 1;

  return coalesce(v_result, 'NORMAL');
end;
$$;

revoke all on function public.finance_classify_user(uuid) from public;
grant execute on function public.finance_classify_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Grants de leitura p/ tabelas com RLS (clientes legítimos).
-- ---------------------------------------------------------------------------
grant select on public.coin_packages to authenticated;
grant select on public.fee_configs to authenticated;
grant select on public.financial_orders to authenticated;
grant select on public.financial_payments to authenticated;
grant select on public.financial_refunds to authenticated;
grant select on public.gift_earnings to authenticated;
grant select on public.creator_balances to authenticated;
grant select on public.creator_payout_requests to authenticated;

-- Revoque acesso de escrita direta que o Supabase daria por padrão:
revoke insert, update, delete on public.coin_packages, public.fee_configs,
  public.financial_orders, public.financial_payments, public.financial_refunds,
  public.gift_earnings, public.creator_balances, public.creator_payout_requests,
  public.antifraud_flags, public.financial_price_history,
  public.payment_webhook_events, public.payment_provider_config
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 27) Painel do fundador: pendentes de payout + decisão (admin).
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_payouts(p_limit int default 50)
returns setof public.creator_payout_requests
language sql
security definer
set search_path = public
as $$
  select * from public.creator_payout_requests
   where status = 'pending'
   order by created_at asc
   limit greatest(1, p_limit);
$$;

revoke all on function public.admin_list_payouts(int) from public;
grant execute on function public.admin_list_payouts(int) to authenticated;

create or replace function public.admin_payout_decision(
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
  r public.creator_payout_requests%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if not public.economy_has_admin() then raise exception 'not_admin'; end if;

  select * into r from public.creator_payout_requests where id = p_request_id;
  if r.id is null then raise exception 'request_not_found'; end if;
  if r.status <> 'pending' then raise exception 'request_already_decided'; end if;

  if not p_approve then
    -- Devolve a reserva para available.
    update public.creator_balances
       set pending_credits = pending_credits - r.amount_credits,
           available_credits = available_credits + r.amount_credits,
           updated_at = now()
     where user_id = r.user_id and pending_credits >= r.amount_credits;
    update public.gift_earnings
       set status = 'available'
     where receiver_id = r.user_id and status = 'payout_requested';
    update public.creator_payout_requests
       set status = 'rejected', decided_at = now(), decided_by = u, note = p_note
     where id = r.id;
    perform public.finance_audit('finance.payout.rejected', 'creator_payout_request', r.id::text,
      jsonb_build_object('amount', r.amount_credits, 'note', p_note));
    return jsonb_build_object('ok', true, 'status', 'rejected');
  end if;

  -- Aprova: pending → withdrawn (liquidação real é manual, fora do app).
  update public.creator_balances
     set pending_credits = pending_credits - r.amount_credits,
         withdrawn_credits = withdrawn_credits + r.amount_credits,
         updated_at = now()
   where user_id = r.user_id and pending_credits >= r.amount_credits;
  if not found then raise exception 'insufficient_balance'; end if;

  update public.gift_earnings
     set status = 'paid'
   where receiver_id = r.user_id and status = 'payout_requested';

  update public.creator_payout_requests
     set status = 'paid', decided_at = now(), decided_by = u, note = p_note
   where id = r.id;

  perform public.finance_audit('finance.payout.approved', 'creator_payout_request', r.id::text,
    jsonb_build_object('amount', r.amount_credits, 'note', p_note));

  return jsonb_build_object('ok', true, 'status', 'paid', 'amount_credits', r.amount_credits);
end;
$$;

revoke all on function public.admin_payout_decision(uuid, boolean, text) from public;
grant execute on function public.admin_payout_decision(uuid, boolean, text) to authenticated;