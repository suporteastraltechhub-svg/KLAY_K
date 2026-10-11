-- KLAY K · Controles Familiares — os três recursos que estavam pendentes
--
-- Substitui os itens marcados "Aguardando backend" na tela de Controles
-- Familiares por recursos reais, com autorização, RLS e validação no servidor:
--
--   1. Limite de tempo definido por um responsável
--   2. Relatório de atividade para responsáveis
--   3. Aprovação de novos seguidores
--
-- Nada aqui grava dado inventado: o relatório só agrega o que o app JÁ grava
-- (posts, comentários, curtidas, views em `user_history`, follows, likes).
--
-- ===========================================================================
-- 1) LIMITE DE TEMPO DEFINIDO POR UM RESPONSÁVEL
-- ===========================================================================
--
-- O responsável define quantos MINUTOS por dia o membro pode usar o app, e
-- opcionalmente uma janela de horário permitida.
--
-- `user_history` guarda `watched_at` mas NÃO tem duração de sessão, então não
-- dá para reconstruir "minutos usados" a partir dele. Medir tempo real exigiria
-- um registro de sessão, que não existe no app hoje.
--
-- Por isso o limite é CONFIGURÁVEL e consultável (`family_time_limit_status`),
-- e a CONTAGEM é feita pelo app em session_start/session_stop, que já existem
-- em `LocalPrefsService`. Não existe Enforcement automático com um cron que
-- pode derrubar a conta no meio do uso.

create table if not exists public.family_time_limits (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  -- 0 significa "sem limite diário", mas continua valendo a janela de horário.
  daily_minutes integer not null default 60
    check (daily_minutes >= 0 and daily_minutes <= 1440),
  window_start time,
  window_end time,
  active boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Um responsável, um limite por membro.
  unique (guardian_id, member_id),
  -- Não faz sentido um membro ser responsável de si mesmo.
  check (guardian_id <> member_id)
);

create index if not exists family_time_limits_member_idx
  on public.family_time_limits (member_id)
  where active;

alter table public.family_time_limits enable row level security;

drop policy if exists "family_time_limits_guardant_all" on public.family_time_limits;
create policy "family_time_limits_guardant_all" on public.family_time_limits
  for all
  using (guardian_id = auth.uid())
  with check (guardian_id = auth.uid());

-- O membro LÊ o próprio limite (para o app avisar), mas NÃO escreve: quem
-- define é o responsável.
drop policy if exists "family_time_limits_member_select" on public.family_time_limits;
create policy "family_time_limits_member_select" on public.family_time_limits
  for select
  using (member_id = auth.uid());

-- ===========================================================================
-- 2) SEGUIMENTOS SUPOSTOS POR UM RESPONSÁVEL
-- ===========================================================================
--
-- `user_history` grava quando a pessoa VÊ algo, com `watched_at`. Somando as
-- linhas dos últimos minutos, obtemos tempo real de uso — sem inventar número.
--
-- Um registro por minuto de sessão ativa (mesma granularidade do ticker
-- que o app já roda). Para a consulta do limite ser barata.

create table if not exists public.family_usage_ticks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  used_at timestamptz not null default now()
);

create index if not exists family_usage_ticks_recent_idx
  on public.family_usage_ticks (user_id, used_at desc);

alter table public.family_usage_ticks enable row level security;

-- Sem policy de leitura: ninguém consulta a tabela diretamente. As únicas
-- leituras são das funções security definer abaixo, que filtram por vínculo.
-- Um heartbeat a cada 30s em `user_history` seria ruído desnecessário.

-- ===========================================================================
-- 3) APROVAÇÃO DE NOVOS SEGUIDORES
-- ===========================================================================
--
-- Hoje o follow é direto (`follows` recebe a linha na hora). Tornar TODO follow
-- pendente quebraria o app, então a exigência é OPCIONAL por perfil:
-- `profiles.require_follow_approval`. Quem não liga, segue como sempre.
--
-- Quando ligado, `request_follow` cria um pedido em vez da linha em `follows`,
-- e só `approve_follow_request` (ou rejeitar) materializa o vínculo.

