-- =============================================================================
-- 20260831215000_users_profession_rankings.sql  (CORRIGIDA / idempotente)
-- -----------------------------------------------------------------------------
-- Motivo da correção: CREATE OR REPLACE FUNCTION NÃO consegue alterar o tipo
-- de retorno (OUT parameters) de uma função existente (ERRO 42P13). As funções
-- abaixo mudam RETURNS TABLE, então precisamos DROP FUNCTION primeiro.
--
-- 1) admin_list_users passa a retornar `profession` (add coluna -> DROP).
-- 2) admin_set_user_profession permite ATRIBUIR e REMOVER profissão usando ''
--    (a coluna profiles.profession é NOT NULL DEFAULT '' — NUNCA usar NULL).
-- 3) Rankings/leaderboards passam a expor `is_verified` (add coluna -> DROP):
--    - game_leaderboard (jogos)
--    - currency_ranking, live_top_supporters, live_ranking (moedas/lives)
-- Todos continuam `SECURITY DEFINER` com validação de acesso no backend.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Admin: listar usuários incluindo profissão
-- ---------------------------------------------------------------------------
drop function if exists public.admin_list_users();

create or replace function public.admin_list_users()
returns table (
  id uuid, username text, display_name text, avatar_url text,
  is_verified boolean, is_private boolean, is_admin boolean,
  profession text, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select u.id, u.username, u.display_name, u.avatar_url,
         u.is_verified, u.is_private, u.is_admin,
         coalesce(u.profession, '') as profession, u.created_at
  from profiles u
  where (select public.is_klayk_admin())
  order by u.created_at desc
  limit 200
$$;

revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Admin: atribuir/remover profissão de usuário
--    - p_profession vazio ('') REMOVE a profissão (profession = '').
--    - case contrário valida que a profissão está ativa e atribui.
--    (Não muda RETURNS TABLE -> CREATE OR REPLACE é suficiente.)
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_user_profession(p_user_id uuid, p_profession text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  -- '' ou NULL => remove (coluna é NOT NULL, então usa '').
  if coalesce(p_profession, '') = '' then
    update public.profiles set profession = '' where id = p_user_id;
  else
    if not exists (
      select 1 from public.professions
      where name = p_profession and status = 'active'
    ) then
      raise exception 'profession_not_active';
    end if;
    update public.profiles set profession = p_profession where id = p_user_id;
  end if;
  perform public.write_audit('profession.assign', 'profile', p_user_id::text,
    jsonb_build_object('profession', coalesce(p_profession, '')));
  return found;
end;
$$;

revoke all on function public.admin_set_user_profession(uuid,text)
  from public, anon;
grant execute on function public.admin_set_user_profession(uuid,text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Rankings com is_verified (DROP antes do CREATE — retorno muda)
-- ---------------------------------------------------------------------------

-- 3a) Leaderboard de jogos ---------------------------------------------------
drop function if exists public.game_leaderboard(text);
create or replace function public.game_leaderboard(p_game_id text)
returns table (
  rank int,
  user_id uuid,
  display_name text,
  username text,
  avatar_url text,
  best_score int,
  duration_seconds int,
  is_verified boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select row_number() over (order by gs.score desc, gs.duration_seconds asc)::int as rank,
           gs.user_id,
           coalesce(p.display_name, 'Participante') as display_name,
           coalesce(p.username, '') as username,
           p.avatar_url,
           gs.score::int,
           gs.duration_seconds::int,
           coalesce(p.is_verified, false) as is_verified
      from public.game_scores gs
      join public.profiles p on p.id = gs.user_id
     where gs.game_id = p_game_id
     order by gs.score desc, gs.duration_seconds asc
     limit 20;
end;
$$;

revoke all on function public.game_leaderboard(text) from public;
grant execute on function public.game_leaderboard(text) to authenticated;

-- 3b) Ranking global por moeda ------------------------------------------------
drop function if exists public.currency_ranking(text, int);
create or replace function public.currency_ranking(
  p_currency text,
  p_limit int default 20
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  value numeric,
  scope text,
  is_verified boolean
)
language plpgsql
security definer
set search_path = public
volatile
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_col text;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  case p_currency
    when 'credits' then v_col := 'credits';
    when 'diamonds' then v_col := 'diamonds';
    when 'crystals' then v_col := 'crystals';
    when 'rubies' then v_col := 'rubies';
    when 'emeralds' then v_col := 'emeralds';
    when 'crystal_rare' then v_col := 'crystal_rare';
    else raise exception 'bad_currency';
  end case;

  return query execute format(
    'select row_number() over (order by w.%I desc, p.created_at asc)::bigint as rank,
            w.user_id::uuid,
            p.username::text,
            p.display_name::text,
            p.avatar_url::text,
            w.%I::numeric as value,
            %L::text as scope,
            coalesce(p.is_verified, false)::boolean as is_verified
     from public.user_wallets w
     join public.profiles p on p.id = w.user_id
     where w.%I > 0
     order by w.%I desc, p.created_at asc
     limit $1',
    v_col, v_col, 'global', v_col, v_col
  ) using v_limit;
end;
$$;

revoke all on function public.currency_ranking(text, int) from public, anon;
grant execute on function public.currency_ranking(text, int) to authenticated;

-- 3c) Top apoiadores da live --------------------------------------------------
drop function if exists public.live_top_supporters(uuid, int);
create or replace function public.live_top_supporters(
  p_live_id uuid,
  p_limit int default 20
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  value numeric,
  scope text,
  is_verified boolean
)
language plpgsql
security definer
set search_path = public
volatile
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select row_number() over (
             order by sum(gt.credits_total) desc, min(gt.created_at) asc
           )::bigint as rank,
           gt.user_id,
           p.username,
           p.display_name,
           p.avatar_url,
           sum(gt.credits_total)::numeric as value,
           'live'::text as scope,
           coalesce(p.is_verified, false) as is_verified
    from public.gift_transactions gt
    join public.profiles p on p.id = gt.user_id
    where gt.live_id = p_live_id
    group by gt.user_id, p.username, p.display_name, p.avatar_url, p.is_verified
    order by value desc, min(gt.created_at) asc
    limit v_limit;
end;
$$;

revoke all on function public.live_top_supporters(uuid, int) from public, anon;
grant execute on function public.live_top_supporters(uuid, int) to authenticated;

-- 3d) Dispatch por moeda -------------------------------------------------------
drop function if exists public.live_ranking(uuid, text, int);
create or replace function public.live_ranking(
  p_live_id uuid,
  p_currency text,
  p_limit int default 20
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  value numeric,
  scope text,
  is_verified boolean
)
language plpgsql
security definer
set search_path = public
volatile
as $$
begin
  if p_currency = 'credits' then
    return query select * from public.live_top_supporters(p_live_id, p_limit);
  else
    return query select * from public.currency_ranking(p_currency, p_limit);
  end if;
end;
$$;

revoke all on function public.live_ranking(uuid, text, int) from public, anon;
grant execute on function public.live_ranking(uuid, text, int) to authenticated;
