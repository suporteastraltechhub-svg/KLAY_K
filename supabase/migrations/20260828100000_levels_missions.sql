-- ============================================================================
-- Níveis, Missões e XP validados no backend (eventos reais, não no cliente).
-- - XP/andamento só são concedidos por triggers no banco (eventos reais).
-- - user_xp_log registra cada pontuação (auditável).
-- - Missões diárias/semanais com período calculado no servidor.
-- ============================================================================

-- Contador de visualizações (usado nas conquistas de views)
alter table public.posts add column if not exists views_count int not null default 0;

-- ---------------------------------------------------------------------------
-- levels: tabela de curva de nível (XP acumulado → nível)
-- ---------------------------------------------------------------------------
create table if not exists public.levels (
  level int primary key,
  xp_required int not null,
  title text not null default ''
);

insert into public.levels (level, xp_required, title) values
  (1, 0,    'Novato'),
  (2, 100,  'Explorador'),
  (3, 250,  'Criador'),
  (4, 500,  'Estrela em ascensão'),
  (5, 1000, 'Estrela K'),
  (6, 2000, 'Ícone'),
  (7, 4000, 'Lenda'),
  (8, 8000, 'Mito K'),
  (9, 16000,'Imortal'),
  (10, 32000,'Deus do KLAY K')
on conflict (level) do nothing;

-- ---------------------------------------------------------------------------
-- user_xp_log: histórico auditável de XP concedido (escrita restrita a RPC/trigger)
-- ---------------------------------------------------------------------------
create table if not exists public.user_xp_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount int not null default 0,
  source text not null default '',
  ref_id text default '',
  created_at timestamptz not null default now()
);

create index if not exists xp_log_user_idx on public.user_xp_log (user_id, created_at desc);

alter table public.user_xp_log enable row level security;
drop policy if exists "xplog_select_owner" on public.user_xp_log;
create policy "xplog_select_owner" on public.user_xp_log for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- missions: catálogo de missões (diárias/semanais), XP real por missão
-- ---------------------------------------------------------------------------
create table if not exists public.missions (
  id text primary key,
  title text not null,
  description text not null default '',
  icon text default '',
  mission_type text not null,
  frequency text not null default 'daily' check (frequency in ('daily','weekly')),
  target int not null default 1,
  xp_reward int not null default 0,
  active boolean not null default true
);

insert into public.missions (id, title, description, icon, mission_type, frequency, target, xp_reward) values
  ('post_daily',   'Publique um vídeo', 'Poste 1 vídeo hoje', '📹', 'post', 'daily', 1, 5),
  ('post_weekly',  'Crie 5 vídeos', 'Poste 5 vídeos na semana', '🎬', 'post', 'weekly', 5, 30),
  ('follow_daily', 'Siga alguém', 'Siga 1 conta hoje', '➕', 'follow', 'daily', 1, 3),
  ('follow_weekly','Siga 10 contas', 'Siga 10 contas na semana', '👥', 'follow', 'weekly', 10, 25),
  ('like_daily',   'Receba curtidas', 'Receba 10 curtidas hoje', '❤️', 'like', 'daily', 10, 5),
  ('like_weekly',  'Receba 100 curtidas', 'Receba 100 curtidas na semana', '💥', 'like', 'weekly', 100, 40),
  ('comment_daily','Receba comentários', 'Receba 5 comentários hoje', '💬', 'comment', 'daily', 5, 5),
  ('comment_weekly','Receba 30 comentários', 'Receba 30 comentários na semana', '🗨️', 'comment', 'weekly', 30, 35),
  ('live_daily',   'Faça uma live', 'Faça 1 transmissão hoje', '🔴', 'live', 'daily', 1, 8),
  ('live_weekly',  'Faça 3 lives', 'Faça 3 transmissões na semana', '📡', 'live', 'weekly', 3, 45)
on conflict (id) do nothing;

alter table public.missions enable row level security;
drop policy if exists "missions_select" on public.missions;
create policy "missions_select" on public.missions for select using (true);

-- ---------------------------------------------------------------------------
-- user_mission_progress: andamento do usuário por missão + período
-- ---------------------------------------------------------------------------
create table if not exists public.user_mission_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mission_id text not null references public.missions(id) on delete cascade,
  progress int not null default 0,
  completed boolean not null default false,
  completed_at timestamptz,
  period_start date not null,
  period_end date not null,
  unique (user_id, mission_id, period_start)
);

create index if not exists umprog_user_idx on public.user_mission_progress (user_id, period_start);

