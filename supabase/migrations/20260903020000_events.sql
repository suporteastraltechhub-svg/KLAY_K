-- ============================================================================
-- KLAY K - Eventos
-- Eventos públicos agendados (shows, maratonas, campeonatos, encontros) que
-- os usuários podem descobrir e confirmar presença (RSVP). Dados reais.
-- O schema de `live_events`/`gift_events` NÃO é tocado (são outros mecanismos).
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  description text not null default '',
  category text default '',
  location text default '',
  banner_url text default '',
  starts_at timestamptz not null,
  ends_at timestamptz,
  organizer_id uuid references auth.users(id) on delete set null,
  participant_count int not null default 0,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- event_rsvps (presença confirmada)
-- ---------------------------------------------------------------------------
create table if not exists public.event_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists events_starts_at_idx on public.events (starts_at);
create index if not exists events_category_idx on public.events (category);
create index if not exists event_rsvps_event_idx on public.event_rsvps (event_id);
create index if not exists event_rsvps_user_idx on public.event_rsvps (user_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.events enable row level security;
alter table public.event_rsvps enable row level security;

-- events: leitura pública só dos públicos; escrita apenas pelo organizador.
drop policy if exists events_select_public on public.events;
drop policy if exists events_insert_owner on public.events;
drop policy if exists events_update_owner on public.events;
drop policy if exists events_delete_owner on public.events;
create policy events_select_public on public.events
  for select using (is_public = true);
create policy events_insert_owner on public.events
  for insert with check (auth.uid() = organizer_id);
create policy events_update_owner on public.events
  for update using (auth.uid() = organizer_id);
create policy events_delete_owner on public.events
  for delete using (auth.uid() = organizer_id);

-- event_rsvps: usuário gerencia a própria presença.
drop policy if exists event_rsvps_select on public.event_rsvps;
drop policy if exists event_rsvps_insert on public.event_rsvps;
drop policy if exists event_rsvps_delete_self on public.event_rsvps;
create policy event_rsvps_select on public.event_rsvps
  for select using (true);
create policy event_rsvps_insert on public.event_rsvps
  for insert with check (auth.uid() = user_id);
create policy event_rsvps_delete_self on public.event_rsvps
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Sincroniza participant_count ao inserir/excluir RSVP.
-- ---------------------------------------------------------------------------
drop trigger if exists event_rsvps_count on public.event_rsvps;
create or replace function public.event_rsvps_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.events set participant_count = participant_count + 1 where id = new.event_id;
  elsif (tg_op = 'DELETE') then
    update public.events set participant_count = greatest(participant_count - 1, 0) where id = old.event_id;
  end if;
  return coalesce(new, old);
end;
$$;
create trigger event_rsvps_count
  after insert or delete on public.event_rsvps
  for each row execute function public.event_rsvps_count();

-- ---------------------------------------------------------------------------
-- RPC: categorias com contagem de eventos (exploração).
-- ---------------------------------------------------------------------------
create or replace function public.event_categories()
returns table (category text, cnt bigint)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(category, ''), 'Outros') as category, count(*)::bigint as cnt
  from public.events
  where is_public = true
  group by coalesce(nullif(category, ''), 'Outros')
  order by cnt desc;
$$;
revoke all on function public.event_categories() from public;
grant execute on function public.event_categories() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC: posição de presença do usuário num evento.
-- ---------------------------------------------------------------------------
create or replace function public.event_rsvp_state(p_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.event_rsvps
    where event_id = p_event_id and user_id = auth.uid()
  );
$$;
revoke all on function public.event_rsvp_state(uuid) from public;
grant execute on function public.event_rsvp_state(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: id dos eventos que o usuário confirmou presença.
-- ---------------------------------------------------------------------------
create or replace function public.event_my_ids()
returns table (event_id uuid)
language sql
security definer
set search_path = public
as $$
  select r.event_id
  from public.event_rsvps r
  where r.user_id = auth.uid();
$$;
revoke all on function public.event_my_ids() from public;
grant execute on function public.event_my_ids() to authenticated;