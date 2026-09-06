-- KLAY K - Conteúdo: posts (vídeos), curtidas, comentários, salvos e notificações
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- posts (vídeos curtos)
-- ---------------------------------------------------------------------------
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  video_url text not null default '',
  cover_url text default '',
  description text not null default '',
  audio_name text default '',
  hashtags text[] not null default '{}',
  likes_count int not null default 0,
  comments_count int not null default 0,
  shares_count int not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- post_likes
-- ---------------------------------------------------------------------------
create table if not exists public.post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);

-- ---------------------------------------------------------------------------
-- comments
-- Obs.: o starter do projeto já declarava uma tabela `comments` de exemplo
-- (colunas id, user_id, video_id, text, created_at), vazia. Descartamos e
-- recriamos com a estrutura do conteúdo, pois não havia dados a preservar.
-- ---------------------------------------------------------------------------
drop table if exists public.comments;
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- saved_posts
-- ---------------------------------------------------------------------------
create table if not exists public.saved_posts (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  type text not null,
  ref_id text,
  message text not null default '',
  read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists posts_user_id_idx on public.posts (user_id);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists post_likes_post_id_idx on public.post_likes (post_id);
create index if not exists post_likes_user_id_idx on public.post_likes (user_id);
create index if not exists comments_post_id_idx on public.comments (post_id, created_at);
create index if not exists saved_posts_user_id_idx on public.saved_posts (user_id);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Contadores com triggers (evita leitura manual/race em likes/comments)
-- ---------------------------------------------------------------------------
create or replace function public.touch_post_like_count()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = NEW.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts set likes_count = greatest(likes_count - 1, 0) where id = OLD.post_id;
  end if;
  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists post_likes_count on public.post_likes;
create trigger post_likes_count
  after insert or delete on public.post_likes
  for each row execute function public.touch_post_like_count();

create or replace function public.touch_post_comment_count()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = NEW.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts set comments_count = greatest(comments_count - 1, 0) where id = OLD.post_id;
  end if;
  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists comments_count on public.comments;
create trigger comments_count
  after insert or delete on public.comments
  for each row execute function public.touch_post_comment_count();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.saved_posts enable row level security;
alter table public.notifications enable row level security;

-- posts: todos leem; dono insere/atualiza/remove
drop policy if exists "posts_select_all" on public.posts;
drop policy if exists "posts_insert_owner" on public.posts;
drop policy if exists "posts_update_owner" on public.posts;
drop policy if exists "posts_delete_owner" on public.posts;
create policy "posts_select_all" on public.posts for select using (true);
create policy "posts_insert_owner" on public.posts for insert with check (user_id = auth.uid());
create policy "posts_update_owner" on public.posts for update using (user_id = auth.uid());
create policy "posts_delete_owner" on public.posts for delete using (user_id = auth.uid());

-- post_likes: todos leem; dono insere/remove
drop policy if exists "post_likes_select_all" on public.post_likes;
drop policy if exists "post_likes_insert_owner" on public.post_likes;
drop policy if exists "post_likes_delete_owner" on public.post_likes;
create policy "post_likes_select_all" on public.post_likes for select using (true);
create policy "post_likes_insert_owner" on public.post_likes for insert with check (user_id = auth.uid());
create policy "post_likes_delete_owner" on public.post_likes for delete using (user_id = auth.uid());

-- comments: todos leem/inserem (comentário exige estar logado); dono ou dono do post remove
drop policy if exists "comments_select_all" on public.comments;
drop policy if exists "comments_insert_owner" on public.comments;
drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_select_all" on public.comments for select using (true);
create policy "comments_insert_owner" on public.comments for insert with check (user_id = auth.uid());
create policy "comments_delete_own" on public.comments for delete using (
  auth.uid() = user_id or
  exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid())
);

-- saved_posts: dono lê/insere/remove
drop policy if exists "saved_posts_select_owner" on public.saved_posts;
drop policy if exists "saved_posts_insert_owner" on public.saved_posts;
drop policy if exists "saved_posts_delete_owner" on public.saved_posts;
create policy "saved_posts_select_owner" on public.saved_posts for select using (user_id = auth.uid());
create policy "saved_posts_insert_owner" on public.saved_posts for insert with check (user_id = auth.uid());
create policy "saved_posts_delete_owner" on public.saved_posts for delete using (user_id = auth.uid());

-- notifications: dono lê/atualiza (mark read); trigger do sistema insere (service role)
drop policy if exists "notifications_select_owner" on public.notifications;
drop policy if exists "notifications_update_owner" on public.notifications;
drop policy if exists "notifications_insert_service" on public.notifications;
create policy "notifications_select_owner" on public.notifications for select using (user_id = auth.uid());
create policy "notifications_update_owner" on public.notifications for update using (user_id = auth.uid());
create policy "notifications_insert_service" on public.notifications for insert with check (true);

-- ---------------------------------------------------------------------------
-- Storage buckets: avatars, covers e vídeos
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true),
  ('covers', 'covers', true),
  ('videos', 'videos', false)
on conflict (id) do nothing;

-- Videos são privados: só o dono sobe/ler; demais acessam via URL assinada
-- (o Flutter pede URL assinada via service role em uma Edge Function, evitando
-- expor a service role no app).
drop policy if exists "avatars_public" on storage.objects;
create policy "avatars_public" on storage.objects
  for all using (bucket_id = 'avatars') with check (bucket_id = 'avatars');

drop policy if exists "covers_public" on storage.objects;
create policy "covers_public" on storage.objects
  for all using (bucket_id = 'covers') with check (bucket_id = 'covers');

drop policy if exists "videos_insert_owner" on storage.objects;
create policy "videos_insert_owner" on storage.objects
  for insert with check (
    bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "videos_select_owner" on storage.objects;
create policy "videos_select_owner" on storage.objects
  for select using (
    bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "videos_delete_owner" on storage.objects;
create policy "videos_delete_owner" on storage.objects
  for delete using (
    bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text
  );
