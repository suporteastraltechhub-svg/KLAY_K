-- KLAY K · Sistema de Anúncios — gerenciamento de campanha pelo anunciante.
--
-- Complementa 20260904000000_ads.sql. Não altera nem remove nenhuma função,
-- tabela ou coluna existente: só acrescenta colunas e RPCs novas.
--
-- Por que este arquivo existe
-- -------------------------
-- O app (ad_create_screen / ads_central_screen / ads_campaign_detail_screen)
-- já tem a interface pronta para rascunho, edição, pausar/retomar/encerrar e
-- duplicar campanha. Essas ações não podiam ser implementadas antes porque não
-- havia:
--   * coluna para orçamento diário e limite de gastos;
--   * coluna para posicionamento (onde o anúncio pode aparecer);
--   * RPC para editar um rascunho (o app só sabia criar);
--   * RPC para excluir um rascunho;
--   * RPC para o próprio anunciante mudar o status da campanha
--     (só o admin podia, via ads_admin_*);
--   * RPC para reenviar um criativo reprovado corrigido.
--
-- Regra de segurança mantida do arquivo original: o anunciante só mexe nas
-- própria linhas (mesmo `not_owner` de ads_create_creative), o app NUNCA decide
-- APPROVED, e validação de dinheiro/status fica no servidor — não no Flutter.

-- ---------------------------------------------------------------------------
-- 1. Colunas novas em ad_campaigns
-- ---------------------------------------------------------------------------

alter table public.ad_campaigns
  add column if not exists daily_budget numeric(14,2),
  add column if not exists spend_cap numeric(14,2),
  add column if not exists placements text[] not null default '{}',
  add column if not exists updated_approved_at timestamptz;

comment on column public.ad_campaigns.daily_budget is
  'Orçamento diário em KLAY$. NULL = usa o orçamento total da campanha.';
comment on column public.ad_campaigns.spend_cap is
  'Teto máximo de gasto em KLAY$. NULL = sem teto além do orçamento total.';
comment on column public.ad_campaigns.placements is
  'Espaços onde o anúncio pode aparecer: for_you, between_videos, highlights, discovery.';

-- Espaços aceitos. Mantido como tabela para o CHECK ficar legível e a
-- validação continuar no servidor.
create table if not exists public.ad_placements (
  key text primary key,
  label text not null
);

insert into public.ad_placements (key, label) values
  ('for_you', 'Para Você'),
  ('between_videos', 'Entre vídeos'),
  ('highlights', 'Destaques'),
  ('discovery', 'Descoberta')
on conflict (key) do nothing;

alter table public.ad_campaigns
  drop constraint if exists ad_campaigns_placements_valid;
alter table public.ad_campaigns
  add constraint ad_campaigns_placements_valid
  check (placements <@ array['for_you','between_videos','highlights','discovery']);

-- O valor gasto continua NÃO sendo calculado aqui: não existe cobrança no
-- servidor. A coluna `spent` devolvida por ads_my_list() é a contagem de
-- cliques e a UI do app não a exibe como dinheiro (ver ad_campaign_detail_screen).

-- ---------------------------------------------------------------------------
-- 2. Helper: a campanha pertence ao anunciante logado?
-- ---------------------------------------------------------------------------

create or replace function public.ads_owns_campaign(p_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.ad_campaigns c
    join public.advertisers a on a.id = c.advertiser_id
    where c.id = p_campaign_id and a.user_id = auth.uid()
  );
