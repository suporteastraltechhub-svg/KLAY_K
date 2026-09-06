-- ============================================================================
-- KLAY K — BAÚS (CHESTS)
-- Baús configuráveis com recompensas ponderadas por raridade. Obtenção:
-- gratuito/diário/missão/evento (+ admin manual). Abertura SEMPRE validada
-- no backend (RPC security definer) com anti-fraude (rate limit, um baú
-- diário por dia, sem repetição indevida). Nenhuma abertura vem do cliente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- chests: catálogo dos baús (configurável pelo painel).
--   type: free | daily | mission | event | admin
--   drops_per_open: 1..12 rolagens ponderadas por rolagem.
-- ---------------------------------------------------------------------------
create table if not exists public.chests (
  id text primary key,
  name text not null,
  description text default '',
  icon text default '🎁',
  type text not null default 'daily'
    check (type in ('free','daily','mission','event','admin')),
  drops_per_open int not null default 1 check (drops_per_open between 1 and 12),
  level_required int not null default 1,
  status text not null default 'active' check (status in ('active','inactive')),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.chests (id, name, description, icon, type, drops_per_open, sort_order) values
  ('diario',   'Baú Diário',      'Abra uma vez por dia e ganhe recompensas.',        '🎁', 'daily',  1, 1),
  ('bonus',    'Baú de Boas-vindas', 'Recompensa de boas-vindas ao KLAY K.',         '🎉', 'free',   2, 2),
  ('evento',   'Baú de Evento A.R.H', 'Bônus de eventos sazonais A.R.H TECH.',       '🌌', 'event',  3, 3),
  ('missao',   'Baú de Missão',   'Recompensa ao completar missões semanais.',       '🎖️', 'mission', 2, 4)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, icon = excluded.icon;

alter table public.chests enable row level security;
drop policy if exists "chests_select" on public.chests;
create policy "chests_select" on public.chests for select using (true);

-- ---------------------------------------------------------------------------
-- chest_drops: rolagens possíveis por baú (ponderação = weight).
-- item_type: moeda (credits/diamonds/crystals/rubies/emeralds/crystal_rare)
--            ou presente (gift + gift_id) / raridade (rarity + gift via gift).
-- Para moedas: amount_min/amount_max. Para presentes: gift_id obrigatório.
-- NINGUÉM lê a tabela de drops no cliente: a rolagem é 100% no servidor.
-- ---------------------------------------------------------------------------
create table if not exists public.chest_drops (
  id uuid primary key default gen_random_uuid(),
  chest_id text not null references public.chests(id) on delete cascade,
  item_type text not null
    check (item_type in ('credits','diamonds','crystals','rubies','emeralds','crystal_rare','gift')),
  gift_id text references public.gifts(id) on delete set null,
  amount_min bigint not null default 1,
  amount_max bigint not null default 1,
  weight int not null default 10 check (weight > 0),
  created_at timestamptz not null default now()
);

create index if not exists chest_drops_chest_idx on public.chest_drops (chest_id);

alter table public.chest_drops enable row level security;
-- Sem política de leitura pública: drops são segredo do servidor.

-- Drops do baú diário (moeda-base + chance de premium + presente de entrada).
-- Limpa e re-seeda (idempotente: chest_drops não tem unique natural). Inclui
-- 'missao' para permitir re-execução segura.
delete from public.chest_drops where chest_id in ('diario','bonus','evento','missao');

insert into public.chest_drops (chest_id, item_type, amount_min, amount_max, weight) values
  ('diario', 'credits', 50, 150, 60),
  ('diario', 'diamonds', 1, 5, 25),
  ('diario', 'crystals', 1, 3, 20),
  ('diario', 'rubies', 1, 2, 6),
  ('diario', 'crystal_rare', 1, 1, 2);

insert into public.chest_drops (chest_id, item_type, amount_min, amount_max, weight) values
  ('bonus', 'credits', 200, 400, 70),
  ('bonus', 'diamonds', 5, 15, 25),
  ('bonus', 'crystals', 3, 8, 15);

insert into public.chest_drops (chest_id, item_type, amount_min, amount_max, weight) values
  ('evento', 'credits', 150, 500, 50),
  ('evento', 'diamonds', 5, 20, 30),
  ('evento', 'crystals', 5, 15, 22),
  ('evento', 'rubies', 2, 5, 12),
  ('evento', 'crystal_rare', 1, 2, 4);

insert into public.chest_drops (chest_id, item_type, amount_min, amount_max, weight) values
  ('missao', 'credits', 100, 300, 55),
  ('missao', 'diamonds', 3, 10, 25),
  ('missao', 'crystals', 2, 6, 18),
  ('missao', 'emeralds', 1, 3, 10);

-- ---------------------------------------------------------------------------
-- user_chests: baús possuídos pelo usuário (fonte de obtenção + estado).
-- status: unlocked (pronto p/ abrir) | opened.
-- ---------------------------------------------------------------------------
create table if not exists public.user_chests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  chest_id text not null references public.chests(id) on delete cascade,
  source text not null default 'daily'
    check (source in ('daily','free','mission','event','admin')),
  status text not null default 'unlocked' check (status in ('unlocked','opened')),
  obtained_at timestamptz not null default now(),
  opened_at timestamptz,
  unique (id)
);

