-- ============================================================================
-- KLAY K — ROLES, EQUIPE E AUDITORIA
-- Substitui o boolean único `is_admin` por um framework de roles seguro:
--   founder / super_admin / admin / moderator / support / user
-- A autorização é SEMPRE validada no backend (has_perm → security definer).
-- O Flutter NUNCA decide permissão por e-mail; ele apenas lê RPCs.
-- Profiles.is_admin é mantido como flag de compatibilidade, mas agora é uma
-- DERIVAÇÃO (trigger) e nunca pode ser gravado pelo cliente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- admin_roles: catálogo de roles + capabilities (o que cada role pode fazer).
-- ---------------------------------------------------------------------------
create table if not exists public.admin_roles (
  id text primary key,
  name text not null,
  rank int not null default 0,
  capabilities text[] not null default '{}',
  description text default '',
  created_at timestamptz not null default now()
);

insert into public.admin_roles (id, name, rank, capabilities, description) values
  ('founder',     'Fundador',        100, '{"*"}',                      'Dono do KLAY K. Acesso total, incluindo gestão de roles.'),
  ('super_admin', 'Super Administrador', 90, '{"users","moderation","verification","gifts","store","live","orders","economy","chests","missions","support","audit","settings"}', 'Acesso total operacional, sem gestão de roles.'),
  ('admin',       'Administrador',   80, '{"users","moderation","verification","gifts","store","live","orders","economy","chests","missions","support","audit","settings"}', 'Administração completa, sem gestão de roles.'),
  ('moderator',   'Moderador',       60, '{"moderation","live","verification_view"}', 'Modera conteúdo, lives e vê verificações.'),
  ('support',     'Suporte',         50, '{"support","tickets","verification_view"}', 'Central de ajuda e tickets.'),
  ('user',        'Usuário',         10, '{}',                           'Conta comum.')
on conflict (id) do update set
  name = excluded.name, rank = excluded.rank,
  capabilities = excluded.capabilities, description = excluded.description;

alter table public.admin_roles enable row level security;
drop policy if exists "admin_roles_select" on public.admin_roles;
create policy "admin_roles_select" on public.admin_roles for select using (true);
grant select on table public.admin_roles to anon, authenticated;

-- ---------------------------------------------------------------------------
-- profiles.role: role atual do usuário (default 'user').
-- A flag is_admin vira derivação via trigger; o cliente NUNCA grava role.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists role text not null default 'user'
  check (role in ('founder','super_admin','admin','moderator','support','user'));

-- ---------------------------------------------------------------------------
-- Triggers de derivação: role → is_admin (compatibilidade com RPCs antigas).
-- ---------------------------------------------------------------------------
create or replace function public.sync_is_admin_from_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  NEW.is_admin := NEW.role in ('founder','super_admin','admin');
  return NEW;
end;
$$;

drop trigger if exists sync_is_admin_from_role on public.profiles;
create trigger sync_is_admin_from_role
  before insert or update of role on public.profiles
  for each row execute function public.sync_is_admin_from_role();

-- Backfill: normaliza is_admin a partir da role existente (idempotente).
update public.profiles
   set is_admin = (role = 'founder' or role = 'super_admin' or role = 'admin')
 where is_admin is distinct from (role = 'founder' or role = 'super_admin' or role = 'admin');

-- ---------------------------------------------------------------------------
-- Helpers de autorização (todos security definer + search_path fixo).
-- Ordem: definidos ANTES das policies/RLPCs que os referenciam.
-- ---------------------------------------------------------------------------

-- Role atual do usuário autenticado ('user' se anônimo/sem perfil).
create or replace function public.my_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select p.role from public.profiles p where p.id = auth.uid()), 'user');
$$;

grant execute on function public.my_role() to anon, authenticated;

-- É ao menos da equipe (moderador/suporte/admin/super/founder)?
create or replace function public.is_klayk_staff()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select p.role <> 'user' from public.profiles p where p.id = auth.uid()), false);
$$;

grant execute on function public.is_klayk_staff() to anon, authenticated;

-- Is the traditional "admin" (admin+)? Mantém compatibilidade: alternativas
-- (moderador/suporte) NÃO passam por aqui, preservando o gate das RPCs antigas.
create or replace function public.is_klayk_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;

grant execute on function public.is_klayk_admin() to anon, authenticated;

-- Fundador (só quem pode gerir roles).
create or replace function public.is_klayk_founder()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select p.role = 'founder' from public.profiles p where p.id = auth.uid()), false);
$$;

grant execute on function public.is_klayk_founder() to anon, authenticated;

-- Capability check: `*` libera tudo; role >= moderador tem suas próprias caps.
create or replace function public.has_perm(p_cap text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((
    select (r.capabilities @> '{*}'::text[] or r.capabilities @> array[p_cap])
    from public.profiles p
    join public.admin_roles r on r.id = p.role
    where p.id = auth.uid()
  ), false);
$$;

grant execute on function public.has_perm(text) to anon, authenticated;

-- Lista as capabilities do usuário atual (para a UI esconder/mostrar tabs).
create or replace function public.my_caps()
returns text[]
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select r.capabilities from public.profiles p join public.admin_roles r on r.id = p.role where p.id = auth.uid()), '{}'::text[]);
$$;

grant execute on function public.my_caps() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- audit_logs: trilha de auditoria imutável (somente o helper security definer
-- grava; clientes apenas leem se forem staff). Nada aqui é fake.
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text default '',
  entity_id text default '',
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists audit_actor_idx on public.audit_logs (actor_id, created_at desc);
create index if not exists audit_entity_idx on public.audit_logs (entity_type, entity_id);
create index if not exists audit_action_idx on public.audit_logs (action);

