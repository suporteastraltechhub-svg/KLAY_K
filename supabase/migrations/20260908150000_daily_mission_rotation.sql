-- ============================================================================
-- KLAY K — MISSÕES DIÁRIAS ROTATIVAS
-- ----------------------------------------------------------------------------
-- As missões diárias passam a ROTAR por dia da semana: a cada dia o feed de
-- missões traz um conjunto diferente (nunca todos ao mesmo tempo). A rotação é
-- decidida SOMENTE no servidor (tabela + RPCs security definer), nunca no
-- cliente — sem contadores fake e sem duplicação de recompensas.
--
-- Como funciona:
--   * `missions.weekday` (0=Domingo .. 6=Sábado) define em qual dia a missão
--     diária aparece. `NULL` = aparece todos os dias (semanais ignoram).
--   * `grant_mission_progress` premia apenas as missões diárias do dia atual
--     (e todas as semanais), então UM evento nunca premia duas missões
--     diárias do mesmo tipo no mesmo dia.
--   * `my_progress` só devolve as missões diárias agendadas para hoje — a
--     "rotação diária detectando novo dia" é automática (current_date).
--
-- Cada dia tem 3 missões de tipos diferentes (curtir, seguir, publicar,
-- comentar, live, presente, baú). A conclusão continua sendo validada no
-- banco (período daily/weekly + completed_at), com histórico em
-- `user_mission_progress` e recompensas pagas 1x.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- missions: coluna weekday (0=Domingo .. 6=Sábado); NULL = todos os dias.
-- ---------------------------------------------------------------------------
alter table public.missions
  add column if not exists weekday int
  check (weekday is null or weekday between 0 and 6);

-- Reagenda as missões diárias existentes para o calendário rotativo.
update public.missions m
set weekday = s.w
from (values
  ('post_daily',    0),  -- Dom
  ('follow_daily',  0),  -- Dom
  ('chest_daily',   0),  -- Dom
  ('like_daily',    1),  -- Seg
  ('live_daily',    1),  -- Seg
  ('gift_daily',    1),  -- Seg
  ('comment_daily', 2)   -- Ter
) as s(id, w)
where m.id = s.id;

-- Novas missões diárias que completam o calendário (uma por tipo por dia —
-- nunca duas do mesmo tipo no mesmo dia, evitando recompensa dupla).
insert into public.missions
  (id, title, description, icon, mission_type, frequency, target, xp_reward, rewards, weekday) values
  ('post_daily2',    'Grave um vídeo',              'Publique 1 vídeo hoje',        '📹', 'post',       'daily', 1, 6,  '{"credits": 30}'::jsonb, 2),
  ('post_daily3',    'Compartilhe sua criatividade','Publique 1 vídeo hoje',        '🎬', 'post',       'daily', 1, 6,  '{"credits": 30}'::jsonb, 5),
  ('follow_daily2',  'Conquiste um seguidor novo',  'Receba 1 novo seguidor hoje',  '➕', 'follow',     'daily', 1, 4,  '{"credits": 15}'::jsonb, 2),
  ('follow_daily3',  'Aumente sua comunidade',      'Receba 2 novos seguidores hoje','👥','follow',     'daily', 2, 6,  '{"credits": 20}'::jsonb, 5),
  ('like_daily2',    'Colete curtidas',             'Receba 5 curtidas hoje',        '❤️', 'like',       'daily', 5, 5,  '{"credits": 15}'::jsonb, 4),
  ('like_daily3',    'Vídeo curtido',               'Receba 5 curtidas hoje',        '💥', 'like',       'daily', 5, 5,  '{"credits": 15}'::jsonb, 6),
  ('comment_daily2', 'Renda papo no seu vídeo',     'Receba 3 comentários hoje',     '💬', 'comment',    'daily', 3, 6,  '{"credits": 25}'::jsonb, 3),
  ('comment_daily3', 'Interaja com quem comenta',   'Receba 2 comentários hoje',     '🗨️', 'comment',    'daily', 2, 5,  '{"credits": 20}'::jsonb, 6),
  ('live_daily2',    'Faça uma live rápida',        'Transmita 1 vez hoje',          '🔴', 'live',       'daily', 1, 9,  '{"credits": 40}'::jsonb, 3),
  ('live_daily3',    'Encontros ao vivo',           'Transmita 1 vez hoje',          '📡', 'live',       'daily', 1, 9,  '{"credits": 40}'::jsonb, 5),
  ('gift_daily2',    'Surpreenda com um presente',  'Envie 1 presente hoje',         '🎁', 'gift_sent',  'daily', 1, 11, '{"credits": 50, "diamonds": 1}'::jsonb, 4),
  ('gift_daily3',    'Corrente de presentes',       'Envie 1 presente hoje',         '🎁', 'gift_sent',  'daily', 1, 11, '{"credits": 50, "diamonds": 1}'::jsonb, 6),
  ('chest_daily2',   'Abra o baú mistério',         'Abra 1 baú hoje',               '📦', 'chest_open', 'daily', 1, 6,  '{"credits": 25}'::jsonb, 3),
  ('chest_daily3',   'Colecione baús',              'Abra 1 baú hoje',               '🎁', 'chest_open', 'daily', 1, 6,  '{"credits": 25}'::jsonb, 4)
