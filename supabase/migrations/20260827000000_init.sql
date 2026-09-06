-- KLAY K - Initial schema
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid() references auth.users(id) on delete cascade,
  username text unique,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- Compatibilidade com projetos que já têm uma tabela `profiles` criada por
-- outro template (ex.: starter com id/username/display_name, sem avatar_url).
alter table public.profiles
  add column if not exists display_name text,
  add column if not exists avatar_url text;

-- ---------------------------------------------------------------------------
-- lives
-- ---------------------------------------------------------------------------
create table if not exists public.lives (
  id uuid primary key default gen_random_uuid(),
  streamer_id uuid not null references auth.users(id) on delete cascade,
  room_name text unique not null,
  title text not null,
  description text default '',
  category text default '',
  hashtags text[] not null default '{}',
  privacy text not null default 'public',
  status text not null default 'live' check (status in ('live','ended','scheduled')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  viewer_count int not null default 0,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- live_participants
-- ---------------------------------------------------------------------------
create table if not exists public.live_participants (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references lives(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz default now(),
  left_at timestamptz,
  is_streamer boolean not null default false,
  unique (live_id, user_id)
);

-- ---------------------------------------------------------------------------
-- live_chat
-- ---------------------------------------------------------------------------
create table if not exists public.live_chat (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references lives(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- live_gifts
-- ---------------------------------------------------------------------------
create table if not exists public.live_gifts (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references lives(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid references auth.users(id) on delete set null,
  gift_id text not null,
  gift_name text not null,
  gift_amount int not null default 1,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- live_events
-- ---------------------------------------------------------------------------
create table if not exists public.live_events (
  id uuid primary key default gen_random_uuid(),
  live_id uuid references lives(id) on delete cascade,
  event_type text not null check (event_type in ('USER_JOINED','USER_LEFT','CHAT_MESSAGE','GIFT_RECEIVED','FOLLOW','LIVE_STARTED','LIVE_ENDED','LIKE','SHARE')),
  user_id uuid references auth.users(id) on delete set null,
  username text,
  metadata jsonb not null default '{}',
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists lives_status_idx on public.lives (status);
create index if not exists lives_streamer_id_idx on public.lives (streamer_id);
create index if not exists live_participants_live_id_idx on public.live_participants (live_id);
create index if not exists live_chat_live_created_idx on public.live_chat (live_id, created_at);
create index if not exists live_gifts_live_id_idx on public.live_gifts (live_id);
create index if not exists live_events_live_created_idx on public.live_events (live_id, created_at);

-- ---------------------------------------------------------------------------
-- Trigger: create a profile row automatically for every new auth user
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'username', ''), 'user-' || left(new.id::text, 8)),
    coalesce(
      nullif(new.raw_user_meta_data->>'full_name', ''),
      coalesce(nullif(new.raw_user_meta_data->>'name', ''), 'Participante')
    ),
    null
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  before insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.lives enable row level security;
alter table public.live_participants enable row level security;
alter table public.live_chat enable row level security;
alter table public.live_gifts enable row level security;
alter table public.live_events enable row level security;

-- profiles
drop policy if exists "profiles_select_all" on public.profiles;
drop policy if exists "profiles_insert_owner" on public.profiles;
drop policy if exists "profiles_update_owner" on public.profiles;
drop policy if exists "profiles_delete_owner" on public.profiles;
create policy "profiles_select_all" on public.profiles for select using (true);
create policy "profiles_insert_owner" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update_owner" on public.profiles for update using (auth.uid() = id);
create policy "profiles_delete_owner" on public.profiles for delete using (auth.uid() = id);

-- lives
create policy "lives_select_all" on public.lives for select using (true);
create policy "lives_insert_owner" on public.lives for insert with check (streamer_id = auth.uid());
create policy "lives_update_owner" on public.lives for update using (streamer_id = auth.uid());
create policy "lives_delete_owner" on public.lives for delete using (streamer_id = auth.uid());

-- live_participants
create policy "live_participants_select_all" on public.live_participants for select using (true);
create policy "live_participants_insert_owner" on public.live_participants for insert with check (user_id = auth.uid());
create policy "live_participants_update_owner" on public.live_participants for update using (user_id = auth.uid());
create policy "live_participants_delete_owner" on public.live_participants for delete using (user_id = auth.uid());

-- live_chat
create policy "live_chat_select_all" on public.live_chat for select using (true);
create policy "live_chat_insert_owner" on public.live_chat for insert with check (user_id = auth.uid());
create policy "live_chat_delete_own" on public.live_chat for delete using (
  user_id = auth.uid() or
  exists (
    select 1 from public.lives l where l.id = live_id and l.streamer_id = auth.uid()
  )
);

-- live_gifts
create policy "live_gifts_select_all" on public.live_gifts for select using (true);
create policy "live_gifts_insert_owner" on public.live_gifts for insert with check (sender_id = auth.uid());

-- live_events
create policy "live_events_select_all" on public.live_events for select using (true);
create policy "live_events_insert_all" on public.live_events for insert with check (true);
