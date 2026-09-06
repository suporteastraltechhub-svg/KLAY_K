-- KLAY K - FK auxiliares p/ embed de perfis via PostgREST
--
-- O app embute dados do perfil com `profiles:user_id(...)`, `profiles:streamer_id(...)`,
-- `actor:actor_id(...)` e `sender:user_id(...)`. Isso só resolve se houver FK real dessas
-- colunas apontando para `public.profiles(id)`. Originalmente todas apontavam só para
-- `auth.users`, então PostgREST devolvia PGRST200 ("Could not find a relationship...").
--
-- Como `profiles.id` ≡ `auth.users.id` (trigger handle_new_user), adicionar uma FK
-- adicional para `profiles(id)` mantém a integridade e desbloqueia os embeds de perfil
-- (posts, comentários, notificações, live chat e lives). Idempotente.

-- lives
alter table public.lives
  drop constraint if exists lives_streamer_id_profiles_fkey;
alter table public.lives
  add constraint lives_streamer_id_profiles_fkey
  foreign key (streamer_id) references public.profiles(id) on delete cascade;

-- live_chat
alter table public.live_chat
  drop constraint if exists live_chat_user_id_profiles_fkey;
alter table public.live_chat
  add constraint live_chat_user_id_profiles_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;

-- posts
alter table public.posts
  drop constraint if exists posts_user_id_profiles_fkey;
alter table public.posts
  add constraint posts_user_id_profiles_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;

-- comments
alter table public.comments
  drop constraint if exists comments_user_id_profiles_fkey;
alter table public.comments
  add constraint comments_user_id_profiles_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;

-- notifications (user_id = destinatário, actor_id = autor da ação)
alter table public.notifications
  drop constraint if exists notifications_user_id_profiles_fkey;
alter table public.notifications
  add constraint notifications_user_id_profiles_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;

alter table public.notifications
  drop constraint if exists notifications_actor_id_profiles_fkey;
alter table public.notifications
  add constraint notifications_actor_id_profiles_fkey
  foreign key (actor_id) references public.profiles(id) on delete cascade;