alter table public.audit_logs enable row level security;

-- Leitura: somente equipe (qualquer role de staff), via helper estável.
drop policy if exists "audit_select_staff" on public.audit_logs;
create policy "audit_select_staff" on public.audit_logs
  for select using (public.is_klayk_staff());

-- SEM política de insert/update/delete: apenas o helper security definer grava.

-- Helper de auditoria: única forma de gravar em audit_logs.
-- Restrito a service_role (Edge Functions) + chamadas internas de RPCs
-- security definer (que rodam como dono). O cliente NÃO tem EXECUTE, então
-- nunca grava auditoria diretamente — contudo, ao chamar RPCs legítimas
-- (ex.: abrir baú) o fluxo registra auditoria com actor = auth.uid() atual
-- (o próprio usuário). Impossível forjar actor de outra pessoa.
create or replace function public.write_audit(
  p_action text,
  p_entity_type text default '',
  p_entity_id text default '',
  p_details jsonb default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_details);
end;
$$;

revoke all on function public.write_audit(text, text, text, jsonb) from public;
revoke execute on function public.write_audit(text, text, text, jsonb) from anon, authenticated;
grant execute on function public.write_audit(text, text, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- RPCs administrativas de EQUIPE + ROLES (backend validado).
-- ---------------------------------------------------------------------------

-- Lista dos membros da equipe (staff) com role/capabilities.
create or replace function public.admin_list_staff()
returns table (
  id uuid, username text, display_name text, role text,
  is_admin boolean, is_verified boolean, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.role, p.is_admin, p.is_verified, p.created_at
  from public.profiles p
  where p.role <> 'user' and public.is_klayk_staff()
  order by p.created_at desc
  limit 100;
$$;

revoke all on function public.admin_list_staff() from public;
grant execute on function public.admin_list_staff() to authenticated;

-- Altera a role. SÓ founder (capability 'roles'). Nunca 'user' via revoga o
-- próprio acesso (proteção contra autodescensão total). Founder/super_admin
-- só podem ser nomeados pelo próprio founder.
create or replace function public.admin_set_role(
  p_user_id uuid,
  p_role text,
  p_reason text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('roles') then
    raise exception 'not_founder';
  end if;
  if p_role not in ('founder','super_admin','admin','moderator','support','user') then
    raise exception 'bad_role';
  end if;
  if p_role = 'user' and auth.uid() = p_user_id then
    raise exception 'cannot_demote_self';
  end if;
  if p_role in ('founder','super_admin') and not public.is_klayk_founder() then
    raise exception 'founder_only';
  end if;
  update public.profiles set role = p_role where id = p_user_id;
  perform public.write_audit('role.set', 'profile', p_user_id::text,
    jsonb_build_object('role', p_role, 'reason', p_reason));
end;
$$;

revoke all on function public.admin_set_role(uuid, text, text) from public;
grant execute on function public.admin_set_role(uuid, text, text) to authenticated;

-- Consulta a trilha de auditoria (staff com cap 'audit' ou 'roles').
create or replace function public.admin_audit_list(
  p_limit int default 100
)
returns table (
  id bigint, actor_id uuid, action text, entity_type text,
  entity_id text, details jsonb, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('audit') and not public.has_perm('roles') then
    raise exception 'not_admin';
  end if;
  return query
    select a.id, a.actor_id, a.action, a.entity_type, a.entity_id, a.details, a.created_at
    from public.audit_logs a
    order by a.created_at desc
    limit greatest(1, least(p_limit, 500));
end;
$$;

revoke all on function public.admin_audit_list(int) from public;
grant execute on function public.admin_audit_list(int) to authenticated;

-- Seed do fundador: identificado pelo e-mail oficial. A autorização NUNCA
-- acontece no Flutter; aqui o dono do banco (dono do projeto) marca o criador.
update public.profiles p
   set role = 'founder', is_admin = true
  from auth.users u
 where u.id = p.id
   and lower(u.email) = 'ceo.arh.tech@gmail.com'
   and p.role <> 'founder';

-- Marcação dinâmica: quando o perfil do dono for criado (ex.: primeiro login
-- via Google OAuth), o trigger o torna fundador automaticamente. Sempre no
-- servidor — o app nunca decide isso. is_admin é derivado em conjunto para
-- independer da ordem dos triggers.
create or replace function public.tg_mark_founder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from auth.users u
    where u.id = NEW.id
      and lower(u.email) = 'ceo.arh.tech@gmail.com'
  ) then
    NEW.role := 'founder';
    NEW.is_admin := true;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_mark_founder on public.profiles;
create trigger tg_mark_founder
  before insert or update of id, role on public.profiles
  for each row execute function public.tg_mark_founder();

-- ---------------------------------------------------------------------------
-- Override de compatibilidade: admin_set_admin (antigo boolean) agora mexe em
-- roles reais. Mantém o nome/assinatura para o FounderPanel existente, mas a
-- permissão passa a ser has_perm('roles') (só founder) e a flag is_admin é
-- derivada automaticamente pelo trigger.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_admin(p_user_id uuid, p_admin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('roles') then
    raise exception 'not_founder';
  end if;
  if p_user_id = auth.uid() and not p_admin then
    raise exception 'cannot_demote_self';
  end if;
  update public.profiles set role = case when p_admin then 'admin' else 'user' end where id = p_user_id;
  perform public.write_audit('role.set_admin', 'profile', p_user_id::text,
    jsonb_build_object('admin', p_admin));
end;
$$;

revoke all on function public.admin_set_admin(uuid, boolean) from public;
grant execute on function public.admin_set_admin(uuid, boolean) to authenticated;