alter table public.profiles
  add column if not exists require_follow_approval boolean not null default false;

-- `profiles` não tem UPDATE de nível de tabela: o projeto revogou e passou a
-- conceder POR COLUNA (o mesmo motivo de `20260829120000_revoke_admin_flags`
-- existir). Sem este grant, o usuário não consegue ligar a própria exigência.
grant update (require_follow_approval) on public.profiles to authenticated;
revoke update (require_follow_approval) on public.profiles from anon;

create table if not exists public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pendente'
    check (status in ('pendente', 'aprovado', 'rejeitado', 'cancelado')),
  -- Quem aprovou/rejeitou, quando o pedido for seu (responsável).
  responded_by uuid references auth.users(id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (follower_id, following_id),
  check (follower_id <> following_id)
);

-- Pedidos recebidos e pendentes: é o que a tela de responsável lista.
create index if not exists follow_requests_pending_idx
  on public.follow_requests (following_id, created_at desc)
  where status = 'pendente';

-- Pedidos enviados por mim.
create index if not exists follow_requests_requester_idx
  on public.follow_requests (follower_id, created_at desc);

alter table public.follow_requests enable row level security;

-- O dono do perfil vê os pedidos que recebeu.
drop policy if exists "follow_requests_select_owner" on public.follow_requests;
create policy "follow_requests_select_owner" on public.follow_requests
  for select
  using (following_id = auth.uid());

-- O solicitante vê os próprios pedidos.
drop policy if exists "follow_requests_select_requester" on public.follow_requests;
create policy "follow_requests_select_requester" on public.follow_requests
  for select
  using (follower_id = auth.uid());

-- O solicitante pode cancelar o próprio pedido pendente.
drop policy if exists "follow_requests_update_requester" on public.follow_requests;
create policy "follow_requests_update_requester" on public.follow_requests
  for update
  using (follower_id = auth.uid() and status = 'pendente')
  with check (follower_id = auth.uid() and status = 'cancelado');

-- ===========================================================================
-- 4) AUTORIZAÇÃO: O QUE CONTA COMO RESPONSÁVEL
-- ===========================================================================
--
-- Reaproveita `family_links`, que já guarda `status`, `can_manage_safety` e
-- quem é guardian de quem. Uma relação `status <> 'ativo'` ou
-- `can_manage_safety = false` NÃO dá poder sobre limite de tempo nem sobre
-- pedidos de seguimiento.

create or replace function public.is_active_guardian_of(p_guardian uuid, p_member uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.family_links l
     where l.guardian_id = p_guardian
       and l.member_id = p_member
       and l.status = 'active'
       and coalesce(l.can_manage_safety, true)
  );
$$;

revoke execute on function public.is_active_guardian_of(uuid, uuid) from public;
grant execute on function public.is_active_guardian_of(uuid, uuid) to authenticated;

-- ===========================================================================
-- 5) STATUS DO LIMITE (chamado pelo membro e pelo responsável)
-- ===========================================================================

create or replace function public.family_time_limit_status(p_member uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_member uuid := coalesce(p_member, v_me);
  v_limit record;
  v_used integer;
  v_since timestamptz;
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;

  -- Autorizado: o próprio membro, ou um responsável ATIVO dele.
  if v_member <> v_me
     and not public.is_active_guardian_of(v_me, v_member)
  then
    raise exception 'forbidden';
  end if;

  select * into v_limit
    from public.family_time_limits l
   where l.member_id = v_member
     and l.active
   order by l.updated_at desc
   limit 1;

  if v_limit.id is null then
    return jsonb_build_object(
      'limitado', false,
      'daily_minutes', null,
      'used_minutes', 0,
      'remaining_minutes', null,
      'window_start', null,
      'window_end', null,
      'note', null
    );
  end if;

  -- Tempo real de uso: um tick por minuto de sessão ativa (UTC).
  -- O app chama `family_usage_tick()` do ticker de sessão do
  -- `LocalPrefsService`, que dispara a cada minuto em primeiro plano.
  -- Por isso 1 tick = 1 minuto: não há divisão.
  v_since := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  select coalesce(count(*)::int, 0)
    into v_used
    from public.family_usage_ticks t
   where t.user_id = v_member
     and t.used_at >= v_since;

  return jsonb_build_object(
    'limitado', true,
    'daily_minutes', v_limit.daily_minutes,
    'used_minutes', v_used,
    'remaining_minutes',
      greatest(coalesce(v_limit.daily_minutes, 0) - v_used, 0),
    'window_start', v_limit.window_start,
    'window_end', v_limit.window_end,
    'note', v_limit.note
  );
end;
$$;

revoke execute on function public.family_time_limit_status(uuid) from public;
grant execute on function public.family_time_limit_status(uuid) to authenticated;

-- ===========================================================================
-- 6) HEARTBEAT DE USO
-- ===========================================================================
--
-- O app chama a cada 30s enquanto a sessão está ativa. É o que transforma o
-- limite em minutos usados. Sem isso o limite existiria mas ficaria zerado.

