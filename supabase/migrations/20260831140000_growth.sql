-- ============================================================================
-- KLAY K — GROWTH: ONBOARDING, PREFERÊNCIAS DE NOTIFICAÇÃO, RASCUNHOS
--  * user_settings.onboarding_done (gate do guia do iniciante)
--  * notification_preferences (categorias de notificação, incl. push futuro)
--  * notifications ganha title + data (para deep link / filtro por categoria)
--  * drafts (rascunhos de post com vídeo/capa): armazenamento privado no
--    bucket `drafts`, RLS por dono, sem aparição pública.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) user_settings.onboarding_done
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column if not exists onboarding_done boolean not null default false;

-- RPC para marcar o onboarding como concluído (segurança: só o próprio).
create or replace function public.set_onboarding_done(p_done boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.user_settings (user_id) values (u)
    on conflict (user_id) do nothing;
  update public.user_settings set onboarding_done = coalesce(p_done, true)
   where user_id = u;
  return jsonb_build_object('onboarding_done', coalesce(p_done, true));
end;
$$;

revoke all on function public.set_onboarding_done(boolean) from public;
grant execute on function public.set_onboarding_done(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) notification_preferences: categorias (likes/comments/follows/follow etc)
-- ---------------------------------------------------------------------------
create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  likes boolean not null default true,
  comments boolean not null default true,
  follows boolean not null default true,
  messages boolean not null default true,
  live boolean not null default true,
  missions boolean not null default true,
  rewards boolean not null default true,
  push_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists notification_prefs_user_idx
  on public.notification_preferences (user_id);

-- Defaults garantidos para qualquer usuário que consulte prefs (idempotente).
create or replace function public.my_notification_prefs()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v public.notification_preferences;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.notification_preferences (user_id) values (u)
    on conflict (user_id) do nothing;
  select * into v from public.notification_preferences where user_id = u;
  return jsonb_build_object(
    'likes', v.likes,
    'comments', v.comments,
    'follows', v.follows,
    'messages', v.messages,
    'live', v.live,
    'missions', v.missions,
    'rewards', v.rewards,
    'push_enabled', v.push_enabled
  );
end;
$$;

create or replace function public.save_notification_prefs(
  p_likes boolean default null,
  p_comments boolean default null,
  p_follows boolean default null,
  p_messages boolean default null,
  p_live boolean default null,
  p_missions boolean default null,
  p_rewards boolean default null,
  p_push_enabled boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.notification_preferences (user_id) values (u)
    on conflict (user_id) do nothing;
  update public.notification_preferences set
    likes = coalesce(p_likes, likes),
    comments = coalesce(p_comments, comments),
    follows = coalesce(p_follows, follows),
    messages = coalesce(p_messages, messages),
    live = coalesce(p_live, live),
    missions = coalesce(p_missions, missions),
    rewards = coalesce(p_rewards, rewards),
    push_enabled = coalesce(p_push_enabled, push_enabled),
    updated_at = now()
   where user_id = u;
  return public.my_notification_prefs();
end;
$$;

revoke all on function public.my_notification_prefs() from public;
grant execute on function public.my_notification_prefs() to authenticated;
revoke all on function public.save_notification_prefs(boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from public;
grant execute on function public.save_notification_prefs(boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;

alter table public.notification_preferences enable row level security;
drop policy if exists "notification_prefs_owner" on public.notification_preferences;
create policy "notification_prefs_owner" on public.notification_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) notifications: título + payload/categoria (deep link futuro)
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column if not exists title text not null default '',
  add column if not exists category text not null default '';

-- Aplica título/categoria padrão para linhas antigas (backfill honesto).
update public.notifications
   set title = case
         when type = 'like' then 'Curtiram seu vídeo'
         when type = 'comment' then 'Novo comentário'
         when type = 'follow' then 'Novo seguidor'
         when type = 'message' then 'Nova mensagem'
         when type in ('gift', 'gift_send', 'gift_sent') then 'Presente recebido'
         else 'Nova atividade'
       end,
       category = case
         when type = 'like' then 'likes'
         when type = 'comment' then 'comments'
         when type = 'follow' then 'follows'
         when type = 'message' then 'messages'
         when type in ('gift', 'gift_send', 'gift_sent') then 'rewards'
         else 'other'
       end
 where title = '' or category = '';

-- RPC de marcar todas como lidas (mais limpa que batch no cliente).
create or replace function public.mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications set read = true
   where user_id = auth.uid() and read = false;
end;
$$;

revoke all on function public.mark_all_notifications_read() from public;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) drafts: rascunhos de publicação (privados, nunca aparecem no feed)
-- ---------------------------------------------------------------------------
create table if not exists public.drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  video_path text,
  cover_path text,
  description text default '',
  audio_name text default '',
  hashtags text[] not null default '{}',
  location text default '',
  duration_seconds int not null default 0,
  status text not null default 'draft' check (status in ('draft', 'published', 'trashed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists drafts_user_idx on public.drafts (user_id, updated_at desc);

alter table public.drafts enable row level security;
drop policy if exists "drafts_owner" on public.drafts;
create policy "drafts_owner" on public.drafts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5) Bucket privado para vídeos/capas de rascunho (patrão `{uid}/...`)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('drafts', 'drafts', false)
on conflict (id) do nothing;

drop policy if exists "drafts_read_owner" on storage.objects;
create policy "drafts_read_owner" on storage.objects
  for select using (bucket_id = 'drafts' and storage.foldername(name)[1] = auth.uid()::text);

drop policy if exists "drafts_write_owner" on storage.objects;
create policy "drafts_write_owner" on storage.objects
  for insert with check (
    bucket_id = 'drafts'
    and storage.foldername(name)[1] = auth.uid()::text
  );

drop policy if exists "drafts_update_owner" on storage.objects;
create policy "drafts_update_owner" on storage.objects
  for update using (
    bucket_id = 'drafts' and storage.foldername(name)[1] = auth.uid()::text
  );

drop policy if exists "drafts_delete_owner" on storage.objects;
create policy "drafts_delete_owner" on storage.objects
  for delete using (
    bucket_id = 'drafts' and storage.foldername(name)[1] = auth.uid()::text
  );