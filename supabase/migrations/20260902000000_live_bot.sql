-- ============================================================================
-- KLAY K — LIVE BOT (settings / announcements / logs)
--
-- O "KLAY K LIVE BOT" é controlado pelo criador/moderador da live pelo app
-- (painel premium). A TRANSMISSÃO de áudio para a sala LiveKit é feita por um
-- bot de BACKEND (services/livekit-bot) que lê estas tabelas via Supabase —
-- o cliente NÃO publica áudio na sala (sem TTS no cliente) nem expõe segredos.
--
-- Segurança:
--   * Tabelas com RLS; leitura pública quando for mostrar estado aos
--     participantes; ESCRITA sempre via RPC `security definer` validando
--     `can_moderate_live()`, que cobre o DONO da live e moderadores.
--   * Nada de chaves/tokens de LiveKit aqui.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- live_bot_settings — configurações do bot por live (1 linha por live).
-- Guardamos um jsonb agnóstico para o bot de backend consumir, sem rigidez.
-- ---------------------------------------------------------------------------
create table if not exists public.live_bot_settings (
  live_id uuid primary key references public.lives(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  voice_settings jsonb not null default '{}'::jsonb,
  comment_reading_mode text not null default 'selected'
    check (comment_reading_mode in ('all','selected','questions','highlighted')),
  comments_enabled boolean not null default true,
  auto_replies_enabled boolean not null default false,
  auto_replies jsonb not null default '[]'::jsonb,
  announcements_enabled boolean not null default true,
  announcements_interval_seconds int not null default 120,
  moderation_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.live_bot_settings enable row level security;

-- Participantes podem ver o estado (ex.: se o bot está ligado/desligado).
drop policy if exists "live_bot_settings_select" on public.live_bot_settings;
create policy "live_bot_settings_select"
  on public.live_bot_settings for select
  using (true);

-- Sem policies de escrita: apenas via RPC security definer (dono/moderador).

-- ---------------------------------------------------------------------------
-- live_bot_announcements — anúncios configurados pelo criador.
-- ---------------------------------------------------------------------------
create table if not exists public.live_bot_announcements (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.lives(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 240),
  interval_seconds int not null default 120,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.live_bot_announcements enable row level security;

-- Participantes veem os anúncios (opcional, útil para UI); escrita só via RPC.
drop policy if exists "live_bot_announcements_select" on public.live_bot_announcements;
create policy "live_bot_announcements_select"
  on public.live_bot_announcements for select
  using (true);

-- ---------------------------------------------------------------------------
-- live_bot_logs — registro das ações do bot (auditoria / moderação).
-- ---------------------------------------------------------------------------
create table if not exists public.live_bot_logs (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.lives(id) on delete cascade,
  event_type text not null default 'bot',
  message text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.live_bot_logs enable row level security;

-- Apenas dono/moderador (ou staff) lê os logs.
drop policy if exists "live_bot_logs_select_mod" on public.live_bot_logs;
create policy "live_bot_logs_select_mod"
  on public.live_bot_logs for select
  using (
    public.can_moderate_live(live_id)
    or public.has_perm('moderation')
    or public.has_perm('audit')
  );

-- ============================================================================
-- RPCs (todas security definer).
-- "claim" de permissão: public.can_moderate_live(live_id)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Obter settings (qualquer participante autenticado).
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_get_settings(p_live_id uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select to_jsonb(s) from public.live_bot_settings s where s.live_id = p_live_id),
    '{}'::jsonb
  );
$$;

revoke all on function public.live_bot_get_settings(uuid) from public;
grant execute on function public.live_bot_get_settings(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Salvar settings (dono/moderador).
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_save_settings(
  p_live_id uuid,
  p_enabled boolean,
  p_voice_settings jsonb,
  p_comment_reading_mode text,
  p_comments_enabled boolean,
  p_auto_replies_enabled boolean,
  p_auto_replies jsonb,
  p_announcements_enabled boolean,
  p_announcements_interval_seconds int,
  p_moderation_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_mode text := coalesce(p_comment_reading_mode, 'selected');
begin
  if u is null then
    raise exception 'not_authenticated' using errcode = '22023';
  end if;
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator' using errcode = '42501';
  end if;
  if v_mode not in ('all','selected','questions','highlighted') then
    v_mode := 'selected';
  end if;

  insert into public.live_bot_settings (
    live_id, owner_id, enabled, voice_settings, comment_reading_mode,
    comments_enabled, auto_replies_enabled, auto_replies,
    announcements_enabled, announcements_interval_seconds, moderation_enabled
  ) values (
    p_live_id, u, coalesce(p_enabled, false), coalesce(p_voice_settings,'{}'::jsonb),
    v_mode, coalesce(p_comments_enabled, true),
    coalesce(p_auto_replies_enabled, false), coalesce(p_auto_replies,'[]'::jsonb),
    coalesce(p_announcements_enabled, true),
    coalesce(p_announcements_interval_seconds, 120),
    coalesce(p_moderation_enabled, false)
  )
  on conflict (live_id) do update set
    enabled = excluded.enabled,
    voice_settings = excluded.voice_settings,
    comment_reading_mode = excluded.comment_reading_mode,
    comments_enabled = excluded.comments_enabled,
    auto_replies_enabled = excluded.auto_replies_enabled,
    auto_replies = excluded.auto_replies,
    announcements_enabled = excluded.announcements_enabled,
    announcements_interval_seconds = excluded.announcements_interval_seconds,
    moderation_enabled = excluded.moderation_enabled,
    updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.live_bot_save_settings(uuid, boolean, jsonb, text, boolean, boolean, jsonb, boolean, int, boolean) from public;
grant execute on function public.live_bot_save_settings(uuid, boolean, jsonb, text, boolean, boolean, jsonb, boolean, int, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Listar anúncios (participantes autenticados).
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_list_announcements(p_live_id uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    jsonb_agg(to_jsonb(a) order by a.created_at),
    '[]'::jsonb
  )
  from public.live_bot_announcements a
  where a.live_id = p_live_id;
$$;

revoke all on function public.live_bot_list_announcements(uuid) from public;
grant execute on function public.live_bot_list_announcements(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Criar anúncio (dono/moderador).
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_add_announcement(
  p_live_id uuid,
  p_message text,
  p_interval_seconds int default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_msg text := btrim(p_message);
  v_id uuid;
begin
  if u is null then
    raise exception 'not_authenticated' using errcode = '22023';
  end if;
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator' using errcode = '42501';
  end if;
  if char_length(v_msg) < 1 or char_length(v_msg) > 240 then
    raise exception 'invalid_message' using errcode = '22000';
  end if;

  insert into public.live_bot_announcements (
    live_id, author_id, message, interval_seconds
  ) values (
    p_live_id, u, v_msg, coalesce(p_interval_seconds, 120)
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

revoke all on function public.live_bot_add_announcement(uuid, text, int) from public;
grant execute on function public.live_bot_add_announcement(uuid, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Ativar/desativar anúncio (dono/moderador).
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_set_announcement_enabled(
  p_announcement_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_live uuid;
begin
  if u is null then
    raise exception 'not_authenticated' using errcode = '22023';
  end if;

  select live_id into v_live
  from public.live_bot_announcements
  where id = p_announcement_id;

  if v_live is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if not public.can_moderate_live(v_live) then
    raise exception 'not_moderator' using errcode = '42501';
  end if;

  update public.live_bot_announcements
  set enabled = coalesce(p_enabled, true), updated_at = now()
  where id = p_announcement_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.live_bot_set_announcement_enabled(uuid, boolean) from public;
grant execute on function public.live_bot_set_announcement_enabled(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Remover anúncio (dono/moderador).
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_delete_announcement(p_announcement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_live uuid;
begin
  if u is null then
    raise exception 'not_authenticated' using errcode = '22023';
  end if;

  select live_id into v_live
  from public.live_bot_announcements
  where id = p_announcement_id;

  if v_live is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if not public.can_moderate_live(v_live) then
    raise exception 'not_moderator' using errcode = '42501';
  end if;

  delete from public.live_bot_announcements where id = p_announcement_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.live_bot_delete_announcement(uuid) from public;
grant execute on function public.live_bot_delete_announcement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Registrar log (qualquer evento do bot — escrito pelo backend/edge ou dono).
-- Apenas quem pode moderar a live pode gravar logs via cliente.
-- ---------------------------------------------------------------------------
create or replace function public.live_bot_log(
  p_live_id uuid,
  p_event_type text default 'bot',
  p_message text default '',
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  -- Permite service_role (bot de backend) gravar logs sem autenticação própria;
  -- pelo cliente, exige ser moderador da live.
  if u is not null and not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator' using errcode = '42501';
  end if;

  insert into public.live_bot_logs (live_id, event_type, message, metadata, actor_id)
  values (p_live_id, coalesce(p_event_type,'bot'), coalesce(p_message,''),
          coalesce(p_metadata,'{}'::jsonb), u);

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.live_bot_log(uuid, text, text, jsonb) from public;
grant execute on function public.live_bot_log(uuid, text, text, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Realtime: anunciar mudanças de settings/anúncios/seleção de comentário para
-- o painel e para o bot de backend reagirem em tempo real.
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.live_bot_announcements;
alter publication supabase_realtime add table public.live_bot_logs;