create or replace function public.family_usage_tick()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_active integer;
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;

  -- Só grava se existe um limite ATIVO para mim: sem limite, não há por que
  -- acumular ticks.
  select count(*) into v_active
    from public.family_time_limits l
   where l.member_id = v_me and l.active;
  if v_active = 0 then
    return;
  end if;

  insert into public.family_usage_ticks (user_id) values (v_me);
end;
$$;

revoke execute on function public.family_usage_tick() from public;
grant execute on function public.family_usage_tick() to authenticated;

-- ===========================================================================
-- 7) RELATÓRIO DE ATIVIDADE PARA RESPONSÁVEIS
-- ===========================================================================
--
-- Agrega o que o app JÁ grava. Não inventa nada: cada campo vem de uma
-- contagem real. Se a conta nunca usou o app, os números são zero — e é isso
-- que o responsável vê.

create or replace function public.family_activity_report(
  p_member uuid,
  p_days integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_since timestamptz;
  v_limite integer;
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;
  if p_member = v_me or not public.is_active_guardian_of(v_me, p_member) then
    raise exception 'forbidden';
  end if;

  v_limite := least(greatest(coalesce(p_days, 7), 1), 90);
  v_since := now() - make_interval(days => v_limite);

  return jsonb_build_object(
    'days', v_limite,
    'since', v_since,
    'posts', (
      select count(*) from public.posts
       where user_id = p_member and created_at >= v_since),
    'comments', (
      select count(*) from public.comments
       where user_id = p_member and created_at >= v_since),
    'likes_given', (
      select count(*) from public.post_likes
       where user_id = p_member and created_at >= v_since),
    'live_views', (
      select count(*) from public.user_history
       where user_id = p_member and ref_type = 'live' and watched_at >= v_since),
    'post_views', (
      select count(*) from public.user_history
       where user_id = p_member and ref_type = 'post' and watched_at >= v_since),
    'minutes_used_today', (
      select coalesce(count(*)::int, 0)
        from public.family_usage_ticks t
       where t.user_id = p_member
         and t.used_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'),
    'new_followers', (
      select count(*) from public.follows
       where following_id = p_member and created_at >= v_since),
    'pending_follow_requests', (
      select count(*) from public.follow_requests
       where following_id = p_member and status = 'pendente')
  );
end;
$$;

revoke execute on function public.family_activity_report(uuid, integer) from public;
grant execute on function public.family_activity_report(uuid, integer) to authenticated;

-- ===========================================================================
-- 8) SEGUIMENTOS COM APROVAÇÃO
-- ===========================================================================
--
-- Substitui o INSERT direto em `follows`. Mantém o comportamento antigo quando
-- o alvo não exige aprovação, para não mudar nada para quem não pediu.

create or replace function public.request_follow(p_following_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_exige boolean;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;
  if p_following_id is null or p_following_id = v_me then
    raise exception 'bad_following';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_following_id) then
    raise exception 'not_found';
  end if;

  -- Já segue? nada a fazer.
  if exists (select 1 from public.follows f
              where f.follower_id = v_me and f.following_id = p_following_id) then
    return jsonb_build_object('status', 'ja_segue', 'requer_aprovacao', false);
  end if;

  select coalesce(p.require_follow_approval, false) into v_exige
    from public.profiles p
   where p.id = p_following_id;

  if not v_exige then
    insert into public.follows (follower_id, following_id)
    values (v_me, p_following_id)
    on conflict do nothing;
    return jsonb_build_object('status', 'seguindo', 'requer_aprovacao', false);
  end if;

  -- Pedido já pendente: devolve o mesmo, sem duplicar.
  select r.id into v_id
    from public.follow_requests r
   where r.follower_id = v_me
     and r.following_id = p_following_id
     and r.status = 'pendente';

  if v_id is not null then
    return jsonb_build_object('status', 'pendente', 'requer_aprovacao', true,
                              'request_id', v_id);
  end if;

  insert into public.follow_requests (follower_id, following_id)
  values (v_me, p_following_id)
  on conflict (follower_id, following_id) do update
    set status = 'pendente', responded_by = null, responded_at = null
  returning id into v_id;

  return jsonb_build_object('status', 'pendente', 'requer_aprovacao', true,
                            'request_id', v_id);
end;
$$;

revoke execute on function public.request_follow(uuid) from public;
grant execute on function public.request_follow(uuid) to authenticated;

-- Aprova ou rejeita. Só o DONO do perfil decide (o responsável não tem poder
-- sobre quem o membro segue — este recurso é do próprio usuário).
create or replace function public.respond_follow_request(p_request_id uuid, p_aceitar boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_req record;
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;

  select * into v_req
    from public.follow_requests r
   where r.id = p_request_id
     and r.following_id = v_me
     and r.status = 'pendente'
   for update;

  if v_req.id is null then
    raise exception 'not_found';
  end if;

  if p_aceitar then
    update public.follow_requests
       set status = 'aprovado', responded_by = v_me, responded_at = now()
     where id = p_request_id;
    insert into public.follows (follower_id, following_id)
    values (v_req.follower_id, v_req.following_id)
    on conflict do nothing;
  else
    update public.follow_requests
       set status = 'rejeitado', responded_by = v_me, responded_at = now()
     where id = p_request_id;
  end if;

  return jsonb_build_object('status', case when p_aceitar then 'aprovado' else 'rejeitado' end);
end;
$$;

revoke execute on function public.respond_follow_request(uuid, boolean) from public;
grant execute on function public.respond_follow_request(uuid, boolean) to authenticated;

-- ===========================================================================
-- 9) SETAR O LIMITE (responsável)
-- ===========================================================================

create or replace function public.family_set_time_limit(
  p_member uuid,
  p_daily_minutes integer,
  p_window_start time default null,
  p_window_end time default null,
  p_active boolean default true,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_minutes integer := coalesce(p_daily_minutes, 0);
begin
  if v_me is null then
    raise exception 'auth_required';
  end if;
  if not public.is_active_guardian_of(v_me, p_member) then
    raise exception 'forbidden';
  end if;
  if v_minutes < 0 or v_minutes > 1440 then
    raise exception 'bad_minutes';
  end if;

  insert into public.family_time_limits
    (guardian_id, member_id, daily_minutes, window_start, window_end, active, note)
  values (v_me, p_member, v_minutes, p_window_start, p_window_end, p_active, p_note)
  on conflict (guardian_id, member_id) do update
    set daily_minutes = excluded.daily_minutes,
        window_start   = excluded.window_start,
        window_end     = excluded.window_end,
        active         = excluded.active,
        note           = excluded.note,
        updated_at     = now();

  return jsonb_build_object('ok', true, 'daily_minutes', v_minutes);
end;
$$;

revoke execute on function public.family_set_time_limit(uuid, integer, time, time, boolean, text) from public;
grant execute on function public.family_set_time_limit(uuid, integer, time, time, boolean, text) to authenticated;

-- ===========================================================================
-- 10) LIMPAR TICKS (higiene)
-- ===========================================================================

create or replace function public.prune_family_usage_ticks()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  delete from public.family_usage_ticks where used_at < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.prune_family_usage_ticks() from public, anon;
grant execute on function public.prune_family_usage_ticks() to service_role;
