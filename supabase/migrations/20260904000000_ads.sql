-- ============================================================================
-- KLAY K - Sistema Oficial de Anúncios
-- Publicidade transparente com selo controlado pelo sistema. Anunciantes reais
-- criam campanhas/conteúdos que passam por moderação (aprovado = único status
-- que recebe o selo oficial). Métricas e decisões sempre validadas no backend
-- (security definer + RLS); o cliente Flutter nunca decide APPROVED/VERIFIED.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Storage: bucket ad-media (imagens/vídeos de anúncios). Público para leitura
-- (as URL são embebidas em cards); escrita autenticada.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('ad-media', 'ad-media', true)
  on conflict (id) do nothing;

drop policy if exists "ad_media_public" on storage.objects;
create policy "ad_media_public" on storage.objects
  for select using (bucket_id = 'ad-media');

drop policy if exists "ad_media_insert" on storage.objects;
create policy "ad_media_insert" on storage.objects
  for insert with check (bucket_id = 'ad-media' and auth.role() = 'authenticated');

drop policy if exists "ad_media_update" on storage.objects;
create policy "ad_media_update" on storage.objects
  for update with check (bucket_id = 'ad-media' and auth.role() = 'authenticated');

drop policy if exists "ad_media_delete" on storage.objects;
create policy "ad_media_delete" on storage.objects
  for delete
  using (bucket_id = 'ad-media' and auth.role() = 'authenticated');

