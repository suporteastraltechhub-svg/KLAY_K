-- ============================================================================
-- KLAY K — Fundador + LIVE JOGANDO
-- Suporte ao modo "LIVE JOGANDO" (nome do jogo e capa) e ao Painel do Fundador
-- com RPCs administrativas validadas no backend (SEMPRE via is_klayk_admin()).
-- ============================================================================

-- 1) Lives: identificação do jogo (LIVE JOGANDO) e capa/miniatura.
alter table public.lives add column if not exists game_name text;
alter table public.lives add column if not exists cover_url text;

-- 2) Realtime do sistema de LIVE: lista de lives, chat, eventos e presentes.
do $$ begin
  alter publication supabase_realtime add table public.lives;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.live_chat;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.live_events;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.live_gifts;
exception when duplicate_object then null;
end $$;

-- ============================================================================
-- 3) Painel do Fundador — RPCs administrativas.
--    Todas re-executam o gate is_klayk_admin() no backend; um usuário comum
--    (mesmo alterando rotas/UI) NUNCA consegue dados administrativos.
-- ============================================================================

create or replace function public.admin_stats()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case when (select public.is_klayk_admin()) then (
    select jsonb_build_object(
      'users', (select count(*) from profiles),
      'new_users_7d', (select count(*) from profiles where created_at > now() - interval '7 days'),
      'videos', (select count(*) from posts),
      'lives', (select count(*) from lives),
      'active_lives', (select count(*) from lives where status = 'live'),
      'reports_pending', (select count(*) from reports where status in ('pending','reviewing')),
      'reports_resolved', (select count(*) from reports where status in ('resolved','dismissed')),
      'gift_transactions', (select count(*) from gift_transactions),
      'gift_credits', (select coalesce(sum(credits_total), 0) from gift_transactions),
      'orders', (select count(*) from store_orders),
      'orders_revenue', (select coalesce(sum(total), 0) from store_orders where status <> 'cancelado'),
      'recent_signups', (select coalesce(jsonb_agg(
          jsonb_build_object('id', t.id, 'username', t.username, 'display_name', t.display_name, 'created_at', t.created_at)
          order by t.created_at desc), '[]'::jsonb)
        from (select id, username, display_name, created_at from profiles order by created_at desc limit 8) t),
      'recent_reports', (select coalesce(jsonb_agg(
          jsonb_build_object('id', r.id, 'target_type', r.target_type, 'reason', r.reason, 'status', r.status, 'created_at', r.created_at)
          order by r.created_at desc), '[]'::jsonb)
        from (select id, target_type, reason, status, created_at from reports order by created_at desc limit 8) r)
    )
  ) else jsonb_build_object('not_admin', true) end
$$;

create or replace function public.admin_list_users()
returns table (
  id uuid, username text, display_name text, avatar_url text,
  is_verified boolean, is_private boolean, is_admin boolean, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select u.id, u.username, u.display_name, u.avatar_url,
         u.is_verified, u.is_private, u.is_admin, u.created_at
  from profiles u
  where (select public.is_klayk_admin())
  order by u.created_at desc
  limit 200
$$;

create or replace function public.admin_list_admins()
returns table (id uuid, username text, display_name text, is_admin boolean, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select u.id, u.username, u.display_name, u.is_admin, u.created_at
  from profiles u
  where u.is_admin and (select public.is_klayk_admin())
  order by u.created_at desc
$$;

create or replace function public.admin_set_verified(p_user_id uuid, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
  update profiles set is_verified = p_verified where id = p_user_id;
end;
$$;

create or replace function public.admin_set_admin(p_user_id uuid, p_admin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
  update profiles set is_admin = p_admin where id = p_user_id;
end;
$$;

create or replace function public.admin_store_stats()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case when (select public.is_klayk_admin()) then (
    select jsonb_build_object(
      'products', (select count(*) from store_products),
      'categories', (select count(*) from store_categories where active),
      'orders', (select count(*) from store_orders),
      'revenue', (select coalesce(sum(total), 0) from store_orders where status <> 'cancelado'),
      'by_status', (select coalesce(jsonb_object_agg(status, cnt), '{}'::jsonb)
        from (select status, count(*) cnt from store_orders group by status) s),
      'sellers', (select count(distinct seller_id) from store_products)
    )
  ) else jsonb_build_object('not_admin', true) end
$$;

create or replace function public.admin_gift_stats()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case when (select public.is_klayk_admin()) then (
    select jsonb_build_object(
      'transactions', (select count(*) from gift_transactions),
      'credits', (select coalesce(sum(credits_total), 0) from gift_transactions),
      'gifts', (select count(*) from gifts where status = 'active'),
      'top', (select coalesce(jsonb_agg(
          jsonb_build_object('id', g.gift_id, 'name', g.gift_name, 'count', g.sent_count)
          order by g.sent_count desc), '[]'::jsonb)
        from (select gift_id, gift_name, sum(amount) sent_count
              from gift_transactions group by gift_id, gift_name
              order by sent_count desc limit 10) g)
    )
  ) else jsonb_build_object('not_admin', true) end
$$;

create or replace function public.admin_live_stats()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case when (select public.is_klayk_admin()) then (
    select jsonb_build_object(
      'total', (select count(*) from lives),
      'active', (select count(*) from lives where status = 'live'),
      'active_list', (select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', l.id, 'title', l.title, 'category', coalesce(l.category, ''),
            'game_name', coalesce(l.game_name, ''),
            'streamer_display', p.display_name, 'streamer_username', p.username,
            'viewer_count', l.viewer_count, 'started_at', l.started_at)
          order by l.started_at desc), '[]'::jsonb)
        from lives l left join profiles p on p.id = l.streamer_id
        where l.status = 'live' limit 50)
    )
  ) else jsonb_build_object('not_admin', true) end
$$;

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

-- Nenhuma função administrativa é chamável por anônimos; somente usuários
-- logados, e mesmo assim o backend re-valida is_klayk_admin() dentro da função.
revoke execute on function public.admin_stats() from public, anon;
revoke execute on function public.admin_list_users() from public, anon;
revoke execute on function public.admin_list_admins() from public, anon;
revoke execute on function public.admin_set_verified(uuid, boolean) from public, anon;
revoke execute on function public.admin_set_admin(uuid, boolean) from public, anon;
revoke execute on function public.admin_store_stats() from public, anon;
revoke execute on function public.admin_gift_stats() from public, anon;
revoke execute on function public.admin_live_stats() from public, anon;
revoke execute on function public.admin_list_orders() from public, anon;

grant execute on function public.admin_stats() to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_list_admins() to authenticated;
grant execute on function public.admin_set_verified(uuid, boolean) to authenticated;
grant execute on function public.admin_set_admin(uuid, boolean) to authenticated;
grant execute on function public.admin_store_stats() to authenticated;
grant execute on function public.admin_gift_stats() to authenticated;
grant execute on function public.admin_live_stats() to authenticated;
grant execute on function public.admin_list_orders() to authenticated;