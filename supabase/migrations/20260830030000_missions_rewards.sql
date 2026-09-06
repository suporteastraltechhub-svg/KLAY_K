-- ============================================================================
-- KLAY K — MISSÕES COM RECOMPENSAS MULTI-MOEDA + ATALHOS DE BAÚ
-- Evolui o sistema de missões (mission_type já existente) para creditar
-- moedas/diamantes/etc no progresso, além do XP. A premiação acontece
-- SOMENTE no backend (triggers/security definer) — o cliente nunca credita.
-- Também desbloqueia baús como recompensa de missão (chest_reward).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- missions: novos campos de recompensa (mantendo xp_reward existente).
--   rewards jsonb  → {"credits":100, "diamonds":2} (multi-moeda, configurável)
--   award_chest text → id de chest liberado como baú de missão (opcional).
-- ---------------------------------------------------------------------------
alter table public.missions
  add column if not exists rewards jsonb not null default '{}';
alter table public.missions
  add column if not exists award_chest text references public.chests(id) on delete set null;

-- ---------------------------------------------------------------------------
-- grant_chest_mission: libera um baú de missão para o usuário (1 por missão).
-- ---------------------------------------------------------------------------
create or replace function public.grant_chest_mission(
  p_user_id uuid,
  p_chest_id text,
  p_mission_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_chest_id is null or p_chest_id = '' then return; end if;
  insert into public.user_chests (user_id, chest_id, source)
  select p_user_id, id, 'mission'
  from public.chests where id = p_chest_id and status = 'active'
  on conflict do nothing;
end;
$$;

revoke all on function public.grant_chest_mission(uuid, text, text) from public;
grant execute on function public.grant_chest_mission(uuid, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- grant_mission_progress (RECRIADA): além de XP (como antes), credita as
-- recompensas multi-moeda e libera baú de missão ao concluir. Idempotente:
-- só paga a recompensa na transição para completed (completed_at nulo).
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
begin
  if p_user_id is null then return; end if;
  period_s := current_date;
  period_e := current_date;
  for m in
    select * from public.missions
    where mission_type = p_mission_type and active
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

      -- Recompensas multi-moeda (cashout 1x, na transição).
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
-- Seeds de missões com recompensas reais (multi-moeda) e baú.
-- Mantém as missões existentes ativas; são idempotentes (on conflict).
-- ---------------------------------------------------------------------------
insert into public.missions (id, title, description, icon, mission_type, frequency, target, xp_reward, rewards, award_chest) values
  ('chest_daily',   'Abra um baú',  'Abra o baú diário hoje',      '📦', 'chest_open', 'daily', 1, 5,  '{"credits": 25}'::jsonb, null),
  ('gift_daily',    'Envie um presente', 'Envie 1 presente hoje', '🎁', 'gift_sent',  'daily', 1, 10, '{"credits": 50, "diamonds": 1}'::jsonb, null),
  ('like_receive_weekly', 'Recompensa de seguidores', 'Receba 20 curtidas na semana', '❤️', 'like', 'weekly', 20, 30, '{"credits": 100, "crystals": 1}'::jsonb, 'diario'),
  ('post_weekly',   'Crie 5 vídeos', 'Poste 5 vídeos na semana',  '🎬', 'post', 'weekly', 5, 45, '{"credits": 150, "emeralds": 1}'::jsonb, 'missao')
on conflict (id) do update set
  rewards = excluded.rewards, award_chest = excluded.award_chest;

-- ---------------------------------------------------------------------------
-- Triggers reais de premiação:
--   * gift_transactions insert → missão 'gift_sent' para quem enviou
--   * chest_opens insert   → missão 'chest_open' para quem abriu
-- ---------------------------------------------------------------------------
create or replace function public.tg_gift_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.grant_mission_progress(NEW.user_id, 'gift_sent', 1);
  return NEW;
end; $$;
drop trigger if exists tg_gift_mission on public.gift_transactions;
create trigger tg_gift_mission after insert on public.gift_transactions
  for each row execute function public.tg_gift_mission();

create or replace function public.tg_chest_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.grant_mission_progress(NEW.user_id, 'chest_open', 1);
  return NEW;
end; $$;
drop trigger if exists tg_chest_mission on public.chest_opens;
create trigger tg_chest_mission after insert on public.chest_opens
  for each row execute function public.tg_chest_mission();

-- ---------------------------------------------------------------------------
-- my_progress (RECRIADA): inclui recompensas e chest_reward no payload.
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
  where m.active;

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