-- ============================================================================
-- KLAY K — CONTROLES FAMILIARES (aditivo, SEM vigilância)
--
-- Princípio inegociável deste arquivo: um responsável ajusta PREFERÊNCIAS de
-- segurança de um perfil que está sob responsabilidade declarada. Ele
-- NUNCA lê mensagens, NUNCA acessa conteúdo privado, NUNCA vê câmera,
-- microfone ou localização. Não existe nenhuma coluna nesta tabela que
-- permita isso, e nenhuma função deste arquivo retorna conteúdo do usuário
-- protegido — apenas as próprias preferências de segurança que ele pode
-- mudar.
--
-- Nada é removido: só cria tabela nova + RLS owner/staff + funções.
-- ============================================================================

create table if not exists public.family_links (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  relationship text not null default 'responsavel'
    check (relationship in ('responsavel','pai_mae','tutor')),
  status text not null default 'pending'
    check (status in ('pending','active','revoked')),
  can_manage_safety boolean not null default true,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz,
  unique (guardian_id, member_id),
  check (guardian_id <> member_id)
);

create index if not exists family_links_guardian_idx
  on public.family_links (guardian_id, status);
create index if not exists family_links_member_idx
  on public.family_links (member_id, status);

alter table public.family_links enable row level security;

drop policy if exists "family_links_select_participants" on public.family_links;
drop policy if exists "family_links_insert_guardian" on public.family_links;
drop policy if exists "family_links_update_participants" on public.family_links;
drop policy if exists "family_links_delete_guardian" on public.family_links;

create policy "family_links_select_participants" on public.family_links
  for select using (guardian_id = auth.uid() or member_id = auth.uid());
create policy "family_links_insert_guardian" on public.family_links
  for insert with check (guardian_id = auth.uid());
create policy "family_links_update_participants" on public.family_links
  for update using (guardian_id = auth.uid() or member_id = auth.uid())
  with check (guardian_id = auth.uid() or member_id = auth.uid());
create policy "family_links_delete_guardian" on public.family_links
  for delete using (guardian_id = auth.uid());

