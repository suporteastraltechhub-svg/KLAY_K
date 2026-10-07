-- ============================================================================
-- KLAY K — RTMP/RTMPS Support + Live Type
-- Adiciona suporte à entrada RTMP/RTMPS e campo live_type.
-- ============================================================================

-- RTMP/RTMPS support
alter table public.lives add column if not exists rtmp_enabled boolean default false;
alter table public.lives add column if not exists rtmp_url text;
alter table public.lives add column if not exists stream_key text;
alter table public.lives add column if not exists live_type text default 'camera';

-- Índice para buscar lives por tipo
create index if not exists lives_live_type_idx on public.lives (live_type);
