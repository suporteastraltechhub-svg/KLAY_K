-- ===========================================================================
-- KLAY K — Loja / Marketplace
-- Categorias, produtos, carrinho, pedidos e vendedor.
-- Pede-se: catálogo público, carrinho do dono, pedidos por comprador/vendedor,
-- transações de estoque e notificação ao vendedor somente via RPCs.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- store_categories
-- ---------------------------------------------------------------------------
create table if not exists public.store_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text not null default '📦',
  slug text not null unique,
  sort_order int not null default 0,
  active bool not null default true
);

insert into public.store_categories (name, icon, slug, sort_order) values
  ('Roupas', '👕', 'roupas', 1),
  ('Acessórios', '👜', 'acessorios', 2),
  ('Eletrônicos', '📱', 'eletronicos', 3),
  ('Decoração', '🖼️', 'decoracao', 4),
  ('Maquiagem', '💄', 'maquiagem', 5),
  ('Esporte', '⚽', 'esporte', 6),
  ('Outros', '📦', 'outros', 7)
on conflict (slug) do nothing;

alter table public.store_categories enable row level security;
drop policy if exists "store_categories_select_all" on public.store_categories;
create policy "store_categories_select_all" on public.store_categories
  for select using (true);

-- ---------------------------------------------------------------------------
-- store_products
-- ---------------------------------------------------------------------------
create table if not exists public.store_products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '',
  price numeric(10,2) not null check (price >= 0),
  image_url text not null default '',
  category_id uuid references public.store_categories(id) on delete set null,
  stock int not null default 0 check (stock >= 0),
  featured bool not null default false,
  is_active bool not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists store_products_category_idx on public.store_products (category_id);
create index if not exists store_products_seller_idx on public.store_products (seller_id, created_at desc);
create index if not exists store_products_active_idx on public.store_products (is_active, created_at desc);

alter table public.store_products enable row level security;
drop policy if exists "store_products_select" on public.store_products;
create policy "store_products_select" on public.store_products
  for select using (is_active = true or seller_id = auth.uid());
drop policy if exists "store_products_insert_owner" on public.store_products;
create policy "store_products_insert_owner" on public.store_products
  for insert with check (seller_id = auth.uid());
drop policy if exists "store_products_update_owner" on public.store_products;
create policy "store_products_update_owner" on public.store_products
  for update using (seller_id = auth.uid());
drop policy if exists "store_products_delete_owner" on public.store_products;
create policy "store_products_delete_owner" on public.store_products
  for delete using (seller_id = auth.uid());

-- ---------------------------------------------------------------------------
-- store_cart_items
-- ---------------------------------------------------------------------------
create table if not exists public.store_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  product_id uuid not null references public.store_products(id) on delete cascade,
  quantity int not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  constraint store_cart_items_user_product_key unique (user_id, product_id)
);

create index if not exists store_cart_items_user_idx on public.store_cart_items (user_id);

alter table public.store_cart_items enable row level security;
drop policy if exists "store_cart_items_owner_all" on public.store_cart_items;
create policy "store_cart_items_owner_all" on public.store_cart_items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- store_orders + store_order_items
-- ---------------------------------------------------------------------------
create table if not exists public.store_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  total numeric(10,2) not null default 0,
  status text not null default 'pendente'
    check (status in ('pendente', 'pago', 'enviado', 'concluido', 'cancelado')),
  shipping_name text not null default '',
  shipping_phone text not null default '',
  shipping_address text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists store_orders_user_idx on public.store_orders (user_id, created_at desc);
create index if not exists store_orders_seller_idx on public.store_orders (seller_id, created_at desc);

create table if not exists public.store_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.store_orders(id) on delete cascade,
  product_id uuid references public.store_products(id) on delete set null,
  title text not null,
  image_url text not null default '',
  unit_price numeric(10,2) not null,
  quantity int not null default 1 check (quantity > 0)
);

create index if not exists store_order_items_order_idx on public.store_order_items (order_id);

alter table public.store_orders enable row level security;
alter table public.store_order_items enable row level security;

-- Pedidos: comprador e vendedor enxergam.
drop policy if exists "store_orders_select_participant" on public.store_orders;
create policy "store_orders_select_participant" on public.store_orders
  for select using (user_id = auth.uid() or seller_id = auth.uid());
-- Vendedor (ou admin) atualiza status; comprador cancela via RPC.
drop policy if exists "store_orders_update_seller" on public.store_orders;
create policy "store_orders_update_seller" on public.store_orders
  for update using (seller_id = auth.uid() or public.is_klayk_admin());

