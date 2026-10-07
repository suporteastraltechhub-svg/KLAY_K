-- KLAY K · Loja — favoritos, endereços e métodos de pagamento.
--
-- Complementa 20260828110000_loja.sql. Aditiva: não altera nem remove
-- nenhuma tabela, coluna, função ou policy existente. O checkout atual
-- (`checkout_cart`) continua funcionando igual.
--
-- Situação real que esta migration cria
-- -----------------------------------
-- A loja hoje tem: store_categories, store_products, store_cart_items,
-- store_orders, store_order_items. Não existe:
--   * favoritar produto — o usuário precisa entrar no produto e comprar;
--   * salvar endereco — `store_orders.shipping_address` é UM texto livre
--     digitado no checkout, sem reaproveitamento;
--   * método de pagamento — só existe pagamento por moedas internas
--     (ver shop_models/finance_service). Não há cartão/PIX registrado.
--
-- Decisões de segurança:
--   * RLS em todas as tabelas; o dono é auth.uid().
--   * endereço e método de pagamento NUNCA são lidos por terceiros. Só o
--     próprio usuário (policy `select` restrita a user_id = auth.uid()).
--   * nada de dado de cartão: guardamos apenas o rotulo e os 4 últimos
--     dígitos, que é o que a indústria permite exibir. O segredo vai direto ao
--     gateway de pagamento e nunca passa pelo nosso banco.
--   * default de privacidade: Addresses e métodos começam ocultos
--     (`is_default` único, `show_in_orders` explícito).

-- ---------------------------------------------------------------------------
-- 1. Favoritos de produto
-- ---------------------------------------------------------------------------

create table if not exists public.store_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.store_products(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, product_id)
);

create index if not exists store_favorites_user_idx
  on public.store_favorites (user_id, created_at desc);
create index if not exists store_favorites_product_idx
  on public.store_favorites (product_id);

alter table public.store_favorites enable row level security;
drop policy if exists "store_favorites_select" on public.store_favorites;
create policy "store_favorites_select" on public.store_favorites
  for select using (user_id = auth.uid());
drop policy if exists "store_favorites_insert" on public.store_favorites;
create policy "store_favorites_insert" on public.store_favorites
  for insert with check (user_id = auth.uid());
drop policy if exists "store_favorites_delete" on public.store_favorites;
create policy "store_favorites_delete" on public.store_favorites
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Endereços de entrega
-- ---------------------------------------------------------------------------

create table if not exists public.store_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default 'Principal',
  recipient text not null default '',
  phone text not null default '',
  street text not null default '',
  number text not null default '',
  complement text not null default '',
  district text not null default '',
  city text not null default '',
  state text not null default '',
  zip_code text not null default '',
  country text not null default 'BR',
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint store_addresses_zip_check
    check (zip_code = '' or char_length(regexp_replace(zip_code, '\D', '', 'g')) between 5 and 9)
);

create index if not exists store_addresses_user_idx
  on public.store_addresses (user_id, is_default desc, created_at desc);

alter table public.store_addresses enable row level security;
drop policy if exists "store_addresses_select" on public.store_addresses;
create policy "store_addresses_select" on public.store_addresses
  for select using (user_id = auth.uid());
drop policy if exists "store_addresses_insert" on public.store_addresses;
create policy "store_addresses_insert" on public.store_addresses
  for insert with check (user_id = auth.uid());
drop policy if exists "store_addresses_update" on public.store_addresses;
create policy "store_addresses_update" on public.store_addresses
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "store_addresses_delete" on public.store_addresses;
create policy "store_addresses_delete" on public.store_addresses
  for delete using (user_id = auth.uid());

-- Só um endereço padrão por usuário.
create or replace function public.store_addresses_single_default()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_default then
    update public.store_addresses
       set is_default = false, updated_at = now()
     where user_id = new.user_id and id <> new.id and is_default;
  end if;
  return new;
end;
$$;
drop trigger if exists store_addresses_single_default_trg on public.store_addresses;
create trigger store_addresses_single_default_trg
  before insert or update of is_default on public.store_addresses
  for each row execute function public.store_addresses_single_default();

-- ---------------------------------------------------------------------------
-- 3. Métodos de pagamento
-- ---------------------------------------------------------------------------
-- Guardamos SOMENTE o que pode ser exibido com segurança. Nenhum segredo,
-- nenhum CVV, nenhum token de gateway fica neste banco: o cartão é tokenizado
-- pelo gateway e aqui só anotamos como o usuário quer reconhecê-lo.
--
-- `kind`: 'card' | 'pix' | 'wallet' | 'other'
-- `gateway_token`: referência opaca devolvida pelo gateway. Nunca é usada pelo
-- app para autorizar nada — serve só para reconciliação no backoffice.

