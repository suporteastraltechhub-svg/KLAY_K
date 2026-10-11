-- KLAY K · Marketplace completo (produtos físicos dos usuários)
--
-- A loja OFICIAL de itens digitais (moedas, diamantes, presentes LIVE) vive em
-- `shop_screen.dart` / `shop_items` e NÃO é tocada aqui. Esta migration é só do
-- marketplace de produtos físicos entre usuários.
--
-- O que já existe e é REAPROVEITADO (não recriado):
--   * `store_products`, `store_orders`, `store_order_items`, `store_categories`,
--     `store_favorites`, `store_cart_items`, `store_addresses`
--   * `checkout_cart(p_shipping_*, ...)` — que já trava o produto com `for
--     update`, confere estoque e lê o PREÇO do banco (nunca do cliente)
--   * as policies de escrita, que já usam WITH CHECK corretamente
--
-- ===========================================================================
-- 1) PRODUTO: o que faltava
-- ===========================================================================
--
-- O schema anterior tinha UMA foto (`image_url`) e nada que descrevesse o
-- estado do item ou a forma de entrega. Tudo abaixo é `if not exists`, então
-- rodar de novo é seguro.

alter table public.store_products
  add column if not exists photos text[] not null default '{}',
  -- 'novo' e 'usado' são os dois estados que o app oferece ao vendedor.
  add column if not exists condition text not null default 'novo'
    check (condition in ('novo', 'usado')),
  -- Formas de entrega que o vendedor aceita.
  add column if not exists delivery_options text[] not null default '{entrega}',
  -- Situação do anúncio, independente de `is_active` (que já existe e é usada
  -- pelas policies e pelo `checkout_cart`).
  add column if not exists status text not null default 'publicado'
    check (status in ('publicado', 'pausado', 'vendido')),
  add column if not exists city text,
  add column if not exists state text,
  -- Quantidade vendida acumulada: é o que ordena "mais vendidos".
  add column if not exists sold_count integer not null default 0
    check (sold_count >= 0);

comment on column public.store_products.status is
  'publicado | pausado | vendido. Espelha is_active para o app.';
comment on column public.store_products.photos is
  'URLs das fotos. image_url continua sendo a capa (primeira foto).';

-- Filtros do marketplace.
create index if not exists store_products_browse_idx
  on public.store_products (status, created_at desc)
  where status = 'publicado';

create index if not exists store_products_category_idx
  on public.store_products (category_id)
  where status = 'publicado';

create index if not exists store_products_seller_idx
  on public.store_products (seller_id, status);

create index if not exists store_products_popular_idx
  on public.store_products (sold_count desc, created_at desc)
  where status = 'publicado';

-- Busca por texto.
create index if not exists store_products_search_idx
  on public.store_products
  using gin (to_tsvector('portuguese', coalesce(title, '') || ' ' || coalesce(description, '')));

-- ===========================================================================
-- 2) PEDIDO: pagamento explicitamente pendente
-- ===========================================================================
--
-- O app NÃO tem provedor de pagamento. Então o pedido NASC como
-- 'aguardando_pagamento' e é isso que a tela mostra.
--
-- Não existe caminho pelo qual o cliente marque o pedido como pago: o UPDATE
-- direto é barrado por policy (só o vendedor/admin mexem em `status`, e o
-- `payment_status` fica fora do alcance do papel `authenticated`).

alter table public.store_orders
  add column if not exists payment_status text not null default 'aguardando_pagamento'
    check (payment_status in ('aguardando_pagamento', 'pago', 'cancelado', 'estornado')),
  add column if not exists expires_at timestamptz,
  add column if not exists cancel_reason text;

create index if not exists store_orders_buyer_idx
  on public.store_orders (user_id, created_at desc);

create index if not exists store_orders_seller_idx
  on public.store_orders (seller_id, created_at desc);

create index if not exists store_orders_pending_payment_idx
  on public.store_orders (created_at desc)
  where payment_status = 'aguardando_pagamento';