create index if not exists user_chests_user_idx on public.user_chests (user_id, obtained_at desc);
create index if not exists user_chests_open_idx on public.user_chests (user_id, status);
create unique index if not exists user_chests_src_unique on public.user_chests (user_id, chest_id, source);

alter table public.user_chests enable row level security;
drop policy if exists "uchest_select_owner" on public.user_chests;
create policy "uchest_select_owner" on public.user_chests for select using (user_id = auth.uid());
-- (criação/abertura acontecem via RPC security definer — nenhum insert/update
--  cliente; evita que o usuário forje baús abertos)

-- ---------------------------------------------------------------------------
-- chest_opens: registro imutável de cada abertura (anti-fraude + auditoria).
-- Retorna drops recebidos. Ninguém apaga/conserta do cliente via RLS.
-- ---------------------------------------------------------------------------
create table if not exists public.chest_opens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  chest_id text not null,
  user_chest_id uuid not null references public.user_chests(id) on delete cascade,
  drops jsonb not null default '[]',
  opened_at timestamptz not null default now()
);

create index if not exists chest_opens_user_idx on public.chest_opens (user_id, opened_at desc);

alter table public.chest_opens enable row level security;
drop policy if exists "chest_opens_select_owner" on public.chest_opens;
create policy "chest_opens_select_owner" on public.chest_opens for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- pick_chest_drop: uma rolagem ponderada para um baú (dados reais do banco).
-- ---------------------------------------------------------------------------
create or replace function public.pick_chest_drop(p_chest_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total int;
  v_roll int;
  v_acc int := 0;
  v_d record;
begin
  select coalesce(sum(weight), 0) into v_total
  from public.chest_drops where chest_id = p_chest_id;
  if v_total is null or v_total <= 0 then
    raise exception 'no_drops_configured';
  end if;
  v_roll := floor(random() * v_total) + 1;
  for v_d in
    select * from public.chest_drops
    where chest_id = p_chest_id
    order by weight desc
  loop
    v_acc := v_acc + v_d.weight;
    if v_roll <= v_acc then
      if v_d.item_type = 'gift' then
        return jsonb_build_object(
          'item_type', 'gift',
          'gift_id', v_d.gift_id,
          'amount', 1
        );
      else
        return jsonb_build_object(
          'item_type', v_d.item_type,
          'amount', floor(random() * (v_d.amount_max - v_d.amount_min + 1)) + v_d.amount_min
        );
      end if;
    end if;
  end loop;
  raise exception 'drop_miss';
end;
$$;

revoke all on function public.pick_chest_drop(text) from public, anon, authenticated;
grant execute on function public.pick_chest_drop(text) to service_role;

-- ---------------------------------------------------------------------------
-- claim_daily_chest: entrega o baú diário (1x/dia) + baú free/boas-vindas
-- (1x total). Usa UMA linha única por usuário (unique user_id,chest_id,source)
-- reutilizada a cada dia: ao virar o dia, o baú volta para 'unlocked'. Isso
-- impede re-clamar 2x no mesmo dia E evita colião com a unique index.
-- Anti-fraude: já aberto hoje → retorna estado honesto (sem novo baú).
-- ---------------------------------------------------------------------------
create or replace function public.claim_daily_chest()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_uc public.user_chests;
  v_free public.user_chests;
  v_today date := current_date;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  -- Baú diário (garante a linha; no-op se já existir).
  insert into public.user_chests (user_id, chest_id, source)
  values (u, 'diario', 'daily')
  on conflict (user_id, chest_id, source) do nothing;

  select * into v_uc from public.user_chests
  where user_id = u and chest_id = 'diario' and source = 'daily';

  -- Novo dia com baú já aberto → reabre para hoje (reset honesto).
  if v_uc.status = 'opened' and v_uc.obtained_at::date < v_today then
    update public.user_chests
       set status = 'unlocked', opened_at = null, obtained_at = now()
     where id = v_uc.id
     returning * into v_uc;
    perform public.write_audit('chest.claimed', 'chest', 'diario',
      jsonb_build_object('source', 'daily'));
  elsif v_uc.status = 'unlocked' and v_uc.obtained_at::date = v_today then
    perform public.write_audit('chest.claimed', 'chest', 'diario',
      jsonb_build_object('source', 'daily'));
  end if;

  -- Baú de boas-vindas: 1x total.
  insert into public.user_chests (user_id, chest_id, source)
  values (u, 'bonus', 'free')
  on conflict (user_id, chest_id, source) do nothing;

  select * into v_free from public.user_chests
  where user_id = u and chest_id = 'bonus' and source = 'free';

  return jsonb_build_object(
    'daily', jsonb_build_object('id', v_uc.id, 'chest_id', v_uc.chest_id, 'status', v_uc.status, 'obtained_at', v_uc.obtained_at),
    'free', jsonb_build_object('id', v_free.id, 'chest_id', v_free.chest_id, 'status', v_free.status, 'obtained_at', v_free.obtained_at)
  );
end;
$$;

revoke all on function public.claim_daily_chest() from public;
grant execute on function public.claim_daily_chest() to authenticated;

-- ---------------------------------------------------------------------------
-- open_chest: valida posse, abre, rola drops, credita e registra tudo.
-- Anti-fraude:
--   * dono do baú, status unlocked (nunca reaberto);
--   * rate limit: máx. 25 aberturas/hora e 60/dia (configurável via consts);
--   * gifts: apenas presentes ativos do catálogo (gift_id válido);
--   * credita via economy_adjust (service-role) — jamestouch o cliente.
-- ---------------------------------------------------------------------------
create or replace function public.open_chest(p_user_chest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_uc public.user_chests;
  v_chests public.chests;
  v_drops jsonb := '[]'::jsonb;
  v_roll jsonb;
  v_i int;
  v_hourly int;
  v_daily int;
  v_gift record;
  v_balance jsonb;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  if p_user_chest_id is null then raise exception 'bad_chest'; end if;

  select * into v_uc from public.user_chests
  where id = p_user_chest_id for update;
  if v_uc is null or v_uc.user_id <> u then raise exception 'not_your_chest'; end if;
  if v_uc.status <> 'unlocked' then raise exception 'already_opened'; end if;

  select * into v_chests from public.chests where id = v_uc.chest_id;
  if v_chests is null or v_chests.status <> 'active' then raise exception 'chest_unavailable'; end if;

  -- Rate limit anti-fraude.
  select count(*) into v_hourly from public.chest_opens
  where user_id = u and opened_at > now() - interval '1 hour';
  select count(*) into v_daily from public.chest_opens
  where user_id = u and opened_at > current_date;
  if v_hourly >= 25 then raise exception 'rate_limited'; end if;
  if v_daily >= 60 then raise exception 'rate_limited'; end if;

  -- Rolações ponderadas.
  for v_i in 1..v_chests.drops_per_open loop
    v_roll := public.pick_chest_drop(v_uc.chest_id);
    v_drops := v_drops || jsonb_build_array(v_roll);
  end loop;

  -- Aplica os drops (moedas e presentes do catálogo ativo).
  for v_roll in select * from jsonb_array_elements(v_drops) loop
    if (v_roll->>'item_type') = 'gift' then
      if (v_roll->>'gift_id') is not null then
        select * into v_gift from public.gifts where id = (v_roll->>'gift_id') and status = 'active';
        if v_gift is not null then
          insert into public.gift_inventory (user_id, gift_id, quantity, source)
          values (u, v_gift.id, 1, 'chest')
          on conflict (user_id, gift_id) do update set quantity = public.gift_inventory.quantity + 1;
        end if;
      end if;
    else
      v_balance := public.economy_adjust(
        u, (v_roll->>'item_type'), ((v_roll->>'amount')::bigint),
        'chest', 'chest_open', v_uc.id::text,
        'Recompensa de ' || v_chests.name || ' (baú)',
        null);
    end if;
  end loop;

  update public.user_chests
     set status = 'opened', opened_at = now()
   where id = v_uc.id;

  insert into public.chest_opens (user_id, chest_id, user_chest_id, drops)
  values (u, v_uc.chest_id, v_uc.id, v_drops);

  perform public.write_audit('chest.opened', 'chest', v_uc.chest_id,
    jsonb_build_object('user_chest_id', v_uc.id::text, 'drops', v_drops));

  -- Missão de baú (evento real) — andamento via trigger.
  return jsonb_build_object(
    'ok', true,
    'chest_id', v_uc.chest_id,
    'chest_name', v_chests.name,
    'icon', v_chests.icon,
    'drops', v_drops
  );
end;
$$;

revoke all on function public.open_chest(uuid) from public;
grant execute on function public.open_chest(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RPCs admin (cap 'chests'): visão + entrega manual (evento/suporte).
-- ---------------------------------------------------------------------------
create or replace function public.admin_chest_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('chests') then raise exception 'not_admin'; end if;
  return jsonb_build_object(
    'chests', (select count(*) from public.chests where status = 'active'),
    'opens_total', (select count(*) from public.chest_opens),
    'opens_7d', (select count(*) from public.chest_opens where opened_at > now() - interval '7 days'),
    'users_with_chests', (select count(distinct user_id) from public.user_chests)
  );
end;
$$;

revoke all on function public.admin_chest_stats() from public;
grant execute on function public.admin_chest_stats() to authenticated;

create or replace function public.admin_grant_chest(
  p_user_id uuid,
  p_chest_id text,
  p_source text default 'admin'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v user_chests;
begin
  if not public.has_perm('chests') then raise exception 'not_admin'; end if;
  if not exists (select 1 from public.chests where id = p_chest_id and status = 'active') then
    raise exception 'chest_unavailable';
  end if;
  if p_source not in ('daily','free','mission','event','admin') then raise exception 'bad_source'; end if;
  insert into public.user_chests (user_id, chest_id, source)
  values (p_user_id, p_chest_id, p_source)
  returning * into v;
  perform public.write_audit('chest.granted', 'chest', p_chest_id,
    jsonb_build_object('to_user', p_user_id::text, 'user_chest_id', v.id::text));
  return jsonb_build_object('ok', true, 'user_chest_id', v.id);
end;
$$;

revoke all on function public.admin_grant_chest(uuid, text, text) from public;
grant execute on function public.admin_grant_chest(uuid, text, text) to authenticated;

create or replace function public.admin_list_chests()
returns table (id text, name text, type text, drops_per_open int, status text, opens bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('chests') then raise exception 'not_admin'; end if;
  return query
    select c.id, c.name, c.type, c.drops_per_open, c.status,
           (select count(*) from public.chest_opens o where o.chest_id = c.id) as opens
    from public.chests c order by c.sort_order, c.id;
end;
$$;

revoke all on function public.admin_list_chests() from public;
grant execute on function public.admin_list_chests() to authenticated;