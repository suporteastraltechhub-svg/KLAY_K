-- ============================================================================
-- KLAY K — CONTROLES DE PRIVACIDADE (aditivo)
--
-- Regra desta migration: NADA é removido, renomeado ou substituído.
--  * Nenhuma tabela, policy, função ou dado existente é apagado.
--  * `user_settings` só GANHA colunas (padrão do projeto).
--  * A restrição de `allow_messages` é AMPLIADA (nunca restringida):
--    'friends' entra na lista, os valores antigos continuam válidos.
--  * RLS continua ativo: as novas colunas são cobertas pelas policies
--    owner já existentes em `user_settings`.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Novas colunas de privacidade em user_settings (todas com default)
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column if not exists allow_mentions text not null default 'everyone',
  add column if not exists allow_tags text not null default 'everyone',
  add column if not exists allow_shares text not null default 'everyone',
  add column if not exists allow_follows text not null default 'everyone',
  add column if not exists allow_video_downloads boolean not null default true,
  add column if not exists show_online_status boolean not null default true,
  add column if not exists view_history_enabled boolean not null default true,
  add column if not exists sensitive_content_filter boolean not null default false,
  add column if not exists blocked_words text[] not null default '{}';

-- ---------------------------------------------------------------------------
-- 2) Amplia (nunca restringe) as opções de interação
--    'friends' = seguidores mútuos no grafo real de `follows`.
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'user_settings'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%allow_messages%'
  loop
    execute format('alter table public.user_settings drop constraint %I', c.conname);
  end loop;

  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'user_settings'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%allow_mentions%'
  loop
    execute format('alter table public.user_settings drop constraint %I', c.conname);
  end loop;
end;
$$;

alter table public.user_settings
  add constraint user_settings_allow_messages_scope
    check (allow_messages in ('everyone','followers','friends','none')),
  add constraint user_settings_allow_mentions_scope
    check (allow_mentions in ('everyone','followers','friends','none')),
  add constraint user_settings_allow_tags_scope
    check (allow_tags in ('everyone','followers','friends','none')),
  add constraint user_settings_allow_shares_scope
    check (allow_shares in ('everyone','followers','friends','none')),
  add constraint user_settings_allow_follows_scope
    check (allow_follows in ('everyone','followers','friends','none'));

-- ---------------------------------------------------------------------------
-- 3) Helper: "amigos" = follow mútuo no grafo real (nunca inventado)
-- ---------------------------------------------------------------------------
create or replace function public.is_mutual_follow(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.follows f1
    where f1.follower_id = p_a and f1.following_id = p_b
  )
  and exists (
    select 1 from public.follows f2
    where f2.follower_id = p_b and f2.following_id = p_a
  );
$$;

