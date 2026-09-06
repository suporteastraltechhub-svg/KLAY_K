-- KLAY K — Fundador: lista de pedidos da Loja (painel administrativo).
create or replace function public.admin_list_orders()
returns table (
  id uuid, user_id uuid, seller_id uuid, total numeric, status text,
  buyer_username text, buyer_name text, seller_username text, seller_name text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select o.id, o.user_id, o.seller_id, o.total, o.status,
         o.buyer_username, o.buyer_display_name,
         o.seller_username, o.seller_display_name, o.created_at
  from store_orders_view o
  where (select public.is_klayk_admin())
  order by o.created_at desc
  limit 100
$$;

revoke execute on function public.admin_list_orders() from public, anon;
grant execute on function public.admin_list_orders() to authenticated;