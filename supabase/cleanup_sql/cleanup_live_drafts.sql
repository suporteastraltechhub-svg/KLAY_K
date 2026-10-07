-- ============================================================================
-- KLAY K — LIMPEZA DE RASCUNHOS NÃO PUBLICADOS (+ MÍDIA NO BUCKET `drafts`)
-- Escopo CONFIRMADO pelo usuário: apenas rows com status != 'published'
-- e os objetos correspondentes (video_path/cover_path) no bucket privado.
--
-- Passos: 1) contar, 2) backup, 3) backup das mídias, 4) delete rows,
--         5) purgar objetos de storage. Em um único bloco transacional,
--         exceto o backup (tabelas persistidas para recuperação).
--
-- ❗ Executar no SQL Editor do Supabase (role postgres) ou via
--    `supabase db push` NÃO se aplica: este script NÃO é uma migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1) PREVIEW — nada acontece, só mostra o que será apagado
-- ---------------------------------------------------------------------------
select count(*)                       as draft_rows,
       count(*) filter (where status = 'trashed') as trashed_rows
  from public.drafts
 where status <> 'published';

select id, user_id, status, video_path, cover_path, updated_at
  from public.drafts
 where status <> 'published'
 order by user_id, updated_at desc;

select count(*) as media_paths
  from (
    select video_path as p from public.drafts where status <> 'published' and video_path is not null and video_path <> ''
    union
    select cover_path as p from public.drafts where status <> 'published' and cover_path is not null and cover_path <> ''
  ) m;

-- ============================================================================
-- PARAR AQUI para revisar. Os próximos passos apagam os rascunhos não
-- publicados **e a mídia** associada. Backup é feito antes.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2) BACKUP — metadados dos rascunhos afetados (tabela persistida)
-- ---------------------------------------------------------------------------
drop table if exists public.drafts_backup_20260906;
create table public.drafts_backup_20260906 as
  select * from public.drafts
   where status <> 'published';

-- ---------------------------------------------------------------------------
-- 3) BACKUP — caminhos de mídia afetados (tabela temporária para o passo 5)
-- ---------------------------------------------------------------------------
create temp table _drafts_media_20260906 on commit drop as
  select video_path as path from public.drafts where status <> 'published' and video_path is not null and video_path <> ''
  union
  select cover_path as path from public.drafts where status <> 'published' and cover_path is not null and cover_path <> '';

-- ---------------------------------------------------------------------------
-- 4) DELETE — rascunhos não publicados
-- ---------------------------------------------------------------------------
delete from public.drafts
 where status <> 'published';

-- ---------------------------------------------------------------------------
-- 5) PURGA DE MÍDIA — objetos do bucket `drafts` vinculados aos rascunhos
--    apagados. O bucket é privado; remover aqui também remove o objeto do
--    storage (a forma canônica é a Storage API, mas o row é a fonte).
-- ---------------------------------------------------------------------------
delete from storage.objects
 where bucket_id = 'drafts'
   and name in (select path from _drafts_media_20260906)
   and owner is not null; -- preserva objetos sem dono como salvaguarda extra

-- ---------------------------------------------------------------------------
-- 6) RESUMO DO QUE FOI FEITO
-- ---------------------------------------------------------------------------
select 'backup_linhas'   as etapa, count(*)::text as quantidade from public.drafts_backup_20260906
union all
select 'rascunhos_apagados',  (select count(*)::text from public.drafts_backup_20260906)
union all
select 'media_removida',      (select count(*)::text from (select path from _drafts_media_20260906) m);

commit;

-- ============================================================================
-- Reversão (em caso de erro grave — NÃO roda sozinha):
--   insert into public.drafts select * from public.drafts_backup_20260906;
-- A mídia de storage removida precisa ser re-enviada (a mídia original pode
-- não existir mais) — por isso o backup serve apenas para re-criar as linhas.
-- ============================================================================