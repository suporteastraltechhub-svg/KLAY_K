-- ============================================================================
-- KLAY K - Criadores em ascensão (território Criadores em Ascensão)
-- Descobrimento de criadores com maior MOMENTUM (não magnitude) nos últimos
-- 7 dias: curtidas recebidas + novos seguidores + novos posts, ponderados.
-- Tudo derivado de tabelas existentes — nada de dados falsos.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- RPC: criadores em ascensão
-- score = 3*likes_7d + 2*followers_7d + 2*posts_7d
-- ---------------------------------------------------------------------------
create or replace function public.rising_creators(p_limit bigint default 20)
returns table (
  creator_id uuid,
  likes_7d bigint,
  followers_7d bigint,
  posts_7d bigint,
  score bigint
)
language sql
security definer
set search_path = public
as $$
  select
    coalesce(lp.creator_id, fr.creator_id, pp.creator_id) as creator_id,
    coalesce(lp.n, 0::bigint) as likes_7d,
    coalesce(fr.n, 0::bigint) as followers_7d,
    coalesce(pp.n, 0::bigint) as posts_7d,
    (3 * coalesce(lp.n, 0::bigint)) +
      (2 * coalesce(fr.n, 0::bigint)) +
      (2 * coalesce(pp.n, 0::bigint)) as score
  from (
    select p.user_id as creator_id, count(pl.*)::bigint as n
    from public.posts p
    join public.post_likes pl on pl.post_id = p.id
      and pl.created_at >= now() - interval '7 days'
    group by p.user_id
  ) lp
  full join (
    select f.following_id as creator_id, count(*)::bigint as n
    from public.follows f
    where f.created_at >= now() - interval '7 days'
    group by f.following_id
  ) fr on fr.creator_id = lp.creator_id
  full join (
    select p.user_id as creator_id, count(*)::bigint as n
    from public.posts p
    where p.created_at >= now() - interval '7 days'
    group by p.user_id
  ) pp on pp.creator_id = coalesce(lp.creator_id, fr.creator_id)
  where coalesce(lp.creator_id, fr.creator_id, pp.creator_id) is not null
  order by score desc
  limit p_limit;
$$;
revoke all on function public.rising_creators(bigint) from public;
grant execute on function public.rising_creators(bigint) to anon, authenticated;