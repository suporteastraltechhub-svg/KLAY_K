-- ============================================================================
-- KLAY K — KLAY GUARDIAN (segurança, automação, monitoramento e manutenção)
-- 1) Capacidade 'guardian' para super_admin/admin (founder já tem '*').
-- 2) Modos de manutenção globais/por recurso + histórico (responsável, mensagem,
--    início/fim) — todo o controle é backend, o Flutter apenas lê guardian_status.
-- 3) Central de alertas de segurança (anti-spam/anti-fraude/economia/abuso) com
--    dedup por key e vida (open → resolved).
-- 4) Motor de regras modular (guardian_rules + guardian_run_rules): cada regra é
--    uma verificação SQL real; a biblioteca é extensível por categoria.
-- 5) Recomendações operacionais derivadas das varreduras.
-- 6) Health checks HONESTOS (guardian_health): apenas métricas reais do banco.
-- 7) Emergência (mode=max, founder-only) com confirmação implícita no backend
--    (capability + auditoria) — nunca decidida por e-mail no Flutter.
-- 8) user_settings ganha preferências de EXPERIÊNCIA (reduce_animations,
--    reduce_effects, show_reactions) usadas pelo aplicativo.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Capacidade guardian nas roles operacionais.
-- ---------------------------------------------------------------------------
update public.admin_roles
   set capabilities = array_append(capabilities, 'guardian')
 where id in ('super_admin','admin') and not (capabilities @> '{guardian}');

-- ---------------------------------------------------------------------------
-- 2) user_settings — preferências de experiência (persistência RLS owner).
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column if not exists reduce_animations boolean not null default false;
alter table public.user_settings
  add column if not exists reduce_effects boolean not null default false;
alter table public.user_settings
  add column if not exists show_reactions boolean not null default true;

-- ---------------------------------------------------------------------------
-- 3) guardian_rules: catálogo de regras do motor (modular e extensível).
--    Cada linha é uma verificação; `config` guarda limiares/toggles extras.
-- ---------------------------------------------------------------------------
create table if not exists public.guardian_rules (
  id text primary key,
  name text not null,
  category text not null default 'safety',
  description text default '',
  enabled boolean not null default true,
  priority int not null default 100,
  config jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

insert into public.guardian_rules (id, name, category, description, enabled, priority, config) values
  ('abuse_tickets',  'Spam de tickets',   'anti_abuse', 'Muitos tickets de suporte em 10 min.', true, 90, '{"max_per_10min": 5}'),
  ('abuse_chests',   'Abuso de baús',     'anti_fraud', 'Muitas aberturas de baú em 10 min.',   true, 90, '{"max_per_10min": 10}'),
  ('abuse_likes',    'Curtidas em massa', 'anti_fraud', 'Curtidas anômalas em 10 min.',         true, 85, '{"max_per_10min": 120}'),
  ('economy_grants', 'Concessão em massa','economy',    'Soma de concessões administrativas em 1h.', true, 88, '{"max_per_hour": 50000}'),
  ('verification_old','Verificações pendentes', 'ops',  'Pedidos de verificação antigos.',      true, 70, '{"max_age_hours": 48}'),
  ('support_old',    'Tickets sem resposta', 'ops',     'Tickets abertos há tempo.' ,           true, 70, '{"max_age_hours": 24}'),
  ('privilege_change','Mudanças de privilégio', 'audit', 'Promoções/rebaixamentos recentes.',    true, 75, '{"window_hours": 24}'),
  ('wallet_negative', 'Carteira inconsistente', 'economy', 'Saldos negativos (bug/dados).', true, 95, '{}'),
  ('reports_queue',  'Fila de moderação', 'moderation', 'Ações de moderação recentes.',        true, 65, '{"window_min": 60}')
on conflict (id) do update set
  name = excluded.name, category = excluded.category,
  description = excluded.description, enabled = excluded.enabled,
  priority = excluded.priority, config = excluded.config, updated_at = now();

alter table public.guardian_rules enable row level security;
drop policy if exists "guardian_rules_select_staff" on public.guardian_rules;
create policy "guardian_rules_select_staff" on public.guardian_rules
  for select using (public.has_perm('guardian') or public.has_perm('audit') or public.has_perm('roles'));

-- ---------------------------------------------------------------------------
-- 4) guardian_alerts: central de alertas. Dedup por `key` (única por ocorrência
--    detectada); sem INSERT/UPDATE/DELETE do cliente — só via RPC definer.
-- ---------------------------------------------------------------------------
create table if not exists public.guardian_alerts (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  severity text not null default 'medium'
    check (severity in ('info','low','medium','high','critical')),
  category text not null default 'safety',
  title text not null,
  message text default '',
  status text not null default 'open' check (status in ('open','ack','resolved')),
  affected_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz
);
create index if not exists guardian_alerts_status_idx on public.guardian_alerts (status, created_at desc);
create index if not exists guardian_alerts_severity_idx on public.guardian_alerts (severity);

