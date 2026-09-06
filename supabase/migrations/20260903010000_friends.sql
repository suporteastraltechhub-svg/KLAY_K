-- ============================================================================
-- KLAY K - Amizades
-- Sugestões de amizade e amigos em comum baseados no grafo real de `follows`
-- (nada de dados inventados). Reutiliza a tabela `follows` já existente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- friend_suggestions(p_user_id): sugestões "pessoas que você talvez conheça".
-- Computa, a partir do grafo real de follows:
--   * quem os usuários que você segue também seguem (2º grau),
--   * dando prioridade a quem tem mais conexões em comum (`mutual_count`),
-- excluindo você mesmo e quem você já segue.
-- Retorna o mesmo shape dos perfis (para o UserProfile.fromJson do app).
-- ---------------------------------------------------------------------------
create or replace function public.friend_suggestions(p_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  is_verified boolean,
  is_following boolean,
  mutual_count bigint
)
language sql
security definer
set search_path = public
as $$
  with target_follows as (
    select following_id
    from public.follows
    where follower_id = p_user_id
  ),
  candidate as (
    select f2.following_id as candidate_id, count(*)::bigint as mutual_count
    from public.follows f1
    join public.follows f2 on f2.follower_id = f1.following_id
    where f1.follower_id = p_user_id
      and f2.following_id <> p_user_id
    group by f2.following_id
  )
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.bio,
    coalesce(p.is_verified, false),
    exists (
      select 1 from public.follows f
      where f.follower_id = p_user_id and f.following_id = p.id
    ),
    c.mutual_count
  from candidate c
  join public.profiles p on p.id = c.candidate_id
  where c.candidate_id not in (select following_id from target_follows)
    and c.mutual_count >= 1
  order by c.mutual_count desc, p.username asc
  limit 30;
$$;

revoke all on function public.friend_suggestions(uuid) from public;
grant execute on function public.friend_suggestions(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- mutual_friends(p_user_id): pessoas com quem há relação recíproca
-- (você segue e ela segue você de volta) — os "amigos" reais do app.
-- ---------------------------------------------------------------------------
create or replace function public.mutual_friends(p_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  is_verified boolean,
  is_following boolean,
  followed_back boolean
)
language sql
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.bio,
    coalesce(p.is_verified, false),
    exists (
      select 1 from public.follows f
      where f.follower_id = p_user_id and f.following_id = p.id
    ) as is_following,
    exists (
      select 1 from public.follows f
      where f.follower_id = p.id and f.following_id = p_user_id
    ) as followed_back
  from public.follows f1
  join public.follows f2 on f2.follower_id = f1.following_id and f2.following_id = p_user_id
  join public.profiles p on p.id = f1.following_id
  where f1.follower_id = p_user_id
    and f1.following_id <> p_user_id
  order by p.username asc;
$$;

revoke all on function public.mutual_friends(uuid) from public;
grant execute on function public.mutual_friends(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- friend_counts(p_user_id): agrupamentos úteis para o hub de Amizades.
--  seguindo   = quantos o usuário segue
--  seguidores = quantos seguem o usuário
--  amigos     = quantos são mútuos (segue-de-volta)
--  convites   = quantos seguidores ele ainda não segue de volta (sugestão)
-- ---------------------------------------------------------------------------
create or replace function public.friend_counts(p_user_id uuid)
returns table (
  following bigint,
  followers bigint,
  friends bigint,
  invitees bigint
)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*) from public.follows where follower_id = p_user_id)::bigint as following,
    (select count(*) from public.follows where following_id = p_user_id)::bigint as followers,
    (select count(*)
       from public.follows f1
       join public.follows f2 on f2.follower_id = f1.following_id and f2.following_id = p_user_id
       where f1.follower_id = p_user_id)::bigint as friends,
    (select count(*)
       from public.follows where following_id = p_user_id
         and follower_id not in (select following_id from public.follows where follower_id = p_user_id)
         and follower_id <> p_user_id)::bigint as invitees;
$$;

revoke all on function public.friend_counts(uuid) from public;
grant execute on function public.friend_counts(uuid) to authenticated;