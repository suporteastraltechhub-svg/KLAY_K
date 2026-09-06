-- ===========================================================================
-- KLAY K — PROFISSÕES + CENTRAL DE BOTS (cargos, verificação e permissões)
-- ---------------------------------------------------------------------------
-- Tudo ADMIN é `security definer` e re-valida `is_klayk_admin()`/`has_perm`
-- no servidor. O cliente NUNCA decide; apenas expõe abas conforme my_caps.
-- ===========================================================================

-- ===========================================================================
-- 1) PROFISSÕES
-- ===========================================================================
create table if not exists public.professions (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  icon        text not null default '',
  category    text not null default 'geral',
  status      text not null default 'active' check (status in ('active','inactive')),
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.professions enable row level security;

-- Qualquer pessoa pode ver as profissões ativas (público); o catálogo completo
-- (incl. inativas) fica restrito a admin via RPC.
drop policy if exists "professions_public_read" on public.professions;
create policy "professions_public_read" on public.professions
  for select using (status = 'active');
grant select on table public.professions to anon, authenticated;

-- Coluna de profissão no perfil (texto exibível; atribuída por admin ou pela
-- própria conta — a lista de opções vem do catálogo ativo).
alter table public.profiles
  add column if not exists profession text not null default '';

-- Lista ativa (público).
create or replace function public.list_professions()
returns table (id uuid, name text, icon text, category text, sort_order int)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.name, p.icon, p.category, p.sort_order
  from public.professions p
  where p.status = 'active'
  order by p.sort_order, p.name;
$$;
grant execute on function public.list_professions() to anon, authenticated;

-- O usuário pode escolher a própria profissão entre as ativas.
create or replace function public.set_my_profession(p_profession text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  -- Apenas um nome existente e ativo (evita texto arbitrário no perfil).
  if not exists (
    select 1 from public.professions
    where name = p_profession and status = 'active'
  ) then
    raise exception 'profession_not_found';
  end if;
  update public.profiles set profession = p_profession where id = v_uid;
  return found;
end;
$$;
grant execute on function public.set_my_profession(text) to authenticated;

-- Catálogo completo (admin).
create or replace function public.admin_list_professions()
returns table (id uuid, name text, icon text, category text, status text, sort_order int, created_at timestamptz)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.name, p.icon, p.category, p.status, p.sort_order, p.created_at
  from public.professions p
  order by p.sort_order, p.name;
$$;
grant execute on function public.admin_list_professions()
  to anon, authenticated, service_role;

-- Criar/editar profissão (admin).
create or replace function public.admin_upsert_profession(
  p_id uuid default null,
  p_name text default null,
  p_icon text default '',
  p_category text default 'geral',
  p_status text default 'active',
  p_sort_order int default 0
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  if p_status not in ('active','inactive') then
    raise exception 'bad_status';
  end if;
  if p_id is null then
    insert into public.professions (name, icon, category, status, sort_order)
    values (p_name, p_icon, p_category, p_status, p_sort_order)
    on conflict (name) do update set
      icon = excluded.icon, category = excluded.category,
      status = excluded.status, sort_order = excluded.sort_order;
    perform public.write_audit('profession.create', 'profession', p_name,
      jsonb_build_object('icon', p_icon, 'category', p_category, 'status', p_status));
  else
    update public.professions set
      name = coalesce(p_name, name),
      icon = coalesce(p_icon, icon),
      category = coalesce(p_category, category),
      status = coalesce(p_status, status),
      sort_order = coalesce(p_sort_order, sort_order)
    where id = p_id;
    perform public.write_audit('profession.update', 'profession', p_id::text,
      jsonb_build_object('name', p_name, 'status', p_status));
  end if;
  return true;
end;
$$;
grant execute on function public.admin_upsert_profession(uuid,text,text,text,text,int)
  to anon, authenticated, service_role;

-- Ativar/desativar profissão (admin).
create or replace function public.admin_set_profession_status(p_id uuid, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  if p_status not in ('active','inactive') then
    raise exception 'bad_status';
  end if;
  update public.professions set status = p_status where id = p_id;
  perform public.write_audit('profession.status', 'profession', p_id::text,
    jsonb_build_object('status', p_status));
  return found;
end;
$$;
grant execute on function public.admin_set_profession_status(uuid,text)
  to anon, authenticated, service_role;

-- Remover profissão (admin).
create or replace function public.admin_delete_profession(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  delete from public.professions where id = p_id;
  perform public.write_audit('profession.delete', 'profession', p_id::text, '{}');
  return found;
end;
$$;
grant execute on function public.admin_delete_profession(uuid)
  to anon, authenticated, service_role;

-- Atribuir profissão a um usuário (admin).
create or replace function public.admin_set_user_profession(p_user_id uuid, p_profession text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  update public.profiles set profession = p_profession where id = p_user_id;
  perform public.write_audit('profession.assign', 'profile', p_user_id::text,
    jsonb_build_object('profession', p_profession));
  return found;
end;
$$;
grant execute on function public.admin_set_user_profession(uuid,text)
  to anon, authenticated, service_role;

-- ===========================================================================
-- 2) BOTS
-- ===========================================================================
create table if not exists public.bots (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  avatar       text not null default '',
  bio          text not null default '',
  bot_role     text not null default 'support'
               check (bot_role in ('support','moderation','voice','system')),
  permissions  jsonb not null default '{}',
  status       text not null default 'inactive'
               check (status in ('active','inactive','paused')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.bots enable row level security;

-- Bots ativos e públicos (support/system) podem aparecer em listas de contato;
-- bots de moderação/voz ficam ocultos do público.
drop policy if exists "bots_public_read" on public.bots;
create policy "bots_public_read" on public.bots
  for select using (status = 'active' and bot_role in ('support','system'));
grant select on table public.bots to anon, authenticated;

-- Catálogo completo (admin).
create or replace function public.admin_list_bots()
returns table (id uuid, name text, avatar text, bio text, bot_role text, permissions jsonb, status text, created_at timestamptz, updated_at timestamptz)
language sql
security definer
set search_path = public
stable
as $$
  select b.id, b.name, b.avatar, b.bio, b.bot_role, b.permissions, b.status, b.created_at, b.updated_at
  from public.bots b
  order by b.bot_role, b.name;
$$;
grant execute on function public.admin_list_bots()
  to anon, authenticated, service_role;

-- Criar/editar bot (admin).
create or replace function public.admin_upsert_bot(
  p_id uuid default null,
  p_name text default null,
  p_avatar text default '',
  p_bio text default '',
  p_bot_role text default 'support',
  p_status text default 'inactive',
  p_permissions jsonb default '{}'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  if p_bot_role not in ('support','moderation','voice','system') then
    raise exception 'bad_role';
  end if;
  if p_status not in ('active','inactive','paused') then
    raise exception 'bad_status';
  end if;
  -- Bots nunca recebem permissões administrativas automaticamente.
  p_permissions := (p_permissions::jsonb) - 'is_admin' - 'is_founder' - 'role';
  if p_id is null then
    insert into public.bots (name, avatar, bio, bot_role, status, permissions)
    values (p_name, p_avatar, p_bio, p_bot_role, p_status, p_permissions);
    perform public.write_audit('bot.create', 'bot', p_name,
      jsonb_build_object('role', p_bot_role, 'status', p_status));
  else
    update public.bots set
      name = coalesce(p_name, name),
      avatar = coalesce(p_avatar, avatar),
      bio = coalesce(p_bio, bio),
      bot_role = coalesce(p_bot_role, bot_role),
      status = coalesce(p_status, status),
      permissions = p_permissions,
      updated_at = now()
    where id = p_id;
    perform public.write_audit('bot.update', 'bot', p_id::text,
      jsonb_build_object('name', p_name, 'role', p_bot_role, 'status', p_status));
  end if;
  return true;
end;
$$;
grant execute on function public.admin_upsert_bot(uuid,text,text,text,text,text,jsonb)
  to anon, authenticated, service_role;

-- Ativar/desativar/pausar bot (admin).
create or replace function public.admin_set_bot_status(p_id uuid, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  if p_status not in ('active','inactive','paused') then
    raise exception 'bad_status';
  end if;
  update public.bots set status = p_status, updated_at = now() where id = p_id;
  perform public.write_audit('bot.status', 'bot', p_id::text,
    jsonb_build_object('status', p_status));
  return found;
end;
$$;
grant execute on function public.admin_set_bot_status(uuid,text)
  to anon, authenticated, service_role;

-- Remover bot (admin).
create or replace function public.admin_delete_bot(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_klayk_admin() or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  delete from public.bots where id = p_id;
  perform public.write_audit('bot.delete', 'bot', p_id::text, '{}');
  return found;
end;
$$;
grant execute on function public.admin_delete_bot(uuid)
  to anon, authenticated, service_role;

-- ===========================================================================
-- 3) get_profile com profession (re-criado depois da coluna existir)
-- ===========================================================================
create or replace function public.get_profile(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_profile jsonb;
  v_total_likes bigint;
  v_is_following boolean;
  v_is_self boolean;
begin
  v_is_self := auth.uid() is not null and auth.uid() = p_user_id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'banner_url', p.banner_url,
    'bio', p.bio,
    'website', p.website,
    'location', p.location,
    'pronouns', p.pronouns,
    'is_private', p.is_private,
    'is_verified', p.is_verified,
    'is_admin', p.is_admin,
    'role', p.role,
    'profession', p.profession,
    'birth_date', case when v_is_self
                        then to_char(p.birth_date, 'YYYY-MM-DD')
                        else null end,
    'followers_count', p.followers_count,
    'following_count', p.following_count,
    'posts_count', p.posts_count,
    'created_at', p.created_at
  )
  into v_profile
  from public.profiles p
  where p.id = p_user_id;

  if v_profile is null then
    return null;
  end if;

  select coalesce(sum(p2.likes_count), 0)::bigint into v_total_likes
  from public.posts p2
  where p2.user_id = p_user_id;

  v_is_following := false;
  if not v_is_self then
    select exists (
      select 1 from public.follows f
      where f.follower_id = auth.uid() and f.following_id = p_user_id
    ) into v_is_following;
  end if;

  return v_profile
    || jsonb_build_object('total_likes', v_total_likes)
    || jsonb_build_object('is_following', v_is_following)
    || jsonb_build_object('is_self', v_is_self);
end;
$$;

grant execute on function public.get_profile(uuid) to anon, authenticated;