alter table public.user_mission_progress enable row level security;
drop policy if exists "umprog_select_owner" on public.user_mission_progress;
create policy "umprog_select_owner" on public.user_mission_progress for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- grant_mission_progress: núcleo de premiação (chamado apenas por triggers
-- do banco, security definer). Concede andamento + XP auditável ao concluir.
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
      -- semana começa na segunda-feira
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
    end if;
  end loop;

  if xp_gain > 0 then
    insert into public.user_xp_log (user_id, amount, source, ref_id)
    values (p_user_id, xp_gain, 'mission:' || p_mission_type, '');

    -- Conquistas condicionais (posts/followers/lives; 'views' sem evento aqui)
    perform public.auto_unlock_achievements(p_user_id);
  end if;
end;
$$;

revoke all on function public.grant_mission_progress(uuid, text, int) from public;
grant execute on function public.grant_mission_progress(uuid, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- auto_unlock_achievements: desbloqueia conquistas reais por condição atendida
-- ---------------------------------------------------------------------------
create or replace function public.auto_unlock_achievements(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  a record;
  actual bigint;
  need bigint;
begin
  for a in
    select * from public.achievements where condition_type <> 'manual'
  loop
    case a.condition_type
      when 'posts' then
        select count(*) into actual from public.posts where user_id = p_user_id;
      when 'followers' then
        select count(*) into actual from public.follows where following_id = p_user_id;
      when 'lives' then
        select count(*) into actual
        from public.lives l
        join public.live_events e on e.live_id = l.id and e.event_type = 'LIVE_STARTED'
        where l.streamer_id = p_user_id;
      when 'views' then
        select coalesce(sum(views_count), 0) into actual from public.posts where user_id = p_user_id;
      else
        continue;
    end case;
    need := a.condition_value;

    if actual >= need then
      insert into public.user_achievements (user_id, achievement_id)
      values (p_user_id, a.id)
      on conflict (user_id, achievement_id) do nothing;

      insert into public.user_xp_log (user_id, amount, source, ref_id)
      values (p_user_id, a.xp, 'achievement:' || a.id, '')
      on conflict do nothing;
    end if;
  end loop;
end;
$$;

revoke all on function public.auto_unlock_achievements(uuid) from public;
grant execute on function public.auto_unlock_achievements(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers em eventos reais (proprietário dos dados recebe o progresso)
-- ---------------------------------------------------------------------------

-- POST publicado → progresso 'post' para o autor
create or replace function public.tg_post_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.grant_mission_progress(NEW.user_id, 'post', 1);
  perform public.auto_unlock_achievements(NEW.user_id);
  return NEW;
end; $$;
drop trigger if exists tg_post_mission on public.posts;
create trigger tg_post_mission after insert on public.posts for each row execute function public.tg_post_mission();

-- Follow → progresso 'follow' para quem recebeu
create or replace function public.tg_follow_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.grant_mission_progress(NEW.following_id, 'follow', 1);
  perform public.auto_unlock_achievements(NEW.following_id);
  return NEW;
end; $$;
drop trigger if exists tg_follow_mission on public.follows;
create trigger tg_follow_mission after insert on public.follows for each row execute function public.tg_follow_mission();

-- Curtida → progresso 'like' para o dono do post
create or replace function public.tg_like_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
declare owner_id uuid;
begin
  select user_id into owner_id from public.posts where id = NEW.post_id;
  if owner_id is not null then
    perform public.grant_mission_progress(owner_id, 'like', 1);
  end if;
  return NEW;
end; $$;
drop trigger if exists tg_like_mission on public.post_likes;
create trigger tg_like_mission after insert on public.post_likes for each row execute function public.tg_like_mission();

-- Comentário → progresso 'comment' para o dono do post
create or replace function public.tg_comment_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
declare owner_id uuid;
begin
  select p.user_id into owner_id from public.posts p where p.id = NEW.post_id;
  if owner_id is not null then
    perform public.grant_mission_progress(owner_id, 'comment', 1);
  end if;
  return NEW;
end; $$;
drop trigger if exists tg_comment_mission on public.comments;
create trigger tg_comment_mission after insert on public.comments for each row execute function public.tg_comment_mission();

-- Live iniciada → progresso 'live' para o streamer
create or replace function public.tg_live_mission()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if NEW.status = 'live' and (OLD.status is distinct from 'live') then
    perform public.grant_mission_progress(NEW.streamer_id, 'live', 1);
  end if;
  return NEW;
end; $$;
drop trigger if exists tg_live_mission on public.lives;
create trigger tg_live_mission after insert or update of status on public.lives
  for each row execute function public.tg_live_mission();

-- ---------------------------------------------------------------------------
-- my_progress: nível + XP total + missões do período atual (somente autenticado)
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

revoke all on function public.my_progress() from public;
grant execute on function public.my_progress() to authenticated;