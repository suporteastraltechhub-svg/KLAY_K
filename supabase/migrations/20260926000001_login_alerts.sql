-- ============================================================================
-- KLAY K — ALERTAS DE LOGIN + STATUS DE MFA (aditivo)
--
-- Nada é removido. Só cria:
--  * `security_login_alerts` (tabela nova com RLS owner-only);
--  * funções de leitura para o app;
--  * um trigger de preenchimento em `auth.sessions` — best effort: se o
--    projeto Supabase não permitir trigger no schema `auth`, a migration
--    emite NOTICE e segue (a tabela continua válida e pode ser populada
--    pelo Auth Hook `login`), nunca falha o deploy.
--
-- 2FA NÃO precisa de migration: é a API nativa `auth.mfa` do Supabase.
-- Aqui apenas expomos o STATUS real em SQL para a Central de Segurança.
-- ============================================================================

create table if not exists public.security_login_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null default 'login'
    check (event_type in ('login','logout','password_change','mfa_enrolled','mfa_unenrolled','token_revoked','suspicious')),
  device_label text default '',
  user_agent text default '',
  ip inet,
  aal text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists security_login_alerts_user_idx
  on public.security_login_alerts (user_id, created_at desc);

alter table public.security_login_alerts enable row level security;

drop policy if exists "security_login_alerts_select_owner" on public.security_login_alerts;
drop policy if exists "security_login_alerts_update_owner" on public.security_login_alerts;
create policy "security_login_alerts_select_owner" on public.security_login_alerts
  for select using (user_id = auth.uid());
create policy "security_login_alerts_update_owner" on public.security_login_alerts
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Trigger best-effort em auth.sessions (somente INSERT = novo acesso)
-- ---------------------------------------------------------------------------
create or replace function public.tg_auth_session_login_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.security_login_alerts
    (user_id, event_type, user_agent, ip, aal)
  values
    (new.user_id, 'login', coalesce(new.user_agent, ''), new.ip, new.aal::text);
  return new;
exception
  when others then
    return new;
end;
$$;

do $$
begin
  if to_regclass('auth.sessions') is null then
    raise notice 'auth.sessions indisponível: alertas de login dependem do Auth Hook.';
    return;
  end if;
  execute 'drop trigger if exists tg_auth_session_login_alert on auth.sessions';
  execute 'create trigger tg_auth_session_login_alert
           after insert on auth.sessions
           for each row execute function public.tg_auth_session_login_alert()';
exception
  when others then
    raise notice 'Trigger de login não criado (sem privilégio em auth.sessions). Use o Auth Hook para popular a tabela.';
end;
$$;

-- ---------------------------------------------------------------------------
-- my_login_alerts: histórico real do próprio usuário
-- ---------------------------------------------------------------------------
create or replace function public.my_login_alerts(p_limit int default 30)
returns table (
  id uuid,
  event_type text,
  device_label text,
  user_agent text,
  ip inet,
  aal text,
  created_at timestamptz,
  read_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  return query
    select a.id, a.event_type, a.device_label, a.user_agent, a.ip, a.aal,
           a.created_at, a.read_at
      from public.security_login_alerts a
     where a.user_id = auth.uid()
     order by a.created_at desc
     limit greatest(1, least(coalesce(p_limit, 30), 100));
end;
$$;

revoke all on function public.my_login_alerts(int) from public, anon;
grant execute on function public.my_login_alerts(int) to authenticated;

-- ---------------------------------------------------------------------------
-- log_login_alert: permite ao app/hook registrar um evento específico
-- (ex.: troca de senha, 2FA). Nunca grava para outro usuário.
-- ---------------------------------------------------------------------------
create or replace function public.log_login_alert(
  p_event_type text default 'login',
  p_device_label text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if p_event_type not in
     ('login','logout','password_change','mfa_enrolled','mfa_unenrolled','token_revoked','suspicious') then
    raise exception 'bad_event_type';
  end if;

  insert into public.security_login_alerts
    (user_id, event_type, device_label, user_agent, aal)
  values
    (auth.uid(), p_event_type, left(coalesce(p_device_label, ''), 80),
     coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'user-agent', ''),
     nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal');
end;
$$;

revoke all on function public.log_login_alert(text, text) from public, anon;
grant execute on function public.log_login_alert(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- my_mfa_status: estado REAL do 2FA lido de auth.mfa_factors
-- ---------------------------------------------------------------------------
create or replace function public.my_mfa_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_enrolled int := 0;
  v_verified int := 0;
  v_sessions int := 0;
begin
  if u is null then raise exception 'auth_required'; end if;

  if to_regclass('auth.mfa_factors') is not null then
    execute 'select count(*) from auth.mfa_factors where user_id = $1'
      into v_enrolled using u;
    execute 'select count(*) from auth.mfa_factors where user_id = $1 and status = ''verified'''
      into v_verified using u;
  end if;

  if to_regclass('auth.sessions') is not null then
    execute 'select count(*) from auth.sessions where user_id = $1'
      into v_sessions using u;
  end if;

  return jsonb_build_object(
    'available', true,
    'enrolled_count', v_enrolled,
    'verified_count', v_verified,
    'is_protected', v_verified > 0,
    'session_count', v_sessions
  );
end;
$$;

revoke all on function public.my_mfa_status() from public, anon;
grant execute on function public.my_mfa_status() to authenticated;

notify pgrst, 'reload schema';
