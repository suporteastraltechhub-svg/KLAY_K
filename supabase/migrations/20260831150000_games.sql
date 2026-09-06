-- ============================================================================
-- KLAY K — ABA JOGOS + RECOMPENSAS PELO BACKEND
--  * games: catálogo (só backend cadastra; o app consome "active")
--  * game_sessions: sessão aberta ao iniciar partida (rate-limit por dia)
--  * game_scores: maior pontuação por jogo/usuário (ranking honesto)
--  * RPC game_submit_score (security definer): valida sessão + pontuação,
--    evita re-submissão, libera cristais por patamar definido em games.rules
--    SOMENTE ao melhorar o recorde. O cliente nunca escreve saldo.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) games (catálogo)
-- ---------------------------------------------------------------------------
create table if not exists public.games (
  id text primary key,
  name text not null,
  description text not null default '',
  emoji text not null default '🎮',
  category text not null default 'arcade',
  status text not null default 'active' check (status in ('active', 'soon')),
  rules jsonb not null default '{}'::jsonb,
  max_score int not null default 100,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists games_id_uidx on public.games (id);

alter table public.games enable row level security;
drop policy if exists "games_select_active" on public.games;
create policy "games_select_active" on public.games
  for select using (true);

-- Seeds: raciocínio (Quiz), arcade (Jogo da Velha), reflexo (Toque Rápido).
-- rules: { "rewards": [ { "min_score": 40, "crystals": 2 }, ... ] }
insert into public.games (id, name, description, emoji, category, status, rules, max_score, sort_order) values
  ('quiz',       'Quiz KLAY K',   'Teste seus conhecimentos em 6 perguntas rápidas.', '🧠', 'raciocinio', 'active', '{"rewards": [{"min_score": 6, "crystals": 3}, {"min_score": 4, "crystals": 2}]}'::jsonb, 6,  1),
  ('velha',      'Jogo da Velha', 'Vença a máquina no clássico jogo da velha (3x3).',  '⭕', 'arcade',      'active', '{"rewards": [{"min_score": 10, "crystals": 3}]}'::jsonb,              10, 2),
  ('toque',      'Toque Rápido',  'Toque o alvo o máximo de vezes em 15 segundos.',   '⚡', 'reflexo',     'active', '{"rewards": [{"min_score": 10, "crystals": 2}, {"min_score": 15, "crystals": 4}]}'::jsonb, 40, 3),
  ('memoria',    'Memória',       'Combine os pares de cartas no menor tempo.',       '🃏', 'raciocinio',  'soon',   '{}'::jsonb, 100, 4),
  ('2048',       '2048',          'Junte os blocos até chegar em 2048.',              '🔢', 'arcade',      'soon',   '{}'::jsonb, 9999, 5)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, emoji = excluded.emoji,
  category = excluded.category, status = excluded.status, rules = excluded.rules,
  max_score = excluded.max_score, sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- 2) game_sessions (uma partida = uma sessão)
-- ---------------------------------------------------------------------------
create table if not exists public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id) on delete restrict,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  score int default 0,
  duration_seconds int default 0,
  submitted boolean not null default false,
  reward_crystals bigint not null default 0
);

create index if not exists game_sessions_user_idx on public.game_sessions (user_id, started_at desc);
create index if not exists game_sessions_game_idx on public.game_sessions (game_id, started_at);

alter table public.game_sessions enable row level security;
drop policy if exists "game_sessions_owner" on public.game_sessions;
create policy "game_sessions_owner" on public.game_sessions
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) game_scores (recorde por jogo/usuário; único por sessão)
-- ---------------------------------------------------------------------------
create table if not exists public.game_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id) on delete restrict,
  score int not null default 0,
  duration_seconds int not null default 0,
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, game_id)
);

create index if not exists game_scores_leader_idx on public.game_scores (game_id, score desc, duration_seconds asc);

alter table public.game_scores enable row level security;
drop policy if exists "game_scores_select" on public.game_scores;
create policy "game_scores_select" on public.game_scores
  for select using (true);

-- ---------------------------------------------------------------------------
-- 4) RPCs
-- ---------------------------------------------------------------------------

