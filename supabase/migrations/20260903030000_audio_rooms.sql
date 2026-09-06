-- ============================================================================
-- KLAY K - Salas de Voz (território Áudio)
-- Espaços de conversa por áudio em tempo real (Clubhouse-style) sobre LiveKit,
-- com dono/speakers/listeners. Nome da sala `voice-<uuid>` gerado no backend.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- audio_rooms
-- ---------------------------------------------------------------------------
create table if not exists public.audio_rooms (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  description text not null default '',
  category text default '',
  room_name text not null unique,
  owner_id uuid references auth.users(id) on delete set null,
  participant_count int not null default 1,
  speaker_count int not null default 1,
  status text not null default 'live' check (status in ('live','ended')),
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists audio_rooms_status_created_idx on public.audio_rooms (status, created_at desc);
create index if not exists audio_rooms_category_idx on public.audio_rooms (category);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.audio_rooms enable row level security;

-- leitura pública só de salas públicas ativas; escrita só do dono.
drop policy if exists audio_rooms_select on public.audio_rooms;
drop policy if exists audio_rooms_insert on public.audio_rooms;
drop policy if exists audio_rooms_update_owner on public.audio_rooms;
drop policy if exists audio_rooms_delete_owner on public.audio_rooms;
create policy audio_rooms_select on public.audio_rooms
  for select using (is_public = true and status = 'live');
create policy audio_rooms_insert on public.audio_rooms
  for insert with check (auth.uid() = owner_id);
create policy audio_rooms_update_owner on public.audio_rooms
  for update using (auth.uid() = owner_id);
create policy audio_rooms_delete_owner on public.audio_rooms
  for delete using (auth.uid() = owner_id);

-- ---------------------------------------------------------------------------
-- RPC: categorias com contagem de salas ativas (exploração).
-- ---------------------------------------------------------------------------
create or replace function public.audio_room_categories()
returns table (category text, cnt bigint)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(category, ''), 'Outros') as category, count(*)::bigint as cnt
  from public.audio_rooms
  where is_public = true and status = 'live'
  group by coalesce(nullif(category, ''), 'Outros')
  order by cnt desc;
$$;
revoke all on function public.audio_room_categories() from public;
grant execute on function public.audio_room_categories() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC: ids das salas que o usuário participa (cria sempre owner rem, simplifica)
-- Nota: por simplicidade de RLS, a "minha sala" é derivada no app via token; este
-- RPC retorna salas cujo owner é o usuário (suas salas criadas/ativas).
-- ---------------------------------------------------------------------------
create or replace function public.audio_rooms_my_ids()
returns table (room_id uuid)
language sql
security definer
set search_path = public
as $$
  select r.id
  from public.audio_rooms r
  where r.owner_id = auth.uid() and r.status = 'live';
$$;
revoke all on function public.audio_rooms_my_ids() from public;
grant execute on function public.audio_rooms_my_ids() to authenticated;