-- ---------------------------------------------------------------------------
-- advertisers
-- Perfil do anunciante — vincula um usuário autenticado à identidade pública
-- usada nos anúncios (nome, logo, categoria, descrição). is_verified é SEMPRE
-- definido pelo backend (admin), nunca pelo cliente.
-- ---------------------------------------------------------------------------
create table if not exists public.advertisers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade unique,
  business_name text not null,
  business_logo text default '',
  category text default '',
  about text default '',
  website text default '',
  contact text default '',
  is_verified boolean not null default false,
  verification_status text not null default 'pending'
    check (verification_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists advertisers_user_idx on public.advertisers (user_id);

-- ---------------------------------------------------------------------------
-- ad_campaigns
-- Configuração da campanha (nome, período, orçamento, público, objetivo).
-- status é controlado pelo backend. approved = único status exibível.
-- ---------------------------------------------------------------------------
create table if not exists public.ad_campaigns (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.advertisers(id) on delete cascade,
  name text not null,
  objective text default 'reach',
  budget numeric(14,2) not null default 0,
  audience text default '',
  interests text default '',
  region text default '',
  start_date timestamptz,
  end_date timestamptz,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_REVIEW','APPROVED','REJECTED','PAUSED','EXPIRED','BLOCKED')),
  rejection_reason text default '',
  reviewed_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ad_campaigns_advertiser_idx on public.ad_campaigns (advertiser_id);
create index if not exists ad_campaigns_status_idx on public.ad_campaigns (status);

-- ---------------------------------------------------------------------------
-- ad_creatives
-- Conteúdo criativo do anúncio (imagem/vídeo, título, descrição, CTA, destino).
-- is_verified/approved derivados da campanha; o selo é rendido pelo app.
-- ---------------------------------------------------------------------------
create table if not exists public.ad_creatives (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.ad_campaigns(id) on delete cascade,
  title text not null,
  description text default '',
  media_url text default '',
  media_type text default 'image' check (media_type in ('image','video')),
  cta_label text default 'Saiba mais',
  cta_url text default '',
  cta_type text default 'link',
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_REVIEW','APPROVED','REJECTED','PAUSED','EXPIRED','BLOCKED')),
  rejection_reason text default '',
  reviewed_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ad_creatives_campaign_idx on public.ad_creatives (campaign_id);

-- ---------------------------------------------------------------------------
-- ad_reviews
-- Histórico de moderação/análise de cada creative (motivo, por admin).
-- ---------------------------------------------------------------------------
create table if not exists public.ad_reviews (
  id uuid primary key default gen_random_uuid(),
  creative_id uuid not null references public.ad_creatives(id) on delete cascade,
  reviewer_id uuid references auth.users(id) on delete set null,
  action text not null default 'submit'
    check (action in ('submit','approve','reject','request_changes','pause','block')),
  reason text default '',
  created_at timestamptz not null default now()
);

create index if not exists ad_reviews_creative_idx on public.ad_reviews (creative_id);

-- ---------------------------------------------------------------------------
-- ad_reports
-- Denúncias de usuários sobre um anúncio. Preview de spam infinito por usuário.
-- ---------------------------------------------------------------------------
create table if not exists public.ad_reports (
  id uuid primary key default gen_random_uuid(),
  creative_id uuid not null references public.ad_creatives(id) on delete cascade,
  reporter_id uuid references auth.users(id) on delete set null,
  category text not null,
  description text default '',
  status text not null default 'open'
    check (status in ('open','dismissed','actioned')),
  created_at timestamptz not null default now()
);

create index if not exists ad_reports_creative_idx on public.ad_reports (creative_id);
create index if not exists ad_reports_reporter_idx on public.ad_reports (reporter_id);

-- ---------------------------------------------------------------------------
-- ad_user_preferences
-- Preferência de "ocultar este anúncio" por usuário.
-- ---------------------------------------------------------------------------
create table if not exists public.ad_user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  creative_id uuid not null references public.ad_creatives(id) on delete cascade,
  hidden boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, creative_id)
);

-- ---------------------------------------------------------------------------
-- ad_events
-- Métricas reais: impressão e clique (cnt_click = 1 quando click, senão 0).
-- ---------------------------------------------------------------------------
create table if not exists public.ad_events (
  id uuid primary key default gen_random_uuid(),
  creative_id uuid not null references public.ad_creatives(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in ('impression','click')),
  cnt_click int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists ad_events_creative_idx on public.ad_events (creative_id);
create index if not exists ad_events_type_created_idx on public.ad_events (event_type, created_at);

-- ============================================================================
-- ROW LEVEL SECURITY
-- O usuário comum só lê o que precisa para exibir o anúncio aprovado (nunca
-- orçamento/gasto/denúncias/preferências). Anunciante escreve seus próprios
-- drafts/pending e lê suas próprias campanhas/budgets/métricas.
-- ============================================================================

alter table public.advertisers enable row level security;
alter table public.ad_campaigns enable row level security;
alter table public.ad_creatives enable row level security;
alter table public.ad_reviews enable row level security;
alter table public.ad_reports enable row level security;
alter table public.ad_user_preferences enable row level security;
alter table public.ad_events enable row level security;

-- --- advertisers: leitura pública só de dados públicos; escrita só do dono ---
drop policy if exists advertisers_public_select on public.advertisers;
drop policy if exists advertisers_owner_insert on public.advertisers;
drop policy if exists advertisers_owner_update on public.advertisers;
create policy advertisers_public_select on public.advertisers
  for select using (true);
create policy advertisers_owner_insert on public.advertisers
  for insert with check (auth.uid() = user_id);
create policy advertisers_owner_update on public.advertisers
  for update using (auth.uid() = user_id);

-- --- campaigns: dono vê as suas; público só aprovadas (sem budget) ---
drop policy if exists ad_campaigns_owner_all on public.ad_campaigns;
drop policy if exists ad_campaigns_public_select on public.ad_campaigns;
create policy ad_campaigns_owner_all on public.ad_campaigns
  for all using (auth.uid() in (
    select a.user_id from public.advertisers a where a.id = advertiser_id
  ));
create policy ad_campaigns_public_select on public.ad_campaigns
  for select using (status = 'APPROVED');

-- --- creatives: dono lê os seus (via campanha); público só aprovados ---
drop policy if exists ad_creatives_owner_select on public.ad_creatives;
drop policy if exists ad_creatives_public_select on public.ad_creatives;
create policy ad_creatives_owner_select on public.ad_creatives
  for select using (auth.uid() in (
    select a.user_id from public.advertisers a
    join public.ad_campaigns c on c.advertiser_id = a.id
    where c.id = campaign_id
  ));
create policy ad_creatives_public_select on public.ad_creatives
  for select using (status = 'APPROVED');

-- --- reviews: só admins leem/escrevem (sem exposição pública) ---
drop policy if exists ad_reviews_admin_select on public.ad_reviews;
drop policy if exists ad_reviews_admin_insert on public.ad_reviews;
create policy ad_reviews_admin_select on public.ad_reviews
  for select using (exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
  ));
create policy ad_reviews_admin_insert on public.ad_reviews
  for insert with check (exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
  ));

-- --- reports: admin lê; usuário autenticado cria (a própria) ---
drop policy if exists ad_reports_admin_select on public.ad_reports;
drop policy if exists ad_reports_user_insert on public.ad_reports;
create policy ad_reports_admin_select on public.ad_reports
  for select using (exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
  ));
