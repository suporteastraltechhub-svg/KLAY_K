-- ============================================================================
-- KLAY K — EXCLUSÃO EM MASSA DE LIVES (delete_lives)
--
-- Apaga com segurança as lives "permitidas" ao solicitante:
--   * qualquer usuário autenticado apaga APENAS as próprias lives
--     (streamer_id = auth.uid());
--   * quem tem capability 'moderation' (founder / super_admin / admin /
--     moderator), ao chamar com p_all = true, apaga todas as lives;
--   * nunca existe caminho para um usuário comum apagar lives de terceiros
--     (a autorização é decidida NO BACKEND — o cliente só envia o boolean).
--
-- O Storage (bucket `covers`) é limpo do lado do servidor com prova de posse
-- no WHERE (primeiro segmento do caminho = streamer), mesmo gateway/padrão de
-- `admin_delete_post`. A remoção das linhas dispara a cascata de
-- participantes/chat/presentes/eventos. A ação é auditada em `audit_logs`.
-- ============================================================================

create or replace function public.delete_lives(
  p_all boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_to_delete uuid[] := '{}';
  v_live record;
  v_cover_path text := '';
  v_removed_cover int := 0;
  v_deleted int := 0;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Autorização backend: todas as lives apenas com capability 'moderation'.
  v_is_admin := public.has_perm('moderation');

  if p_all and v_is_admin then
    select array_agg(id) into v_to_delete from public.lives;
  else
    -- Usuário comum (e admin chamando sem p_all): apenas as próprias lives.
    select array_agg(id) into v_to_delete
      from public.lives
     where streamer_id = v_uid;
  end if;

  if v_to_delete is null then v_to_delete := '{}'::uuid[]; end if;
  if cardinality(v_to_delete) = 0 then
    return jsonb_build_object('ok', true, 'deleted', 0);
  end if;

  -- O trigger storage.protect_delete bloqueia DELETE direto em storage.objects;
  -- o Mecanismo oficial é liberar o GUC só dentro desta função (por-capa,
  -- com caminhos confirmados e prova de posse no WHERE).
  set local storage.allow_delete_query = 'true';

  for v_live in
    select id, streamer_id, cover_url
      from public.lives
     where id = any(v_to_delete)
  loop
    v_cover_path := split_part(
      split_part(v_live.cover_url, '/object/public/covers/', 2), '?', 1);
    if v_cover_path = '' and v_live.cover_url like 'covers/%' then
      v_cover_path := split_part(v_live.cover_url, '?', 1);
    end if;
    if v_cover_path <> '' then
      delete from storage.objects
       where bucket_id = 'covers'
         and name = v_cover_path
         and (storage.foldername(name))[1] = v_live.streamer_id::text;
      get diagnostics v_removed_cover = row_count;
    end if;
  end loop;

  -- Cascata limpa participantes/chat/presentes/eventos das lives removidas.
  delete from public.lives where id = any(v_to_delete);
  get diagnostics v_deleted = row_count;

  perform public.write_audit(
    'delete_lives', 'live', '',
    jsonb_build_object(
      'count', v_deleted,
      'all', p_all and v_is_admin,
      'covers_removed', v_removed_cover
    )
  );

  return jsonb_build_object('ok', true, 'deleted', v_deleted);
end;
$$;

revoke all on function public.delete_lives(boolean) from public, anon;
grant execute on function public.delete_lives(boolean) to authenticated;