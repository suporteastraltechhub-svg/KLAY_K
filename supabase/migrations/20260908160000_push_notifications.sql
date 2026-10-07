-- ============================================================================
-- KLAY K — Push Android (FCM como transporte, Supabase continua backend)
-- ============================================================================
-- Fluxo: EVENTO REAL → linha em `notifications` → trigger enfileira o envio
-- via pg_net → Edge Function `send-push` (ambiente confiável) → FCM → barra de
-- notificações do Android. Nenhuma credencial administrativa no APK; tokens de
-- dispositivo são privados (RLS); o envio somente na Edge Function com secrets.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) push_tokens: token de dispositivo por usuário (vários por usuário)
-- ---------------------------------------------------------------------------
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint push_tokens_token_unique unique (token),
  constraint push_tokens_check check (char_length(token) between 8 and 512)
);

create index if not exists push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;

-- Usuário só gerencia os PRÓPRIOS tokens; nunca faz leitura pública.
drop policy if exists "push_tokens_insert_owner" on public.push_tokens;
create policy "push_tokens_insert_owner" on public.push_tokens
  for insert with check (user_id = auth.uid());
drop policy if exists "push_tokens_select_owner" on public.push_tokens;
create policy "push_tokens_select_owner" on public.push_tokens
  for select using (user_id = auth.uid());
drop policy if exists "push_tokens_delete_owner" on public.push_tokens;
create policy "push_tokens_delete_owner" on public.push_tokens
  for delete using (user_id = auth.uid());

revoke all on table public.push_tokens from anon;
grant insert, select, delete on table public.push_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- 2) RPCs de gestão de token (security definer: anexa/desanexa do dono)
-- ---------------------------------------------------------------------------
create or replace function public.register_push_token(
  p_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated' using errcode = '28503'; end if;
  if p_token is null or char_length(p_token) < 8 or char_length(p_token) > 512 then
    raise exception 'invalid_token' using errcode = '22000';
  end if;
  insert into public.push_tokens (user_id, token, platform, updated_at, last_seen_at)
  values (u, p_token, coalesce(nullif(p_platform, ''), 'android'), now(), now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now(),
        last_seen_at = now();
end;
$$;

-- Remove o token deste dispositivo (logout/após token inválido).
create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated' using errcode = '28503'; end if;
  delete from public.push_tokens
   where token = p_token
     and user_id = u;
end;
$$;

-- Desassocia TODOS os tokens do usuário (logout em todos os dispositivos).
create or replace function public.clear_push_tokens()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated' using errcode = '28503'; end if;
  delete from public.push_tokens where user_id = u;
end;
$$;

revoke all on function public.register_push_token(text, text) from public;
grant execute on function public.register_push_token(text, text) to authenticated;
revoke all on function public.unregister_push_token(text) from public;
grant execute on function public.unregister_push_token(text) to authenticated;
revoke all on function public.clear_push_tokens() from public;
grant execute on function public.clear_push_tokens() to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Config do push (somente servidor): URL da Edge Function + segredo do
--    webhook. NUNCA é exposta ao cliente (sem grants, sem RLS de leitura).
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto;

create table if not exists public.push_notification_config (
  id smallint primary key default 1 check (id = 1),
  function_url text not null,
  webhook_secret text not null,
  updated_at timestamptz not null default now()
);

-- Seed idempotente: URL da função do projeto e um segredo aleatório.
-- Depois de aplicar a migration, copie o segredo (`select webhook_secret from
-- public.push_notification_config;`) e registre como secret da Edge Function
-- `send-push` com o nome PUSH_WEBHOOK_SECRET (ver relatório final).
insert into public.push_notification_config (function_url, webhook_secret)
values (
  'https://oysyuialaelzcxxkfdsl.functions.supabase.co/functions/v1/send-push',
  replace(gen_random_uuid()::text, '-', '') ||
  replace(gen_random_uuid()::text, '-', '')
)
on conflict (id) do nothing;

alter table public.push_notification_config enable row level security;
drop policy if exists "push_config_none" on public.push_notification_config;
create policy "push_config_none" on public.push_notification_config
  for select using (false);
revoke all on table public.push_notification_config from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Trigger: a cada notificação real inserida, enfileira o envio do push à
--    Edge Function (via pg_net, sem bloquear a transação). Idempotência: o
--    evento existe uma única vez em `notifications` → no máximo um push.
--    Categorias sem push Android são ignoradas aqui.
-- ---------------------------------------------------------------------------
create extension if not exists pg_net;

create or replace function public.push_notification_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.push_notification_config%rowtype;
begin
  -- Eventos sem push Android (self/estado interno do próprio app).
  if NEW.type in ('record', 'reward', 'live_end', 'live_viewer', 'verification', 'sale') then
    return NEW;
  end if;
  if NEW.user_id is null then
    return NEW;
  end if;

  select * into cfg from public.push_notification_config where id = 1;
  if cfg.webhook_secret is null or cfg.function_url is null then
    return NEW;
  end if;

  perform net.http_post(
    url => cfg.function_url,
    headers => jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cfg.webhook_secret
    ),
    body => jsonb_build_object('notification_id', NEW.id::text),
    timeout_milliseconds => 10000
  );
  return NEW;
exception when others then
  -- Falha no agendamento do push NUNCA derruba a criação da notificação.
  return NEW;
end;
$$;

drop trigger if exists push_notification_on_insert on public.notifications;
create trigger push_notification_on_insert
  after insert on public.notifications
  for each row execute function public.push_notification_on_insert();