create policy ad_reports_user_insert on public.ad_reports
  for insert with check (auth.uid() = reporter_id);

-- --- preferences: cada usuário apenas as suas ---
drop policy if exists ad_prefs_owner on public.ad_user_preferences;
create policy ad_prefs_owner on public.ad_user_preferences
  for all using (auth.uid() = user_id);

-- --- events: inserção autenticada; leitura apenas do dono/metrics ---
drop policy if exists ad_events_user_insert on public.ad_events;
drop policy if exists ad_events_owner_select on public.ad_events;
create policy ad_events_user_insert on public.ad_events
  for insert with check (auth.uid() = user_id);
create policy ad_events_owner_select on public.ad_events
  for select using (auth.uid() = user_id);

-- ============================================================================
-- FUNÇÕES AUXILIARES (helpers shared)
-- ============================================================================

-- Anunciante do usuário logado (id do advertiser), ou null.
-- security definer + set search_path = public: eleva privilégios para ler o
-- advertiser do usuário logado sem expor dados de outros anunciantes, com
-- search_path fixo para evitar hijacking.
create or replace function public.my_advertiser_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select a.id from public.advertisers a where a.user_id = auth.uid();
$$;
revoke all on function public.my_advertiser_id() from public;
grant execute on function public.my_advertiser_id() to authenticated;