-- ---------------------------------------------------------------------------
-- request_family_link: o responsável pede o vínculo (fica pending até o
-- próprio titular aceitar — consentimento real, nada é ativado sozinho).
-- ---------------------------------------------------------------------------
create or replace function public.request_family_link(
  p_member_id uuid,
  p_relationship text default 'responsavel'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_guardian uuid := auth.uid();
  v_link_id uuid;
begin
  if v_guardian is null then raise exception 'auth_required'; end if;
  if p_member_id is null or p_member_id = v_guardian then
    raise exception 'bad_member';
  end if;
  if p_relationship not in ('responsavel','pai_mae','tutor') then
    raise exception 'bad_relationship';
  end if;

  insert into public.family_links (guardian_id, member_id, relationship)
  values (v_guardian, p_member_id, p_relationship)
  on conflict (guardian_id, member_id) do update
    set relationship = excluded.relationship,
        status = 'pending',
        revoked_at = null
  returning id into v_link_id;

  return v_link_id;
end;
$$;

revoke all on function public.request_family_link(uuid, text) from public, anon;
grant execute on function public.request_family_link(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- respond_family_link: só o MEMBRO aceita/recusa o pedido.
-- ---------------------------------------------------------------------------
create or replace function public.respond_family_link(p_link_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;

  update public.family_links
     set status = case when p_accept then 'active' else 'revoked' end,
         accepted_at = case when p_accept then now() else null end,
         revoked_at = case when p_accept then null else now() end
   where id = p_link_id
     and member_id = auth.uid()
     and status = 'pending';

  if not found then raise exception 'link_not_found'; end if;

  return jsonb_build_object('ok', true, 'status', case when p_accept then 'active' else 'revoked' end);
end;
$$;

revoke all on function public.respond_family_link(uuid, boolean) from public, anon;
grant execute on function public.respond_family_link(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- revoke_family_link: qualquer das duas partes pode revogar.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_family_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;

  update public.family_links
     set status = 'revoked', revoked_at = now()
   where id = p_link_id
     and (guardian_id = auth.uid() or member_id = auth.uid());

  if not found then raise exception 'link_not_found'; end if;
end;
$$;

revoke all on function public.revoke_family_link(uuid) from public, anon;
grant execute on function public.revoke_family_link(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- my_family_links: vínculos próprios (só metadados do vínculo).
-- ---------------------------------------------------------------------------
create or replace function public.my_family_links()
returns table (
  id uuid,
  direction text,
  other_id uuid,
  relationship text,
  status text,
  can_manage_safety boolean,
  created_at timestamptz,
  accepted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'auth_required'; end if;
  return query
    select l.id,
           case when l.guardian_id = u then 'guardian' else 'member' end,
           case when l.guardian_id = u then l.member_id else l.guardian_id end,
           l.relationship, l.status, l.can_manage_safety,
           l.created_at, l.accepted_at
      from public.family_links l
     where l.guardian_id = u or l.member_id = u
     order by l.created_at desc;
end;
$$;

revoke all on function public.my_family_links() from public, anon;
grant execute on function public.my_family_links() to authenticated;

-- ---------------------------------------------------------------------------
-- family_safety_snapshot: SOMENTE as preferências de segurança do titular
-- (nada de mensagens, mídia ou localização). É o limite explícito do
-- produto: o responsável ajusta descanso, filtro ejuberação, nunca conteúdo.
-- ---------------------------------------------------------------------------
create or replace function public.family_safety_snapshot(p_link_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_link public.family_links%rowtype;
  v_profile public.profiles%rowtype;
begin
  if u is null then raise exception 'auth_required'; end if;

  select * into v_link from public.family_links l
   where l.id = p_link_id
     and l.guardian_id = u
     and l.status = 'active'
     and l.can_manage_safety;

  if not found then raise exception 'link_not_found'; end if;

  select p.id, p.display_name, p.username, p.birth_date
    into v_profile
    from public.profiles p
   where p.id = v_link.member_id;

  return jsonb_build_object(
    'member_id', v_link.member_id,
    'display_name', v_profile.display_name,
    'username', v_profile.username,
    'has_birth_date', v_profile.birth_date is not null,
    'settings', jsonb_build_object(
      'allow_messages', coalesce((select us.allow_messages from public.user_settings us where us.user_id = v_link.member_id), 'everyone'),
      'allow_comments', coalesce((select us.allow_comments from public.user_settings us where us.user_id = v_link.member_id), true),
      'allow_mentions', coalesce((select us.allow_mentions from public.user_settings us where us.user_id = v_link.member_id), 'everyone'),
      'sensitive_content_filter', coalesce((select us.sensitive_content_filter from public.user_settings us where us.user_id = v_link.member_id), false),
      'security_confirm_actions', coalesce((select us.security_confirm_actions from public.user_settings us where us.user_id = v_link.member_id), true)
    )
  );
end;
$$;

revoke all on function public.family_safety_snapshot(uuid) from public, anon;
grant execute on function public.family_safety_snapshot(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- family_set_safety_settings: o responsável ajusta apenas os campos de
-- segurança permitidos abaixo. Lista fechada — não aceita conteúdo.
-- ---------------------------------------------------------------------------
create or replace function public.family_set_safety_settings(
  p_link_id uuid,
  p_allow_messages text default null,
  p_allow_comments boolean default null,
  p_allow_mentions text default null,
  p_sensitive_content_filter boolean default null,
  p_security_confirm_actions boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member uuid;
  scopes text[] := array['everyone','followers','friends','none'];
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;

  select l.member_id into v_member
    from public.family_links l
   where l.id = p_link_id
     and l.guardian_id = auth.uid()
     and l.status = 'active'
     and l.can_manage_safety;

  if v_member is null then raise exception 'forbidden'; end if;

  if p_allow_messages is not null and not (p_allow_messages = any (scopes)) then
    raise exception 'bad_scope';
  end if;
  if p_allow_mentions is not null and not (p_allow_mentions = any (scopes)) then
    raise exception 'bad_scope';
  end if;

  update public.user_settings
     set allow_messages = coalesce(p_allow_messages, allow_messages),
         allow_comments = coalesce(p_allow_comments, allow_comments),
         allow_mentions = coalesce(p_allow_mentions, allow_mentions),
         sensitive_content_filter = coalesce(p_sensitive_content_filter, sensitive_content_filter),
         security_confirm_actions = coalesce(p_security_confirm_actions, security_confirm_actions),
         updated_at = now()
   where user_id = v_member;

  return public.family_safety_snapshot(p_link_id);
end;
$$;

revoke all on function public.family_set_safety_settings(
  uuid, text, boolean, text, boolean, boolean
) from public, anon;
grant execute on function public.family_set_safety_settings(
  uuid, text, boolean, text, boolean, boolean
) to authenticated;

notify pgrst, 'reload schema';
