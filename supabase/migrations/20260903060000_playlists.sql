-- ============================================================================
-- KLAY K - Playlists (território Playlists)
-- Listas públicas curadas pelo próprio criador com seus vídeos publicados.
-- Diferente de `collections` (favoritos/salvos privados do usuário): aqui é
-- organização do conteúdo do criador, navegável por qualquer pessoa.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- playlists
-- ---------------------------------------------------------------------------
create table if not exists public.playlists (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text not null default '',
  cover_url text default '',
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- playlist_posts (vídeos do criador dentro de uma playlist, ordenados)
-- ---------------------------------------------------------------------------
create table if not exists public.playlist_posts (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  position int not null default 0,
  added_at timestamptz not null default now(),
  unique (playlist_id, post_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists playlists_creator_idx on public.playlists (creator_id, created_at desc);
create index if not exists playlist_posts_playlist_idx on public.playlist_posts (playlist_id, position asc);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Leitura pública só de playlists públicas; escrita só do próprio criador.
-- ---------------------------------------------------------------------------
alter table public.playlists enable row level security;

drop policy if exists playlists_select on public.playlists;
drop policy if exists playlists_insert on public.playlists;
drop policy if exists playlists_update on public.playlists;
drop policy if exists playlists_delete on public.playlists;

create policy playlists_select on public.playlists
  for select using (is_public = true);
create policy playlists_insert on public.playlists
  for insert with check (auth.uid() = creator_id);
create policy playlists_update on public.playlists
  for update using (auth.uid() = creator_id);
create policy playlists_delete on public.playlists
  for delete using (auth.uid() = creator_id);

alter table public.playlist_posts enable row level security;

drop policy if exists playlist_posts_select on public.playlist_posts;
drop policy if exists playlist_posts_insert on public.playlist_posts;
drop policy if exists playlist_posts_update on public.playlist_posts;
drop policy if exists playlist_posts_delete on public.playlist_posts;

create policy playlist_posts_select on public.playlist_posts
  for select using (
    exists (
      select 1 from public.playlists pl
      where pl.id = playlist_id and pl.is_public = true
    )
  );
create policy playlist_posts_insert on public.playlist_posts
  for insert with check (
    exists (
      select 1 from public.playlists pl
      where pl.id = playlist_id and pl.creator_id = auth.uid()
    )
  );
create policy playlist_posts_update on public.playlist_posts
  for update using (
    exists (
      select 1 from public.playlists pl
      where pl.id = playlist_id and pl.creator_id = auth.uid()
    )
  );
create policy playlist_posts_delete on public.playlist_posts
  for delete using (
    exists (
      select 1 from public.playlists pl
      where pl.id = playlist_id and pl.creator_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- RPC: ids das playlists publicas do usuario logado (para o hub "Meu KLAY K").
-- ---------------------------------------------------------------------------
create or replace function public.my_playlist_ids()
returns table (playlist_id uuid)
language sql
security definer
set search_path = public
as $$
  select p.id from public.playlists p
  where p.creator_id = auth.uid() and p.is_public = true;
$$;
revoke all on function public.my_playlist_ids() from public;
grant execute on function public.my_playlist_ids() to authenticated;