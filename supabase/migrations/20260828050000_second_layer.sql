-- KLAY K - Segunda camada: busca, notificações, coleções, histórico,
-- denúncia/bloqueio/silêncio, moderação, anti-spam, painel do criador,
-- conquistas/níveis.

-- ---------------------------------------------------------------------------
-- muted_users: silenciar usuários (não receber o conteúdo/interações)
-- ---------------------------------------------------------------------------
create table if not exists public.muted_users (
  muter_id uuid not null references auth.users(id) on delete cascade,
  muted_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id)
);

-- ---------------------------------------------------------------------------
-- collections + collection_posts: favoritos/coleções do usuário
-- ---------------------------------------------------------------------------
create table if not exists public.collections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text default '',
  cover_url text default '',
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.collection_posts (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.collections(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (collection_id, post_id)
);

-- ---------------------------------------------------------------------------
-- user_history: histórico de visualização
-- ---------------------------------------------------------------------------
create table if not exists public.user_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete set null,
  live_id uuid references public.lives(id) on delete set null,
  ref_type text not null default 'post' check (ref_type in ('post','live')),
  watched_at timestamptz not null default now(),
  unique (user_id, post_id, live_id, ref_type)
);

-- ---------------------------------------------------------------------------
-- reports: denúncias (usuários, vídeos, lives, comentários, chats)
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('user','post','live','comment','chat')),
  target_id text not null,
  reason text not null,
  details text default '',
  status text not null default 'pending' check (status in ('pending','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

-- ---------------------------------------------------------------------------
-- live_moderators: moderadores de uma LIVE (indicados pelo criador)
-- ---------------------------------------------------------------------------
create table if not exists public.live_moderators (
  live_id uuid not null references public.lives(id) on delete cascade,
  moderator_id uuid not null references auth.users(id) on delete cascade,
  added_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (live_id, moderator_id)
);

-- ---------------------------------------------------------------------------
-- moderation_actions: log de ações de moderação (excluir post/chat/comentário)
-- ---------------------------------------------------------------------------
create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  live_id uuid references public.lives(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target text not null default '',
  reason text default '',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- anti_spam_rules: regras de filtro anti-spam (geridas por administrador)
-- ---------------------------------------------------------------------------
create table if not exists public.anti_spam_rules (
  id uuid primary key default gen_random_uuid(),
  pattern text not null,
  rule_type text not null default 'block' check (rule_type in ('block','flag','warn')),
  scope text not null default 'chat' check (scope in ('chat','comment','message','all')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- user_stats: estatísticas agregadas do criador (painel do criador)
-- ---------------------------------------------------------------------------
create table if not exists public.user_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  followers_count int not null default 0,
  following_count int not null default 0,
  posts_count int not null default 0,
  total_likes int not null default 0,
  total_comments int not null default 0,
  total_views int not null default 0,
  total_live_views int not null default 0,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- achievements + user_achievements: conquistas e níveis
-- ---------------------------------------------------------------------------
create table if not exists public.achievements (
  id text primary key,
  name text not null,
  description text not null default '',
  icon text default '',
  xp integer not null default 0,
  condition_type text not null default 'manual' check (condition_type in ('manual','followers','posts','views','lives','level')),
  condition_value integer not null default 0
);

create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references public.achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  unique (user_id, achievement_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists collections_user_idx on public.collections (user_id);
create index if not exists collection_posts_col_idx on public.collection_posts (collection_id);
create index if not exists collection_posts_post_idx on public.collection_posts (post_id);
create index if not exists history_user_idx on public.user_history (user_id, watched_at desc);
create index if not exists reports_status_idx on public.reports (status);
create index if not exists reports_target_idx on public.reports (target_type, target_id);
create index if not exists live_mods_live_idx on public.live_moderators (live_id);
create index if not exists mod_actions_comment_idx on public.moderation_actions (comment_id);
create index if not exists spam_scope_active_idx on public.anti_spam_rules (scope) where active;
create index if not exists user_achievements_user_idx on public.user_achievements (user_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.muted_users enable row level security;
alter table public.collections enable row level security;
alter table public.collection_posts enable row level security;
alter table public.user_history enable row level security;
alter table public.reports enable row level security;
alter table public.live_moderators enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.anti_spam_rules enable row level security;
alter table public.user_stats enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;

-- muted_users: o dono gerencia; leitura pública p/ ocultar conteúdo do mutado
drop policy if exists "muted_select_all" on public.muted_users;
drop policy if exists "muted_insert_owner" on public.muted_users;
drop policy if exists "muted_delete_owner" on public.muted_users;
create policy "muted_select_all" on public.muted_users for select using (true);
create policy "muted_insert_owner" on public.muted_users for insert with check (muter_id = auth.uid());
create policy "muted_delete_owner" on public.muted_users for delete using (muter_id = auth.uid());

-- collections: dono gerencia; leitura pública das públicas
drop policy if exists "collections_select" on public.collections;
drop policy if exists "collections_insert_owner" on public.collections;
drop policy if exists "collections_update_owner" on public.collections;
drop policy if exists "collections_delete_owner" on public.collections;
create policy "collections_select" on public.collections for select using (user_id = auth.uid() or is_public);
create policy "collections_insert_owner" on public.collections for insert with check (user_id = auth.uid());
create policy "collections_update_owner" on public.collections for update using (user_id = auth.uid());
create policy "collections_delete_owner" on public.collections for delete using (user_id = auth.uid());

-- collection_posts: dono das coleções gerencia; leitura pública das públicas
drop policy if exists "cposts_select" on public.collection_posts;
drop policy if exists "cposts_insert_owner" on public.collection_posts;
drop policy if exists "cposts_delete_owner" on public.collection_posts;
create policy "cposts_select" on public.collection_posts
  for select using (
    exists (select 1 from public.collections c
            where c.id = collection_id and (c.user_id = auth.uid() or c.is_public))
  );
create policy "cposts_insert_owner" on public.collection_posts
  for insert with check (
    exists (select 1 from public.collections c
            where c.id = collection_id and c.user_id = auth.uid())
  );
create policy "cposts_delete_owner" on public.collection_posts
  for delete using (
    exists (select 1 from public.collections c
            where c.id = collection_id and c.user_id = auth.uid())
  );

-- user_history: só o dono lê/insere/remove o próprio histórico
drop policy if exists "history_select_owner" on public.user_history;
drop policy if exists "history_insert_owner" on public.user_history;
drop policy if exists "history_delete_owner" on public.user_history;
create policy "history_select_owner" on public.user_history for select using (user_id = auth.uid());
create policy "history_insert_owner" on public.user_history for insert with check (user_id = auth.uid());
create policy "history_delete_owner" on public.user_history for delete using (user_id = auth.uid());

-- reports: qualquer usuário logado pode denunciar; só admin (service role) revisa
drop policy if exists "reports_insert" on public.reports;
drop policy if exists "reports_select_own" on public.reports;
drop policy if exists "reports_update_service" on public.reports;
create policy "reports_insert" on public.reports for insert with check (reporter_id = auth.uid());
create policy "reports_select_own" on public.reports for select using (reporter_id = auth.uid());
create policy "reports_update_service" on public.reports for update using (true) with check (true);

-- live_moderators: criador da live adiciona; moderador/qualquer lê
drop policy if exists "livemods_select" on public.live_moderators;
drop policy if exists "livemods_insert_creator" on public.live_moderators;
drop policy if exists "livemods_delete_creator" on public.live_moderators;
create policy "livemods_select" on public.live_moderators for select using (true);
create policy "livemods_insert_creator" on public.live_moderators
  for insert with check (
    exists (select 1 from public.lives l where l.id = live_id and l.streamer_id = auth.uid())
  );
create policy "livemods_delete_creator" on public.live_moderators
  for delete using (
    exists (select 1 from public.lives l where l.id = live_id and l.streamer_id = auth.uid())
  );

-- moderation_actions: criador/moderador registram; admin lê tudo; leitura pública
-- das ações de um post p/ refletir "removido por moderação"
drop policy if exists "modactions_insert_autorized" on public.moderation_actions;
drop policy if exists "modactions_select_own" on public.moderation_actions;
create policy "modactions_insert_autorized" on public.moderation_actions
  for insert with check (
    exists (select 1 from public.live_moderators lm where lm.live_id = live_id and lm.moderator_id = auth.uid())
    or exists (select 1 from public.lives l where l.id = live_id and l.streamer_id = auth.uid())
  );
create policy "modactions_select_own" on public.moderation_actions
  for select using (
    actor_id = auth.uid()
    or exists (select 1 from public.live_moderators lm where lm.moderator_id = auth.uid())
  );

-- anti_spam_rules: leitura pública (p/ clientes aplicarem filtro local).
-- Escrita é exclusiva do service role (painel administrativo), que ignora RLS.
drop policy if exists "spam_select" on public.anti_spam_rules;
create policy "spam_select" on public.anti_spam_rules for select using (true);

-- user_stats: dono lê e atualiza (painel do criador); leitura pública mínima
drop policy if exists "stats_select_owner" on public.user_stats;
drop policy if exists "stats_update_owner" on public.user_stats;
drop policy if exists "stats_upsert_owner" on public.user_stats;
create policy "stats_select_owner" on public.user_stats for select using (user_id = auth.uid());
create policy "stats_update_owner" on public.user_stats for update using (user_id = auth.uid());
create policy "stats_upsert_owner" on public.user_stats for insert with check (user_id = auth.uid());

-- achievements: leitura pública do catálogo de conquistas
drop policy if exists "ach_select" on public.achievements;
create policy "ach_select" on public.achievements for select using (true);

-- user_achievements: dono lê/desbloqueia o próprio; admin (service role) força
drop policy if exists "uach_select_owner" on public.user_achievements;
drop policy if exists "uach_insert_owner" on public.user_achievements;
create policy "uach_select_owner" on public.user_achievements for select using (user_id = auth.uid());
create policy "uach_insert_owner" on public.user_achievements for insert with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Catálogo base de conquistas + níveis (seed em PT-BR)
-- ---------------------------------------------------------------------------
insert into public.achievements (id, name, description, icon, xp, condition_type, condition_value) values
  ('welcome', 'Boas-vindas', 'Ser bem-vindo ao KLAY K', '🎉', 10, 'manual', 1),
  ('first_post', 'Primeiro post', 'Publicar o primeiro vídeo', '📹', 20, 'posts', 1),
  ('first_follower', 'Primeiro seguidor', 'Conquistar o primeiro seguidor', '❤️', 15, 'followers', 1),
  ('ten_posts', 'Criador ativo', 'Publicar 10 vídeos', '🎬', 50, 'posts', 10),
  ('hundred_views', 'Em alta', 'Acumular 100 visualizações', '🔥', 30, 'views', 100),
  ('tenthousand_views', 'Viralizando', 'Acumular 10.000 visualizações', '🚀', 100, 'views', 10000),
  ('first_live', 'Ao vivo', 'Fazer a primeira transmissão', '🔴', 25, 'lives', 1),
  ('level_2', 'Nível 2', 'Alcançar o nível 2', '⭐', 20, 'level', 2),
  ('level_5', 'Nível 5', 'Alcançar o nível 5', '🌟', 50, 'level', 5)
on conflict (id) do nothing;
