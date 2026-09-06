-- KLAY K - Configurações, Central de Ajuda e Verificação de Perfil
-- Tabelas novas (sem duplicar as existentes) + colunas de perfil.

-- ---------------------------------------------------------------------------
-- profiles: novos campos (privacidade + verificação)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_private boolean not null default false,
  add column if not exists is_verified boolean not null default false,
  add column if not exists bio text default '';

-- ---------------------------------------------------------------------------
-- user_settings: configurações persistentes do app (uma linha por usuário)
-- ---------------------------------------------------------------------------
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  notify_curtidas boolean not null default true,
  notify_comentarios boolean not null default true,
  notify_novos_seguidores boolean not null default true,
  notify_mensagens boolean not null default true,
  notify_live boolean not null default true,
  notify_outras boolean not null default true,
  auto_play boolean not null default true,
  wifi_only boolean not null default false,
  video_quality text not null default 'auto',
  save_data boolean not null default false,
  background_play boolean not null default false,
  account_private boolean not null default false,
  allow_comments boolean not null default true,
  allow_messages text not null default 'everyone' check (allow_messages in ('everyone','followers','none')),
  security_confirm_actions boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- verification_requests: pedidos de verificação de perfil
-- ---------------------------------------------------------------------------
create table if not exists public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  reason text default '',
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  admin_note text default '',
  unique (user_id)
);

-- ---------------------------------------------------------------------------
-- support_tickets: chamados da Central de Ajuda
-- ---------------------------------------------------------------------------
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  subject text not null,
  message text not null,
  status text not null default 'open'
    check (status in ('open','in_review','answered','closed')),
  admin_reply text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- blocked_users: bloqueios de privacidade/segurança
-- ---------------------------------------------------------------------------
create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists verification_user_idx on public.verification_requests (user_id);
create index if not exists verification_status_idx on public.verification_requests (status);
create index if not exists support_user_idx on public.support_tickets (user_id, created_at desc);
create index if not exists support_status_idx on public.support_tickets (status);
create index if not exists blocked_user_idx on public.blocked_users (blocked_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.user_settings enable row level security;
alter table public.verification_requests enable row level security;
alter table public.support_tickets enable row level security;
alter table public.blocked_users enable row level security;

-- user_settings: o dono lê/insere/atualiza os próprios
drop policy if exists "user_settings_select_owner" on public.user_settings;
drop policy if exists "user_settings_insert_owner" on public.user_settings;
drop policy if exists "user_settings_update_owner" on public.user_settings;
create policy "user_settings_select_owner" on public.user_settings for select using (user_id = auth.uid());
create policy "user_settings_insert_owner" on public.user_settings for insert with check (user_id = auth.uid());
create policy "user_settings_update_owner" on public.user_settings for update using (user_id = auth.uid());

-- verification_requests: o dono cria e consulta o próprio; aprovação só via service role (admin)
drop policy if exists "verif_select_owner" on public.verification_requests;
drop policy if exists "verif_insert_owner" on public.verification_requests;
drop policy if exists "verif_update_service" on public.verification_requests;
create policy "verif_select_owner" on public.verification_requests for select using (user_id = auth.uid());
create policy "verif_insert_owner" on public.verification_requests for insert with check (user_id = auth.uid());
create policy "verif_update_service" on public.verification_requests for update using (true);

-- support_tickets: o dono cria/consulta o próprio; pode atualizar (ex.: fechar) o seu;
-- o painel administrativo (service role) lê/atualiza todos
drop policy if exists "tickets_select_owner" on public.support_tickets;
drop policy if exists "tickets_insert_owner" on public.support_tickets;
drop policy if exists "tickets_update_owner" on public.support_tickets;
drop policy if exists "tickets_update_service" on public.support_tickets;
create policy "tickets_select_owner" on public.support_tickets for select using (user_id = auth.uid());
create policy "tickets_insert_owner" on public.support_tickets for insert with check (user_id = auth.uid());
create policy "tickets_update_owner" on public.support_tickets for update using (user_id = auth.uid());
create policy "tickets_update_service" on public.support_tickets for update using (true) with check (true);

-- blocked_users: o bloqueador gerencia seus próprios bloqueios; a leitura da
-- lista de "quem me bloqueou" não é necessária, então só o dono lê os seus
drop policy if exists "blocked_select_owner" on public.blocked_users;
drop policy if exists "blocked_insert_owner" on public.blocked_users;
drop policy if exists "blocked_delete_owner" on public.blocked_users;
create policy "blocked_select_owner" on public.blocked_users for select using (blocker_id = auth.uid());
create policy "blocked_insert_owner" on public.blocked_users for insert with check (blocker_id = auth.uid());
create policy "blocked_delete_owner" on public.blocked_users for delete using (blocker_id = auth.uid());
