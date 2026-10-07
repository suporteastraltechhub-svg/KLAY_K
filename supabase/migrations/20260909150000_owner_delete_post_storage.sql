-- ============================================================================
-- KLAY K — EXCLUSÃO PRÓPRIA COM LIMPEZA REAL DE STORAGE (delete_post)
--
-- A versão anterior de `public.delete_post` (20260901010000) apagava APENAS a
-- linha em `public.posts` — o comentário prometia remover o vídeo e a capa do
-- Storage, mas a função não removia NADA lá. A limpeza ficava a cargo do
-- cliente (best-effort, disparada sem `await`, engolindo erros), o que deixava
-- arquivos órfãos nos buckets `videos`/`covers` e escondia falhas reais.
--
-- Esta versão faz exatamente o que o comentário original prometia, usando o
-- MESMO mecanismo já comprovado em `admin_delete_post` (20260906010000):
--   * `security definer` + `auth.uid()` (apenas autenticado);
--   * exclusivamente do DONO: post de terceiro → `not_owner`;
--   * limpeza server-side de `videos`/`covers` com prova de posse no WHERE
--     ((storage.foldername(name))[1] = user_id) — jamais apaga arquivo alheio;
--   * idempotente: post já excluído → `post_not_found`.
-- A cascata continua limpando curtidas/comentários/salvos/playlists.
-- ============================================================================

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
  v_cover_path text := '';
  v_removed_video bigint := 0;
  v_removed_cover bigint := 0;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.posts where id = p_post_id;
  if not found then raise exception 'post_not_found'; end if;
  if v_row.user_id <> v_uid then raise exception 'not_owner'; end if;

  -- O trigger storage.protect_delete bloqueia DELETE direto em storage.objects.
  -- Mecanismo oficial do Supabase: liberar o GUC de sessão
  -- `storage.allow_delete_query` SOMENTE dentro desta função, por-post, com
  -- caminhos confirmados e prova de posse no WHERE.
  set local storage.allow_delete_query = 'true';

  -- 1) Vídeo: `video_url` guarda o caminho do objeto no bucket `videos`
  --    ({user_id}/{arquivo}). Remove apenas se for caminho (não URL).
  if coalesce(v_row.video_url, '') <> ''
     and v_row.video_url like '%/%'
     and v_row.video_url not like 'http%' then
    delete from storage.objects
     where bucket_id = 'videos'
       and name = v_row.video_url
       and (storage.foldername(name))[1] = v_row.user_id::text;
    get diagnostics v_removed_video = row_count;
  end if;

  -- 2) Capa: `cover_url` guarda a URL pública (…/object/public/covers/…).
  --    Extrai o caminho do objeto e remove apenas o arquivo certo.
  v_cover_path := split_part(
    split_part(v_row.cover_url, '/object/public/covers/', 2), '?', 1);
  if v_cover_path = '' and v_row.cover_url like 'covers/%' then
    v_cover_path := split_part(v_row.cover_url, '?', 1);
  end if;
  if v_cover_path <> '' then
    delete from storage.objects
     where bucket_id = 'covers'
       and name = v_cover_path
       and (storage.foldername(name))[1] = v_row.user_id::text;
    get diagnostics v_removed_cover = row_count;
  end if;

  -- 3) Publicação (cascata limpa curtidas/comentários/salvos/playlists).
  delete from public.posts where id = p_post_id;

  return jsonb_build_object(
    'ok', true,
    'id', p_post_id,
    'video_removed', v_removed_video,
    'cover_removed', v_removed_cover
  );
end;
$$;

revoke all on function public.delete_post(uuid) from public, anon;
grant execute on function public.delete_post(uuid) to authenticated;