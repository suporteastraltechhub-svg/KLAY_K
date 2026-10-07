-- ============================================================================
-- Central de Marketing (KLAY K) — camada administrativa offline-first
-- sobre o sistema de anúncios existente.
--
-- Segurança:
--  * Acesso APENAS a administradores (profiles.is_admin), validado no backend
--    via `marketing_is_admin()` (security definer) — nunca decidido pelo app.
--  * RLS habilitada + policies restritas a admins em todas as tabelas.
--  * Entradas nunca expostas via tabela direta: o app só usa as RPCs.
--  * Campos mínimos. Nenhum secret armazenado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper de admin (mesmo padrão de `ad_is_admin` do sistema de anúncios).
-- ----------------------------------------------------------------------------
create or replace function public.marketing_is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;
revoke all on function public.marketing_is_admin() from public;
grant execute on function public.marketing_is_admin() to authenticated;

-- ----------------------------------------------------------------------------
-- Tabelas
-- ----------------------------------------------------------------------------
create table if not exists public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid(),
  name text not null default '',
  objective text not null default '',
  audience text not null default '',
  format text not null default '',
  tone text not null default '',
  keywords text[] not null default '{}',
  title text not null default '',
  description text not null default '',
  cta text not null default '',
  script_category text not null default '',
  script_text text not null default '',
  checklist text[] not null default '{}',
  status text not null default 'draft' check (status in ('draft', 'approved', 'archived')),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.marketing_variants (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.marketing_campaigns(id) on delete cascade,
  label text not null,
  title text not null default '',
  description text not null default '',
  cta text not null default '',
  unique (campaign_id, label)
);

create table if not exists public.marketing_briefs (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid(),
  title text not null default '',
  format text not null default '',
  product text not null default '',
  brief_text text not null default '',
  created_at timestamptz not null default now()
);

alter table public.marketing_campaigns enable row level security;
alter table public.marketing_variants enable row level security;
alter table public.marketing_briefs enable row level security;

create policy marketing_admin_campaigns_all
  on public.marketing_campaigns for all to authenticated
  using (public.marketing_is_admin())
  with check (public.marketing_is_admin());

create policy marketing_admin_variants_all
  on public.marketing_variants for all to authenticated
  using (public.marketing_is_admin())
  with check (public.marketing_is_admin());

create policy marketing_admin_briefs_all
  on public.marketing_briefs for all to authenticated
  using (public.marketing_is_admin())
  with check (public.marketing_is_admin());

revoke all on table public.marketing_campaigns from anon, authenticated;
revoke all on table public.marketing_variants from anon, authenticated;
revoke all on table public.marketing_briefs from anon, authenticated;

-- ----------------------------------------------------------------------------
-- RPCs (security definer; re-validam admin no backend)
-- ----------------------------------------------------------------------------

