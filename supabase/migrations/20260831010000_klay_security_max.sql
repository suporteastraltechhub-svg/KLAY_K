-- ============================================================================
-- KLAY K — SECURITY MAX
-- Camada de segurança: Youth Shield, Account Guard, Scam/Anti-spam,
-- Fake Profile, Comment Shield, Report Center e Live Safety.
-- Princípios: autorização SEMPRE no backend (RPCs security definer +
-- has_perm + write_audit); nunca confiar no cliente; triggers de escrita
-- são aplicadas no banco (não na UI); flags/verificação honestas (nunca
-- deduzir culpa, apenas sinais reais mensuráveis).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) CAPABILITIES — 'security' p/ operadores; 'security_view' p/ suporte/moderação
-- ---------------------------------------------------------------------------
insert into public.admin_roles (id, name, rank, capabilities, description) values
  ('super_admin', 'Super Administrador', 90, '{users,moderation,verification,gifts,store,live,orders,economy,chests,missions,support,audit,settings,security,guardian}', 'Acesso total operacional, sem gestão de roles.'),
  ('admin',       'Administrador',   80, '{users,moderation,verification,gifts,store,live,orders,economy,chests,missions,support,audit,settings,security,guardian}', 'Administração completa, sem gestão de roles.'),
  ('moderator',   'Moderador',       60, '{moderation,live,verification_view,security_view}', 'Modera conteúdo, lives, flags e vê verificações.'),
  ('support',     'Suporte',         50, '{support,tickets,verification_view,security_view}', 'Central de ajuda, tickets e análise de segurança.')
on conflict (id) do update set
  capabilities = excluded.capabilities, description = excluded.description;

-- ---------------------------------------------------------------------------
-- 1) COLUNAS NOVAS
-- ---------------------------------------------------------------------------
-- Identidade/salvaguarda da CONTA (perfil): data de nascimento auto-declarada
-- (sinais honestos, nunca verificação) + modo jovem + restrição por análise.
alter table public.profiles
  add column if not exists birth_date date,
  add column if not exists youth_mode boolean not null default false,
  add column if not exists account_restricted boolean not null default false;

-- Preferência do VISUalizador (app settings): consentimento explícito 18+.
alter table public.user_settings
  add column if not exists adult_content_ok boolean not null default false;

-- LIVES: marcador de faixa etária (criada pelo streamer via RPC/Edge).
alter table public.lives
  add column if not exists age_restricted boolean not null default false;

-- COMMENT SHIELD: marcação interna de moderação (nunca remove dado).
alter table public.comments
  add column if not exists flagged boolean not null default false,
  add column if not exists hidden boolean not null default false;

-- MESSAGES (DM): marcação para revisão de moderação.
alter table public.messages
  add column if not exists flagged boolean not null default false;

-- REPORT CENTER: resolução administrativa visível ao denunciante.
alter table public.reports
  add column if not exists resolution text default '';

create index if not exists reports_reporter_idx
  on public.reports (reporter_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2) FAKE PROFILE — profile_flags (apenas RPC security definer escreve)
-- ---------------------------------------------------------------------------
create table if not exists public.profile_flags (
  id uuid primary key default gen_random_uuid(),
  flagged_user_id uuid not null references auth.users(id) on delete cascade,
  flagger_id uuid references auth.users(id) on delete set null,
  source text not null default 'manual' check (source in ('manual','auto')),
  reason text not null default '',
  decision text not null default 'open' check (decision in ('open','ok','attention')),
  note text default '',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null
);

create index if not exists profile_flags_user_idx on public.profile_flags (flagged_user_id);
create index if not exists profile_flags_decision_idx on public.profile_flags (decision);

alter table public.profile_flags enable row level security;
drop policy if exists "profile_flags_select_staff" on public.profile_flags;
create policy "profile_flags_select_staff" on public.profile_flags
  for select using (public.has_perm('moderation') or public.has_perm('audit'));

-- ---------------------------------------------------------------------------
-- 3) HELPERS ANTI-SPAM (normatização + decisão por regras/escopo)
-- ---------------------------------------------------------------------------
create or replace function public.spam_fold(p_text text)
returns text
language sql
immutable
as $$
  select lower(translate(coalesce(p_text, ''),
    'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
    'aaaaaeeeeiiiiooooouuuucnaaaaaeeeeiiiiooooouuuucn'));
