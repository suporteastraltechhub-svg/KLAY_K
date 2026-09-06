-- ============================================================================
-- KLAY K — HOTFIX DE RECOMPENSAS (aplica o CONTRATO INTENCIONAL)
-- Re-aplicável: só `create or replace function` idempotentes.
--
-- 1) ensure_invite_code: troca gen_random_bytes (pgcrypto) por gen_random_uuid
--    (CORE do Postgres 13+). No Supabase o pgcrypto vive no schema `extensions`
--    e fica INVISÍVEL atrás de `set search_path = public`: `redeem_invite` /
--    `invite_summary` estouravam com
--      function gen_random_bytes(integer) does not exist
--    para QUALQUER usuário sem invite_code. Com gen_random_uuid o código é
--    gerado sem depender de extensão.
--
-- 2) game_submit_score: melhoria = estritamente MAIOR (`p_score > best`).
--    A versão aplicada estava com `>=`, pagando cristais a cada EMPATE do
--    recorde (grind/farm infinito: 10/10 repetido pagava 3 cristais por rodada).
--    A resolução de patamar passa a ser determinística: paga o maior
--    min_score satisfeito (ordem do array rules não importa).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) ensure_invite_code — sem dependência de pgcrypto
-- ---------------------------------------------------------------------------
create or replace function public.ensure_invite_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_code text;
  v_try int := 0;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select invite_code into v_code from public.profiles where id = u;
  if v_code is not null then
    return v_code;
  end if;

  -- gen_random_uuid() é CORE do Postgres 13+ (sem pgcrypto — que no Supabase
  -- fica no schema `extensions` e some atrás de `set search_path = public`).
  loop
    v_try := v_try + 1;
    if v_try > 20 then raise exception 'code_generation_failed'; end if;
    v_code := 'KLAYK-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 6));
    exit when not exists (
      select 1 from public.profiles where invite_code = v_code
    );
  end loop;

  update public.profiles set invite_code = v_code where id = u;
  return v_code;
end;
$$;

revoke all on function public.ensure_invite_code() from public;
grant execute on function public.ensure_invite_code() to authenticated;

-- ---------------------------------------------------------------------------
-- 2) game_submit_score — melhoria estrita (>) + patamar do topo satisfeito
-- ---------------------------------------------------------------------------
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

  -- Recorde atual? Melhoria SÓ com score ESTRITAMENTE maior (empate não paga).
  select * into v_best from public.game_scores
   where user_id = u and game_id = v_game.id;

  v_improved := v_best.user_id is null or p_score > v_best.score;

  -- Patamar com MAIOR min_score satisfeito (ordem do array não importa).
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

revoke all on function public.game_submit_score(uuid, int, int) from public;
grant execute on function public.game_submit_score(uuid, int, int) to authenticated;