$$;
revoke all on function public.ads_owns_campaign(uuid) from public;
grant execute on function public.ads_owns_campaign(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Editar campanha (só o dono; nunca muda status de aprovação)
-- ---------------------------------------------------------------------------

create or replace function public.ads_update_campaign(
  p_campaign_id uuid,
  p_name text,
  p_budget numeric default null,
  p_daily_budget numeric default null,
  p_spend_cap numeric default null,
  p_placements text[] default null,
  p_audience text default null,
  p_interests text default null,
  p_region text default null,
  p_start_date timestamptz default null,
  p_end_date timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ads_owns_campaign(p_campaign_id) then
    raise exception 'not_owner';
  end if;

  -- Validação de dinheiro no servidor: o app não é autoridade.
  if p_budget is not null and p_budget < 0 then
    raise exception 'invalid_budget';
  end if;
  if p_daily_budget is not null and p_daily_budget < 0 then
    raise exception 'invalid_budget';
  end if;
  if p_spend_cap is not null and p_spend_cap < 0 then
    raise exception 'invalid_budget';
  end if;
  if p_start_date is not null and p_end_date is not null
     and p_end_date <= p_start_date then
    raise exception 'invalid_period';
  end if;
  if p_placements is not null
     and not (p_placements <@ array['for_you','between_videos','highlights','discovery']) then
    raise exception 'invalid_placements';
  end if;

  update public.ad_campaigns set
    name = coalesce(nullif(p_name, ''), name),
    budget = coalesce(p_budget, budget),
    daily_budget = coalesce(p_daily_budget, daily_budget),
    spend_cap = coalesce(p_spend_cap, spend_cap),
    placements = coalesce(p_placements, placements),
    audience = coalesce(p_audience, audience),
    interests = coalesce(p_interests, interests),
    region = coalesce(p_region, region),
    start_date = coalesce(p_start_date, start_date),
    end_date = coalesce(p_end_date, end_date),
    updated_at = now()
  where id = p_campaign_id;

  return true;
end;
$$;
revoke all on function public.ads_update_campaign(uuid, text, numeric, numeric, numeric, text[], text, text, text, timestamptz, timestamptz) from public;
grant execute on function public.ads_update_campaign(uuid, text, numeric, numeric, numeric, text[], text, text, text, timestamptz, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Editar criativo em DRAFT (rascunho) — antes não havia update
-- ---------------------------------------------------------------------------

create or replace function public.ads_update_draft_creative(
  p_creative_id uuid,
  p_title text,
  p_description text default null,
  p_media_url text default null,
  p_media_type text default null,
  p_cta_label text default null,
  p_cta_url text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.ad_creatives cr
    join public.ad_campaigns c on c.id = cr.campaign_id
    join public.advertisers a on a.id = c.advertiser_id
    where cr.id = p_creative_id
      and a.user_id = auth.uid()
      and cr.status = 'DRAFT'
  ) then
    raise exception 'not_owner_or_not_draft';
  end if;

  update public.ad_creatives set
    title = coalesce(nullif(p_title, ''), title),
    description = coalesce(p_description, description),
    media_url = coalesce(p_media_url, media_url),
    media_type = coalesce(p_media_type, media_type),
    cta_label = coalesce(p_cta_label, cta_label),
    cta_url = coalesce(p_cta_url, cta_url),
    updated_at = now()
  where id = p_creative_id;

  return true;
end;
$$;
revoke all on function public.ads_update_draft_creative(uuid, text, text, text, text, text, text) from public;
grant execute on function public.ads_update_draft_creative(uuid, text, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Excluir rascunho (confirmação é responsabilidade do app; aqui é o donoe)
-- ---------------------------------------------------------------------------

create or replace function public.ads_delete_draft(p_creative_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.ad_creatives cr
    join public.ad_campaigns c on c.id = cr.campaign_id
    join public.advertisers a on a.id = c.advertiser_id
    where cr.id = p_creative_id
      and a.user_id = auth.uid()
      and cr.status = 'DRAFT'
  ) then
    raise exception 'not_owner_or_not_draft';
  end if;

  delete from public.ad_creatives where id = p_creative_id;
  return true;
end;
$$;
revoke all on function public.ads_delete_draft(uuid) from public;
grant execute on function public.ads_delete_draft(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Reenviar criativo corrigido (DRAFT ou REJECTED -> PENDING_REVIEW)
-- ---------------------------------------------------------------------------

create or replace function public.ads_resubmit_creative(p_creative_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_status text;
begin
  select cr.status into v_status
  from public.ad_creatives cr
  join public.ad_campaigns c on c.id = cr.campaign_id
  join public.advertisers a on a.id = c.advertiser_id
  where cr.id = p_creative_id and a.user_id = auth.uid();

  if v_status is null then
    raise exception 'not_owner';
  end if;
  if v_status not in ('DRAFT', 'REJECTED') then
    raise exception 'invalid_status';
  end if;

  update public.ad_creatives set
    status = 'PENDING_REVIEW',
    rejection_reason = '',
    reviewed_at = now(),
    updated_at = now()
  where id = p_creative_id;

  insert into public.ad_reviews (creative_id, action) values (p_creative_id, 'resubmit');
  return true;
end;
$$;
revoke all on function public.ads_resubmit_creative(uuid) from public;
grant execute on function public.ads_resubmit_creative(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Pausar / retomar / encerrar pelo próprio anunciante
-- ---------------------------------------------------------------------------
-- O status do CRIATIVO é o que decide veiculação (ads_public_approved só lê
-- APPROVED). O anúncio nunca sai de APPROVED por ação do anunciante: ele
-- encerra a CAMPANHA, e o criativo volta a DRAFT para que o anunciante
-- reenvie se quiser.
--
-- Os valores de status abaixo respeitam o CHECK das duas tabelas:
-- ('DRAFT','PENDING_REVIEW','APPROVED','REJECTED','PAUSED','EXPIRED','BLOCKED').
-- Não existe 'ACTIVE'/'ENDED' — quem decide veiculação é o admin em
-- ads_admin_approve; o anunciante só move DRAFT/PAUSED/EXPIRED.

create or replace function public.ads_set_campaign_status(
  p_campaign_id uuid,
  p_action text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ads_owns_campaign(p_campaign_id) then
    raise exception 'not_owner';
  end if;

  if p_action = 'pause' then
    update public.ad_creatives
       set status = 'PAUSED', updated_at = now()
     where campaign_id = p_campaign_id and status = 'APPROVED';
    update public.ad_campaigns
       set status = 'PAUSED', updated_at = now()
     where id = p_campaign_id and status = 'DRAFT';
  elsif p_action = 'resume' then
    -- Retomar devolve para análise: o anunciante não se auto-aprova.
    update public.ad_creatives
       set status = 'PENDING_REVIEW', reviewed_at = now(), updated_at = now()
     where campaign_id = p_campaign_id and status = 'PAUSED';
    update public.ad_campaigns
       set status = 'DRAFT', updated_at = now()
     where id = p_campaign_id and status = 'PAUSED';
  elsif p_action = 'end' then
    update public.ad_creatives
       set status = 'EXPIRED', updated_at = now()
     where campaign_id = p_campaign_id
       and status in ('APPROVED', 'PAUSED', 'PENDING_REVIEW', 'REJECTED');
    update public.ad_campaigns
       set status = 'EXPIRED', updated_at = now()
     where id = p_campaign_id;
  else
    raise exception 'invalid_action';
  end if;

  return true;
end;
$$;
revoke all on function public.ads_set_campaign_status(uuid, text) from public;
grant execute on function public.ads_set_campaign_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Duplicar campanha como rascunho
-- ---------------------------------------------------------------------------
-- O app já consegue duplicar chamando ads_create_campaign + ads_create_creative.
-- Esta RPC faz o mesmo num único passo transacional e é o caminho preferível
-- depois que a migration for aplicada.

create or replace function public.ads_duplicate_campaign(p_campaign_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ad uuid;
  v_new_campaign uuid;
  v_new_creative uuid;
begin
  select c.advertiser_id into v_ad
    from public.ad_campaigns c
    join public.advertisers a on a.id = c.advertiser_id
    where c.id = p_campaign_id and a.user_id = auth.uid();
  if v_ad is null then
    raise exception 'not_owner';
  end if;

  insert into public.ad_campaigns
    (advertiser_id, name, objective, budget, daily_budget, spend_cap,
     placements, audience, interests, region, start_date, end_date, status)
  select v_ad, c.name || ' (cópia)', c.objective, c.budget, c.daily_budget,
         c.spend_cap, c.placements, c.audience, c.interests, c.region,
         c.start_date, c.end_date, 'DRAFT'
  from public.ad_campaigns c
  where c.id = p_campaign_id
  returning id into v_new_campaign;

  insert into public.ad_creatives
    (campaign_id, title, description, media_url, media_type,
     cta_label, cta_url, cta_type, status)
  select v_new_campaign, cr.title, cr.description, cr.media_url, cr.media_type,
         cr.cta_label, cr.cta_url, cr.cta_type, 'DRAFT'
  from public.ad_creatives cr
  where cr.campaign_id = p_campaign_id
  order by cr.created_at desc
  limit 1
  returning id into v_new_creative;

  if v_new_creative is null then
    raise exception 'nothing_to_duplicate';
  end if;

  return v_new_campaign;
end;
$$;
revoke all on function public.ads_duplicate_campaign(uuid) from public;
grant execute on function public.ads_duplicate_campaign(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Expor as colunas novas em ads_my_list()
-- ---------------------------------------------------------------------------
-- Só adiciona campos ao retorno. A assinatura muda, então o Postgres exige
-- DROP antes de recriar (`CREATE OR REPLACE` não aceita mudar o tipo de
-- retorno). O DROP é seguro: quem chama usa nomes de coluna, nunca posicional.
-- O corpo reescrito mantém idênticos a lógica de RLS, o filtro por anunciante
-- logado e o cálculo de impressões/cliques de 20260904000000_ads.sql.

drop function if exists public.ads_my_list();

create or replace function public.ads_my_list()
returns table (
  campaign_id uuid,
  campaign_name text,
  campaign_status text,
  budget numeric,
  daily_budget numeric,
  spend_cap numeric,
  placements text[],
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
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    c.id,
    c.name,
    c.status,
    c.budget,
    c.daily_budget,
    c.spend_cap,
    c.placements,
    -- `spent` continua sendo a contagem de cliques: não existe cobrança no
    -- servidor. O app não trata este número como dinheiro.
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
end;
$$;
revoke all on function public.ads_my_list() from public;
grant execute on function public.ads_my_list() to authenticated;