revoke all on function public.is_mutual_follow(uuid, uuid) from anon;
grant execute on function public.is_mutual_follow(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) can_interact: resolve a política REAL do dono para um tipo de ação.
--    Usado pela Central de Segurança e por enforcement futureiro.
-- ---------------------------------------------------------------------------
create or replace function public.can_interact(p_owner uuid, p_kind text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_scope text;
begin
  if p_owner is null or p_kind is null then return false; end if;

  select case p_kind
           when 'message'   then us.allow_messages
           when 'comment'   then case when us.allow_comments then 'everyone' else 'none' end
           when 'mention'   then us.allow_mentions
           when 'tag'       then us.allow_tags
           when 'share'     then us.allow_shares
           when 'follow'    then us.allow_follows
           else 'none'
         end
    into v_scope
    from public.user_settings us
   where us.user_id = p_owner;

  v_scope := coalesce(v_scope, 'everyone');

  if p_kind = 'comment' then
    return v_scope <> 'none';
  end if;

  if auth.uid() is null then
    return v_scope = 'everyone';
  end if;
  if auth.uid() = p_owner then
    return true;
  end if;

  case v_scope
    when 'none' then return false;
    when 'followers' then
      return exists (
        select 1 from public.follows f
        where f.follower_id = p_owner and f.following_id = auth.uid()
      );
    when 'friends' then
      return public.is_mutual_follow(p_owner, auth.uid());
    else return true;
  end case;
end;
$$;

revoke all on function public.can_interact(uuid, text) from anon;
grant execute on function public.can_interact(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) my_privacy_settings: leitura validada do bloco de privacidade
-- ---------------------------------------------------------------------------
create or replace function public.my_privacy_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'auth_required'; end if;

  insert into public.user_settings (user_id) values (u)
    on conflict (user_id) do nothing;

  return jsonb_build_object(
    'account_private', coalesce((select us.account_private from public.user_settings us where us.user_id = u), false),
    'allow_messages', coalesce((select us.allow_messages from public.user_settings us where us.user_id = u), 'everyone'),
    'allow_comments', coalesce((select us.allow_comments from public.user_settings us where us.user_id = u), true),
    'allow_mentions', coalesce((select us.allow_mentions from public.user_settings us where us.user_id = u), 'everyone'),
    'allow_tags', coalesce((select us.allow_tags from public.user_settings us where us.user_id = u), 'everyone'),
    'allow_shares', coalesce((select us.allow_shares from public.user_settings us where us.user_id = u), 'everyone'),
    'allow_follows', coalesce((select us.allow_follows from public.user_settings us where us.user_id = u), 'everyone'),
    'allow_video_downloads', coalesce((select us.allow_video_downloads from public.user_settings us where us.user_id = u), true),
    'show_online_status', coalesce((select us.show_online_status from public.user_settings us where us.user_id = u), true),
    'view_history_enabled', coalesce((select us.view_history_enabled from public.user_settings us where us.user_id = u), true),
    'sensitive_content_filter', coalesce((select us.sensitive_content_filter from public.user_settings us where us.user_id = u), false),
    'blocked_words', coalesce((select us.blocked_words from public.user_settings us where us.user_id = u), '{}')
  );
end;
$$;

revoke all on function public.my_privacy_settings() from public, anon;
grant execute on function public.my_privacy_settings() to authenticated;

-- ---------------------------------------------------------------------------
-- 6) save_privacy_settings: grava validando os escopos permitidos
-- ---------------------------------------------------------------------------
create or replace function public.save_privacy_settings(
  p_account_private boolean default null,
  p_allow_messages text default null,
  p_allow_comments boolean default null,
  p_allow_mentions text default null,
  p_allow_tags text default null,
  p_allow_shares text default null,
  p_allow_follows text default null,
  p_allow_video_downloads boolean default null,
  p_show_online_status boolean default null,
  p_view_history_enabled boolean default null,
  p_sensitive_content_filter boolean default null,
  p_blocked_words text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  scopes text[] := array['everyone','followers','friends','none'];
  clean_words text[] := null;
begin
  if u is null then raise exception 'auth_required'; end if;

  if p_allow_messages is not null and not (p_allow_messages = any (scopes)) then
    raise exception 'bad_scope';
  end if;
  if p_allow_mentions is not null and not (p_allow_mentions = any (scopes)) then
    raise exception 'bad_scope';
  end if;
  if p_allow_tags is not null and not (p_allow_tags = any (scopes)) then
    raise exception 'bad_scope';
  end if;
  if p_allow_shares is not null and not (p_allow_shares = any (scopes)) then
    raise exception 'bad_scope';
  end if;
  if p_allow_follows is not null and not (p_allow_follows = any (scopes)) then
    raise exception 'bad_scope';
  end if;

  clean_words := '{}';
  if p_blocked_words is not null then
    select coalesce(array_agg(distinct lower(btrim(w))), '{}')
      into clean_words
      from unnest(p_blocked_words) as w
     where btrim(w) <> '' and length(btrim(w)) <= 40;
  end if;

  insert into public.user_settings (user_id) values (u)
    on conflict (user_id) do nothing;

  update public.user_settings
     set account_private = coalesce(p_account_private, account_private),
         allow_messages = coalesce(p_allow_messages, allow_messages),
         allow_comments = coalesce(p_allow_comments, allow_comments),
         allow_mentions = coalesce(p_allow_mentions, allow_mentions),
         allow_tags = coalesce(p_allow_tags, allow_tags),
         allow_shares = coalesce(p_allow_shares, allow_shares),
         allow_follows = coalesce(p_allow_follows, allow_follows),
         allow_video_downloads = coalesce(p_allow_video_downloads, allow_video_downloads),
         show_online_status = coalesce(p_show_online_status, show_online_status),
         view_history_enabled = coalesce(p_view_history_enabled, view_history_enabled),
         sensitive_content_filter = coalesce(p_sensitive_content_filter, sensitive_content_filter),
         blocked_words = coalesce(clean_words, blocked_words),
         updated_at = now()
   where user_id = u;

  return public.my_privacy_settings();
end;
$$;

revoke all on function public.save_privacy_settings(
  boolean, text, boolean, text, text, text, text, boolean, boolean, boolean, boolean, text[]
) from public, anon;
grant execute on function public.save_privacy_settings(
  boolean, text, boolean, text, text, text, text, boolean, boolean, boolean, boolean, text[]
) to authenticated;

notify pgrst, 'reload schema';