on conflict (id) do update set
  weekday = excluded.weekday,
  title = excluded.title,
  description = excluded.description,
  target = excluded.target,
  xp_reward = excluded.xp_reward,
  rewards = excluded.rewards;

-- ---------------------------------------------------------------------------
-- grant_mission_progress (RECRIADA): agora premia somente as missões diárias
-- agendadas para o dia atual (e todas as semanais). UM evento de um tipo NUNCA
-- premia duas missões diárias no mesmo dia → sem duplicação de recompensas.
-- ---------------------------------------------------------------------------
create or replace function public.grant_mission_progress(
  p_user_id uuid,
  p_mission_type text,
  p_delta int default 1
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  m public.missions%rowtype;
  rec record;
  period_s date;
  period_e date;
  xp_gain int := 0;
  rew jsonb;
  rew_item record;
  today int := extract(dow from current_date)::int;
begin
  if p_user_id is null then return; end if;
  period_s := current_date;
  period_e := current_date;
  for m in
    select * from public.missions
    where mission_type = p_mission_type and active
      and (frequency = 'weekly'
           or weekday is null
           or weekday = today)
    order by frequency
  loop
    if m.frequency = 'daily' then
      period_s := current_date;
      period_e := current_date;
    else
      period_s := date_trunc('week', current_date)::date;
      period_e := period_s + 6;
    end if;

    insert into public.user_mission_progress
      (user_id, mission_id, progress, period_start, period_end)
    values (p_user_id, m.id, 0, period_s, period_e)
    on conflict (user_id, mission_id, period_start) do nothing;

    update public.user_mission_progress
    set progress = progress + p_delta
    where user_id = p_user_id and mission_id = m.id and period_start = period_s;

    select * into rec from public.user_mission_progress
    where user_id = p_user_id and mission_id = m.id and period_start = period_s;

    if rec.progress >= m.target and not coalesce(rec.completed, false) then
      update public.user_mission_progress
      set completed = true, completed_at = now()
      where id = rec.id;
      xp_gain := xp_gain + m.xp_reward;

      -- Recompensas multi-moeda (cashout 1x, na transição para completed).
      if m.rewards is not null and m.rewards <> '{}'::jsonb then
        for rew_item in select * from jsonb_each_text(m.rewards) loop
          perform public.economy_adjust(
            p_user_id,
            rew_item.key,
            (rew_item.value)::bigint,
            'mission',
            'mission:' || m.id,
            rec.id::text,
            'Recompensa da missão ' || m.title,
            null);
        end loop;
      end if;

      -- Baú de missão (1x).
      if m.award_chest is not null and m.award_chest <> '' then
        perform public.grant_chest_mission(p_user_id, m.award_chest, m.id);
      end if;
    end if;
  end loop;

  if xp_gain > 0 then
    insert into public.user_xp_log (user_id, amount, source, ref_id)
    values (p_user_id, xp_gain, 'mission:' || p_mission_type, '');

    perform public.auto_unlock_achievements(p_user_id);
  end if;
end;
$$;

revoke execute on function public.grant_mission_progress(uuid, text, int) from public, anon, authenticated;
grant execute on function public.grant_mission_progress(uuid, text, int) to service_role;

-- ---------------------------------------------------------------------------
-- my_progress (RECRIADA): retorna somente as missões diárias de HOJE
-- (rotação) + todas as semanais. O cliente nunca decide o conjunto.
-- ---------------------------------------------------------------------------
create or replace function public.my_progress()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  u uuid := auth.uid();
  total_xp int;
  cur_level int;
  cur_title text;
  cur_req int;
  next_req int;
  missions jsonb;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  select coalesce(sum(amount), 0) into total_xp from public.user_xp_log where user_id = u;

  select l.level, l.title, l.xp_required into cur_level, cur_title, cur_req
  from public.levels l
  where l.xp_required <= total_xp
  order by l.level desc limit 1;

  if cur_level is null then
    cur_level := 1; cur_title := 'Novato'; cur_req := 0;
  end if;

  select l.xp_required into next_req from public.levels l
  where l.xp_required > total_xp
  order by l.level asc limit 1;

  select jsonb_agg(jsonb_build_object(
    'id', m.id,
    'title', m.title,
    'description', m.description,
    'icon', m.icon,
    'frequency', m.frequency,
    'target', m.target,
    'xp_reward', m.xp_reward,
    'rewards', m.rewards,
    'award_chest', m.award_chest,
    'progress', coalesce(p.progress, 0),
    'completed', coalesce(p.completed, false),
    'period_start', coalesce(p.period_start, current_date)
  ) order by m.frequency, m.id)
  into missions
  from public.missions m
  left join public.user_mission_progress p
    on p.mission_id = m.id and p.user_id = u
    and p.period_start = current_date and m.frequency = 'daily'
    or p.mission_id = m.id and p.user_id = u
    and p.period_start = date_trunc('week', current_date)::date
    and m.frequency = 'weekly'
  where m.active
    and (m.frequency = 'weekly'
         or m.weekday is null
         or m.weekday = extract(dow from current_date)::int);

  return jsonb_build_object(
    'xp_total', total_xp,
    'level', cur_level,
    'level_title', cur_title,
    'xp_level_start', cur_req,
    'xp_next_level', next_req,
    'missions', coalesce(missions, '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.my_progress() from public, anon;
grant execute on function public.my_progress() to authenticated;