$$;

-- Decisão por regras ativas de anti_spam_rules para o escopo dado.
-- Retorna: 'ok' | 'flag' | 'block' (block tem prioridade).
create or replace function public.spam_action(p_text text, p_scope text)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_text text := public.spam_fold(p_text);
  v_rule public.anti_spam_rules;
begin
  if v_text = '' then return 'ok'; end if;
  for v_rule in
    select r.*
      from public.anti_spam_rules r
     where r.active and (r.scope = p_scope or r.scope = 'all')
     order by r.created_at desc
  loop
    if position(public.spam_fold(v_rule.pattern) in v_text) > 0 then
      return case when v_rule.rule_type = 'block' then 'block' else 'flag' end;
    end if;
  end loop;
  return 'ok';
end;
$$;

-- Inspeção honesta: o que as regras diriam sobre um texto (para preview da UI).
create or replace function public.scan_spam(p_text text, p_scope text default 'all')
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_fold_text text := public.spam_fold(p_text);
  v_matches text[] := '{}';
  v_rule public.anti_spam_rules;
  v_action text := 'ok';
begin
  if v_fold_text <> '' then
    for v_rule in
      select r.*
        from public.anti_spam_rules r
       where r.active and (r.scope = p_scope or r.scope = 'all')
       order by r.created_at desc
    loop
      if position(public.spam_fold(v_rule.pattern) in v_fold_text) > 0 then
        v_matches := array_append(v_matches, v_rule.pattern);
        if v_rule.rule_type = 'block' and v_action = 'ok' then
          v_action := 'block';
        elsif v_action = 'ok' then
          v_action := 'flag';
        end if;
      end if;
    end loop;
  end if;
  return jsonb_build_object(
    'scope', p_scope,
    'action', v_action,
    'matches', v_matches,
    'blocked', v_action = 'block',
    'flagged', v_action in ('flag','block')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) COMMENT SHIELD / MESSAGES SHIELD (triggers de escrita ENFORÇADAS no banco)
-- ---------------------------------------------------------------------------
create or replace function public.tg_comment_shield()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_action text := public.spam_action(NEW.text, 'comment');
begin
  if v_action = 'block' then
    raise exception 'blocked_spam';
  end if;
  if v_action = 'flag' then
    NEW.flagged := true;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_comment_shield on public.comments;
create trigger tg_comment_shield
  before insert on public.comments
  for each row execute function public.tg_comment_shield();

create or replace function public.tg_message_shield()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_action text := public.spam_action(NEW.text, 'message');
begin
  if v_action = 'block' then
    raise exception 'blocked_spam';
  end if;
  if v_action = 'flag' then
    NEW.flagged := true;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_message_shield on public.messages;
create trigger tg_message_shield
  before insert on public.messages
  for each row execute function public.tg_message_shield();

-- Comentários ocultos por moderação somem do feed público (a equipe vê tudo).
drop policy if exists "comments_select_all" on public.comments;
create policy "comments_select_all" on public.comments
  for select using (
    not (hidden and not public.has_perm('moderation'))
  );