alter table public.guardian_alerts enable row level security;
drop policy if exists "guardian_alerts_select_staff" on public.guardian_alerts;
create policy "guardian_alerts_select_staff" on public.guardian_alerts
  for select using (public.has_perm('guardian') or public.has_perm('audit') or public.has_perm('roles'));

-- ---------------------------------------------------------------------------
-- 5) guardian_recommendations: recomendações geradas pelas varreduras.
-- ---------------------------------------------------------------------------
create table if not exists public.guardian_recommendations (
  id uuid primary key default gen_random_uuid(),
  rule_id text not null,
  alert_id uuid references public.guardian_alerts(id) on delete set null,
  severity text not null default 'medium',
  title text not null,
  action text default '',
  status text not null default 'open' check (status in ('open','done','dismissed')),
  created_at timestamptz not null default now()
);
-- rule_id é textual (rótulo de origem/regra); sem FK para permitir rótulos derivados de categoria.
alter table public.guardian_recommendations drop constraint if exists guardian_recommendations_rule_id_fkey;
create index if not exists guardian_recs_status_idx on public.guardian_recommendations (status, created_at desc);

alter table public.guardian_recommendations enable row level security;
drop policy if exists "guardian_recs_select_staff" on public.guardian_recommendations;
create policy "guardian_recs_select_staff" on public.guardian_recommendations
  for select using (public.has_perm('guardian') or public.has_perm('audit') or public.has_perm('roles'));

-- ---------------------------------------------------------------------------
-- 6) guardian_maintenance_windows: modo de manutenção (global ou por recurso).
--    Histórico preservado (status ended/cancelled). created_by = responsável.
-- ---------------------------------------------------------------------------
create table if not exists public.guardian_maintenance_windows (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'active' check (status in ('pending','active','ended','cancelled')),
  mode text not null check (mode in ('low','medium','max')),
  feature text not null default 'all',
  message text default '',
  created_by uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default now(),
  end_at timestamptz,
  is_emergency boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists guardian_maint_active_idx on public.guardian_maintenance_windows (status, started_at desc);
create index if not exists guardian_maint_feature_idx on public.guardian_maintenance_windows (feature, status);

alter table public.guardian_maintenance_windows enable row level security;
drop policy if exists "guardian_maint_select_staff" on public.guardian_maintenance_windows;
create policy "guardian_maint_select_staff" on public.guardian_maintenance_windows
  for select using (public.has_perm('guardian') or public.has_perm('audit') or public.has_perm('roles'));

-- ---------------------------------------------------------------------------
-- 7) guardian_status(): visível para TODOS (anon/autenticado) — é assim que o
--    app descobre modos de manutenção ativos (banner/bloqueio por recurso).
--    Somente janelas ATIVAS e sanitizadas (sem dados internos).
-- ---------------------------------------------------------------------------
create or replace function public.guardian_status()
returns table (
  feature text, mode text, message text, started_at timestamptz, is_emergency boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select m.feature, m.mode, coalesce(m.message, ''), m.started_at, m.is_emergency
  from public.guardian_maintenance_windows m
  where m.status = 'active'
  order by m.started_at desc
  limit 20;
$$;

revoke all on function public.guardian_status() from public;
grant execute on function public.guardian_status() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8) guardian_health(): saúde REAL da plataforma (métricas computadas sob
--    demanda — nada de falsos positivos/monitoramento inventado).
-- ---------------------------------------------------------------------------
create or replace function public.guardian_health()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
  db_size bigint;