-- Cria (ou retorna) o perfil de anunciante do usuário logado e atualiza o
-- proprietário da campanha para ele. Uso: primeira vez que abre a Central.
create or replace function public.ads_upsert_advertiser(
  p_business_name text,
  p_category text default '',
  p_about text default '',
  p_website text default '',
  p_contact text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  select id into v_id from public.advertisers where user_id = auth.uid();
  if v_id is null then
    insert into public.advertisers (user_id, business_name, category, about, website, contact)
    values (auth.uid(), p_business_name, coalesce(p_category,''), coalesce(p_about,''),
            coalesce(p_website,''), coalesce(p_contact,''))
    returning id into v_id;
  else
    update public.advertisers
      set business_name = coalesce(p_business_name, business_name),
          category = coalesce(p_category, category),
          about = coalesce(p_about, about),
          website = coalesce(p_website, website),
          contact = coalesce(p_contact, contact),
          updated_at = now()
      where id = v_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.ads_upsert_advertiser(text, text, text, text, text) from public;
grant execute on function public.ads_upsert_advertiser(text, text, text, text, text) to authenticated;

-- Cria campanha (status DRAFT) para o anunciante logado.
create or replace function public.ads_create_campaign(
  p_name text,
  p_objective text default 'reach',
  p_budget numeric default 0,
  p_audience text default '',
  p_interests text default '',
  p_region text default '',
  p_start_date timestamptz default null,
  p_end_date timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_ad uuid; v_id uuid;
begin
  select id into v_ad from public.advertisers where user_id = auth.uid();
  if v_ad is null then
    raise exception 'advertiser_required';
  end if;
  insert into public.ad_campaigns
    (advertiser_id, name, objective, budget, audience, interests, region,
     start_date, end_date, status)
  values
    (v_ad, p_name, coalesce(p_objective,'reach'), coalesce(p_budget,0),
     coalesce(p_audience,''), coalesce(p_interests,''), coalesce(p_region,''),
     p_start_date, p_end_date, 'DRAFT')
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.ads_create_campaign(text, text, numeric, text, text, text, timestamptz, timestamptz) from public;
grant execute on function public.ads_create_campaign(text, text, numeric, text, text, text, timestamptz, timestamptz) to authenticated;

-- Cria creative (status DRAFT) e envia para análise (PENDING_REVIEW).
create or replace function public.ads_create_creative(
  p_campaign_id uuid,
  p_title text,
  p_description text default '',
  p_media_url text default '',
  p_media_type text default 'image',
  p_cta_label text default 'Saiba mais',
  p_cta_url text default '',
  p_cta_type text default 'link',
  p_submit boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_ad uuid; v_id uuid; v_status text := 'DRAFT';
begin
  if p_submit then v_status := 'PENDING_REVIEW'; end if;
  select a.id into v_ad
    from public.advertisers a
    join public.ad_campaigns c on c.advertiser_id = a.id
    where a.user_id = auth.uid() and c.id = p_campaign_id;
  if v_ad is null then
    raise exception 'not_owner';
  end if;
  insert into public.ad_creatives
    (campaign_id, title, description, media_url, media_type, cta_label,
     cta_url, cta_type, status, reviewed_at)
  values
    (p_campaign_id, p_title, coalesce(p_description,''), coalesce(p_media_url,''),
     coalesce(p_media_type,'image'), coalesce(p_cta_label,'Saiba mais'),
     coalesce(p_cta_url,''), coalesce(p_cta_type,'link'), v_status,
     case when p_submit then now() else null end)
  returning id into v_id;
  if p_submit then
    insert into public.ad_reviews (creative_id, action) values (v_id, 'submit');
  end if;
  return v_id;
end;
$$;
revoke all on function public.ads_create_creative(uuid, text, text, text, text, text, text, text, boolean) from public;
grant execute on function public.ads_create_creative(uuid, text, text, text, text, text, text, text, boolean) to authenticated;

-- Lista "meus anúncios" (campanhas + creatives) do anunciante logado.
create or replace function public.ads_my_list()
returns table (
  campaign_id uuid,
  campaign_name text,
  campaign_status text,
  budget numeric,
  spent numeric,
  creative_id uuid,
  creative_title text,
  creative_status text,
  creative_media text,
  creative_cta text,
  creative_url text,
  impressions bigint,
  clicks bigint,
  rejection_reason text,
  created_at timestamptz,
  approved_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.status,
    c.budget,
    coalesce((select coalesce(sum(case when e.cnt_click > 0 then 1 else 0 end),0)::numeric
              from public.ad_events e where e.creative_id = cr.id), 0) as spent,
    cr.id,
    cr.title,
    cr.status,
    cr.media_url,
    cr.cta_label,
    cr.cta_url,
    (select count(*) from public.ad_events e where e.creative_id = cr.id
       and e.event_type = 'impression'),
    (select count(*) from public.ad_events e where e.creative_id = cr.id
       and e.event_type = 'click'),
    cr.rejection_reason,
    c.created_at,
    cr.approved_at
  from public.ad_campaigns c
  join public.advertisers a on a.id = c.advertiser_id and a.user_id = auth.uid()
  join public.ad_creatives cr on cr.campaign_id = c.id
  order by c.created_at desc;
$$;
revoke all on function public.ads_my_list() from public;
grant execute on function public.ads_my_list() to authenticated;

-- Métricas agregadas do anunciante logado (reais, do backend).
create or replace function public.ads_my_metrics()
returns table (
  total_impressions bigint,
  total_clicks bigint,
  active_campaigns bigint,
  pending_campaigns bigint,
  budget numeric
)
language sql
security definer
set search_path = public
as $$
  select
    coalesce(sum(t.impressions),0),
    coalesce(sum(t.clicks),0),
    coalesce(sum(case when t.campaign_status = 'APPROVED' then 1 else 0 end),0),
    coalesce(sum(case when t.campaign_status = 'PENDING_REVIEW' then 1 else 0 end),0),
    coalesce(sum(t.budget),0)
  from public.ads_my_list() t;
$$;
revoke all on function public.ads_my_metrics() from public;
grant execute on function public.ads_my_metrics() to authenticated;

-- Registra experiência/anúncio visto (impressão) ou clique.
create or replace function public.ads_track_event(
  p_creative_id uuid,
  p_event_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Só conta para creatives aprovados (evita inflar métricas de pending).
  if not exists (
    select 1 from public.ad_creatives cr
    join public.ad_campaigns c on c.id = cr.campaign_id
    where cr.id = p_creative_id
      and cr.status = 'APPROVED' and c.status = 'APPROVED'
  ) then
    return;
  end if;
  insert into public.ad_events (creative_id, user_id, event_type, cnt_click)
  values (p_creative_id, auth.uid(), p_event_type, case when p_event_type='click' then 1 else 0 end);
end;
$$;
revoke all on function public.ads_track_event(uuid, text) from public;
grant execute on function public.ads_track_event(uuid, text) to authenticated;

-- Oculta anúncio para o usuário logado.
create or replace function public.ads_hide_creative(p_creative_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.ad_user_preferences (user_id, creative_id, hidden)
  values (auth.uid(), p_creative_id, true)
  on conflict (user_id, creative_id) do update set hidden = true, created_at = now();
end;
$$;
revoke all on function public.ads_hide_creative(uuid) from public;
grant execute on function public.ads_hide_creative(uuid) to authenticated;

-- Denúncia (com limite anti-spam: máx. 3 abertas por usuário).
create or replace function public.ads_report_creative(
  p_creative_id uuid,
  p_category text,
  p_description text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  select count(*) into v_count from public.ad_reports
    where reporter_id = auth.uid() and status = 'open';
  if v_count >= 3 then
    raise exception 'too_many_reports';
  end if;
  insert into public.ad_reports (creative_id, reporter_id, category, description)
  values (p_creative_id, auth.uid(), p_category, coalesce(p_description,''));
end;
$$;
revoke all on function public.ads_report_creative(uuid, text, text) from public;
grant execute on function public.ads_report_creative(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC público: anúncios aprovados prontos para exibição.
-- Expõe SOMENTE colunas seguras para exibição (nunca orçamento/regiao/público/
-- dados privados do anunciante). É o único caminho público para o feed.
-- ---------------------------------------------------------------------------
create or replace function public.ads_public_approved(p_limit int default 10)
returns table (
  creative_id uuid,
  campaign_name text,
  title text,
  description text,
  media_url text,
  media_type text,
  cta_label text,
  cta_url text,
  cta_type text,
  business_name text,
  business_logo text,
  advertiser_category text,
  verified boolean,
  impressions bigint,
  clicks bigint
)
language sql
security definer
set search_path = public
as $$
  select
    cr.id, c.name, cr.title, cr.description, cr.media_url, cr.media_type,
    cr.cta_label, cr.cta_url, cr.cta_type,
    a.business_name, a.business_logo, a.category, a.is_verified,
    (select count(*) from public.ad_events e where e.creative_id = cr.id and e.event_type='impression'),
    (select count(*) from public.ad_events e where e.creative_id = cr.id and e.event_type='click')
  from public.ad_creatives cr
  join public.ad_campaigns c on c.id = cr.campaign_id and c.status = 'APPROVED'
  join public.advertisers a on a.id = c.advertiser_id
  where cr.status = 'APPROVED'
  order by cr.updated_at desc
  limit greatest(1, least(p_limit, 50));
$$;
revoke all on function public.ads_public_approved(int) from public;
grant execute on function public.ads_public_approved(int) to anon, authenticated;

-- ============================================================================
-- MODERAÇÃO/ADMIN (security definer; sempre valida profiles.is_admin no backend)
-- ============================================================================

create or replace function public.ad_is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;
revoke all on function public.ad_is_admin() from public;
grant execute on function public.ad_is_admin() to authenticated;

-- Lista anúncios para moderação/admin com filtros.
create or replace function public.admin_ads_list(
  p_status text default '',
  p_advertiser_name text default '',
  p_category text default ''
)
returns table (
  creative_id uuid,
  campaign_id uuid,
  title text,
  description text,
  media text,
  cta text,
  cta_url text,
  creative_status text,
  campaign_name text,
  campaign_status text,
  business_name text,
  category text,
  budget numeric,
  impressions bigint,
  clicks bigint,
  rejection_reason text,
  created_at timestamptz,
  approved_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then
    raise exception 'not_admin';
  end if;
  return query
    select
      cr.id, c.id, cr.title, cr.description, cr.media_url, cr.cta_label,
      cr.cta_url, cr.status, c.name, c.status, a.business_name, a.category,
      c.budget,
      (select count(*) from public.ad_events e where e.creative_id = cr.id and e.event_type='impression'),
      (select count(*) from public.ad_events e where e.creative_id = cr.id and e.event_type='click'),
      cr.rejection_reason,
      cr.created_at, cr.approved_at
    from public.ad_creatives cr
    join public.ad_campaigns c on c.id = cr.campaign_id
    join public.advertisers a on a.id = c.advertiser_id
    where
      (p_status = '' or cr.status = p_status)
      and (p_advertiser_name = '' or a.business_name ilike '%'||p_advertiser_name||'%')
      and (p_category = '' or a.category = p_category)
    order by cr.created_at desc;
end;
$$;
revoke all on function public.admin_ads_list(text, text, text) from public;
grant execute on function public.admin_ads_list(text, text, text) to authenticated;

-- Aprova creative + campanha (único caminho para o selo oficial).
create or replace function public.admin_ads_approve(
  p_creative_id uuid,
  p_reason text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then raise exception 'not_admin'; end if;
  update public.ad_creatives
    set status='APPROVED', approved_at=now(), reviewed_at=now(), rejection_reason=''
    where id = p_creative_id;
  update public.ad_campaigns
    set status='APPROVED',
        approved_at = now(),
        reviewed_at = now(),
        rejection_reason=''
    where id = (select campaign_id from public.ad_creatives where id = p_creative_id);
  insert into public.ad_reviews (creative_id, reviewer_id, action, reason)
    values (p_creative_id, auth.uid(), 'approve', coalesce(p_reason,''));
end;
$$;
revoke all on function public.admin_ads_approve(uuid, text) from public;
grant execute on function public.admin_ads_approve(uuid, text) to authenticated;

-- Rejeita creative (campanha fica REJECTED também; motivo obrigatório).
create or replace function public.admin_ads_reject(
  p_creative_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then raise exception 'not_admin'; end if;
  update public.ad_creatives
    set status='REJECTED', rejection_reason=coalesce(p_reason,''), reviewed_at=now()
    where id = p_creative_id;
  update public.ad_campaigns set status='REJECTED', reviewed_at=now()
    where id = (select campaign_id from public.ad_creatives where id = p_creative_id);
  insert into public.ad_reviews (creative_id, reviewer_id, action, reason)
    values (p_creative_id, auth.uid(), 'reject', coalesce(p_reason,''));
end;
$$;
revoke all on function public.admin_ads_reject(uuid, text) from public;
grant execute on function public.admin_ads_reject(uuid, text) to authenticated;

-- Solicita alteração (PENDING_REVIEW -> reabre para o dono editar/envir).
create or replace function public.admin_ads_request_changes(
  p_creative_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then raise exception 'not_admin'; end if;
  update public.ad_creatives
    set status='PENDING_REVIEW', rejection_reason=coalesce(p_reason,''), reviewed_at=now()
    where id = p_creative_id;
  insert into public.ad_reviews (creative_id, reviewer_id, action, reason)
    values (p_creative_id, auth.uid(), 'request_changes', coalesce(p_reason,''));
end;
$$;
revoke all on function public.admin_ads_request_changes(uuid, text) from public;
grant execute on function public.admin_ads_request_changes(uuid, text) to authenticated;

-- Pausa (deixa de ser exibido para usuários).
create or replace function public.admin_ads_pause(p_creative_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then raise exception 'not_admin'; end if;
  update public.ad_creatives set status='PAUSED', reviewed_at=now() where id = p_creative_id;
  update public.ad_campaigns set status='PAUSED' where id = (
    select campaign_id from public.ad_creatives where id = p_creative_id);
  insert into public.ad_reviews (creative_id, reviewer_id, action) values (p_creative_id, auth.uid(), 'pause');
end;
$$;
revoke all on function public.admin_ads_pause(uuid) from public;
grant execute on function public.admin_ads_pause(uuid) to authenticated;

-- Bloqueia (não pode ser exibido; motivo obrigatório).
create or replace function public.admin_ads_block(
  p_creative_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then raise exception 'not_admin'; end if;
  update public.ad_creatives
    set status='BLOCKED', rejection_reason=coalesce(p_reason,''), reviewed_at=now()
    where id = p_creative_id;
  update public.ad_campaigns set status='BLOCKED' where id = (
    select campaign_id from public.ad_creatives where id = p_creative_id);
  insert into public.ad_reviews (creative_id, reviewer_id, action, reason)
    values (p_creative_id, auth.uid(), 'block', coalesce(p_reason,''));
end;
$$;
revoke all on function public.admin_ads_block(uuid, text) from public;
grant execute on function public.admin_ads_block(uuid, text) to authenticated;

-- Lista de denúncias dos anúncios (admin).
create or replace function public.admin_ads_reports()
returns table (
  report_id uuid,
  creative_id uuid,
  title text,
  category text,
  description text,
  report_status text,
  reporter_username text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ad_is_admin() then
    raise exception 'not_admin';
  end if;
  return query
    select
      r.id, r.creative_id, cr.title, r.category, r.description, r.status,
      pr.username,
      r.created_at
    from public.ad_reports r
    join public.ad_creatives cr on cr.id = r.creative_id
    left join public.profiles pr on pr.id = r.reporter_id
    order by r.created_at desc;
end;
$$;
revoke all on function public.admin_ads_reports() from public;
grant execute on function public.admin_ads_reports() to authenticated;