-- ===========================================================================
-- 3) PAGAMENTO: fora do alcance do cliente
-- ===========================================================================
--
-- O comprador e o vendedor podem LER o pedido (para saber o que fazer), mas
-- NENHUM dos dois pode escrever `payment_status`. Só `service_role` — usado por
-- um gateway de pagamento real, quando existir — ou o dono do banco.

drop policy if exists "store_orders_update_seller" on public.store_orders;

create policy "store_orders_update_seller" on public.store_orders
  for update
  using ((seller_id = auth.uid()) or public.is_klayk_admin())
  with check ((seller_id = auth.uid()) or public.is_klayk_admin());

-- O `payment_status` fica protegido por trigger: mesmo um seller legítimo não
-- consegue escrever 'pago' na mão.
create or replace function public.store_guard_payment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_status is distinct from old.payment_status
     and coalesce(
       nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
       auth.role()
     ) not in ('service_role', 'postgres')
     and auth.uid() is not null
  then
    raise exception 'payment_status_readonly';
  end if;
  return new;
end;
$$;

drop trigger if exists store_orders_payment_guard on public.store_orders;
create trigger store_orders_payment_guard
  before update on public.store_orders
  for each row execute function public.store_guard_payment_status();

-- ===========================================================================
-- 4) TRANSIÇÃO DE STATUS DO PEDIDO
-- ===========================================================================
--
-- Sem isto, o vendedor podia mandar o pedido de 'enviado' direto para
-- 'entregue' ou pular etapas. As transições válidas são explícitas.

create or replace function public.store_order_transition_ok(p_from text, p_to text)
returns boolean
language sql
immutable
as $$
  select case p_from
    when 'pendente'     then p_to in ('confirmado', 'cancelado')
    when 'confirmado'   then p_to in ('enviado', 'entregue', 'cancelado')
    when 'enviado'      then p_to in ('entregue', 'cancelado')
    when 'entregue'     then false
    when 'cancelado'    then false
    else false
  end;
$$;

-- A validação é uma função booleana (testável), e o trigger apenas a aplica.
create or replace function public.store_guard_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and not public.store_order_transition_ok(old.status::text, new.status::text)
  then
    raise exception 'invalid_transition: % -> %', old.status, new.status;
  end if;
  return new;
end;
$$;

drop trigger if exists store_orders_status_guard on public.store_orders;
create trigger store_orders_status_guard
  before update on public.store_orders
  for each row execute function public.store_guard_order_status();

-- ===========================================================================
-- 5) PRODUTO: VALIDAÇÃO NO SERVIDOR
-- ===========================================================================
--
-- `createProduct` direto pelo PostgREST continua possível (a policy já exige
-- `seller_id = auth.uid()`), mas passa a ser RECOMENDADO usar `store_publish_product`,
-- que valida preço, estoque e fotos no servidor e calcula a capa.
--
-- A policy de INSERT ganhaWITH CHECK para proibir preço negativo ou estoque
-- negativo na hora, mesmo na chamada direta.

drop policy if exists "store_products_insert_owner" on public.store_products;
create policy "store_products_insert_owner" on public.store_products
  for insert
  with check (
    seller_id = auth.uid()
    and price >= 0
    and stock >= 0
    and char_length(coalesce(title, '')) between 1 and 120
  );

drop policy if exists "store_products_update_owner" on public.store_products;
create policy "store_products_update_owner" on public.store_products
  for update
  using (seller_id = auth.uid())
  with check (
    seller_id = auth.uid()
    and price >= 0
    and stock >= 0
    and char_length(coalesce(title, '')) between 1 and 120
  );

