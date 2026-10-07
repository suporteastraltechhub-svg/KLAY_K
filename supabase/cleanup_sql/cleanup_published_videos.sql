-- ============================================================================
-- KLAY K — LIMPEZA DE VÍDEOS PUBLICADOS (tabela `public.posts`)
-- ⚠️ Escopo CONFIRMADO pelo usuário: TODOS os posts do feed.
--
-- Cascata: deletar posts remove likes/comentários/salvos/playlist_items
-- automaticamente (FKs com `on delete cascade`). Objetos de storage
-- (buckets `videos`/`covers`) NÃO são removidos por cascata — ver passo 5.
--
-- Passos: 1) preview, 2+3) backups, 4) delete posts, 5) purga de storage,
--         6) resumo. O backup de linhas é persistido; a mídia removida só
--         pode ser recuperada se os arquivos originais existirem.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) PREVIEW — perfil do conteúdo publicado hoje
-- ---------------------------------------------------------------------------
select count(*)                               as total_posts,
       count(distinct user_id)                as autores_distintos,
       count(*) filter (where video_url <> '') as com_video,
       count(*) filter (where cover_url <> '') as com_capa
  from public.posts;

select user_id,
       count(*) as posts,
       min(created_at) as mais_antigo,
       max(created_at) as mais_recente
  from public.posts
 group by user_id
 order by posts desc;

-- Visualizar tudo (para conferir se há conteúdo que NÃO pode sumir)
select id, user_id, video_url, cover_url, description, created_at
  from public.posts
 order by created_at desc
 limit 500;

-- ---------------------------------------------------------------------------
-- 2) BACKUP — linhas que serão apagadas (tabela persistida)
-- ---------------------------------------------------------------------------
drop table if exists public.posts_backup_20260906;
create table public.posts_backup_20260906 as
  select * from public.posts;

-- ---------------------------------------------------------------------------
-- 3) BACKUP — caminhos de mídia dos posts afetados
-- ---------------------------------------------------------------------------
begin;

create temp table _posts_media_20260906 on commit drop as
  select id, video_url as path, 'videos' as bucket from public.posts
   where video_url <> '' and video_url like '%/%'
  union
  select id, cover_url as path, 'covers' as bucket from public.posts
   where cover_url <> '' and cover_url like '%/%';

-- ---------------------------------------------------------------------------
-- 4) DELETE — posts (cascata limpa likes/comentários/salvos/playlists)
-- ---------------------------------------------------------------------------
delete from public.posts;

-- ---------------------------------------------------------------------------
-- 5) PURGA DE STORAGE — objetos dos buckets `videos`/`covers` vinculados
--    aos posts apagados
-- ---------------------------------------------------------------------------
delete from storage.objects
 where (bucket_id = 'videos' and name in (select path from _posts_media_20260906 where bucket = 'videos'))
    or (bucket_id = 'covers' and name in (select path from _posts_media_20260906 where bucket = 'covers'));

-- ---------------------------------------------------------------------------
-- 6) RESUMO
-- ---------------------------------------------------------------------------
select 'backup_linhas' as etapa, count(*)::text as quantidade from public.posts_backup_20260906;

commit;

-- ============================================================================
-- Reversão (em caso de erro grave — NÃO roda sozinha):
--   insert into public.posts select * from public.posts_backup_20260906;
-- A mídia de storage removida precisa ser re-enviada (o backup serve apenas
-- para re-criar as linhas; likes/comentários/salvos não são recuperáveis).
-- ============================================================================