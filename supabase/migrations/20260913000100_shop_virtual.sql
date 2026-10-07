-- ============================================================================
-- KLAY K — LOJA VIRTUAL (cosméticos, boosts e itens de comunidade)
--
-- Greenfield: até aqui o app só tinha presentes (gifts) e loja física
-- (store_*). Não existia catálogo de itens virtuais compráveis, nem inventário
-- do usuário, nem equipamento de cosméticos. Migration ADITIVA e idempotente.
--
-- ARQUITETURA (segue as REGRAS DE OURO do financeiro):
--   1) Preço/quantidade recomputados no backend (security definer): o cliente
--      nunca escolhe o valor a debitar — só o item e a quantidade pedida.
--   2) Débito SEMPRE via update atômico por moeda (WHITELIST credits/diamonds/
--      crystals) + ledger em credit_transactions (mesmo padrão do process_gift
--      _spend / economy_adjust). Saldo nunca fica negativo.
--   3) Idempotência: request_id é "clamado" em shop_purchase_requests; retry
--      com o mesmo id reaproveita a compra (duplicate) — nunca debita 2x.
--   4) Inventário (user_items) e equipados (user_equipped): cliente só LÊ o
--      próprio (RLS). Toda escrita passa por RPC security definer.
--   5) Without fake data: nada de itens "grátis de mentira"; tudo custa moeda
--      virtual real da wallet (que vem de presentes/chests/missões ou compra).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- shop_items: CATÁLOGO de itens virtuais (configurável pelo backend).
-- `rarity` reutiliza as raridades dos presentes (comum…ultra) para render.
-- `price_currency` é uma das moedas da wallet (credits/diamonds/crystals).
-- `kind` define o comportamento: frame/entry_effect/badge são EQUIPÁVEIS
-- (slot único por usuário); boost e community são itens de posse (coleção).
-- ---------------------------------------------------------------------------
create table if not exists public.shop_items (
  id text primary key,
  kind text not null check (kind in ('frame','entry_effect','badge','boost','community')),
  name text not null,
  description text default '',
  icon text not null default '🛍️',
  rarity text not null default 'comum',
  price_units bigint not null check (price_units > 0),
  price_currency text not null default 'credits'
    check (price_currency in ('credits','diamonds','crystals')),
  is_active boolean not null default true,
  is_featured boolean not null default false,
  sort_order int not null default 0,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shop_items_kind_idx on public.shop_items (kind, is_active, sort_order);
create index if not exists shop_items_active_idx on public.shop_items (is_active, sort_order);

alter table public.shop_items enable row level security;
drop policy if exists "shop_items_select" on public.shop_items;
create policy "shop_items_select" on public.shop_items for select using (true);

-- ---------------------------------------------------------------------------
-- shop_purchase_requests: claim atômico de request_id (idempotência).
-- Cliente NUNCA escreve (RLS bloqueada).
-- ---------------------------------------------------------------------------
create table if not exists public.shop_purchase_requests (
  request_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text,
  quantity int,
  status text not null default 'claimed' check (status in ('claimed','done')),
  created_at timestamptz not null default now()
);

alter table public.shop_purchase_requests enable row level security;
-- Sem políticas: nenhum acesso direto pelo cliente.

-- ---------------------------------------------------------------------------
-- user_items: INVENTÁRIO (o que o usuário possui e quantos).
-- Escrita apenas via RPC security definer (shop_buy_item).
-- ---------------------------------------------------------------------------
create table if not exists public.user_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null references public.shop_items(id) on delete cascade,
  quantity int not null default 1 check (quantity >= 0),
  source text not null default 'purchase',
  acquired_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

alter table public.user_items enable row level security;
drop policy if exists "user_items_select" on public.user_items;
create policy "user_items_select" on public.user_items for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- user_equipped: cosmético equipado por slot (1 por slot).
-- Escrita apenas via RPC security definer (shop_equip_item / shop_unequip_slot).
-- ---------------------------------------------------------------------------
create table if not exists public.user_equipped (
  user_id uuid not null references auth.users(id) on delete cascade,
  slot text not null check (slot in ('frame','entry_effect','badge')),
  item_id text not null references public.shop_items(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (user_id, slot)
);

alter table public.user_equipped enable row level security;
drop policy if exists "user_equipped_select" on public.user_equipped;
create policy "user_equipped_select" on public.user_equipped for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- shop_buy_item: compra atômica + idempotente pelo CLIENTE autenticado.
--   * clama o request_id (on conflict) — retry com o mesmo id devolve duplicate
--     (nunca debita 2x); duplicate_in_progress → cliente gera novo id.
--   * valida item ativo e replica o preço no backend.
--   * debita a moeda correta (whitelist) com update atômico (saldo >= total).
--   * grava ledger (credit_transactions kind 'spend' ref shop_item*).
--   * incrementa o inventário (user_items).
-- ---------------------------------------------------------------------------
create or replace function public.shop_buy_item(
  p_item_id text,
  p_request_id text,
  p_quantity int default 1
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  it record;
  v_total bigint;
  v_balance bigint;
  v_claim record;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_request_id is null or length(p_request_id) < 8 then raise exception 'bad_request_id'; end if;
  if p_item_id is null or p_item_id = '' then raise exception 'item_required'; end if;
  if p_quantity <= 0 then raise exception 'invalid_quantity'; end if;

  insert into public.shop_purchase_requests (request_id, user_id, item_id, quantity)
  values (p_request_id, v_user, p_item_id, p_quantity)
  on conflict (request_id) do nothing;

  if not found then
    select item_id, quantity, status into v_claim
      from public.shop_purchase_requests
     where request_id = p_request_id;
    if v_claim.status = 'done' then
      return jsonb_build_object(
        'ok', true, 'duplicate', true,
        'item_id', v_claim.item_id, 'quantity', v_claim.quantity
      );
    end if;
    raise exception 'duplicate_in_progress';
  end if;

  select * into it from public.shop_items
   where id = p_item_id and is_active limit 1;
  if it is null then raise exception 'item_not_found'; end if;

  insert into public.user_wallets (user_id) values (v_user) on conflict (user_id) do nothing;

  v_total := it.price_units * p_quantity;
  case it.price_currency
    when 'credits' then
      update public.user_wallets
         set credits = credits - v_total, updated_at = now()
       where user_id = v_user and credits >= v_total
       returning credits into v_balance;
    when 'diamonds' then
      update public.user_wallets
         set diamonds = diamonds - v_total, updated_at = now()
       where user_id = v_user and diamonds >= v_total
       returning diamonds into v_balance;
    when 'crystals' then
      update public.user_wallets
         set crystals = crystals - v_total, updated_at = now()
       where user_id = v_user and crystals >= v_total
       returning crystals into v_balance;
    else
      raise exception 'bad_currency';
  end case;
  if v_balance is null then raise exception 'insufficient_funds'; end if;

  insert into public.credit_transactions
    (user_id, delta, balance_after, kind, ref_type, ref_id, note, currency)
  values
    (v_user, -v_total, v_balance, 'spend', 'shop_item', p_item_id,
     'Compra de ' || it.name || ' x' || p_quantity, it.price_currency);

  insert into public.user_items (user_id, item_id, quantity, source)
  values (v_user, p_item_id, p_quantity, 'purchase')
  on conflict (user_id, item_id) do update set
    quantity = public.user_items.quantity + excluded.quantity;

  update public.shop_purchase_requests
     set status = 'done'
   where request_id = p_request_id;

  return jsonb_build_object(
    'ok', true, 'duplicate', false,
    'item_id', p_item_id, 'quantity', p_quantity,
    'balance', v_balance, 'currency', it.price_currency
  );
end;
$$;

revoke all on function public.shop_buy_item(text, text, int) from public, anon;
grant execute on function public.shop_buy_item(text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- shop_equip_item / shop_unequip_slot: equipar/remover cosmético por slot.
-- Valida posse e compatibilidade kind → slot no backend.
-- ---------------------------------------------------------------------------
create or replace function public.shop_equip_item(
  p_item_id text,
  p_slot text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  it record;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  if list_position(array['frame','entry_effect','badge'], p_slot) is null then
    raise exception 'bad_slot';
  end if;

  select * into it from public.shop_items where id = p_item_id and is_active;
  if it is null then raise exception 'item_not_found'; end if;
  if it.kind is distinct from p_slot then
    raise exception 'slot_mismatch';
  end if;

  if not exists (
    select 1 from public.user_items
     where user_id = v_user and item_id = p_item_id and quantity > 0
  ) then
    raise exception 'not_owned';
  end if;

  insert into public.user_equipped (user_id, slot, item_id, updated_at)
  values (v_user, p_slot, p_item_id, now())
  on conflict (user_id, slot) do update set
    item_id = excluded.item_id, updated_at = now();

  return jsonb_build_object('ok', true, 'slot', p_slot, 'item_id', p_item_id);
end;
$$;

create or replace function public.shop_unequip_slot(
  p_slot text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  if list_position(array['frame','entry_effect','badge'], p_slot) is null then
    raise exception 'bad_slot';
  end if;
  delete from public.user_equipped where user_id = v_user and slot = p_slot;
  return jsonb_build_object('ok', true, 'slot', p_slot);
end;
$$;

revoke all on function public.shop_equip_item(text, text) from public, anon;
grant execute on function public.shop_equip_item(text, text) to authenticated;
revoke all on function public.shop_unequip_slot(text) from public, anon;
grant execute on function public.shop_unequip_slot(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Seeds: Loja virtual inicial (14 itens — molduras, entradas, badges, boost,
-- comunidade). Raridades seguem o catálogo de presentes (comum..ultra).
-- ---------------------------------------------------------------------------
insert into public.shop_items
  (id, kind, name, description, icon, rarity, price_units, price_currency, is_active, is_featured, sort_order, tags)
values
  -- Molduras (frame / slot frame)
  ('frame-neon-violeta', 'frame', 'Moldura Neon Violeta',
   'Borda neon roxa para seu avatar no app.', '🟣', 'especial', 250, 'diamonds',
   true, true, 1, '{"avatar","neon"}'),
  ('frame-galaxia-arh', 'frame', 'Moldura Galáxia A.R.H',
   'Moldura cósmica profunda da coleção A.R.H TECH.', '🌌', 'lendario', 2000, 'diamonds',
   true, true, 2, '{"avatar","premium"}'),
  ('frame-estrela-klayk', 'frame', 'Moldura Estrela KLAY K',
   'Moldura com a estrela oficial da marca.', '⭐', 'raro', 350, 'diamonds',
   true, false, 3, '{"avatar","klayk"}'),
  -- Efeitos de entrada (entry_effect / slot entry_effect)
  ('entry-brilhante', 'entry_effect', 'Entrada Brilhante',
   'Faíscas de luz ao entrar na live.', '✨', 'incomum', 150, 'credits',
   true, true, 4, '{"live","entry"}'),
  ('entry-portal-violeta', 'entry_effect', 'Entrada Portal Violeta',
   'Um portal roxo anuncia sua chegada na transmissão.', '🌀', 'epico', 900, 'diamonds',
   true, false, 5, '{"live","entry"}'),
  ('entry-dragao', 'entry_effect', 'Entrada Dragão do Céu',
   'Seu dragão celestial atravessa a tela ao entrar.', '🐉', 'lendario', 1800, 'diamonds',
   true, false, 6, '{"live","entry"}'),
  -- Badges (badge / slot badge)
  ('badge-early-klayk', 'badge', 'Early KLAY K',
   'Insígnia dos primeiros a chegarem à plataforma.', '🏆', 'raro', 500, 'credits',
   true, false, 7, '{"badge","founding"}'),
  ('badge-festa', 'badge', 'Festa KLAY K',
   'Insígnia de quem anima qualquer live.', '🎉', 'especial', 200, 'credits',
   true, true, 8, '{"badge","community"}'),
  ('badge-lenda-viva', 'badge', 'Lenda Viva',
   'A insígnia máxima dos grandes doadores.', '🔥', 'mitico', 1500, 'diamonds',
   true, false, 9, '{"badge","legendary"}'),
  -- Boosts (boost / posse)
  ('boost-comentario-destaque', 'boost', 'Destaque nos Comentários',
   'Seus comentários ganham destaque visual nas lives.', '📌', 'especial', 600, 'diamonds',
   true, false, 10, '{"boost","live"}'),
  ('boost-xp-1d', 'boost', 'Boost de XP (1 dia)',
   'Ganhe XP extra por atividade durante 1 dia.', '⚡', 'raro', 750, 'crystals',
   true, false, 11, '{"boost","xp"}'),
  -- Comunidade (community / posse)
  ('community-fan-club', 'community', 'Membro do Fan Club',
   'Mostra que você pertence à família KLAY K.', '💜', 'especial', 1000, 'diamonds',
   true, true, 12, '{"community","fan"}'),
  ('community-kit-criador', 'community', 'Kit Criador',
   'Pacote de ferramentas visuais para criadores.', '🎬', 'raro', 900, 'credits',
   true, false, 13, '{"community","creator"}'),
  ('community-escudo-arh', 'community', 'Escudo A.R.H',
   'Escudo colecionável da linha A.R.H TECH.', '🛡️', 'lendario', 2200, 'diamonds',
   true, false, 14, '{"community","premium"}')
on conflict (id) do update set
  kind = excluded.kind, name = excluded.name, description = excluded.description,
  icon = excluded.icon, rarity = excluded.rarity, price_units = excluded.price_units,
  price_currency = excluded.price_currency, is_active = excluded.is_active,
  is_featured = excluded.is_featured, sort_order = excluded.sort_order,
  updated_at = now();