-- ============================================================================
-- KLAY K — EXCLUSÃO ADMINISTRATIVA DE PUBLICAÇÃO (admin_delete_post)
--
-- Permite que um membro autorizado da equipe (capability 'moderation':
-- founder / super_admin / admin / moderator) exclua QUALQUER publicação,
-- mesmo sem ser o dono. Toda a autorização é validada NO BACKEND
-- (`has_perm('moderation')` via security definer) — o cliente nunca decide.
--
-- O Storage (buckets `videos`/`covers`) é limpo do lado do servidor: a
-- função roda como o dono (postgres, que ignora as policies RLS de owner
-- dos buckets) e apaga os objetos exatos do post, confirmando que o
-- primeiro segmento do caminho é o dono da publicação (nada de apagar
-- arquivos de outra publicação).
--
-- Auditado em `public.audit_logs` via `write_audit` (actor = admin atual).
-- Chamadas repetidas a um post já excluído retornam 'post_not_found'.
-- ============================================================================

create or replace function public.admin_delete_post(
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

  -- Autorização: capability 'moderation' (founder/super_admin/admin/
  -- moderator). Nunca confia em flag/parâmetro enviado pelo cliente.
  if not public.has_perm('moderation') then
    raise exception 'not_admin';
  end if;

  select * into v_row from public.posts where id = p_post_id;
  if not found then raise exception 'post_not_found'; end if;

  -- O trigger storage.protect_delete bloqueia DELETE direto em storage.objects.
  -- O Mecanismo oficial do Supabase para limpeza programática via SQL é liberar
  -- o GUC de sessão `storage.allow_delete_query` — aqui só dentro desta função
  -- (por-post, com caminhos confirmados e prova de posse no WHERE).
  set local storage.allow_delete_query = 'true';

  -- 1) Vídeo: `video_url` guarda o caminho do objeto no bucket `videos`
  --    ({user_id}/{arquivo}). Remove apenas se for um caminho (não URL) e se
  --    o primeiro segmento pertencer ao dono do post.
  if coalesce(v_row.video_url, '') <> ''
     and v_row.video_url like '%/%'
     and v_row.video_url not like 'http%' then
    delete from storage.objects
     where bucket_id = 'videos'
       and name = v_row.video_url
       and (storage.foldername(name))[1] = v_row.user_id::text;
    get diagnostics v_removed_video = row_count;
  end if;

  -- 2) Capa: `cover_url` guarda a URL pública (…/storage/v1/object/public/
  --    covers/…). Extrai o caminho do objeto e remove apenas o arquivo certo.
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

  -- 4) Auditoria: quem, o quê, de quem, quando e resultado.
  perform public.write_audit(
    'admin_delete_post', 'post', p_post_id::text,
    jsonb_build_object(
      'owner_id', v_row.user_id,
      'video_path', nullif(v_row.video_url, ''),
      'cover_path', nullif(v_cover_path, ''),
      'video_removed', v_removed_video,
      'cover_removed', v_removed_cover
    )
  );

  return jsonb_build_object(
    'ok', true,
    'id', p_post_id,
    'user_id', v_row.user_id
  );
end;
$$;

revoke all on function public.admin_delete_post(uuid) from public, anon;
grant execute on function public.admin_delete_post(uuid) to authenticated;

-- ============================================================================
-- KLAY K — LISTAGEM ADMINISTRATIVA DE PUBLICAÇÕES (admin_list_posts)
--
-- Alimenta a aba "Publicações" do painel: retorna as publicações recentes de
-- TODOS os autores (para moderação de conteúdo), com o perfil do autor no
-- formato já usado pelo feed (`profiles`). Mesmo gate de autorização da
-- exclusão: capability 'moderation'. O cliente nunca lista posts "por conta
-- própria" — tudo vem desta RPC `security definer`.
-- ============================================================================

create or replace function public.admin_list_posts(
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if not public.has_perm('moderation') then
    raise exception 'not_admin';
  end if;

  select coalesce(jsonb_agg(x), '[]'::jsonb)
    into v_rows
    from (
      select p.id,
             p.user_id,
             p.video_url,
             p.cover_url,
             p.description,
             p.audio_name,
             p.likes_count,
             p.comments_count,
             p.shares_count,
             p.created_at,
             jsonb_build_object(
               'id', pr.id,
               'username', pr.username,
               'display_name', pr.display_name,
               'avatar_url', pr.avatar_url,
               'is_verified', pr.is_verified
             ) as profiles
        from public.posts p
        left join public.profiles pr on pr.id = p.user_id
       order by p.created_at desc
       limit greatest(1, least(p_limit, 200))
       offset greatest(0, p_offset)
    ) x;

  return v_rows;
end;
$$;

revoke all on function public.admin_list_posts(int, int) from public, anon;
grant execute on function public.admin_list_posts(int, int) to authenticated;