-- ---------------------------------------------------------------------------
-- 5) YOUTH SHIELD — idade/modo jovem + consentimento + gate de lives
-- ---------------------------------------------------------------------------
create or replace function public.set_birth_date(p_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if p_date is not null then
    if p_date > now()::date then raise exception 'bad_birth_date'; end if;
    if p_date < date '1900-01-01' then raise exception 'bad_birth_date'; end if;
  end if;
  update public.profiles set birth_date = p_date where id = auth.uid();
end;
$$;

create or replace function public.set_youth_mode(p_on boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  update public.profiles set youth_mode = coalesce(p_on, false) where id = auth.uid();
end;
$$;

create or replace function public.set_adult_content_ok(p_on boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  insert into public.user_settings (user_id, adult_content_ok)
  values (auth.uid(), coalesce(p_on, false))
  on conflict (user_id) do update set adult_content_ok = excluded.adult_content_ok;
end;
$$;

create or replace function public.my_safety_profile()
returns table (
  birth_date date,
  age integer,
  youth_mode boolean,
  adult_content_ok boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.birth_date,
    case when p.birth_date is not null
         then date_part('year'::text, age(now(), p.birth_date))::integer
         else null end,
    p.youth_mode,
    coalesce(us.adult_content_ok, false)
  from public.profiles p
  left join public.user_settings us on us.user_id = p.id
  where p.id = auth.uid();
$$;

-- Gate de faixa etária para assistir/participar de uma live.
create or replace function public.live_view_allowed(p_live_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_age_restricted boolean;
  v_youth boolean;
  v_birth date;
  v_adult_ok boolean;
  v_age int;
begin
  select age_restricted into v_age_restricted
    from public.lives where id = p_live_id;
  if v_age_restricted is null then return false; end if;
  if not v_age_restricted then return true; end if;

  select p.youth_mode, p.birth_date
    into v_youth, v_birth
    from public.profiles p where p.id = auth.uid();
  if coalesce(v_youth, false) then return false; end if;

  -- Menor de idade COM data de nascimento provada: nega SEMPRE, mesmo que o
  -- perfil tenha consentimento marcado (idade real vence a auto-declaração).
  if v_birth is not null then
    v_age := date_part('year'::text, age(now(), v_birth))::integer;
    if v_age < 18 then return false; end if;
  end if;

  select coalesce(us.adult_content_ok, false) into v_adult_ok
    from public.user_settings us where us.user_id = auth.uid();

  -- Sem data de nascimento: consentimento explícito basta (auto-declaração).
  if coalesce(v_adult_ok, false) then return true; end if;
  if v_birth is not null and v_age >= 18 then return true; end if;
  return false;
end;
$$;

-- Streamer marca a live como restrita a maiores (dono/moderador).
create or replace function public.set_live_age_restricted(p_live_id uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator';
  end if;
  update public.lives set age_restricted = coalesce(p_on, false) where id = p_live_id;
  perform public.write_audit('live.age_restricted', 'live', p_live_id::text,
    jsonb_build_object('on', coalesce(p_on, false)));
end;
$$;

-- Enforce do gate no chat: chat de live restrita exige autorização.
create or replace function public.tg_live_chat_age_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Escritas autoritativas do servidor (ex.: linha de presente do Edge) passam.
  if auth.uid() is null then
    return NEW;
  end if;
  if exists (
    select 1 from public.lives l
    where l.id = NEW.live_id and l.streamer_id = NEW.user_id
  ) then
    return NEW;
  end if;
  if not public.live_view_allowed(NEW.live_id) then
    raise exception 'age_gate_required';
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_live_chat_age_gate on public.live_chat;
create trigger tg_live_chat_age_gate
  before insert on public.live_chat
  for each row execute function public.tg_live_chat_age_gate();

-- ---------------------------------------------------------------------------
-- 6) ACCOUNT GUARD — sessões reais + auditoria (auth.sessions é a fonte)
-- ---------------------------------------------------------------------------
create or replace function public.auth_list_sessions()
returns table (
  id uuid,
  user_agent text,
  ip inet,
  aal text,
  created_at timestamptz,
  refreshed_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if to_regclass('auth.sessions') is null then return; end if;
  return query
    select s.id, s.user_agent, s.ip, s.aal::text, s.created_at, s.refreshed_at::timestamptz
    from auth.sessions s
    where s.user_id = auth.uid()
    order by s.refreshed_at desc nulls last;
end;
$$;

create or replace function public.auth_revoke_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not exists (
    select 1 from auth.sessions s where s.id = p_session_id and s.user_id = auth.uid()
  ) then
    raise exception 'session_not_found';
  end if;
  delete from auth.refresh_tokens where session_id = p_session_id;
  delete from auth.sessions where id = p_session_id;
  perform public.write_audit('account.revoke_session', 'session', p_session_id::text, '{}');
end;
$$;

-- Revoga TODAS as outras sessões mantendo apenas a do refresh token fornecido.
create or replace function public.auth_revoke_other_sessions(p_refresh_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'auth_required'; end if;
  if p_refresh_token is null or p_refresh_token = '' then
    raise exception 'bad_refresh_token';
  end if;
  select s.id into v_session_id
    from auth.refresh_tokens rt
    join auth.sessions s on s.id = rt.session_id
   where rt.token = p_refresh_token
     and rt.user_id = v_uid::text
     and not coalesce(rt.revoked, false);
  if v_session_id is null then raise exception 'session_not_found'; end if;

  delete from auth.refresh_tokens
   where session_id in (
     select id from auth.sessions where user_id = v_uid and id <> v_session_id
   );
  delete from auth.sessions
   where user_id = v_uid and id <> v_session_id;
  perform public.write_audit('account.revoke_others', 'session', v_session_id::text, '{}');
end;
$$;

-- Dados honestos da própria conta (exibição p/ o Account Guard do app).
create or replace function public.my_account()
returns table (
  email text,
  email_confirmed boolean,
  last_sign_in_at timestamptz,
  account_created_at timestamptz,
  providers text[]
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  return query
    select
      u.email::text,
      (u.email_confirmed_at is not null),
      u.last_sign_in_at,
      u.created_at,
      coalesce((
        select array_agg(distinct i.provider)::text[]
          from auth.identities i where i.user_id = u.id
      ), '{}'::text[])
    from auth.users u
    where u.id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- 7) REPORT CENTER — denúncia com anti-abuso + histórico real da própria
-- ---------------------------------------------------------------------------
create or replace function public.file_report(
  p_target_type text,
  p_target_id text,
  p_reason text,
  p_details text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if p_target_type not in ('user','post','live','comment','chat') then
    raise exception 'bad_target_type';
  end if;
  if p_target_id is null or p_target_id = '' then raise exception 'bad_target'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'bad_reason'; end if;

  if exists (
    select 1 from public.reports
     where reporter_id = auth.uid()
       and target_type = p_target_type
       and target_id = p_target_id
       and status in ('pending','reviewing')
       and created_at > now() - interval '24 hours'
  ) then
    raise exception 'duplicate_report';
  end if;

  select count(*) into v_count from public.reports
   where reporter_id = auth.uid() and created_at > now() - interval '1 hour';
  if v_count >= 10 then raise exception 'report_rate_limited'; end if;

  insert into public.reports (reporter_id, target_type, target_id, reason, details)
  values (auth.uid(), p_target_type, p_target_id, trim(p_reason), coalesce(p_details, ''));
end;
$$;

create or replace function public.my_reports(p_limit int default 50)
returns table (
  id uuid,
  target_type text,
  target_id text,
  reason text,
  details text,
  status text,
  resolution text,
  created_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  return query
    select r.id, r.target_type, r.target_id, r.reason, r.details,
           r.status, coalesce(r.resolution, ''), r.created_at, r.reviewed_at
      from public.reports r
     where r.reporter_id = auth.uid()
     order by r.created_at desc
     limit greatest(1, least(p_limit, 200));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8) UPGRADE DAS RPCs DE MODERAÇÃO — has_perm('moderation') + resolução
-- ---------------------------------------------------------------------------
-- A assinatura DE SAÍDA muda (novo campo resolution) → DROP antes do replace.
drop function if exists public.mod_list_reports(text);
create or replace function public.mod_list_reports(p_status text default null)
returns table (
  id uuid,
  reporter_id uuid,
  target_type text,
  target_id text,
  reason text,
  details text,
  status text,
  resolution text,
  created_at timestamptz
)
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  return query
    select r.id, r.reporter_id, r.target_type, r.target_id, r.reason,
           r.details, r.status, coalesce(r.resolution, ''), r.created_at
    from public.reports r
    where (p_status is null or r.status = p_status)
    order by r.created_at asc
    limit 200;
end;
$$;

create or replace function public.mod_update_report(
  p_report_id uuid,
  p_status text,
  p_note text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  if p_status not in ('pending','reviewing','resolved','dismissed') then
    raise exception 'bad_status';
  end if;
  update public.reports
     set status = p_status,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         resolution = case
           when p_status in ('resolved','dismissed') and p_note <> ''
             then p_note
           else resolution end
   where id = p_report_id;
  perform public.write_audit('report.update', 'report', p_report_id::text,
    jsonb_build_object('status', p_status, 'note', p_note));
end;
$$;

create or replace function public.mod_add_spam_rule(
  p_pattern text,
  p_rule_type text default 'block',
  p_scope text default 'all'
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  if p_pattern is null or length(trim(p_pattern)) = 0 then raise exception 'bad_pattern'; end if;
  insert into public.anti_spam_rules (pattern, rule_type, scope)
  values (lower(trim(p_pattern)), p_rule_type, p_scope);
end;
$$;

create or replace function public.mod_remove_spam_rule(p_rule_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  delete from public.anti_spam_rules where id = p_rule_id;
end;
$$;

create or replace function public.mod_list_spam_rules()
returns table (
  id uuid,
  pattern text,
  rule_type text,
  scope text,
  active boolean,
  created_at timestamptz
)
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  return query
    select r.id, r.pattern, r.rule_type, r.scope, r.active, r.created_at
    from public.anti_spam_rules r
    order by r.created_at desc
    limit 200;
end;
$$;

create or replace function public.mod_toggle_spam_rule(p_rule_id uuid, p_active boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  update public.anti_spam_rules set active = coalesce(p_active, true) where id = p_rule_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9) COMMENT SHIELD — RPC de ocultar/restaurar (equipe de moderação)
-- ---------------------------------------------------------------------------
create or replace function public.admin_comment_hide(
  p_comment_id uuid,
  p_hidden boolean,
  p_reason text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  update public.comments set hidden = coalesce(p_hidden, true) where id = p_comment_id;
  perform public.write_audit(
    'comment.' || case when coalesce(p_hidden, true) then 'hide' else 'restore' end,
    'comment', p_comment_id::text, jsonb_build_object('reason', p_reason));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10) FAKE PROFILE — heurísticas reais + flags resolvíveis (auditadas)
-- ---------------------------------------------------------------------------
create or replace function public.admin_suspect_profiles(p_recency_days int default 3)
returns table (
  id uuid,
  username text,
  display_name text,
  account_age_days int,
  has_avatar boolean,
  has_bio boolean,
  is_default_username boolean,
  open_flags int
)
language plpgsql security definer set search_path = public
stable
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  return query
    select
    p.id,
    p.username,
    p.display_name,
    greatest(0, extract(day from (now() - p.created_at))::int),
    (coalesce(p.avatar_url, '') <> ''),
    (coalesce(p.bio, '') <> ''),
    (p.username like 'user-%'),
    (select count(*)::int from public.profile_flags pf
      where pf.flagged_user_id = p.id and pf.decision = 'open')::int
  from public.profiles p
  where p.role = 'user'
    and (now() - p.created_at) < (p_recency_days || ' days')::interval
    and (
      coalesce(p.avatar_url, '') = ''
      or coalesce(p.bio, '') = ''
      or p.username like 'user-%'
    )
  order by p.created_at desc
  limit 100;
end;
$$;

create or replace function public.admin_flag_profile(p_user_id uuid, p_reason text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  if p_user_id is null then raise exception 'invalid_target'; end if;
  insert into public.profile_flags (flagged_user_id, flagger_id, source, reason)
  values (p_user_id, auth.uid(), 'manual', coalesce(trim(p_reason), ''));
  perform public.write_audit('profile.flag', 'profile', p_user_id::text,
    jsonb_build_object('reason', p_reason));
end;
$$;

create or replace function public.admin_resolve_profile_flag(
  p_flag_id uuid,
  p_decision text,
  p_note text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare v_user uuid;
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  if p_decision not in ('ok','attention') then raise exception 'bad_decision'; end if;
  select flagged_user_id into v_user from public.profile_flags where id = p_flag_id;
  if v_user is null then raise exception 'flag_not_found'; end if;

  update public.profile_flags
     set decision = p_decision, note = coalesce(p_note, ''),
         resolved_at = now(), resolved_by = auth.uid()
   where id = p_flag_id;

  update public.profiles set account_restricted = (p_decision = 'attention')
   where id = v_user;
  perform public.write_audit('profile.flag.resolve', 'profile', v_user::text,
    jsonb_build_object('flag_id', p_flag_id::text, 'decision', p_decision, 'note', p_note));
end;
$$;

create or replace function public.admin_list_profile_flags(p_status text default null)
returns table (
  id uuid,
  flagged_user_id uuid,
  flagger_id uuid,
  source text,
  reason text,
  decision text,
  note text,
  created_at timestamptz,
  resolved_at timestamptz
)
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  return query
    select f.id, f.flagged_user_id, f.flagger_id, f.source, f.reason,
           f.decision, coalesce(f.note, ''), f.created_at, f.resolved_at
      from public.profile_flags f
     where (p_status is null or f.decision = p_status)
     order by f.created_at desc
     limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11) GRANTS (nunca anon; somente authenticated; write_audit só service_role)
-- ---------------------------------------------------------------------------
-- Helpers spam (leitura de regras usada pelo app p/ preview).
revoke all on function public.spam_action(text, text) from public, anon;
grant execute on function public.spam_action(text, text) to authenticated;
revoke all on function public.scan_spam(text, text) from public, anon;
grant execute on function public.scan_spam(text, text) to authenticated;

-- Youth Shield
revoke all on function public.set_birth_date(date) from public, anon;
revoke all on function public.set_youth_mode(boolean) from public, anon;
revoke all on function public.set_adult_content_ok(boolean) from public, anon;
revoke all on function public.my_safety_profile() from public, anon;
revoke all on function public.live_view_allowed(uuid) from public, anon;
revoke all on function public.set_live_age_restricted(uuid, boolean) from public, anon;
grant execute on function public.set_birth_date(date) to authenticated;
grant execute on function public.set_youth_mode(boolean) to authenticated;
grant execute on function public.set_adult_content_ok(boolean) to authenticated;
grant execute on function public.my_safety_profile() to authenticated;
grant execute on function public.live_view_allowed(uuid) to authenticated;
grant execute on function public.set_live_age_restricted(uuid, boolean) to authenticated;

-- Account Guard
revoke all on function public.auth_list_sessions() from public, anon;
revoke all on function public.auth_revoke_session(uuid) from public, anon;
revoke all on function public.auth_revoke_other_sessions(text) from public, anon;
revoke all on function public.my_account() from public, anon;
grant execute on function public.auth_list_sessions() to authenticated;
grant execute on function public.auth_revoke_session(uuid) to authenticated;
grant execute on function public.auth_revoke_other_sessions(text) to authenticated;
grant execute on function public.my_account() to authenticated;

-- Report Center
revoke all on function public.file_report(text, text, text, text) from public, anon;
revoke all on function public.my_reports(int) from public, anon;
grant execute on function public.file_report(text, text, text, text) to authenticated;
grant execute on function public.my_reports(int) to authenticated;

-- Moderação (has_perm) — re-grant dos nomes existentes após o create or replace.
revoke all on function public.mod_list_reports(text) from public, anon;
revoke all on function public.mod_update_report(uuid, text, text) from public, anon;
revoke all on function public.mod_add_spam_rule(text, text, text) from public, anon;
revoke all on function public.mod_remove_spam_rule(uuid) from public, anon;
revoke all on function public.mod_list_spam_rules() from public, anon;
revoke all on function public.mod_toggle_spam_rule(uuid, boolean) from public, anon;
grant execute on function public.mod_list_reports(text) to authenticated;
grant execute on function public.mod_update_report(uuid, text, text) to authenticated;
grant execute on function public.mod_add_spam_rule(text, text, text) to authenticated;
grant execute on function public.mod_remove_spam_rule(uuid) to authenticated;
grant execute on function public.mod_list_spam_rules() to authenticated;
grant execute on function public.mod_toggle_spam_rule(uuid, boolean) to authenticated;

-- Comment Shield + Fake Profile
revoke all on function public.admin_comment_hide(uuid, boolean, text) from public, anon;
revoke all on function public.admin_suspect_profiles(int) from public, anon;
revoke all on function public.admin_flag_profile(uuid, text) from public, anon;
revoke all on function public.admin_resolve_profile_flag(uuid, text, text) from public, anon;
revoke all on function public.admin_list_profile_flags(text) from public, anon;
grant execute on function public.admin_comment_hide(uuid, boolean, text) to authenticated;
grant execute on function public.admin_suspect_profiles(int) to authenticated;
grant execute on function public.admin_flag_profile(uuid, text) to authenticated;
grant execute on function public.admin_resolve_profile_flag(uuid, text, text) to authenticated;
grant execute on function public.admin_list_profile_flags(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 12) Recarga do schema (pgrst)
-- ---------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';