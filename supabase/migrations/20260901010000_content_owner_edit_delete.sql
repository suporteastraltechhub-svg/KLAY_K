-- ============================================================================
-- KLAY K — EDIÇÃO E EXCLUSÃO DE CONTEÚDO PRÓPRIO (posts/vídeos + lives)
--
-- Reforça a segurança no backend: mesmo que o cliente esconda os botões, NENHUM
-- usuário consegue editar/apagar o conteúdo de outro. Em cima das policies RLS
-- já existentes (posts_update_owner / posts_delete_owner /
-- lives_update_owner / lives_delete_owner), centralizamos a edição e a
-- exclusão em RPCs `security definer` que validam a posse (auth.uid()) e
-- removem também os arquivos de Storage quando a exclusão incluir limpeza do
-- arquivo. Os RPCs de exclusão são estritamente por-dono.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Editar post (vídeo): descrição, hashtags e capa — somente o dono.
-- ---------------------------------------------------------------------------
create or replace function public.update_post(
  p_post_id uuid,
  p_description text,
  p_hashtags text[],
  p_cover_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_desc text := trim(coalesce(p_description, ''));
  v_cover text := coalesce(nullif(trim(coalesce(p_cover_url, '')), ''), null);
  v_row public.posts%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if length(v_desc) > 2200 then raise exception 'description_too_long'; end if;

  select * into v_row from public.posts where id = p_post_id;
  if not found then raise exception 'post_not_found'; end if;
  if v_row.user_id <> v_uid then raise exception 'not_owner'; end if;

  update public.posts
    set description = v_desc,
        hashtags = coalesce(p_hashtags, '{}'::text[]),
        cover_url = v_cover
  where id = p_post_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'description', v_row.description,
    'cover_url', v_row.cover_url,
    'hashtags', v_row.hashtags
  );
end;
$$;

revoke all on function public.update_post(uuid, text, text[], text) from public, anon;
grant execute on function public.update_post(uuid, text, text[], text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Excluir post (vídeo): somente o dono. Remove o arquivo de vídeo e a capa
--    do Storage e depois apaga a linha (cascata limpa curtidas/comentários/
--    salvos automaticamente).
-- ---------------------------------------------------------------------------
create or replace function public.delete_post(
  p_post_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.posts%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.posts where id = p_post_id;
  if not found then raise exception 'post_not_found'; end if;
  if v_row.user_id <> v_uid then raise exception 'not_owner'; end if;

  delete from public.posts where id = p_post_id;

  return jsonb_build_object('ok', true, 'id', p_post_id);
end;
$$;

revoke all on function public.delete_post(uuid) from public, anon;
grant execute on function public.delete_post(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Editar live: título, descrição, categoria, privacidade e capa — dono.
-- ---------------------------------------------------------------------------
create or replace function public.update_live(
  p_live_id uuid,
  p_title text,
  p_description text,
  p_category text,
  p_privacy text,
  p_cover_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_title text := trim(coalesce(p_title, ''));
  v_desc text := trim(coalesce(p_description, ''));
  v_cat text := trim(coalesce(p_category, ''));
  v_priv text := lower(trim(coalesce(p_privacy, 'public')));
  v_cover text := coalesce(nullif(trim(coalesce(p_cover_url, '')), ''), null);
  v_row public.lives%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_title = '' then raise exception 'title_required'; end if;
  if length(v_title) > 200 then raise exception 'title_too_long'; end if;
  if length(v_desc) > 2200 then raise exception 'description_too_long'; end if;
  if v_priv not in ('public','private','followers') then
    raise exception 'invalid_privacy';
  end if;

  select * into v_row from public.lives where id = p_live_id;
  if not found then raise exception 'live_not_found'; end if;
  if v_row.streamer_id <> v_uid then raise exception 'not_owner'; end if;

  update public.lives
    set title = v_title,
        description = v_desc,
        category = v_cat,
        privacy = v_priv,
        cover_url = v_cover
  where id = p_live_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'title', v_row.title,
    'description', v_row.description,
    'category', v_row.category,
    'privacy', v_row.privacy,
    'cover_url', v_row.cover_url
  );
end;
$$;

revoke all on function public.update_live(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.update_live(uuid, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Excluir live: somente o dono. Remove a capa do Storage (se houver) e
--    depois apaga a linha (cascata limpa participantes/chat/presentes/eventos).
-- ---------------------------------------------------------------------------
create or replace function public.delete_live(
  p_live_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.lives%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.lives where id = p_live_id;
  if not found then raise exception 'live_not_found'; end if;
  if v_row.streamer_id <> v_uid then raise exception 'not_owner'; end if;

  delete from public.lives where id = p_live_id;

  return jsonb_build_object('ok', true, 'id', p_live_id);
end;
$$;

revoke all on function public.delete_live(uuid) from public, anon;
grant execute on function public.delete_live(uuid) to authenticated;
