-- KLAY K - Sistema completo de Perfil do Usuário.
--
-- Base de dados para a tela de perfil (próprio e alheio):
--   * novos campos no perfil (banner, site, localização, pronomes);
--   * contadores desnormalizados em `profiles` (segue, seguindo, posts)
--     mantidos por triggers (consulta O(1) em vez de COUNT() a cada tela);
--   * RPC `get_profile` (payload completo de um perfil em 1 round-trip);
--   * RPCs `profile_followers` / `profile_following` (listas com relação);
--   * grants de UPDATE para as colunas novas (mesmo padrão das existentes).
--
-- Nada aqui altera o fluxo de autenticação (Supabase Auth) ou o AppGate: o
-- trigger `handle_new_user` e as policies de `profiles` permanecem intactos.

-- ---------------------------------------------------------------------------
-- 1) Colunas novas em public.profiles
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists banner_url text,
  add column if not exists banner_path text,
  add column if not exists website text,
  add column if not exists location text,
  add column if not exists pronouns text,
  add column if not exists followers_count int not null default 0,
  add column if not exists following_count int not null default 0,
  add column if not exists posts_count int not null default 0,
  add column if not exists updated_at timestamptz;

-- updated_at automático em todo UPDATE de perfil.
create or replace function public.profiles_touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.profiles_touch_updated_at();

-- ---------------------------------------------------------------------------
-- 2) Contadores desnormalizados (segue / seguindo / posts)
-- ---------------------------------------------------------------------------
-- As funções são SECURITY DEFINER: o UPDATE de `profiles` é restrito por
-- grants de coluna ao dono, então a manutenção dos contadores não pode (nem
-- deve) passar pela RLS do usuário — roda como o dono da tabela.
create or replace function public.profile_bump_follow_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    update public.profiles
       set followers_count = followers_count + 1
     where id = NEW.following_id;
    update public.profiles
       set following_count = following_count + 1
     where id = NEW.follower_id;
  elsif TG_OP = 'DELETE' then
    update public.profiles
       set followers_count = greatest(followers_count - 1, 0)
     where id = OLD.following_id;
    update public.profiles
       set following_count = greatest(following_count - 1, 0)
     where id = OLD.follower_id;
  end if;
  return null;
end;
$$;

drop trigger if exists profile_bump_follow_ai on public.follows;
create trigger profile_bump_follow_ai
  after insert on public.follows
  for each row execute function public.profile_bump_follow_counts();

drop trigger if exists profile_bump_follow_ad on public.follows;
create trigger profile_bump_follow_ad
  after delete on public.follows
  for each row execute function public.profile_bump_follow_counts();

create or replace function public.profile_bump_post_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    update public.profiles
       set posts_count = posts_count + 1
     where id = NEW.user_id;
  elsif TG_OP = 'DELETE' then
    update public.profiles
       set posts_count = greatest(posts_count - 1, 0)
     where id = OLD.user_id;
  end if;
  return null;
end;
$$;

drop trigger if exists profile_bump_post_ai on public.posts;
create trigger profile_bump_post_ai
  after insert on public.posts
  for each row execute function public.profile_bump_post_counts();

drop trigger if exists profile_bump_post_ad on public.posts;
create trigger profile_bump_post_ad
  after delete on public.posts
  for each row execute function public.profile_bump_post_counts();

-- Backfill idempotente a partir do estado atual (dados antigos ficam certos).
update public.profiles p
   set followers_count = (
         select count(*) from public.follows f where f.following_id = p.id),
       following_count = (
         select count(*) from public.follows f where f.follower_id = p.id),
       posts_count = (
         select count(*) from public.posts x where x.user_id = p.id),
       updated_at = now();

-- ---------------------------------------------------------------------------
-- 3) RPC get_profile — perfil completo + agregados em um único round-trip
-- ---------------------------------------------------------------------------
create or replace function public.get_profile(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_profile jsonb;
  v_total_likes bigint;
  v_is_following boolean;
  v_is_self boolean;
begin
  v_is_self := auth.uid() is not null and auth.uid() = p_user_id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'banner_url', p.banner_url,
    'bio', p.bio,
    'website', p.website,
    'location', p.location,
    'pronouns', p.pronouns,
    'is_private', p.is_private,
    'is_verified', p.is_verified,
    'is_admin', p.is_admin,
    'role', p.role,
    'birth_date', case when v_is_self
                        then to_char(p.birth_date, 'YYYY-MM-DD')
                        else null end,
    'followers_count', p.followers_count,
    'following_count', p.following_count,
    'posts_count', p.posts_count,
    'created_at', p.created_at
  )
  into v_profile
  from public.profiles p
  where p.id = p_user_id;

  if v_profile is null then
    return null;
  end if;

  select coalesce(sum(p2.likes_count), 0)::bigint into v_total_likes
  from public.posts p2
  where p2.user_id = p_user_id;

  v_is_following := false;
  if not v_is_self then
    select exists (
      select 1 from public.follows f
      where f.follower_id = auth.uid() and f.following_id = p_user_id
    ) into v_is_following;
  end if;

  return v_profile
    || jsonb_build_object('total_likes', v_total_likes)
    || jsonb_build_object('is_following', v_is_following)
    || jsonb_build_object('is_self', v_is_self);
end;
$$;

grant execute on function public.get_profile(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) RPCs de listas — seguidores / seguindo (com relação do usuário atual)
-- ---------------------------------------------------------------------------
create or replace function public.profile_followers(p_user_id uuid)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  is_verified boolean, is_following boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return query
    select p.id, p.username, p.display_name, p.avatar_url, p.is_verified,
           exists (
             select 1 from public.follows f
             where f.follower_id = auth.uid() and f.following_id = p.id
           ) as is_following
    from public.follows f
    join public.profiles p on p.id = f.follower_id
    where f.following_id = p_user_id
    order by f.created_at desc
    limit 300;
end;
$$;

grant execute on function public.profile_followers(uuid) to anon, authenticated;

create or replace function public.profile_following(p_user_id uuid)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  is_verified boolean, is_following boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return query
    select p.id, p.username, p.display_name, p.avatar_url, p.is_verified,
           exists (
             select 1 from public.follows f
             where f.follower_id = auth.uid() and f.following_id = p.id
           ) as is_following
    from public.follows f
    join public.profiles p on p.id = f.following_id
    where f.follower_id = p_user_id
    order by f.created_at desc
    limit 300;
end;
$$;

grant execute on function public.profile_following(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) Grants de UPDATE para as colunas novas (mesmo padrão das já existentes:
--    o usuário só atualiza os próprios campos de perfil).
-- ---------------------------------------------------------------------------
grant update (banner_url, banner_path, website, location, pronouns)
  on table public.profiles to authenticated;