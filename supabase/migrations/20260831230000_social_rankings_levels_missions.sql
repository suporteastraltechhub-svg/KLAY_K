-- =============================================================================
-- 20260831230000_social_rankings_levels_missions.sql
-- Ranking de NÍVEIS e de MISSÕES (novos), ambos com `is_verified`.
-- -----------------------------------------------------------------------------
-- - level_ranking  : usuários ranqueados pelo XP total acumulado (user_xp_log).
-- - mission_ranking: usuários ranqueados pelo XP ganho via missões.
-- - Tanto list_followers quanto list_following JÁ retornam is_verified (não
--   mudam aqui). Os rankings de jogos/moedas/lives foram tratados na migration
--   20260831215000 (DROP + CREATE, retorno mudou p/ incluir is_verified).
--
-- São funções NOVAS -> não precisam de DROP. Garantem acesso autenticado e
-- retornam apenas dados públicos (id, nome, avatar, XP/nível, is_verified).
-- =============================================================================

-- Ranking de níveis: mais XP total primeiro.
-- Na primeira versão a função não tinha `is_verified`; como o RETURNS TABLE
-- mudou, removemos a assinatura antiga antes de recriar (evita erro 42P13).
drop function if exists public.level_ranking(int);

create function public.level_ranking(p_limit int default 20)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  level int,
  xp_total bigint,
  is_verified boolean
)
language sql
security definer
set search_path = public
stable
as $$
  -- Soma o XP total acumulado por usuário (user_xp_log).
  with totals as (
    select p.id as user_id,
           p.username,
           coalesce(p.display_name, '') as display_name,
           p.avatar_url,
           p.is_verified,
           p.created_at,
           coalesce(sum(x.amount), 0)::bigint as xp_total
    from public.profiles p
    left join public.user_xp_log x on x.user_id = p.id
    group by p.id
  )
  -- Ordena por maior XP e calcula o nível usando a tabela `levels`.
  select row_number() over (order by t.xp_total desc, t.created_at asc)::bigint as rank,
         t.user_id,
         t.username,
         t.display_name,
         t.avatar_url,
         coalesce((
           select lv.level from public.levels lv
           where lv.xp_required <= t.xp_total
           order by lv.level desc limit 1
         ), 1)::int as level,
         t.xp_total,
         coalesce(t.is_verified, false) as is_verified
  from totals t
  order by t.xp_total desc, t.created_at asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

revoke all on function public.level_ranking(int) from public, anon;
grant execute on function public.level_ranking(int) to authenticated;

-- Ranking de missões: XP ganho exclusivamente via missões (source 'mission:%').
create or replace function public.mission_ranking(p_limit int default 20)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  missions_done bigint,
  xp_mission bigint,
  is_verified boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select row_number() over (order by sum(x.amount) desc, p.created_at asc)::bigint as rank,
         p.id as user_id,
         p.username,
         coalesce(p.display_name, '') as display_name,
         p.avatar_url,
         count(*)::bigint as missions_done,
         sum(x.amount)::bigint as xp_mission,
         coalesce(p.is_verified, false) as is_verified
  from public.user_xp_log x
  join public.profiles p on p.id = x.user_id
  where x.source like 'mission:%'
  group by p.id
  order by xp_mission desc, p.created_at asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

revoke all on function public.mission_ranking(int) from public, anon;
grant execute on function public.mission_ranking(int) to authenticated;
