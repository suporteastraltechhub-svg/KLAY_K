-- KLAY K - Comunidades
-- Comunidades: espaços temáticos (Games, Música, Tecnologia, Esportes, Humor...)
-- com membros, moderadores, posts/discussões e denúncia/moderação.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- communities
-- ---------------------------------------------------------------------------
create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  description text not null default '',
  icon text default '',
  cover_url text default '',
  category text default '',
  created_by uuid references auth.users(id) on delete set null,
  member_count int not null default 1,
  post_count int not null default 0,
  is_public boolean not null default true,
  rules text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- community_members
-- ---------------------------------------------------------------------------
create table if not exists public.community_members (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member','moderator','admin')),
  joined_at timestamptz not null default now(),
  unique (community_id, user_id)
);

-- ---------------------------------------------------------------------------
-- community_posts
-- ---------------------------------------------------------------------------
create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  media_url text default '',
  media_type text default '' check (media_type in ('','image','video')),
  likes_count int not null default 0,
  comments_count int not null default 0,
  status text not null default 'published' check (status in ('published','hidden')),
  pinned boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- community_post_comments
-- ---------------------------------------------------------------------------
create table if not exists public.community_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- community_post_likes
-- ---------------------------------------------------------------------------
create table if not exists public.community_post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);

-- ---------------------------------------------------------------------------
-- community_reports (denúncia de post/comentário dentro da comunidade)
-- ---------------------------------------------------------------------------
create table if not exists public.community_reports (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  post_id uuid references community_posts(id) on delete set null,
  reporter_id uuid references auth.users(id) on delete set null,
  reason text not null,
  details text default '',
  status text not null default 'open' check (status in ('open','resolved','dismissed')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists communities_category_idx on public.communities (category);
create index if not exists communities_member_count_idx on public.communities (member_count desc);
create index if not exists community_members_community_idx on public.community_members (community_id);
create index if not exists community_members_user_idx on public.community_members (user_id);
create index if not exists community_posts_community_created_idx
  on public.community_posts (community_id, created_at desc);
create index if not exists community_post_comments_post_idx
  on public.community_post_comments (post_id, created_at);
create index if not exists community_reports_status_idx on public.community_reports (status);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_post_comments enable row level security;
alter table public.community_post_likes enable row level security;
alter table public.community_reports enable row level security;

-- communities: leitura pública (só públicas), criação por autenticado.
drop policy if exists "communities_select" on public.communities;
drop policy if exists "communities_insert" on public.communities;
drop policy if exists "communities_update_admin" on public.communities;
drop policy if exists "communities_delete_admin" on public.communities;
create policy "communities_select" on public.communities
  for select using (is_public = true);
create policy "communities_insert" on public.communities
  for insert with check (auth.uid() = created_by);
create policy "communities_update_admin" on public.communities
  for update using (
    exists (
      select 1 from public.community_members m
      where m.community_id = id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );
create policy "communities_delete_admin" on public.communities
  for delete using (
    exists (
      select 1 from public.community_members m
      where m.community_id = id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );

-- community_members: qualquer pessoa vê, usuário gerencia o próprio vínculo.
drop policy if exists "community_members_select" on public.community_members;
drop policy if exists "community_members_insert" on public.community_members;
drop policy if exists "community_members_update" on public.community_members;
drop policy if exists "community_members_delete_self" on public.community_members;
create policy "community_members_select" on public.community_members
  for select using (true);
create policy "community_members_insert" on public.community_members
  for insert with check (auth.uid() = user_id);
create policy "community_members_update" on public.community_members
  for update using (auth.uid() = user_id);
create policy "community_members_delete_self" on public.community_members
  for delete using (auth.uid() = user_id);

-- community_posts: membro lê/posta; moderador esconde.
drop policy if exists "community_posts_select" on public.community_posts;
drop policy if exists "community_posts_insert" on public.community_posts;
drop policy if exists "community_posts_delete" on public.community_posts;
drop policy if exists "community_posts_update_mod" on public.community_posts;
create policy "community_posts_select" on public.community_posts
  for select using (status = 'published');
create policy "community_posts_insert" on public.community_posts
  for insert with check (
    auth.uid() = user_id and exists (
      select 1 from public.community_members m
      where m.community_id = community_id and m.user_id = auth.uid()
    )
  );
create policy "community_posts_update_mod" on public.community_posts
  for update using (
    auth.uid() = user_id or exists (
      select 1 from public.community_members m
      where m.community_id = community_id
        and m.user_id = auth.uid()
        and m.role in ('moderator','admin')
    )
  );
create policy "community_posts_delete" on public.community_posts
  for delete using (
    auth.uid() = user_id or exists (
      select 1 from public.community_members m
      where m.community_id = community_id
        and m.user_id = auth.uid()
        and m.role in ('moderator','admin')
    )
  );

-- community_post_comments / likes: leitura e escrita por autenticado.
drop policy if exists "community_comments_select" on public.community_post_comments;
drop policy if exists "community_comments_insert" on public.community_post_comments;
drop policy if exists "community_comments_delete" on public.community_post_comments;
create policy "community_comments_select" on public.community_post_comments
  for select using (true);
create policy "community_comments_insert" on public.community_post_comments
  for insert with check (auth.uid() = user_id);
create policy "community_comments_delete" on public.community_post_comments
  for delete using (auth.uid() = user_id);

drop policy if exists "community_likes_select" on public.community_post_likes;
drop policy if exists "community_likes_insert" on public.community_post_likes;
drop policy if exists "community_likes_delete" on public.community_post_likes;
create policy "community_likes_select" on public.community_post_likes
  for select using (true);
create policy "community_likes_insert" on public.community_post_likes
  for insert with check (auth.uid() = user_id);
create policy "community_likes_delete" on public.community_post_likes
  for delete using (auth.uid() = user_id);

-- comunidade é criada pelo dono e vira admin automaticamente (trigger).
drop trigger if exists community_owner_admin on public.communities;
create or replace function public.community_owner_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.community_members (community_id, user_id, role)
  values (new.id, new.created_by, 'admin')
  on conflict (community_id, user_id) do nothing;
  return new;
end;
$$;
create trigger community_owner_admin
  after insert on public.communities
  for each row execute function public.community_owner_admin();

-- Mantém member_count sincronizado.
drop trigger if exists community_members_count on public.community_members;
create or replace function public.community_members_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.communities set member_count = member_count + 1 where id = new.community_id;
  elsif (tg_op = 'DELETE') then
    update public.communities set member_count = greatest(member_count - 1, 0) where id = old.community_id;
  end if;
  return coalesce(new, old);
end;
$$;
create trigger community_members_count
  after insert or delete on public.community_members
  for each row execute function public.community_members_count();

-- ---------------------------------------------------------------------------
-- RPC: categorias com contagem de comunidades (exploração).
-- ---------------------------------------------------------------------------
create or replace function public.community_categories()
returns table (category text, cnt bigint)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(category, ''), 'Outros') as category, count(*)::bigint as cnt
  from public.communities
  where is_public = true
  group by coalesce(nullif(category, ''), 'Outros')
  order by cnt desc;
$$;