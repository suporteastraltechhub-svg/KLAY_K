-- ============================================================================
-- KLAY K — FOUNDER GOD MODE (Painel de Fundador nível Rei)
-- Gerenciador de Moedas + Segurança Máxima (Anti-Hack) + Dashboard Supremo.
--
-- PRINCÍPIOS:
-- 1) TODA ação sensível é RPC `security definer` que RE-VALIDA a role no
--    backend (is_klayk_founder() / has_perm(...)). O cliente nunca decide
--    saldo, ban, ip ou score.
-- 2) Qualquer ajuste/remoção de moeda exige FUNDADOR (is_klayk_founder()),
--    motivo obrigatório e grava audit_logs + credit_transactions.
-- 3) O módulo de segurança registra bloqueios de IP/dispositivo e score de
--    suspeição por usuário; leitura por staff com cap 'security'.
-- 4) Dashboard é agregado sob demanda (nada de monitoramento inventado).
-- ============================================================================

-- ============================================================================
-- PARTE 1 — GERENCIADOR DE MOEDAS (fundador)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Busca de usuários pelo fundador (nome, username, display ou ID exato).
-- Só devolve identidade pública + role — NUNCA saldo/dados sensíveis.
-- ---------------------------------------------------------------------------
create or replace function public.founder_search_users(
  p_query text,
  p_limit int default 20
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  is_verified boolean,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_q text := coalesce(trim(p_query), '');
  v_lim int := least(greatest(p_limit, 1), 50);
begin
  if not public.is_klayk_founder() and not public.has_perm('economy') then
    raise exception 'not_founder';
  end if;
  if v_q = '' then raise exception 'empty_query'; end if;
  return query
    select u.id, u.username, u.display_name, u.avatar_url,
           u.is_verified, u.role, u.created_at
      from public.profiles u
     where u.id::text = v_q
        or u.username ilike '%' || v_q || '%'
        or coalesce(u.display_name, '') ilike '%' || v_q || '%'
     order by u.created_at desc
     limit v_lim;
end;
$$;

revoke all on function public.founder_search_users(text, int) from public;
revoke all on function public.founder_search_users(text, int) from anon;
revoke execute on function public.founder_search_users(text, int) from anon, public;
grant execute on function public.founder_search_users(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Carteira completa de um usuário + identidade (fundador/equipe economy).
-- ---------------------------------------------------------------------------
create or replace function public.founder_user_wallet(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  w record;
  u record;
begin
  if not public.is_klayk_founder() and not public.has_perm('economy') then
    raise exception 'not_founder';
  end if;
  if p_user_id is null then raise exception 'invalid_target'; end if;
  select * into w from public.user_wallets where user_id = p_user_id;
  select id, username, display_name, role, is_verified into u
    from public.profiles where id = p_user_id;
  if u.id is null then raise exception 'user_not_found'; end if;
  return jsonb_build_object(
    'user_id', p_user_id,
    'username', coalesce(u.username, ''),
    'display_name', coalesce(u.display_name, ''),
    'role', coalesce(u.role, 'user'),
    'is_verified', coalesce(u.is_verified, false),
    'credits', coalesce(w.credits, 0),
    'diamonds', coalesce(w.diamonds, 0),
    'crystals', coalesce(w.crystals, 0),
    'rubies', coalesce(w.rubies, 0),
    'emeralds', coalesce(w.emeralds, 0),
    'crystal_rare', coalesce(w.crystal_rare, 0)
  );
end;
$$;

revoke all on function public.founder_user_wallet(uuid) from public;
revoke all on function public.founder_user_wallet(uuid) from anon;
grant execute on function public.founder_user_wallet(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Ajuste de qualquer moeda em qualquer conta (adicionar OU remover).
-- SÓ fundador. p_delta > 0 adiciona; p_delta < 0 remove (piso 0 — nunca
-- permite saldo negativo). Motivo é obrigatório (>= 4 caracteres) e tudo vai
-- para audit_logs + credit_transactions.
-- ---------------------------------------------------------------------------
create or replace function public.founder_adjust_currency(
  p_user_id uuid,
  p_currency text,
  p_delta bigint,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := coalesce(trim(p_reason), '');
  r jsonb;
begin
  if not public.is_klayk_founder() then raise exception 'founder_only'; end if;
  if p_user_id is null then raise exception 'invalid_target'; end if;
  if p_delta = 0 then raise exception 'zero_delta'; end if;
  if char_length(v_reason) < 4 then raise exception 'reason_required'; end if;

  -- economy_adjust é atomicamente seguro (piso 0, whitelist de moedas) e grava
  -- credit_transactions com o ator atual (o fundador).
  r := public.economy_adjust(
    p_user_id,
    p_currency,
    p_delta,
    'admin',          -- kind
    'founder',        -- ref_type
    '',
    v_reason,
    'founder.currency.adjust'
  );
  return r;
end;
$$;

revoke all on function public.founder_adjust_currency(uuid, text, bigint, text) from public;
revoke all on function public.founder_adjust_currency(uuid, text, bigint, text) from anon;
revoke execute on function public.founder_adjust_currency(uuid, text, bigint, text) from anon, public;
grant execute on function public.founder_adjust_currency(uuid, text, bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Histórico das últimas movimentações do fundador (auditoria, só fundador).
-- ---------------------------------------------------------------------------
create or replace function public.founder_recent_adjustments(p_limit int default 25)
returns table (
  id text,
  actor_id uuid,
  actor_name text,
  target_id text,
  target_name text,
  details jsonb,
  label text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_klayk_founder() then raise exception 'founder_only'; end if;
  return query
    select
      a.id::text,
      a.actor_id,
      coalesce(ap.display_name, ap.username, 'FUNDADOR'),
      a.entity_id,
      coalesce(tp.display_name, tp.username, a.entity_id),
      a.details,
      a.action,
      a.created_at
    from public.audit_logs a
    left join public.profiles ap on ap.id = a.actor_id
    left join public.profiles tp on tp.id::text = a.entity_id
    where a.action = 'founder.currency.adjust'
    order by a.created_at desc
    limit least(greatest(p_limit, 1), 200);
end;
$$;

revoke all on function public.founder_recent_adjustments(int) from public;
revoke all on function public.founder_recent_adjustments(int) from anon;
grant execute on function public.founder_recent_adjustments(int) to authenticated;

-- ============================================================================
-- PARTE 2 — SEGURANÇA MÁXIMA (Anti-Hack)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- security_scores: score de suspeição por usuário (100 = máx suspeição).
-- level é derivado: block >= 70, suspicious >= 40, watch >= 15, senão low.
-- Somente RPC security definer escreve; staff (cap security/audit) lê.
-- ---------------------------------------------------------------------------
create table if not exists public.security_scores (
  user_id uuid primary key references auth.users(id) on delete cascade,
  score int not null default 0,
  flags jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

create index if not exists security_scores_score_idx on public.security_scores (score desc);

alter table public.security_scores enable row level security;
drop policy if exists "security_scores_select_staff" on public.security_scores;
create policy "security_scores_select_staff" on public.security_scores
  for select using (public.has_perm('security') or public.has_perm('audit'));

-- ---------------------------------------------------------------------------
-- founder_blocked_ips / founder_blocked_devices: listas de bloqueio.
-- ---------------------------------------------------------------------------
create table if not exists public.founder_blocked_ips (
  ip text primary key,
  reason text not null default '',
  auto boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.founder_blocked_ips enable row level security;
drop policy if exists "blocked_ips_select_staff" on public.founder_blocked_ips;
create policy "blocked_ips_select_staff" on public.founder_blocked_ips
  for select using (public.has_perm('security') or public.has_perm('audit'));

create table if not exists public.founder_blocked_devices (
  device_id text primary key,
  reason text not null default '',
  auto boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.founder_blocked_devices enable row level security;
drop policy if exists "blocked_devices_select_staff" on public.founder_blocked_devices;
create policy "blocked_devices_select_staff" on public.founder_blocked_devices
  for select using (public.has_perm('security') or public.has_perm('audit'));

-- ---------------------------------------------------------------------------
-- founder_login_attempts: registro de tentativas de login. A tabela é
-- INSERT-only por RPC limitada; leitura por staff (cap security/audit).
-- ---------------------------------------------------------------------------
create table if not exists public.founder_login_attempts (
  id bigint generated always as identity primary key,
  attempt_user uuid references auth.users(id) on delete set null,
  email_or_username text default '',
  ip text default '',
  device_id text default '',
  success boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists login_attempts_created_idx on public.founder_login_attempts (created_at desc);
create index if not exists login_attempts_user_idx on public.founder_login_attempts (attempt_user);

alter table public.founder_login_attempts enable row level security;
-- Sem policy de escrita: só a RPC security definer insere.
drop policy if exists "login_attempts_select_staff" on public.founder_login_attempts;
create policy "login_attempts_select_staff" on public.founder_login_attempts
  for select using (public.has_perm('security') or public.has_perm('audit'));

-- ---------------------------------------------------------------------------
-- Log de tentativa de login (telemetria honesta do app — nunca inventada).
-- Chama na falha/sucesso de sign-in. Insert leve, sem dados sensíveis.
-- ---------------------------------------------------------------------------
create or replace function public.log_auth_attempt(
  p_email text,
  p_success boolean,
  p_device_id text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(coalesce(trim(p_email), ''));
begin
  if v_email = '' and v_uid is null then return; end if;
  insert into public.founder_login_attempts
    (attempt_user, email_or_username, device_id, success)
  values (v_uid, v_email, coalesce(p_device_id, ''), coalesce(p_success, false));
  -- Manutenção simples: retém só os últimos 90 dias de tentativas.
  delete from public.founder_login_attempts
   where created_at < now() - interval '90 days';
end;
$$;

revoke all on function public.log_auth_attempt(text, boolean, text) from public;
revoke all on function public.log_auth_attempt(text, boolean, text) from anon;
grant execute on function public.log_auth_attempt(text, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Bloquear / desbloquear IP (staff security ou fundador). Audita tudo.
-- ---------------------------------------------------------------------------
create or replace function public.founder_block_ip(p_ip text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := coalesce(trim(p_reason), '');
begin
  if not public.has_perm('security') and not public.is_klayk_founder() then
    raise exception 'not_staff';
  end if;
  if coalesce(trim(p_ip), '') = '' then raise exception 'invalid_ip'; end if;
  if char_length(v_reason) < 4 then raise exception 'reason_required'; end if;
  insert into public.founder_blocked_ips (ip, reason, auto, created_by)
  values (trim(p_ip), v_reason, false, auth.uid())
  on conflict (ip) do update set
    reason = excluded.reason, auto = false, created_by = excluded.created_by,
    created_at = now();
  perform public.write_audit('security.ip.block', 'ip', trim(p_ip),
    jsonb_build_object('reason', v_reason));
end;
$$;

revoke all on function public.founder_block_ip(text, text) from public;
revoke all on function public.founder_block_ip(text, text) from anon;
grant execute on function public.founder_block_ip(text, text) to authenticated;

create or replace function public.founder_unblock_ip(p_ip text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('security') and not public.is_klayk_founder() then
    raise exception 'not_staff';
  end if;
  delete from public.founder_blocked_ips where ip = trim(p_ip);
  perform public.write_audit('security.ip.unblock', 'ip', trim(p_ip), '{}');
end;
$$;

revoke all on function public.founder_unblock_ip(text) from public;
revoke all on function public.founder_unblock_ip(text) from anon;
grant execute on function public.founder_unblock_ip(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Bloquear / desbloquear dispositivo.
-- ---------------------------------------------------------------------------
create or replace function public.founder_block_device(p_device_id text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := coalesce(trim(p_reason), '');
begin
  if not public.has_perm('security') and not public.is_klayk_founder() then
    raise exception 'not_staff';
  end if;
  if coalesce(trim(p_device_id), '') = '' then raise exception 'invalid_device'; end if;
  if char_length(v_reason) < 4 then raise exception 'reason_required'; end if;
  insert into public.founder_blocked_devices (device_id, reason, auto, created_by)
  values (trim(p_device_id), v_reason, false, auth.uid())
  on conflict (device_id) do update set
    reason = excluded.reason, auto = false, created_by = excluded.created_by,
    created_at = now();
  perform public.write_audit('security.device.block', 'device', trim(p_device_id),
    jsonb_build_object('reason', v_reason));
end;
$$;

revoke all on function public.founder_block_device(text, text) from public;
revoke all on function public.founder_block_device(text, text) from anon;
grant execute on function public.founder_block_device(text, text) to authenticated;

create or replace function public.founder_unblock_device(p_device_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('security') and not public.is_klayk_founder() then
    raise exception 'not_staff';
  end if;
  delete from public.founder_blocked_devices where device_id = trim(p_device_id);
  perform public.write_audit('security.device.unblock', 'device', trim(p_device_id), '{}');
end;
$$;

revoke all on function public.founder_unblock_device(text) from public;
revoke all on function public.founder_unblock_device(text) from anon;
grant execute on function public.founder_unblock_device(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Ajustar score de suspeição de um usuário (delta pode ser negativo para
-- limpar). Audita e deriva o nivel de risco.
-- ---------------------------------------------------------------------------
create or replace function public.founder_set_security_score(
  p_user_id uuid,
  p_delta int,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new int;
  v_note text := coalesce(trim(p_reason), '');
begin
  if not public.has_perm('security') and not public.is_klayk_founder() then
    raise exception 'not_staff';
  end if;
  if p_user_id is null then raise exception 'invalid_target'; end if;
  if p_delta = 0 then raise exception 'zero_delta'; end if;
  if char_length(v_note) < 4 then raise exception 'reason_required'; end if;

  insert into public.security_scores (user_id, score, updated_by)
  values (p_user_id, greatest(-100, least(100, p_delta)), auth.uid())
  on conflict (user_id) do update set
    score = greatest(-100, least(100, security_scores.score + excluded.score)),
    flags = security_scores.flags,
    updated_at = now(),
    updated_by = auth.uid()
  returning score into v_new;

  perform public.write_audit('security.score.adjust', 'profile', p_user_id::text,
    jsonb_build_object('delta', p_delta, 'score', v_new, 'reason', v_note));
  return jsonb_build_object('score', v_new,
    'level', case
      when v_new >= 70 then 'blocked'
      when v_new >= 40 then 'suspicious'
      when v_new >= 15 then 'watch'
      else 'low' end);
end;
$$;

revoke all on function public.founder_set_security_score(uuid, int, text) from public;
revoke all on function public.founder_set_security_score(uuid, int, text) from anon;
grant execute on function public.founder_set_security_score(uuid, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Visão consolidada de segurança para o Painel (staff security ou fundador).
-- ---------------------------------------------------------------------------
create or replace function public.founder_security_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.has_perm('security') and not public.is_klayk_founder() then
    raise exception 'not_staff';
  end if;
  select jsonb_build_object(
    'blocked_ips', (select count(*)::int from public.founder_blocked_ips),
    'blocked_devices', (select count(*)::int from public.founder_blocked_devices),
    'open_alerts', (select count(*)::int from public.guardian_alerts where status in ('open','ack')),
    'critical_alerts', (select count(*)::int from public.guardian_alerts where status in ('open','ack') and severity = 'critical'),
    'suspicious', (select count(*)::int from public.security_scores where score >= 15),
    'blocked_users', (select count(*)::int from public.security_scores where score >= 70),
    'top_suspicious', (select coalesce(jsonb_agg(t order by t.score desc), '[]'::jsonb) from (
      select s.score, s.updated_at, p.id, p.username, p.display_name, p.role
        from public.security_scores s
        join public.profiles p on p.id = s.user_id
       where s.score >= 15
       order by s.score desc limit 20) t),
    'blocked_ip_list', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select b.ip, b.reason, b.auto, b.created_at from public.founder_blocked_ips b
       order by b.created_at desc limit 50) t),
    'blocked_device_list', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select d.device_id, d.reason, d.auto, d.created_at from public.founder_blocked_devices d
       order by d.created_at desc limit 50) t),
    'recent_alerts', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select a.id, a.severity, a.category, a.title, a.message, a.status,
             a.affected_user_id, a.created_at
        from public.guardian_alerts a
       order by a.created_at desc limit 15) t),
    'recent_login_attempts', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select l.id, l.email_or_username, l.device_id, l.success, l.created_at, l.attempt_user
        from public.founder_login_attempts l
       order by l.created_at desc limit 15) t),
    'emergency_active', (select coalesce(bool_or(w.status = 'active' and w.is_emergency), false)
      from public.guardian_maintenance_windows w)
  ) into v;
  return v;
end;
$$;

revoke all on function public.founder_security_overview() from public;
revoke all on function public.founder_security_overview() from anon;
grant execute on function public.founder_security_overview() to authenticated;

-- ============================================================================
-- PARTE 3 — DASHBOARD SUPREMO (fundador)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Retenção D1/D7/D30: % da coorte mais recente totalmente decorrida que teve
-- QUALQUER atividade em até 24h/7d/30d após o cadastro. Sem inventar métricas:
-- apenas coortes completas entram na conta.
-- ---------------------------------------------------------------------------
create or replace function public.founder_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_klayk_founder() then raise exception 'founder_only'; end if;
  select jsonb_build_object(
    'generated_at', now(),
    'active_lives', (select count(*)::int from public.lives where status = 'live'),
    'total_viewers', (select coalesce(sum(viewer_count), 0)::bigint from public.lives where status = 'live'),
    'gifts_1h', (select count(*)::bigint from public.gift_transactions where created_at > now() - interval '1 hour'),
    'gifts_today', (select count(*)::bigint from public.gift_transactions where created_at > date_trunc('day', now())),
    'gifts_7d', (select count(*)::bigint from public.gift_transactions where created_at > now() - interval '7 days'),
    'gifts_30d', (select count(*)::bigint from public.gift_transactions where created_at > now() - interval '30 days'),
    'diamonds_spent_1h', (select coalesce(sum(abs(delta)), 0)::bigint from public.credit_transactions where currency = 'diamonds' and delta < 0 and created_at > now() - interval '1 hour'),
    'diamonds_spent_today', (select coalesce(sum(abs(delta)), 0)::bigint from public.credit_transactions where currency = 'diamonds' and delta < 0 and created_at > date_trunc('day', now())),
    'diamonds_spent_7d', (select coalesce(sum(abs(delta)), 0)::bigint from public.credit_transactions where currency = 'diamonds' and delta < 0 and created_at > now() - interval '7 days'),
    'diamonds_spent_30d', (select coalesce(sum(abs(delta)), 0)::bigint from public.credit_transactions where currency = 'diamonds' and delta < 0 and created_at > now() - interval '30 days'),
    'new_users_today', (select count(*)::int from public.profiles where created_at > date_trunc('day', now())),
    'new_users_7d', (select count(*)::int from public.profiles where created_at > now() - interval '7 days'),
    'new_users_30d', (select count(*)::int from public.profiles where created_at > now() - interval '30 days'),
    'retention_d1', (select case when count(*) = 0 then 0 else
        round(100.0 * count(case when
          exists (select 1 from public.credit_transactions ct where ct.user_id = c.id
            and ct.created_at > c.created_at and ct.created_at < c.created_at + interval '24 hours')
          or exists (select 1 from public.gift_transactions gt where gt.user_id = c.id
            and gt.created_at > c.created_at and gt.created_at < c.created_at + interval '24 hours')
          or exists (select 1 from public.live_chat lc where lc.user_id = c.id
            and lc.created_at > c.created_at and lc.created_at < c.created_at + interval '24 hours')
          then 1 end) / count(*)) end
      from public.profiles c
      where c.created_at between now() - interval '2 days' and now() - interval '1 day'),
    'retention_d7', (select case when count(*) = 0 then 0 else
        round(100.0 * count(case when
          exists (select 1 from public.credit_transactions ct where ct.user_id = c.id
            and ct.created_at > c.created_at and ct.created_at < c.created_at + interval '7 days')
          or exists (select 1 from public.gift_transactions gt where gt.user_id = c.id
            and gt.created_at > c.created_at and gt.created_at < c.created_at + interval '7 days')
          or exists (select 1 from public.live_chat lc where lc.user_id = c.id
            and lc.created_at > c.created_at and lc.created_at < c.created_at + interval '7 days')
          then 1 end) / count(*)) end
      from public.profiles c
      where c.created_at between now() - interval '8 days' and now() - interval '7 days'),
    'retention_d30', (select case when count(*) = 0 then 0 else
        round(100.0 * count(case when
          exists (select 1 from public.credit_transactions ct where ct.user_id = c.id
            and ct.created_at > c.created_at and ct.created_at < c.created_at + interval '30 days')
          or exists (select 1 from public.gift_transactions gt where gt.user_id = c.id
            and gt.created_at > c.created_at and gt.created_at < c.created_at + interval '30 days')
          or exists (select 1 from public.live_chat lc where lc.user_id = c.id
            and lc.created_at > c.created_at and lc.created_at < c.created_at + interval '30 days')
          then 1 end) / count(*)) end
      from public.profiles c
      where c.created_at between now() - interval '31 days' and now() - interval '30 days'),
    'health', (select public.guardian_health())
  ) into v;
  return v;
end;
$$;

revoke all on function public.founder_dashboard() from public;
revoke all on function public.founder_dashboard() from anon;
grant execute on function public.founder_dashboard() to authenticated;

-- ============================================================================
-- GRANTS FINAIS (nenhum anon/public; somente authenticated com revalidação
-- interna das funções acima).
-- ============================================================================
-- (Cada função já revoga anon/public individualmente acima.)