-- ============================================================================
-- 20260915000000_feedback_system.sql
-- Feedbacks dos usuários (sugestão/bug/elogio/outro) com nota 1–5.
-- Fluxo: usuário envia num único RPC; equipe (cap `support`) lê/atualiza via
-- RPCs security definer; cada decisão vira `audit_logs`.
-- ============================================================================

create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null default 'other'
    check (category in ('suggestion','bug','praise','other')),
  rating int not null default 5 check (rating between 1 and 5),
  message text not null,
  status text not null default 'new'
    check (status in ('new','reviewed','archived')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists feedback_user_idx on public.app_feedback (user_id, created_at desc);
create index if not exists feedback_status_idx on public.app_feedback (status, created_at desc);

alter table public.app_feedback enable row level security;

-- Dono lê/apaga somente os próprios; inserir também é do dono (sem exclusão:
-- feedback é permanente para auditoria). Equipe lê/atualiza via RPC definer.
drop policy if exists "feedback_select_owner" on public.app_feedback;
drop policy if exists "feedback_insert_owner" on public.app_feedback;
create policy "feedback_select_owner" on public.app_feedback
  for select using (user_id = auth.uid());
create policy "feedback_insert_owner" on public.app_feedback
  for insert with check (user_id = auth.uid());

revoke all on table public.app_feedback from anon;
grant insert, select on table public.app_feedback to authenticated;
grant select on table public.app_feedback to service_role;

-- ---------------------------------------------------------------------------
-- Envio (qualquer usuário autenticado, 1 por chamada; sem rate-limit aqui —
-- a camada de edge/push rejeita abuso).
-- ---------------------------------------------------------------------------
create or replace function public.submit_feedback(
  p_category text,
  p_rating int,
  p_message text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cat text := lower(trim(coalesce(p_category, 'other')));
  v_msg text := trim(coalesce(p_message, ''));
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_cat not in ('suggestion','bug','praise','other') then
    raise exception 'bad_category';
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'bad_rating';
  end if;
  if length(v_msg) < 4 then raise exception 'short_message'; end if;
  insert into public.app_feedback (user_id, category, rating, message)
  values (v_uid, v_cat, p_rating, v_msg)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;

revoke all on function public.submit_feedback(text, int, text) from anon, public;
grant execute on function public.submit_feedback(text, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Painel: listar (cap `support`).
-- ---------------------------------------------------------------------------
create or replace function public.mod_list_feedbacks(p_status text default null)
returns table (
  id uuid,
  user_id uuid,
  username text,
  display_name text,
  category text,
  rating int,
  message text,
  status text,
  notes text,
  created_at timestamptz
)
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('support') then raise exception 'not_admin'; end if;
  return query
    select f.id,
           f.user_id,
           coalesce(p.username, ''),
           coalesce(p.display_name, ''),
           f.category,
           f.rating,
           f.message,
           f.status,
           coalesce(f.notes, ''),
           f.created_at
    from public.app_feedback f
    left join public.profiles p on p.id = f.user_id
    where (p_status is null or f.status = p_status)
    order by f.created_at desc
    limit 200;
end;
$$;

revoke all on function public.mod_list_feedbacks(text) from anon, public;
grant execute on function public.mod_list_feedbacks(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Painel: atualizar estado (revisar/arquivar). Cap `support`.
-- ---------------------------------------------------------------------------
create or replace function public.mod_update_feedback(
  p_feedback_id uuid,
  p_status text,
  p_notes text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('support') then raise exception 'not_admin'; end if;
  if p_status not in ('new','reviewed','archived') then
    raise exception 'bad_status';
  end if;
  update public.app_feedback
     set status = p_status,
         notes = case when p_notes <> '' then p_notes else notes end,
         updated_at = now()
   where id = p_feedback_id;
  perform public.write_audit('feedback.update', 'feedback', p_feedback_id::text,
    jsonb_build_object('status', p_status, 'notes', p_notes));
end;
$$;

revoke all on function public.mod_update_feedback(uuid, text, text) from anon, public;
grant execute on function public.mod_update_feedback(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Painel: agregados (cap `support`).
-- ---------------------------------------------------------------------------
create or replace function public.founder_feedback_stats()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.has_perm('support') then raise exception 'not_admin'; end if;
  return (
    select jsonb_build_object(
      'total', count(*),
      'new', count(*) filter (where status = 'new'),
      'reviewed', count(*) filter (where status = 'reviewed'),
      'archived', count(*) filter (where status = 'archived'),
      'today', count(*) filter (where created_at >= date_trunc('day', now())),
      'avg_rating', coalesce(round(avg(rating)::numeric, 1), 0)
    )
    from public.app_feedback
  );
end;
$$;

revoke all on function public.founder_feedback_stats() from anon, public;
grant execute on function public.founder_feedback_stats() to authenticated;