-- Salva (insert/update) uma campanha + substitui suas variações.
create or replace function public.marketing_save_campaign(
  p_name text,
  p_objective text,
  p_audience text,
  p_format text,
  p_tone text,
  p_keywords text[],
  p_title text,
  p_description text,
  p_cta text,
  p_script_category text default '',
  p_script_text text default '',
  p_checklist text[] default '{}',
  p_status text default 'draft',
  p_id uuid default null,
  p_variants jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  -- Normalizações simples de conteúdo (valores mínimos e seguros).
  v_id := coalesce(p_id, gen_random_uuid());

  if p_status not in ('draft', 'approved', 'archived') then
    p_status := 'draft';
  end if;

  insert into public.marketing_campaigns (
    id, created_by, name, objective, audience, format, tone, keywords,
    title, description, cta, script_category, script_text, checklist, status,
    approved_at, updated_at
  )
  values (
    v_id, auth.uid(),
    left(coalesce(p_name, ''), 160),
    left(coalesce(p_objective, ''), 40),
    left(coalesce(p_audience, ''), 300),
    left(coalesce(p_format, ''), 40),
    left(coalesce(p_tone, ''), 40),
    coalesce(p_keywords, '{}'),
    left(coalesce(p_title, ''), 200),
    left(coalesce(p_description, ''), 2000),
    left(coalesce(p_cta, ''), 40),
    left(coalesce(p_script_category, ''), 40),
    left(coalesce(p_script_text, ''), 20000),
    coalesce(p_checklist, '{}'),
    p_status,
    case when p_status = 'approved' then now() else null end,
    now()
  )
  on conflict (id) do update set
    name = excluded.name,
    objective = excluded.objective,
    audience = excluded.audience,
    format = excluded.format,
    tone = excluded.tone,
    keywords = excluded.keywords,
    title = excluded.title,
    description = excluded.description,
    cta = excluded.cta,
    script_category = excluded.script_category,
    script_text = excluded.script_text,
    checklist = excluded.checklist,
    status = excluded.status,
    approved_at = excluded.approved_at,
    updated_at = now();

  delete from public.marketing_variants where campaign_id = v_id;
  insert into public.marketing_variants (campaign_id, label, title, description, cta)
  select
    v_id,
    coalesce(e->>'label', 'A'),
    left(coalesce(e->>'title', ''), 200),
    left(coalesce(e->>'description', ''), 2000),
    left(coalesce(e->>'cta', ''), 40)
  from jsonb_array_elements(coalesce(p_variants, '[]'::jsonb)) as e
  where e->>'label' is not null;

  return v_id;
end;
$$;
revoke all on function public.marketing_save_campaign from public;
grant execute on function public.marketing_save_campaign to authenticated;

-- Lista campanhas (com variações embutidas) para o painel admin.
create or replace function public.marketing_list_campaigns(p_status text default '')
returns table (
  id uuid,
  name text,
  objective text,
  audience text,
  format text,
  tone text,
  keywords text[],
  title text,
  description text,
  cta text,
  script_category text,
  script_text text,
  checklist text[],
  status text,
  created_at timestamptz,
  approved_at timestamptz,
  updated_at timestamptz,
  variants jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.name,
    c.objective,
    c.audience,
    c.format,
    c.tone,
    c.keywords,
    c.title,
    c.description,
    c.cta,
    c.script_category,
    c.script_text,
    c.checklist,
    c.status,
    c.created_at,
    c.approved_at,
    c.updated_at,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'label', v.label,
          'title', v.title,
          'description', v.description,
          'cta', v.cta
        ) order by v.label
      ) filter (where v.id is not null),
      '[]'::jsonb
    ) as variants
  from public.marketing_campaigns c
  left join public.marketing_variants v on v.campaign_id = c.id
  where (p_status = '' or c.status = p_status)
  group by c.id
  order by c.updated_at desc;
end;
$$;
revoke all on function public.marketing_list_campaigns from public;
grant execute on function public.marketing_list_campaigns to authenticated;

-- Busca uma campanha (com variações).
create or replace function public.marketing_get_campaign(p_id uuid)
returns table (
  id uuid,
  name text,
  objective text,
  audience text,
  format text,
  tone text,
  keywords text[],
  title text,
  description text,
  cta text,
  script_category text,
  script_text text,
  checklist text[],
  status text,
  created_at timestamptz,
  approved_at timestamptz,
  updated_at timestamptz,
  variants jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.name,
    c.objective,
    c.audience,
    c.format,
    c.tone,
    c.keywords,
    c.title,
    c.description,
    c.cta,
    c.script_category,
    c.script_text,
    c.checklist,
    c.status,
    c.created_at,
    c.approved_at,
    c.updated_at,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'label', v.label,
          'title', v.title,
          'description', v.description,
          'cta', v.cta
        ) order by v.label
      ) filter (where v.id is not null),
      '[]'::jsonb
    ) as variants
  from public.marketing_campaigns c
  left join public.marketing_variants v on v.campaign_id = c.id
  where c.id = p_id
  group by c.id;
end;
$$;
revoke all on function public.marketing_get_campaign from public;
grant execute on function public.marketing_get_campaign to authenticated;

