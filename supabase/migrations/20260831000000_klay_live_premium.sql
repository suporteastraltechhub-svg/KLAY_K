-- ============================================================================
-- KLAY K — LIVE PREMIUM
-- 1) Chat ao vivo com anti-flood + anti-spam validados NO BACKEND
--    (o cliente NÃO insere live_chat diretamente; passa por live_send_chat).
-- 2) Reações rápidas (emoji) em mensagens do chat (tabela + toggle RPC).
-- 3) Ranking por moeda REAL: top apoiadores da live (moedas) e top carteira
--    por moeda (diamantes/cristais/rubis/esmeraldas/cristal raro) — nunca
--    pontuação inventada.
-- 4) Idempotência do envio de presentes (gift_requests + request_id) para
--    impedir débito duplo em retry/double-tap.
-- 5) Preferências da bolinha flutuante premium da live + bot de voz honesto
--    (flags em user_settings; provedor só é ativado quando configurado).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4) Idempotência de presentes
-- ---------------------------------------------------------------------------
create table if not exists public.gift_requests (
  request_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.gift_requests enable row level security;
drop policy if exists "gift_requests_none" on public.gift_requests;
-- Ninguém lê/escreve diretamente: somente a Edge Function (service role).
create policy "gift_requests_none" on public.gift_requests for select using (false);

alter table public.gift_transactions
  add column if not exists request_id text;

create unique index if not exists gift_tx_request_uidx
  on public.gift_transactions (request_id) where request_id is not null;

-- Claim atômico de request_id (edge functions / service role). Retorna true
-- quando este chamador ganhou o request_id; false quando já existe (duplicado).
-- O cliente NUNCA chama: revogado para anon/authenticated.
create or replace function public.claim_gift_request(
  p_request_id text,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.gift_requests (request_id, user_id)
  values (p_request_id, p_user_id)
  on conflict (request_id) do nothing;
  return found;
end;
$$;

revoke all on function public.claim_gift_request(text, uuid) from public, anon, authenticated;
grant execute on function public.claim_gift_request(text, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 1) Chat ao vivo: anti-flood/anti-spam no backend.
-- ---------------------------------------------------------------------------
revoke insert on table public.live_chat from anon, authenticated, public;

create index if not exists live_chat_user_time_idx
  on public.live_chat (user_id, created_at desc);

-- Envia/valida uma mensagem de chat da live. Retorna {ok, id, created_at,
-- flagged}. Regras ENFORÇADAS aqui (não no cliente):
--   * autenticado, live ativa
--   * não banido, não silenciado (janela)
--   * mensagem 1..240 caracteres
--   * anti-flood: máx. 20 mensagens/10s por usuário nesta live
--   * anti-spam: regras ativas scope 'chat'/'all' — 'block' rejeita;
--     'flag'/'warn' permite e marca `flagged`.
create or replace function public.live_send_chat(
  p_live_id uuid,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_msg text := trim(coalesce(p_message, ''));
  v_flagged boolean := false;
  v_row public.live_chat%rowtype;
  v_recent int;
  r record;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_msg = '' then raise exception 'empty_message'; end if;
  if length(v_msg) > 240 then raise exception 'message_too_long'; end if;

  -- Live ativa?
  if not exists (select 1 from public.lives where id = p_live_id and status = 'live') then
    raise exception 'live_not_active';
  end if;

  -- Não banido na live.
  if exists (select 1 from public.live_bans where live_id = p_live_id and user_id = v_uid) then
    raise exception 'banned_from_live';
  end if;

  -- Não silenciado (sem expiração ou ainda dentro da janela).
  if exists (
    select 1 from public.live_mutes
    where live_id = p_live_id and user_id = v_uid
      and (until is null or until > now())
  ) then
    raise exception 'muted_in_live';
  end if;

  -- Anti-flood: máx. 20 mensagens nos últimos 10 segundos nesta live.
  select count(*) into v_recent
    from public.live_chat
    where live_id = p_live_id and user_id = v_uid
      and created_at > now() - interval '10 seconds';
  if v_recent >= 20 then raise exception 'rate_limited'; end if;

  -- Anti-spam (regras ativas; scope 'chat' ou 'all').
  for r in
    select pattern, rule_type from public.anti_spam_rules
    where active and scope in ('chat', 'all')
  loop
    if v_msg ilike '%' || r.pattern || '%' then
      if r.rule_type = 'block' then
        raise exception 'blocked_spam';
      else
        v_flagged := true;
      end if;
    end if;
  end loop;

  insert into public.live_chat (live_id, user_id, message)
  values (p_live_id, v_uid, left(v_msg, 240))
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'created_at', to_char(v_row.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'flagged', v_flagged
  );
end;
$$;

revoke all on function public.live_send_chat(uuid, text) from public, anon;
grant execute on function public.live_send_chat(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Reações rápidas (emoji) em mensagens do chat.
-- ---------------------------------------------------------------------------
create table if not exists public.live_message_reactions (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.lives(id) on delete cascade,
  message_id uuid not null references public.live_chat(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('❤️','🔥','😂','👍','🎉','💎')),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create index if not exists live_reactions_live_idx
  on public.live_message_reactions (live_id, message_id);

alter table public.live_message_reactions enable row level security;
drop policy if exists "live_reactions_select_all" on public.live_message_reactions;
create policy "live_reactions_select_all" on public.live_message_reactions
  for select using (true);
-- Escrita através do RPC (security definer); o cliente não escreve a tabela.
revoke insert, update, delete on table public.live_message_reactions from anon, authenticated, public;

-- Alterna reação do usuário numa mensagem: insere se não existe, remove se
-- existe. Retorna active/removed + o total daquela reação na mensagem.
create or replace function public.live_toggle_reaction(
  p_message_id uuid,
  p_emoji text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_live_id uuid;
  v_total int;
  v_removed boolean := false;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_emoji not in ('❤️','🔥','😂','👍','🎉','💎') then raise exception 'bad_emoji'; end if;

  select live_id into v_live_id from public.live_chat where id = p_message_id;
  if v_live_id is null then raise exception 'message_not_found'; end if;

  if exists (
    select 1 from public.live_message_reactions
    where message_id = p_message_id and user_id = v_uid and emoji = p_emoji
  ) then
    delete from public.live_message_reactions
    where message_id = p_message_id and user_id = v_uid and emoji = p_emoji;
    v_removed := true;
  else
    insert into public.live_message_reactions (live_id, message_id, user_id, emoji)
    values (v_live_id, p_message_id, v_uid, p_emoji);
  end if;

  select count(*) into v_total
    from public.live_message_reactions
    where message_id = p_message_id and emoji = p_emoji;

  return jsonb_build_object('ok', true, 'removed', v_removed, 'total', v_total);
end;
$$;

revoke all on function public.live_toggle_reaction(uuid, text) from public, anon;
grant execute on function public.live_toggle_reaction(uuid, text) to authenticated;

-- Agregado inicial de reações da sala (o cliente complementa com realtime).
create or replace function public.live_chat_reactions(p_live_id uuid)
returns table (
  message_id uuid,
  emoji text,
  total bigint
)
language plpgsql
security definer
set search_path = public
volatile
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  return query
    select r.message_id, r.emoji, count(*)::bigint as total
    from public.live_message_reactions r
    where r.live_id = p_live_id
    group by r.message_id, r.emoji;
end;
$$;

revoke all on function public.live_chat_reactions(uuid) from public, anon;
grant execute on function public.live_chat_reactions(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Ranking por moeda real.
-- ---------------------------------------------------------------------------
create or replace function public.currency_ranking(
  p_currency text,
  p_limit int default 20
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  value numeric,
  scope text
)
language plpgsql
security definer
set search_path = public
volatile
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_col text;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  case p_currency
    when 'credits' then v_col := 'credits';
    when 'diamonds' then v_col := 'diamonds';
    when 'crystals' then v_col := 'crystals';
    when 'rubies' then v_col := 'rubies';
    when 'emeralds' then v_col := 'emeralds';
    when 'crystal_rare' then v_col := 'crystal_rare';
    else raise exception 'bad_currency';
  end case;

  return query execute format(
    'select row_number() over (order by w.%I desc, p.created_at asc)::bigint as rank,
            w.user_id::uuid,
            p.username::text,
            p.display_name::text,
            p.avatar_url::text,
            w.%I::numeric as value,
            %L::text as scope
     from public.user_wallets w
     join public.profiles p on p.id = w.user_id
     where w.%I > 0
     order by w.%I desc, p.created_at asc
     limit $1',
    v_col, v_col, 'global', v_col, v_col
  ) using v_limit;
end;
$$;

revoke all on function public.currency_ranking(text, int) from public, anon;
grant execute on function public.currency_ranking(text, int) to authenticated;

-- Top apoiadores da live: quem mais enviou presentes (em moedas) nesta live.
create or replace function public.live_top_supporters(
  p_live_id uuid,
  p_limit int default 20
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  value numeric,
  scope text
)
language plpgsql
security definer
set search_path = public
volatile
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select row_number() over (
             order by sum(gt.credits_total) desc, min(gt.created_at) asc
           )::bigint as rank,
           gt.user_id,
           p.username,
           p.display_name,
           p.avatar_url,
           sum(gt.credits_total)::numeric as value,
           'live'::text as scope
    from public.gift_transactions gt
    join public.profiles p on p.id = gt.user_id
    where gt.live_id = p_live_id
    group by gt.user_id, p.username, p.display_name, p.avatar_url
    order by value desc, min(gt.created_at) asc
    limit v_limit;
end;
$$;

revoke all on function public.live_top_supporters(uuid, int) from public, anon;
grant execute on function public.live_top_supporters(uuid, int) to authenticated;

-- Dispatch por moeda: 'credits' → top apoiadores DESTA live; demais moedas →
-- ranking global de carteira daquela moeda. Abas separadas por moeda.
create or replace function public.live_ranking(
  p_live_id uuid,
  p_currency text,
  p_limit int default 20
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  value numeric,
  scope text
)
language plpgsql
security definer
set search_path = public
volatile
as $$
begin
  if p_currency = 'credits' then
    return query select * from public.live_top_supporters(p_live_id, p_limit);
  else
    return query select * from public.currency_ranking(p_currency, p_limit);
  end if;
end;
$$;

revoke all on function public.live_ranking(uuid, text, int) from public, anon;
grant execute on function public.live_ranking(uuid, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Preferências da bolinha premium da live + bot de voz (config honesta).
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column if not exists live_bubble_enabled boolean not null default true;
alter table public.user_settings
  add column if not exists live_bubble_x double precision not null default 0.16;
alter table public.user_settings
  add column if not exists live_bubble_y double precision not null default 0.32;
alter table public.user_settings
  add column if not exists live_bubble_minimized boolean not null default false;
alter table public.user_settings
  add column if not exists voice_bot_enabled boolean not null default false;
alter table public.user_settings
  add column if not exists voice_bot_provider text default '';
alter table public.user_settings
  add column if not exists voice_bot_voice text default '';

-- ---------------------------------------------------------------------------
-- Realtime: reações do chat (INSERT + DELETE p/ atualização ao vivo).
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.live_message_reactions;
exception when duplicate_object then null;
end $$;

-- Recarregar schema no PostgREST (Management API exige NOTIFY após DDL).
notify pgrst, 'reload schema';