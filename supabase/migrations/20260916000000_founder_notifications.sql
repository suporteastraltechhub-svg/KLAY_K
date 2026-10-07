-- ============================================================================
-- KLAY K — Notificações no Painel do Fundador (tab equipe)
-- ============================================================================
-- Visão/estatísticas de notificações, listagem com filtros e broadcast oficial
-- (cria 1 notificação por usuário). Tudo calculado sob demanda no servidor com
-- caps e auditoria — o Flutter apenas exibe e dispara RPCs `security definer`.
-- Envio físico do push fica no trigger existente (push_notification_on_insert).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) founder_notification_stats(): agregados (cap roles/moderation/support)
-- ---------------------------------------------------------------------------
create or replace function public.founder_notification_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not (
    public.has_perm('roles') or public.has_perm('moderation') or public.has_perm('support')
  ) then
    raise exception 'not_admin';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.notifications),
    'unread', (select count(*) from public.notifications where not read),
    'today', (select count(*) from public.notifications where created_at > now() - interval '24 hours'),
    'broadcasts_7d', (select count(*) from public.notifications
                      where type in ('broadcast','announcement','event','alert')
                        and created_at > now() - interval '7 days'),
    'active_tokens', (select count(*) from public.push_tokens),
    'by_type', (select coalesce(jsonb_object_agg(t, n), '{}'::jsonb)
                from (select type as t, count(*) as n
                      from public.notifications
                      group by type order by count(*) desc limit 12) s)
  ) into v;
  return v;
end;
$$;

revoke all on function public.founder_notification_stats() from public;
revoke execute on function public.founder_notification_stats() from anon, authenticated;
grant execute on function public.founder_notification_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- 2) mod_list_notifications(): listagem com filtros (cap roles/moderation/support)
-- ---------------------------------------------------------------------------
create or replace function public.mod_list_notifications(
  p_type text default null,
  p_username text default null,
  p_limit int default 50
)
returns table (
  id uuid, user_id uuid, username text, display_name text,
  type text, message text, read boolean, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.has_perm('roles') or public.has_perm('moderation') or public.has_perm('support')
  ) then
    raise exception 'not_admin';
  end if;
  return query
    select n.id, n.user_id, p.username, p.display_name,
           n.type, n.message, n.read, n.created_at
    from public.notifications n
    left join public.profiles p on p.id = n.user_id
    where (p_type is null or n.type = p_type)
      and (p_username is null or p.username ilike '%' || p_username || '%')
    order by n.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

revoke all on function public.mod_list_notifications(text, text, int) from public;
revoke execute on function public.mod_list_notifications(text, text, int) from anon, authenticated;
grant execute on function public.mod_list_notifications(text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) founder_broadcast_notification(): transmite para TODOS os usuários
--    (cap roles/moderation; audita). 1 linha por usuário em `notifications`;
--    o trigger de push enfileira os envios Android automaticamente.
-- ---------------------------------------------------------------------------
create or replace function public.founder_broadcast_notification(
  p_type text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
  v_msg text;
  v_count int;
begin
  if not (public.has_perm('roles') or public.has_perm('moderation')) then
    raise exception 'not_admin';
  end if;
  if p_type is null or p_type not in ('broadcast','announcement','event','alert') then
    raise exception 'bad_type';
  end if;
  v_type := p_type;
  v_msg := btrim(coalesce(p_message, ''));
  if char_length(v_msg) < 4 or char_length(v_msg) > 500 then
    raise exception 'bad_message';
  end if;

  insert into public.notifications (user_id, actor_id, type, message)
  select u.id, auth.uid(), v_type, v_msg
  from auth.users u;
  get diagnostics v_count = row_count;

  perform public.write_audit('notification.broadcast', 'notification', v_type,
    jsonb_build_object('count', v_count, 'type', v_type, 'message', v_msg));
  return jsonb_build_object('ok', true, 'count', v_count, 'type', v_type);
end;
$$;

revoke all on function public.founder_broadcast_notification(text, text) from public;
revoke execute on function public.founder_broadcast_notification(text, text) from anon, authenticated;
grant execute on function public.founder_broadcast_notification(text, text) to authenticated;