-- Altera status (draft -> approved/archived, etc.). Aprovar exige revisão.
create or replace function public.marketing_set_status(p_id uuid, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated boolean := false;
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  if p_status not in ('draft', 'approved', 'archived') then
    raise exception 'invalid status' using errcode = '22023';
  end if;

  update public.marketing_campaigns
  set status = p_status,
      approved_at = case when p_status = 'approved' then now() else approved_at end,
      updated_at = now()
  where id = p_id and status <> 'archived'
  returning true into v_updated;

  return coalesce(v_updated, false);
end;
$$;
revoke all on function public.marketing_set_status from public;
grant execute on function public.marketing_set_status to authenticated;

-- Duplica campanha (novo rascunho com variações copiadas).
create or replace function public.marketing_duplicate_campaign(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid := gen_random_uuid();
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  insert into public.marketing_campaigns (
    id, created_by, name, objective, audience, format, tone, keywords,
    title, description, cta, script_category, script_text, checklist, status,
    created_at, updated_at
  )
  select
    v_new_id, auth.uid(), left(name || ' (cópia)', 160), objective, audience,
    format, tone, keywords, title, description, cta, script_category,
    script_text, checklist, 'draft', now(), now()
  from public.marketing_campaigns
  where id = p_id;

  if not found then
    return null;
  end if;

  insert into public.marketing_variants (campaign_id, label, title, description, cta)
  select v_new_id, label, title, description, cta
  from public.marketing_variants
  where campaign_id = p_id;

  return v_new_id;
end;
$$;
revoke all on function public.marketing_duplicate_campaign from public;
grant execute on function public.marketing_duplicate_campaign to authenticated;

-- Exclui campanha (apenas rascunho/arquivada; aprovada precisa arquivar 1º).
create or replace function public.marketing_delete_campaign(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted boolean := false;
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  delete from public.marketing_campaigns
  where id = p_id and status in ('draft', 'archived')
  returning true into v_deleted;

  return coalesce(v_deleted, false);
end;
$$;
revoke all on function public.marketing_delete_campaign from public;
grant execute on function public.marketing_delete_campaign to authenticated;

-- ----------------------------------------------------------------------------
-- Briefings (admins salvam/copiam texto; sem geração de imagens)
-- ----------------------------------------------------------------------------
create or replace function public.marketing_save_brief(
  p_title text,
  p_format text,
  p_product text,
  p_brief_text text,
  p_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  v_id := coalesce(p_id, gen_random_uuid());

  insert into public.marketing_briefs (
    id, created_by, title, format, product, brief_text, created_at
  )
  values (
    v_id, auth.uid(),
    left(coalesce(p_title, ''), 160),
    left(coalesce(p_format, ''), 40),
    left(coalesce(p_product, ''), 200),
    left(coalesce(p_brief_text, ''), 20000),
    now()
  )
  on conflict (id) do update set
    title = excluded.title,
    format = excluded.format,
    product = excluded.product,
    brief_text = excluded.brief_text;

  return v_id;
end;
$$;
revoke all on function public.marketing_save_brief from public;
grant execute on function public.marketing_save_brief to authenticated;

create or replace function public.marketing_list_briefs()
returns table (
  id uuid,
  title text,
  format text,
  product text,
  brief_text text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  return query
  select b.id, b.title, b.format, b.product, b.brief_text, b.created_at
  from public.marketing_briefs b
  order by b.created_at desc;
end;
$$;
revoke all on function public.marketing_list_briefs from public;
grant execute on function public.marketing_list_briefs to authenticated;

create or replace function public.marketing_delete_brief(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted boolean := false;
begin
  if not public.marketing_is_admin() then
    raise exception 'permission denied for marketing' using errcode = '42501';
  end if;

  delete from public.marketing_briefs where id = p_id
  returning true into v_deleted;

  return coalesce(v_deleted, false);
end;
$$;
revoke all on function public.marketing_delete_brief from public;
grant execute on function public.marketing_delete_brief to authenticated;