-- Itens: somente participantes do pedido.
drop policy if exists "store_order_items_select_participant" on public.store_order_items;
create policy "store_order_items_select_participant" on public.store_order_items
  for select using (
    exists (
      select 1 from public.store_orders o
      where o.id = order_id
        and (o.user_id = auth.uid() or o.seller_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- updated_at automático
-- ---------------------------------------------------------------------------
create or replace function public.store_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists "store_products_set_updated_at" on public.store_products;
create trigger "store_products_set_updated_at" before update on public.store_products
for each row execute function public.store_set_updated_at();

drop trigger if exists "store_orders_set_updated_at" on public.store_orders;
create trigger "store_orders_set_updated_at" before update on public.store_orders
for each row execute function public.store_set_updated_at();

-- ---------------------------------------------------------------------------
-- View para listagem de pedidos com dados do vendedor/comprador.
-- security_invoker: mantém a RLS da tabela base.
-- ---------------------------------------------------------------------------
create or replace view public.store_orders_view
with (security_invoker = true) as
select
  o.id,
  o.user_id,
  o.seller_id,
  o.total,
  o.status,
  o.shipping_name,
  o.shipping_phone,
  o.shipping_address,
  o.created_at,
  o.updated_at,
  s.username  as seller_username,
  s.display_name as seller_display_name,
  b.username  as buyer_username,
  b.display_name as buyer_display_name
from public.store_orders o
left join public.profiles s on s.id = o.seller_id
left join public.profiles b on b.id = o.user_id;

grant select on public.store_orders_view to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPCs de transação (somente autenticado; escritas feitas com security definer)
-- ---------------------------------------------------------------------------

-- checkout_cart: agrupa itens do carrinho por vendedor, gera pedidos,
-- baixa estoque e notifica cada vendedor. Retorna os ids dos pedidos.
create or replace function public.checkout_cart(
  p_shipping_name text,
  p_shipping_phone text,
  p_shipping_address text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  u uuid := auth.uid();
  cart_item record;
  prod public.store_products%rowtype;
  oid uuid;
  order_ids uuid[] := '{}';
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_shipping_name is null or p_shipping_name = '' then
    raise exception 'missing_shipping_name';
  end if;
  if p_shipping_address is null or p_shipping_address = '' then
    raise exception 'missing_shipping_address';
  end if;

  for cart_item in
    select c.product_id, c.quantity
    from public.store_cart_items c
    where c.user_id = u
    order by c.created_at asc, c.id asc
  loop
    select * into prod from public.store_products p
    where p.id = cart_item.product_id and p.is_active = true
    for update;

    if prod.id is null then
      continue;
    end if;
    if prod.stock < cart_item.quantity then
      raise exception 'insufficient_stock: %', prod.title;
    end if;

    -- Reaproveita pedido "pendente" aberto com o mesmo vendedor.
    select o.id into oid
    from public.store_orders o
    where o.user_id = u and o.seller_id = prod.seller_id and o.status = 'pendente'
    order by o.created_at asc limit 1;

    if oid is null then
      oid := gen_random_uuid();
      insert into public.store_orders
        (id, user_id, seller_id, total, shipping_name, shipping_phone, shipping_address)
      values
        (oid, u, prod.seller_id, 0, p_shipping_name, p_shipping_phone, p_shipping_address);
      order_ids := order_ids || oid;
    end if;

    insert into public.store_order_items
      (order_id, product_id, title, image_url, unit_price, quantity)
    values
      (oid, prod.id, prod.title, coalesce(prod.image_url, ''), prod.price, cart_item.quantity);

    update public.store_products
    set stock = stock - cart_item.quantity
    where id = prod.id;

    update public.store_orders
    set total = round((total + (prod.price * cart_item.quantity))::numeric, 2),
        updated_at = now()
    where id = oid;

    insert into public.notifications (user_id, actor_id, type, ref_id, message)
    values (prod.seller_id, u, 'sale', oid::text, 'Nova venda no KLAY K');
  end loop;

  delete from public.store_cart_items where user_id = u;

  return jsonb_build_object(
    'order_ids', to_jsonb(order_ids),
    'count', coalesce(array_length(order_ids, 1), 0)
  );
end;
$$;

-- cancel_order: comprador (ou admin) cancela pedido pendente e devolve estoque.
create or replace function public.cancel_order(p_order_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  u uuid := auth.uid();
  o public.store_orders%rowtype;
  it public.store_order_items%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select * into o from public.store_orders where id = p_order_id;
  if o.id is null then raise exception 'order_not_found'; end if;
  if o.user_id <> u and not public.is_klayk_admin() then
    raise exception 'not_owner';
  end if;
  if o.status = 'cancelado' then return false; end if;
  if o.status not in ('pendente') then
    raise exception 'order_not_cancellable';
  end if;

  for it in select * from public.store_order_items where order_id = p_order_id loop
    update public.store_products set stock = stock + it.quantity where id = it.product_id;
  end loop;

  update public.store_orders set status = 'cancelado', updated_at = now()
  where id = p_order_id;
  return true;
end;
$$;

-- update_order_status: vendedor (ou admin) atualiza o status do pedido.
create or replace function public.update_order_status(p_order_id uuid, p_status text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  u uuid := auth.uid();
  o public.store_orders%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_status not in ('pendente', 'pago', 'enviado', 'concluido', 'cancelado') then
    raise exception 'invalid_status';
  end if;

  select * into o from public.store_orders where id = p_order_id;
  if o.id is null then raise exception 'order_not_found'; end if;
  if o.seller_id <> u and not public.is_klayk_admin() then
    raise exception 'not_seller';
  end if;

  update public.store_orders set status = p_status, updated_at = now()
  where id = p_order_id;
  return true;
end;
$$;

-- Grants: revoga de public/anon (por padrão o Supabase garante execute ao
-- público) e libera somente para autenticado.
revoke all on function public.checkout_cart(text, text, text) from public, anon;
grant execute on function public.checkout_cart(text, text, text) to authenticated;

revoke all on function public.cancel_order(uuid) from public, anon;
grant execute on function public.cancel_order(uuid) to authenticated;

revoke all on function public.update_order_status(uuid, text) from public, anon;
grant execute on function public.update_order_status(uuid, text) to authenticated;

-- Grants de tabelas (público com RLS).
grant select on public.store_categories to anon, authenticated;
grant select, insert, update, delete on public.store_products to authenticated;
grant select on public.store_products to anon;
grant select, insert, update, delete on public.store_cart_items to authenticated;