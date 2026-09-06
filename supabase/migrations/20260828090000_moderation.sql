-- ============================================================================
-- Moderação: ban/silêncio de LIVE persistidos + RPCs administrativas + RLS
-- de administrador (profiles.is_admin).
-- ============================================================================

-- Helper: é administrador do KLAY K?
create or replace function public.is_klayk_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;

grant execute on function public.is_klayk_admin() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- live_bans: usuários banidos de uma live (criador/moderadores)
-- ---------------------------------------------------------------------------
create table if not exists public.live_bans (
  live_id uuid not null references public.lives(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  banned_by uuid not null references auth.users(id) on delete cascade,
  reason text default '',
  created_at timestamptz not null default now(),
  primary key (live_id, user_id)
);

create index if not exists live_bans_live_idx on public.live_bans (live_id);

alter table public.live_bans enable row level security;
drop policy if exists "livebans_select_all" on public.live_bans;
create policy "livebans_select_all" on public.live_bans for select using (true);

-- ---------------------------------------------------------------------------
-- live_mutes: usuários silenciados numa live (criador/moderadores)
-- ---------------------------------------------------------------------------
create table if not exists public.live_mutes (
  live_id uuid not null references public.lives(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  muted_by uuid not null references auth.users(id) on delete cascade,
  reason text default '',
  until timestamptz,
  created_at timestamptz not null default now(),
  primary key (live_id, user_id)
);

create index if not exists live_mutes_live_idx on public.live_mutes (live_id);

alter table public.live_mutes enable row level security;
drop policy if exists "livemutes_select_all" on public.live_mutes;
create policy "livemutes_select_all" on public.live_mutes for select using (true);

-- ---------------------------------------------------------------------------
-- Helper: quem pode moderar uma live? (dono ou moderador cadastrado)
-- ---------------------------------------------------------------------------
create or replace function public.can_moderate_live(p_live_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.lives l
    where l.id = p_live_id and l.streamer_id = auth.uid()
  ) or exists (
    select 1 from public.live_moderators lm
    where lm.live_id = p_live_id and lm.moderator_id = auth.uid()
  );
$$;

revoke all on function public.can_moderate_live(uuid) from public;
grant execute on function public.can_moderate_live(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- live_mod_ban / live_mod_unban / live_mod_mute / live_mod_unmute
-- Escrita real e persistida; broadcast fica a cargo do cliente (realtime).
-- ---------------------------------------------------------------------------
create or replace function public.live_mod_ban(
  p_live_id uuid,
  p_user_id uuid,
  p_reason text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator';
  end if;
  if p_user_id is null then raise exception 'invalid_target'; end if;
  insert into public.live_bans (live_id, user_id, banned_by, reason)
  values (p_live_id, p_user_id, auth.uid(), p_reason)
  on conflict (live_id, user_id) do update set reason = excluded.reason, banned_by = excluded.banned_by;
  delete from public.live_mutes where live_id = p_live_id and user_id = p_user_id;
end;
$$;

create or replace function public.live_mod_unban(p_live_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator';
  end if;
  delete from public.live_bans where live_id = p_live_id and user_id = p_user_id;
end;
$$;

create or replace function public.live_mod_mute(
  p_live_id uuid,
  p_user_id uuid,
  p_minutes int default 10,
  p_reason text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator';
  end if;
  if p_user_id is null then raise exception 'invalid_target'; end if;
  insert into public.live_mutes (live_id, user_id, muted_by, reason, until)
  values (
    p_live_id, p_user_id, auth.uid(), p_reason,
    case when p_minutes > 0 then now() + (p_minutes || ' minutes')::interval else null end
  )
  on conflict (live_id, user_id) do update set until = excluded.until, muted_by = excluded.muted_by, reason = excluded.reason;
end;
$$;

create or replace function public.live_mod_unmute(p_live_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.can_moderate_live(p_live_id) then
    raise exception 'not_moderator';
  end if;
  delete from public.live_mutes where live_id = p_live_id and user_id = p_user_id;
end;
$$;

revoke all on function public.live_mod_ban(uuid, uuid, text) from public;
revoke all on function public.live_mod_unban(uuid, uuid) from public;
revoke all on function public.live_mod_mute(uuid, uuid, int, text) from public;
revoke all on function public.live_mod_unmute(uuid, uuid) from public;
grant execute on function public.live_mod_ban(uuid, uuid, text) to authenticated;
grant execute on function public.live_mod_unban(uuid, uuid) to authenticated;
grant execute on function public.live_mod_mute(uuid, uuid, int, text) to authenticated;
grant execute on function public.live_mod_unmute(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Painel administrativo: denúncias + regras anti-spam (somente admin)
-- ---------------------------------------------------------------------------

create or replace function public.mod_list_reports(p_status text default null)
returns table (
  id uuid,
  reporter_id uuid,
  target_type text,
  target_id text,
  reason text,
  details text,
  status text,
  created_at timestamptz
)
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
  return query
    select r.id, r.reporter_id, r.target_type, r.target_id, r.reason,
           r.details, r.status, r.created_at
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
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
  if p_status not in ('pending','reviewing','resolved','dismissed') then
    raise exception 'bad_status';
  end if;
  update public.reports
  set status = p_status, reviewed_at = now(), reviewed_by = auth.uid(),
      details = case when p_note != '' then p_note else details end
  where id = p_report_id;
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
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
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
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
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
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
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
  if not public.is_klayk_admin() then
    raise exception 'not_admin';
  end if;
  update public.anti_spam_rules set active = coalesce(p_active, true) where id = p_rule_id;
end;
$$;

revoke all on function public.mod_list_reports(text) from public;
revoke all on function public.mod_update_report(uuid, text, text) from public;
revoke all on function public.mod_add_spam_rule(text, text, text) from public;
revoke all on function public.mod_remove_spam_rule(uuid) from public;
revoke all on function public.mod_list_spam_rules() from public;
revoke all on function public.mod_toggle_spam_rule(uuid, boolean) from public;
grant execute on function public.mod_list_reports(text) to authenticated;
grant execute on function public.mod_update_report(uuid, text, text) to authenticated;
grant execute on function public.mod_add_spam_rule(text, text, text) to authenticated;
grant execute on function public.mod_remove_spam_rule(uuid) to authenticated;
grant execute on function public.mod_list_spam_rules() to authenticated;
grant execute on function public.mod_toggle_spam_rule(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Fix de RLS: apenas administradores atualizam/leem todas as denúncias.
-- Denunciante continua podendo apenas ler a própria.
-- ---------------------------------------------------------------------------
drop policy if exists "reports_select_own" on public.reports;
drop policy if exists "reports_update_service" on public.reports;
drop policy if exists "reports_admin_select" on public.reports;
drop policy if exists "reports_admin_update" on public.reports;
create policy "reports_select_own"
  on public.reports for select using (
    reporter_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );
create policy "reports_admin_update"
  on public.reports for update using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

-- ---------------------------------------------------------------------------
-- Realtime das tabelas de moderação de live (clientes filtram em tempo real)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where schemaname = 'public' and tablename in ('live_bans','live_mutes')
  ) then
    alter publication supabase_realtime add table public.live_bans;
    alter publication supabase_realtime add table public.live_mutes;
  end if;
end;
$$;