begin
  if not public.has_perm('guardian') and not public.has_perm('audit') then
    raise exception 'not_admin';
  end if;
  begin
    select pg_database_size(current_database()) into db_size;
  exception when others then db_size := null;
  end;

  select jsonb_build_object(
    'ok', true,
    'generated_at', now(),
    'users_total', (select count(*) from auth.users),
    'users_last_30d', (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'posts_total', (select count(*) from public.posts),
    'post_likes_total', (select count(*) from public.post_likes),
    'posts_last_24h', (select count(*) from public.posts where created_at > now() - interval '24 hours'),
    'alerts_open', (select count(*)::int from public.guardian_alerts where status in ('open','ack')),
    'alerts_critical', (select count(*)::int from public.guardian_alerts where status in ('open','ack') and severity = 'critical'),
    'active_maintenance', (select count(*)::int from public.guardian_maintenance_windows where status = 'active'),
    'economy', (select jsonb_build_object(
        'wallets', count(*),
        'total_credits', coalesce(sum(credits), 0),
        'total_diamonds', coalesce(sum(diamonds), 0),
        'total_crystals', coalesce(sum(crystals), 0),
        'ledger_rows', (select count(*) from public.credit_transactions)) from public.user_wallets),
    'chests', (select jsonb_build_object(
        'opens_24h', count(*) filter (where opened_at > now() - interval '24 hours'),
        'opens_total', count(*)) from public.chest_opens),
    'support_open', (select count(*)::int from public.support_tickets where status in ('open','in_review')),
    'verification_pending', (select count(*)::int from public.verification_requests where status = 'pending'),
    'audit_actions_24h', (select count(*) from public.audit_logs where created_at > now() - interval '24 hours'),
    'missions_total', (select count(*) from public.missions),
    'db_size_bytes', db_size
  ) into v;
  return v;
end;
$$;

revoke all on function public.guardian_health() from public;
grant execute on function public.guardian_health() to authenticated;

-- ---------------------------------------------------------------------------
-- 9) Geração/alteração de manutenção (backend-validada).
-- ---------------------------------------------------------------------------
create or replace function public.guardian_set_maintenance(
  p_mode text,
  p_feature text default 'all',
  p_message text default '',
  p_emergency boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_perm('guardian') then raise exception 'not_admin'; end if;
  if p_mode not in ('low','medium','max') then raise exception 'bad_mode'; end if;
  if p_feature is null or btrim(p_feature) = '' then p_feature := 'all'; end if;
  if p_feature = 'all' and exists (
    select 1 from public.guardian_maintenance_windows
    where status = 'active' and feature = 'all'
  ) then raise exception 'already_active'; end if;

  insert into public.guardian_maintenance_windows
    (status, mode, feature, message, created_by, started_at, is_emergency)
  values ('active', p_mode, btrim(p_feature), coalesce(p_message, ''), auth.uid(), now(), p_emergency)
  returning id into v_id;

  perform public.write_audit('guardian.maintenance.start', 'maintenance', v_id::text,
    jsonb_build_object('mode', p_mode, 'feature', btrim(p_feature), 'emergency', p_emergency));
  return jsonb_build_object('ok', true, 'id', v_id::text, 'mode', p_mode, 'feature', btrim(p_feature));
end;
$$;

revoke all on function public.guardian_set_maintenance(text, text, text, boolean) from public;
grant execute on function public.guardian_set_maintenance(text, text, text, boolean) to authenticated;

create or replace function public.guardian_end_maintenance(
  p_window_id uuid,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('guardian') then raise exception 'not_admin'; end if;
  update public.guardian_maintenance_windows
     set status = 'ended', end_at = now()
   where id = p_window_id and status = 'active';
  if not found then raise exception 'not_active'; end if;
  perform public.write_audit('guardian.maintenance.end', 'maintenance', p_window_id::text,
    jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guardian_end_maintenance(uuid, text) from public;
grant execute on function public.guardian_end_maintenance(uuid, text) to authenticated;

-- Emergência: só founder (cap 'roles', que só founder tem). Encerra janela
-- global ativa (se houver) e abre mode=max como emergência com auditoria.
create or replace function public.guardian_emergency(
  p_message text default 'Manutenção de emergência em andamento.'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_perm('roles') then raise exception 'founder_only'; end if;
  update public.guardian_maintenance_windows
     set status = 'ended', end_at = now()
   where status = 'active' and feature = 'all';
  insert into public.guardian_maintenance_windows
    (status, mode, feature, message, created_by, started_at, is_emergency)
  values ('active', 'max', 'all', coalesce(p_message, ''), auth.uid(), now(), true)
  returning id into v_id;
  perform public.write_audit('guardian.emergency', 'maintenance', v_id::text,
    jsonb_build_object('mode', 'max', 'message', p_message));
  return jsonb_build_object('ok', true, 'id', v_id::text, 'mode', 'max', 'emergency', true);
end;
$$;

revoke all on function public.guardian_emergency(text) from public;
grant execute on function public.guardian_emergency(text) to authenticated;

-- Lista janelas de manutenção (histórico) — staff guardian/audit/roles.
create or replace function public.guardian_list_maintenance(
  p_limit int default 50
)
returns table (
  id uuid, status text, mode text, feature text, message text,
  created_by uuid, started_at timestamptz, end_at timestamptz,
  is_emergency boolean, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('guardian') and not public.has_perm('audit') and not public.has_perm('roles') then
    raise exception 'not_admin';
  end if;
  return query
    select m.id, m.status, m.mode, m.feature, m.message, m.created_by,
           m.started_at, m.end_at, m.is_emergency, m.created_at
    from public.guardian_maintenance_windows m
    order by m.started_at desc
    limit greatest(1, least(p_limit, 200));
end;
$$;

revoke all on function public.guardian_list_maintenance(int) from public;
grant execute on function public.guardian_list_maintenance(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 10) Motor de regras (varredura). Cada regra habilitada roda uma verificação
--     SQL REAL; alertas deduplicam por key. Recomendações derivadas.
-- ---------------------------------------------------------------------------
create or replace function public.guardian_run_rules(
  p_limit int default 200
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_any text;
  n int;
  inserted int := 0;
begin
  if not public.has_perm('guardian') then raise exception 'not_admin'; end if;

  -- abuse_tickets: usuários com muitos tickets em 10 min.
  if exists (select 1 from public.guardian_rules where id = 'abuse_tickets' and enabled) then
    n := coalesce((select (config->>'max_per_10min')::int from public.guardian_rules where id = 'abuse_tickets'), 5);
    insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
    select 'ticket_flood:' || u.id::text, 'high', 'anti_abuse',
           'Possível spam de tickets',
           'Usuário abriu vários tickets de suporte em 10 minutos.',
           u.id, jsonb_build_object('count', c)
    from (select user_id as id, count(*) c from public.support_tickets
           where created_at > now() - interval '10 minutes'
           group by user_id having count(*) > n limit p_limit) u
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- abuse_chests: muitas aberturas de baú em 10 min.
  if exists (select 1 from public.guardian_rules where id = 'abuse_chests' and enabled) then
    n := coalesce((select (config->>'max_per_10min')::int from public.guardian_rules where id = 'abuse_chests'), 10);
    insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
    select 'chest_flood:' || u.id::text, 'high', 'anti_fraud',
           'Abuso de baús detectado',
           'Usuário abriu muitos baús em 10 minutos (possível automação).',
           u.id, jsonb_build_object('count', c)
    from (select user_id as id, count(*) c from public.chest_opens
           where opened_at > now() - interval '10 minutes'
           group by user_id having count(*) > n limit p_limit) u
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- abuse_likes: curtidas em massa em 10 min.
  if exists (select 1 from public.guardian_rules where id = 'abuse_likes' and enabled) then
    n := coalesce((select (config->>'max_per_10min')::int from public.guardian_rules where id = 'abuse_likes'), 120);
    insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
    select 'like_flood:' || u.id::text, 'medium', 'anti_fraud',
           'Curtidas em massa',
           'Usuário curtiu muitos posts em 10 minutos (possível bot).',
           u.id, jsonb_build_object('count', c)
    from (select user_id as id, count(*) c from public.post_likes
           where created_at > now() - interval '10 minutes'
           group by user_id having count(*) > n limit p_limit) u
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- economy_grants: concessões administrativas em 1h.
  if exists (select 1 from public.guardian_rules where id = 'economy_grants' and enabled) then
    n := coalesce((select (config->>'max_per_hour')::int from public.guardian_rules where id = 'economy_grants'), 50000);
    insert into public.guardian_alerts (key, severity, category, title, message, metadata)
    select 'economy_grant_spike', 'high', 'economy',
           'Concessão administrativa em massa',
           'Soma de concessões de moedas em 1 hora acima do limiar.',
           jsonb_build_object('total', t, 'window_secs', 3600)
    from (select coalesce(sum(delta), 0) t
            from public.credit_transactions
           where kind = 'admin' and delta > 0
             and created_at > now() - interval '1 hour') s
    where t > n
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- verification_old: pedidos antigos sem análise.
  if exists (select 1 from public.guardian_rules where id = 'verification_old' and enabled) then
    n := coalesce((select (config->>'max_age_hours')::int from public.guardian_rules where id = 'verification_old'), 48);
    insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
    select 'verification_old:' || v.id::text, 'low', 'ops',
           'Verificação pendente há tempo',
           'Pedido de verificação aguarda análise há mais de ' || n || ' horas.',
           v.user_id, jsonb_build_object('hours', n)
    from public.verification_requests v
    where v.status = 'pending' and v.submitted_at < now() - make_interval(hours => n)
    limit p_limit
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- support_old: tickets abertos há tempo.
  if exists (select 1 from public.guardian_rules where id = 'support_old' and enabled) then
    n := coalesce((select (config->>'max_age_hours')::int from public.guardian_rules where id = 'support_old'), 24);
    insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
    select 'support_old:' || t.id::text, 'low', 'ops',
           'Ticket sem resposta',
           'Ticket de suporte aberto há mais de ' || n || ' horas.',
           t.user_id, jsonb_build_object('hours', n)
    from public.support_tickets t
    where t.status in ('open','in_review') and t.created_at < now() - make_interval(hours => n)
    limit p_limit
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- privilege_change: mudanças de role recentes (auditoria sensível).
  if exists (select 1 from public.guardian_rules where id = 'privilege_change' and enabled) then
    n := coalesce((select (config->>'window_hours')::int from public.guardian_rules where id = 'privilege_change'), 24);
    insert into public.guardian_alerts (key, severity, category, title, message, metadata)
    select 'privilege_change:' || a.id::text, 'info', 'audit',
           'Mudança de privilégio recente',
           'Role de um usuário foi alterada nas últimas ' || n || ' horas.',
           jsonb_build_object('details', a.details)
    from public.audit_logs a
    where a.action in ('role.set','role.set_admin') and a.created_at > now() - make_interval(hours => n)
    limit p_limit
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- wallet_negative: saldos negativos (inconsistência de dados).
  if exists (select 1 from public.guardian_rules where id = 'wallet_negative' and enabled) then
    insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
    select 'wallet_negative:' || w.user_id::text, 'critical', 'economy',
           'Carteira inconsistente (saldos negativos)',
           'Detectado saldo negativo — revisar ledger.',
           w.user_id,
           jsonb_build_object('credits', w.credits, 'diamonds', w.diamonds)
    from public.user_wallets w
    where w.credits < 0 or w.diamonds < 0 or w.crystals < 0 or w.rubies < 0
       or w.emeralds < 0 or w.crystal_rare < 0
    limit p_limit
    on conflict (key) do nothing;
    inserted := inserted + 1;
  end if;

  -- reports_queue: atividades recentes de moderação → recomendação.
  if exists (select 1 from public.guardian_rules where id = 'reports_queue' and enabled) then
    n := coalesce((select (config->>'window_min')::int from public.guardian_rules where id = 'reports_queue'), 60);
    declare
      v_mod int;
    begin
      select count(*) into v_mod from public.moderation_actions
       where created_at > now() - make_interval(mins => n);
      if v_mod > 0 then
        insert into public.guardian_alerts (key, severity, category, title, message, metadata)
        values ('moderation_queue:' || now()::date::text, 'low', 'moderation',
                'Atividade de moderação recente', v_mod || ' ação(ões) de moderação nas últimas ' || n || ' minutos.',
                jsonb_build_object('count', v_mod))
        on conflict (key) do nothing;
      end if;
    end;
    inserted := inserted + 1;
  end if;

  -- Recomendações derivadas dos alertas abertos por categoria (1 por categoria).
  insert into public.guardian_recommendations (rule_id, alert_id, severity, title, action)
  select distinct on (c.category) 'rule:' || c.category, c.latest_id, c.sev, c.title, 'Revisar na central de alertas do Guardian.'
  from (
    select a.category, (array_agg(a.id order by a.created_at desc))[1] as latest_id,
           (array_agg(a.severity order by a.created_at desc))[1] as sev,
           'Revisar alertas de ' || a.category as title
    from public.guardian_alerts a
    where a.status in ('open','ack')
    group by a.category
  ) c
  where not exists (
    select 1 from public.guardian_recommendations r
    join public.guardian_alerts ga on ga.id = r.alert_id
    where ga.id = c.latest_id and r.status = 'open'
  );

  perform public.write_audit('guardian.rules.run', 'system', '', jsonb_build_object('rules_checked', inserted));
  return jsonb_build_object('ok', true, 'checks', inserted);
end;
$$;

revoke all on function public.guardian_run_rules(int) from public;
grant execute on function public.guardian_run_rules(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 11) Central de alertas (leitura/resolução) + denúncias anti-spam.
-- ---------------------------------------------------------------------------
create or replace function public.guardian_list_alerts(
  p_status text default null,
  p_severity text default null,
  p_limit int default 100
)
returns table (
  id uuid, key text, severity text, category text, title text, message text,
  status text, affected_user_id uuid, metadata jsonb, created_at timestamptz,
  resolved_by uuid, resolved_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('guardian') and not public.has_perm('audit') and not public.has_perm('roles') then
    raise exception 'not_admin';
  end if;
  return query
    select a.id, a.key, a.severity, a.category, a.title, a.message, a.status,
           a.affected_user_id, a.metadata, a.created_at, a.resolved_by, a.resolved_at
    from public.guardian_alerts a
    where (p_status is null or a.status = p_status)
      and (p_severity is null or a.severity = p_severity)
    order by a.created_at desc
    limit greatest(1, least(p_limit, 500));
end;
$$;

revoke all on function public.guardian_list_alerts(text, text, int) from public;
grant execute on function public.guardian_list_alerts(text, text, int) to authenticated;

create or replace function public.guardian_resolve_alert(
  p_alert_id uuid,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('guardian') then raise exception 'not_admin'; end if;
  update public.guardian_alerts
     set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(),
         metadata = metadata || jsonb_build_object('resolution_note', p_note)
   where id = p_alert_id and status in ('open','ack');
  if not found then raise exception 'not_open'; end if;
  perform public.write_audit('guardian.alert.resolve', 'alert', p_alert_id::text,
    jsonb_build_object('note', p_note));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guardian_resolve_alert(uuid, text) from public;
grant execute on function public.guardian_resolve_alert(uuid, text) to authenticated;

-- Denúncia anti-spam/abuso por staff de moderação (gera alerta rastreável).
create or replace function public.guardian_report_spam(
  p_user_id uuid,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
begin
  if not public.has_perm('guardian') and not public.has_perm('moderation') then
    raise exception 'not_admin';
  end if;
  select username into v_username from public.profiles where id = p_user_id;
  if v_username is null then raise exception 'user_not_found'; end if;
  insert into public.guardian_alerts (key, severity, category, title, message, affected_user_id, metadata)
  values ('spam_report:' || p_user_id::text, 'high', 'anti_spam',
          'Denúncia de spam/abuso', 'Denunciado por: ' || coalesce(p_reason, ''),
          p_user_id, jsonb_build_object('reported_by', auth.uid()::text, 'reason', p_reason))
  on conflict (key) do update set
    status = 'open', message = 'Denunciado por: ' || coalesce(p_reason, ''),
    metadata = jsonb_build_object('reported_by', auth.uid()::text, 'reason', p_reason);
  perform public.write_audit('guardian.spam.report', 'profile', p_user_id::text,
    jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'username', v_username);
end;
$$;

revoke all on function public.guardian_report_spam(uuid, text) from public;
grant execute on function public.guardian_report_spam(uuid, text) to authenticated;

-- Toggle de regra (habilitar/desabilitar) — founder/super_admin with roles cap.
create or replace function public.guardian_toggle_rule(
  p_rule_id text,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('roles') then raise exception 'founder_only'; end if;
  update public.guardian_rules set enabled = p_enabled, updated_at = now() where id = p_rule_id;
  if not found then raise exception 'rule_not_found'; end if;
  perform public.write_audit('guardian.rule.toggle', 'rule', p_rule_id::text,
    jsonb_build_object('enabled', p_enabled));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guardian_toggle_rule(text, boolean) from public;
grant execute on function public.guardian_toggle_rule(text, boolean) to authenticated;

create or replace function public.guardian_list_rules()
returns table (
  id text, name text, category text, description text,
  enabled boolean, priority int, config jsonb, updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('guardian') and not public.has_perm('audit') and not public.has_perm('roles') then
    raise exception 'not_admin';
  end if;
  return query
    select r.id, r.name, r.category, r.description, r.enabled, r.priority, r.config, r.updated_at
    from public.guardian_rules r order by r.priority desc, r.id;
end;
$$;

revoke all on function public.guardian_list_rules() from public;
grant execute on function public.guardian_list_rules() to authenticated;

create or replace function public.guardian_list_recommendations(
  p_status text default null,
  p_limit int default 100
)
returns table (
  id uuid, rule_id text, alert_id uuid, severity text, title text,
  action text, status text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('guardian') and not public.has_perm('audit') and not public.has_perm('roles') then
    raise exception 'not_admin';
  end if;
  return query
    select r.id, r.rule_id, r.alert_id, r.severity, r.title, r.action, r.status, r.created_at
    from public.guardian_recommendations r
    where (p_status is null or r.status = p_status)
    order by r.created_at desc
    limit greatest(1, least(p_limit, 500));
end;
$$;

revoke all on function public.guardian_list_recommendations(text, int) from public;
grant execute on function public.guardian_list_recommendations(text, int) to authenticated;

-- Recarrega o schema para o PostgREST enxergar as funções novas.
NOTIFY pgrst, 'reload schema';