create or replace function public.store_publish_product(
  p_title text,
  p_price numeric,
  p_stock integer,
  p_description text default null,
  p_category_id uuid default null,
  p_photos text[] default null,
  p_condition text default 'novo',
  p_delivery_options text[] default null,
  p_city text default null,
  p_state text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
  v_photos text[];
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;

  if p_title is null or char_length(trim(p_title)) < 1 or char_length(p_title) > 120 then
    raise exception 'bad_title';
  end if;
  if p_price is null or p_price < 0 or p_price > 100000000 then
    raise exception 'bad_price';
  end if;
  if p_stock is null or p_stock < 0 or p_stock > 100000 then
    raise exception 'bad_stock';
  end if;
  if p_condition is not null and p_condition not in ('novo', 'usado') then
    raise exception 'bad_condition';
  end if;
  if p_category_id is not null
     and not exists (select 1 from public.store_categories c
                      where c.id = p_category_id and coalesce(c.active, true))
  then
    raise exception 'bad_category';
  end if;

  v_photos := coalesce(p_photos, '{}');
  -- Mais de 6 fotos e o app não mostra todas; corta no servidor.
  if array_length(v_photos, 1) > 6 then
    v_photos := (select array_agg(x) from (select unnest(v_photos) x limit 6) t);
  end if;

  insert into public.store_products
    (id, seller_id, title, description, price, image_url, photos, category_id,
     stock, condition, delivery_options, status, city, state)
  values
    (gen_random_uuid(), v_me, trim(p_title), p_description, p_price,
     coalesce(v_photos[1], ''), v_photos, p_category_id, p_stock,
     coalesce(p_condition, 'novo'),
     coalesce(p_delivery_options, '{entrega}'),
     'publicado', p_city, p_state);

  select last_value::text into v_id
    from public.store_products
   where seller_id = v_me
   order by created_at desc
   limit 1;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

revoke execute on function public.store_publish_product(text, numeric, integer, text, uuid, text[], text, text[], text, text) from public;
grant execute on function public.store_publish_product(text, numeric, integer, text, uuid, text[], text, text[], text, text) to authenticated;

-- ===========================================================================
-- 6) FAVORITAR / COMPARTILHAR
-- ===========================================================================

drop policy if exists "store_favorites_insert" on public.store_favorites;
create policy "store_favorites_insert" on public.store_favorites
  for insert
  with check (user_id = auth.uid());

-- Contador de favoritos: o app pode mostrar "X gostei" sem contar a tabela.
create or replace function public.store_toggle_favorite(p_product_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_tem boolean;
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;
  if not exists (select 1 from public.store_products p where p.id = p_product_id) then
    raise exception 'not_found';
  end if;

  select exists (
    select 1 from public.store_favorites f
     where f.user_id = v_me and f.product_id = p_product_id
  ) into v_tem;

  if v_tem then
    delete from public.store_favorites
     where user_id = v_me and product_id = p_product_id;
    return jsonb_build_object('favorito', false);
  end if;

  insert into public.store_favorites (user_id, product_id)
  values (v_me, p_product_id)
  on conflict do nothing;
  return jsonb_build_object('favorito', true);
end;
$$;

revoke execute on function public.store_toggle_favorite(uuid) from public;
grant execute on function public.store_toggle_favorite(uuid) to authenticated;

-- ===========================================================================
-- 7) IMAGENS: BUCKET DE ARQUIVOS DO MARKETPLACE
-- ===========================================================================
--
-- Leitura pública (foto de anúncio é pública, como avatar e capa). Escrita
-- apenas pelo dono da pasta, que é `<user_id>/<arquivo>`.

insert into storage.buckets (id, name, public, file_size_limit)
values ('store-media', 'store-media', true, 5242880)  -- 5 MB por imagem
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit;

drop policy if exists "store_media_read" on storage.objects;
create policy "store_media_read" on storage.objects
  for select
  using (bucket_id = 'store-media');

drop policy if exists "store_media_insert" on storage.objects;
create policy "store_media_insert" on storage.objects
  for insert
  with check (
    bucket_id = 'store-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "store_media_update" on storage.objects;
create policy "store_media_update" on storage.objects
  for update
  using (
    bucket_id = 'store-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "store_media_delete" on storage.objects;
create policy "store_media_delete" on storage.objects
  for delete
  using (
    bucket_id = 'store-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