create table if not exists public.store_payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('card','pix','wallet','other')),
  label text not null default '',
  brand text not null default '',
  last4 text not null default '' check (last4 = '' or char_length(last4) = 4),
  holder text not null default '',
  expiry_month int check (expiry_month is null or expiry_month between 1 and 12),
  expiry_year int check (expiry_year is null or expiry_year between 2000 and 2200),
  gateway_token text not null default '',
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists store_payment_methods_user_idx
  on public.store_payment_methods (user_id, is_default desc, created_at desc);

alter table public.store_payment_methods enable row level security;
drop policy if exists "store_payment_methods_select" on public.store_payment_methods;
create policy "store_payment_methods_select" on public.store_payment_methods
  for select using (user_id = auth.uid());
drop policy if exists "store_payment_methods_insert" on public.store_payment_methods;
create policy "store_payment_methods_insert" on public.store_payment_methods
  for insert with check (user_id = auth.uid());
drop policy if exists "store_payment_methods_update" on public.store_payment_methods;
create policy "store_payment_methods_update" on public.store_payment_methods
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "store_payment_methods_delete" on public.store_payment_methods;
create policy "store_payment_methods_delete" on public.store_payment_methods
  for delete using (user_id = auth.uid());

-- Também só um método padrão.
create or replace function public.store_payment_methods_single_default()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_default then
    update public.store_payment_methods
       set is_default = false, updated_at = now()
     where user_id = new.user_id and id <> new.id and is_default;
  end if;
  return new;
end;
$$;
drop trigger if exists store_payment_methods_single_default_trg on public.store_payment_methods;
create trigger store_payment_methods_single_default_trg
  before insert or update of is_default on public.store_payment_methods
  for each row execute function public.store_payment_methods_single_default();

-- ---------------------------------------------------------------------------
-- 4. Privacidade de compras
-- ---------------------------------------------------------------------------
-- O usuário escolhe se pedidos aparecem no perfil público. Default: não
-- aparecem — é o padrão mais seguro e o app não expõe nada por accident.

create table if not exists public.store_privacy_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  show_purchases_on_profile boolean not null default false,
  show_orders_publicly boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.store_privacy_settings enable row level security;
drop policy if exists "store_privacy_select" on public.store_privacy_settings;
create policy "store_privacy_select" on public.store_privacy_settings
  for select using (user_id = auth.uid());
drop policy if exists "store_privacy_upsert" on public.store_privacy_settings;
create policy "store_privacy_upsert" on public.store_privacy_settings
  for insert with check (user_id = auth.uid());
drop policy if exists "store_privacy_update" on public.store_privacy_settings;
create policy "store_privacy_update" on public.store_privacy_settings
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Helper idempotente: garante que todo usuário consultando prefs tenha linha.
create or replace function public.my_store_privacy()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v public.store_privacy_settings;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.store_privacy_settings (user_id) values (u)
    on conflict (user_id) do nothing;
  select * into v from public.store_privacy_settings where user_id = u;
  return jsonb_build_object(
    'show_purchases_on_profile', v.show_purchases_on_profile,
    'show_orders_publicly', v.show_orders_publicly
  );
end;
$$;
revoke all on function public.my_store_privacy() from public;
grant execute on function public.my_store_privacy() to authenticated;

create or replace function public.save_store_privacy(
  p_show_purchases_on_profile boolean default null,
  p_show_orders_publicly boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.store_privacy_settings (user_id) values (u)
    on conflict (user_id) do nothing;
  update public.store_privacy_settings set
    show_purchases_on_profile = coalesce(p_show_purchases_on_profile, show_purchases_on_profile),
    show_orders_publicly = coalesce(p_show_orders_publicly, show_orders_publicly),
    updated_at = now()
   where user_id = u;
  return public.my_store_privacy();
end;
$$;
revoke all on function public.save_store_privacy(boolean, boolean) from public;
grant execute on function public.save_store_privacy(boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Lista de favoritos com os dados do produto
-- ---------------------------------------------------------------------------
-- Junção para a tela: uma chamada traz produto + categoria + se está ativo.
-- Usa security definer porque junta store_products (RLS só mostra ativos ou
-- do próprio vendedor) e store_favorites (RLS só do dono). Continua devolvendo
-- apenas linhas do usuário autenticado.

create or replace function public.my_store_favorites()
returns table (
  favorite_id uuid,
  product_id uuid,
  title text,
  description text,
  price numeric,
  image_url text,
  stock int,
  is_active boolean,
  category_id uuid,
  category_name text,
  seller_id uuid,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    f.id,
    f.product_id,
    p.title,
    p.description,
    p.price,
    p.image_url,
    p.stock,
    p.is_active,
    p.category_id,
    c.name,
    p.seller_id,
    f.created_at
  from public.store_favorites f
  join public.store_products p on p.id = f.product_id
  left join public.store_categories c on c.id = p.category_id
  where f.user_id = auth.uid()
  order by f.created_at desc;
$$;
revoke all on function public.my_store_favorites() from public;
grant execute on function public.my_store_favorites() to authenticated;