-- ============================================================================
-- KLAY K - Momentos (território Momentos)
-- Publicações efêmeras (texto + imagem opcional) que expiram após um tempo,
-- estilo "status". Visíveis publicamente apenas enquanto não expiradas.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- moments
-- ---------------------------------------------------------------------------
create table if not exists public.moments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null default '',
  image_url text,
  sticker text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

-- ---------------------------------------------------------------------------
-- Indexes (expiração + feed por autor + ordenação nova->velha)
-- ---------------------------------------------------------------------------
create index if not exists moments_expires_idx on public.moments (expires_at);
create index if not exists moments_user_created_idx on public.moments (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Row Level Security: leitura pública só de momentos ainda não expirados;
-- escrita sempre do próprio dono; delete só do dono.
-- ---------------------------------------------------------------------------
alter table public.moments enable row level security;

drop policy if exists moments_select on public.moments;
drop policy if exists moments_insert on public.moments;
drop policy if exists moments_delete_owner on public.moments;

create policy moments_select on public.moments
  for select using (expires_at > now());
create policy moments_insert on public.moments
  for insert with check (auth.uid() = user_id);
create policy moments_delete_owner on public.moments
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- RPC: moments ativos (não expirados) mais recentes primeiro, com o perfil
-- do autor embutido (count agregado de curtidas e visualizações).
-- ---------------------------------------------------------------------------
create or replace function public.moment_feed(p_limit bigint default 50)
returns table (
  id uuid,
  user_id uuid,
  text text,
  image_url text,
  sticker text,
  created_at timestamptz,
  expires_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select m.id, m.user_id, m.text, m.image_url, m.sticker, m.created_at, m.expires_at
  from public.moments m
  where m.expires_at > now()
  order by m.created_at desc
  limit p_limit;
$$;
revoke all on function public.moment_feed(bigint) from public;
grant execute on function public.moment_feed(bigint) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC: contagem de momentos ativos do usuario logado (para o hub "Meu KLAY K").
-- ---------------------------------------------------------------------------
create or replace function public.moments_my_ids()
returns table (moment_id uuid)
language sql
security definer
set search_path = public
as $$
  select m.id from public.moments m
  where m.user_id = auth.uid() and m.expires_at > now();
$$;
revoke all on function public.moments_my_ids() from public;
grant execute on function public.moments_my_ids() to authenticated;