-- Abre uma sessão. Limite diário (30) + jogo precisa estar "active".
create or replace function public.game_start_session(p_game_id text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_id uuid;
  v_today_count int;
  v_game public.games%rowtype;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select * into v_game from public.games where id = p_game_id;
  if v_game.status <> 'active' then raise exception 'game_not_active'; end if;

  select count(*) into v_today_count from public.game_sessions
    where user_id = u and started_at::date = current_date;
  if v_today_count >= 30 then raise exception 'daily_session_limit'; end if;

  insert into public.game_sessions (user_id, game_id) values (u, p_game_id)
    returning id into v_id;
  return v_id;
end;
$$;

-- Submete a pontuação da sessão: valida dono, não re-submit, patamar honesto.
-- Libera cristais APENAS se melhorou o recorde; grava game_scores (melhor)
-- e mantém a sessão com o resultado para telemetria.
create or replace function public.game_submit_score(
  p_session_id uuid,
  p_score int,
  p_duration_seconds int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_s public.game_sessions%rowtype;
  v_game public.games%rowtype;
  v_best public.game_scores%rowtype;
  v_reward bigint := 0;
  v_improved boolean := false;
  v_rec record;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select * into v_s from public.game_sessions where id = p_session_id;
  if v_s.user_id is null or v_s.user_id <> u then
    raise exception 'session_not_found';
  end if;
  if v_s.submitted then raise exception 'session_already_submitted'; end if;

  select * into v_game from public.games where id = v_s.game_id;

  -- Sanidade básica (anti-speedhack grosseiro): score limitado + duração mínima.
  if p_score < 0 or p_score > v_game.max_score then raise exception 'invalid_score'; end if;
  if p_duration_seconds is null or p_duration_seconds < 0 then
    p_duration_seconds := 0;
  end if;

  -- Recorde atual?
  select * into v_best from public.game_scores
   where user_id = u and game_id = v_game.id;

  v_improved := v_best.user_id is null or p_score > v_best.score;

  -- Regra de recompensa por patamar (backend define; nunca cliente).
  -- Paga o patamar com MAIOR min_score satisfeito (ordem do array não muda o
  -- resultado): sobe de min_score decrescente e paga o primeiro atingido.
  if v_improved then
    for v_rec in
      select (e->>'min_score')::int as min_score,
             (e->>'crystals')::bigint as crystals
        from jsonb_array_elements(coalesce(v_game.rules->'rewards', '[]'::jsonb)) e
       order by (e->>'min_score')::int desc
    loop
      if p_score >= v_rec.min_score then
        v_reward := v_rec.crystals;
        exit;
      end if;
    end loop;
  end if;

  -- Grava recorde (upsert) SÓ quando melhora; senão mantém o melhor atual
  -- (a tabela game_scores guarda o RECORDE — um score pior nunca o apaga).
  if v_improved then
    insert into public.game_scores (user_id, game_id, score, duration_seconds, session_id)
    values (u, v_game.id, p_score, p_duration_seconds, v_s.id)
    on conflict (user_id, game_id) do update
      set score = excluded.score,
          duration_seconds = excluded.duration_seconds,
          session_id = excluded.session_id,
          created_at = now()
    returning * into v_best;
  else
    select * into v_best from public.game_scores
     where user_id = u and game_id = v_game.id;
  end if;

  -- Sessão finalizada.
  update public.game_sessions
     set submitted = true, ended_at = now(),
         score = p_score, duration_seconds = p_duration_seconds,
         reward_crystals = v_reward
   where id = v_s.id;

  -- Credita cristais apenas se melhorou (mesmo critério da recompensa).
  if v_improved and v_reward > 0 then
    perform public.economy_adjust(
      u, 'crystals', v_reward, 'reward', 'game:' || v_game.id,
      p_session_id::text, 'Recompensa de ' || v_game.name, null);
  end if;

  return jsonb_build_object(
    'score', p_score,
    'reward', v_reward,
    'improved', v_improved,
    'best_score', v_best.score
  );
end;
$$;

-- Ranking por jogo (top 20, retorna tb nome/avatar do perfil).
create or replace function public.game_leaderboard(p_game_id text)
returns table (
  rank int,
  user_id uuid,
  display_name text,
  username text,
  avatar_url text,
  best_score int,
  duration_seconds int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select row_number() over (order by gs.score desc, gs.duration_seconds asc)::int as rank,
           gs.user_id,
           coalesce(p.display_name, 'Participante') as display_name,
           coalesce(p.username, '') as username,
           p.avatar_url,
           gs.score::int,
           gs.duration_seconds::int
      from public.game_scores gs
      join public.profiles p on p.id = gs.user_id
     where gs.game_id = p_game_id
     order by gs.score desc, gs.duration_seconds asc
     limit 20;
end;
$$;

-- Meus recordes em todos os jogos (para o catálogo: selo "recordista").
create or replace function public.my_game_records()
returns table (
  game_id text,
  best_score int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select gs.game_id, gs.score::int
      from public.game_scores gs
     where gs.user_id = auth.uid();
end;
$$;

revoke all on function public.game_start_session(text) from public;
grant execute on function public.game_start_session(text) to authenticated;
revoke all on function public.game_submit_score(uuid, int, int) from public;
grant execute on function public.game_submit_score(uuid, int, int) to authenticated;
revoke all on function public.game_leaderboard(text) from public;
grant execute on function public.game_leaderboard(text) to authenticated;
revoke all on function public.my_game_records() from public;
grant execute on function public.my_game_records() to authenticated;

-- Realtime do ranking novo (opcional, sem expor saldos).
alter publication supabase_realtime add table public.game_sessions;
alter publication supabase_realtime add table public.game_scores;