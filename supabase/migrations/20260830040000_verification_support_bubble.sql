-- ============================================================================
-- KLAY K — VERIFICAÇÃO & SUPORTE ADMIN (backend validado) + BOLHA DE BG
-- 1) Aprovação/rejeição de verificação e tickets por RPCs que re-validam
--    has_perm (verification/support/tickets) no backend. O usuário comum
--    nunca aprova a si mesmo (nem via coluna/alteração direta).
-- 2) Atualiza RLS de verification_requests para impedir auto-aprovação
--    (só service role escreve status via função).
-- 3) user_settings ganha a posição/estado da BOLHA FLUTUANTE (persistida).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- RLS: verification_requests — usuário só INSERT/SELECT o próprio; escrita
-- de status reservada a service_role (funções security definer ignoram RLS).
-- Fecha o furo anterior (policy sem `to` permitia o próprio usuário alterar o
-- status e "se aprovar") — auto-aprovação fica impossível.
-- ---------------------------------------------------------------------------
drop policy if exists "verif_update_service" on public.verification_requests;
create policy "verif_update_service" on public.verification_requests
  for update to service_role using (true) with check (true);

-- ---------------------------------------------------------------------------
-- RLS: support_tickets — o dono cria/consulta; a resposta administrativa é
-- feita via RPC security definer (admin_reply_ticket), logo o UPDATE de
-- campo admin via cliente é bloqueado (antigo furo: tickets_update_service
-- com using(true) permitia qualquer usuário editar QUALQUER ticket).
-- ---------------------------------------------------------------------------
drop policy if exists "tickets_update_service" on public.support_tickets;
create policy "tickets_update_service" on public.support_tickets
  for update to service_role using (true) with check (true);

-- ---------------------------------------------------------------------------
-- admin_review_verification: decide um pedido (aprovado → is_verified=true +
-- trigga conquista 'verified'; rejeitado → is_verified=false). Audita.
-- ---------------------------------------------------------------------------
create or replace function public.admin_review_verification(
  p_request_id uuid,
  p_approve boolean,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.verification_requests;
  v_user uuid;
begin
  if not public.has_perm('verification') then raise exception 'not_admin'; end if;
  select * into v_req from public.verification_requests where id = p_request_id;
  if v_req is null then raise exception 'request_not_found'; end if;
  if v_req.status <> 'pending' then raise exception 'already_reviewed'; end if;

  v_user := v_req.user_id;
  update public.verification_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         admin_note = coalesce(p_note, '')
   where id = p_request_id;

  update public.profiles set is_verified = p_approve where id = v_user;

  perform public.write_audit('verification.review', 'verification', p_request_id::text,
    jsonb_build_object('user_id', v_user::text, 'approved', p_approve, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end;
$$;

revoke all on function public.admin_review_verification(uuid, boolean, text) from public;
grant execute on function public.admin_review_verification(uuid, boolean, text) to authenticated;

-- Lista pedidos de verificação (staff com cap verification/verification_view).
create or replace function public.admin_list_verifications(
  p_status text default 'pending'
)
returns table (
  id uuid, user_id uuid, username text, display_name text,
  status text, reason text, admin_note text, submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('verification') and not public.has_perm('verification_view') then
    raise exception 'not_admin';
  end if;
  return query
    select v.id, v.user_id, p.username, p.display_name,
           v.status, v.reason, v.admin_note, v.submitted_at
    from public.verification_requests v
    left join public.profiles p on p.id = v.user_id
    where (p_status is null or v.status = p_status)
    order by v.submitted_at asc
    limit 200;
end;
$$;

revoke all on function public.admin_list_verifications(text) from public;
grant execute on function public.admin_list_verifications(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Suporte: responder/atualizar tickets (cap 'support'/'tickets').
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_tickets(
  p_status text default null
)
returns table (
  id uuid, user_id uuid, username text, display_name text,
  category text, subject text, message text, status text,
  admin_reply text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('support') and not public.has_perm('tickets') then
    raise exception 'not_support';
  end if;
  return query
    select t.id, t.user_id, p.username, p.display_name,
           t.category, t.subject, t.message, t.status,
           t.admin_reply, t.created_at
    from public.support_tickets t
    left join public.profiles p on p.id = t.user_id
    where (p_status is null or t.status = p_status)
    order by t.created_at asc
    limit 200;
end;
$$;

revoke all on function public.admin_list_tickets(text) from public;
grant execute on function public.admin_list_tickets(text) to authenticated;

create or replace function public.admin_reply_ticket(
  p_ticket_id uuid,
  p_status text default 'answered',
  p_reply text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_perm('support') and not public.has_perm('tickets') then
    raise exception 'not_support';
  end if;
  if p_status not in ('open','in_review','answered','closed') then
    raise exception 'bad_status';
  end if;
  update public.support_tickets
     set status = p_status, admin_reply = p_reply, updated_at = now()
   where id = p_ticket_id;
  perform public.write_audit('support.reply', 'ticket', p_ticket_id::text,
    jsonb_build_object('status', p_status));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_reply_ticket(uuid, text, text) from public;
grant execute on function public.admin_reply_ticket(uuid, text, text) to authenticated;

-- Moderação de conteúdo por posts (cap 'moderation'): marcar oculto/restaurar.
-- Como `posts` não possui coluna `status`, moderação é registrada em
-- moderation_actions (rastreável) e o conteúdo continua existindo — a exibição
-- fica a cargo do app respeitando as ações de moderação. Audita.
create or replace function public.admin_toggle_post_status(
  p_post_id uuid,
  p_hidden boolean,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  if not public.has_perm('moderation') then raise exception 'not_admin'; end if;
  select user_id into v_owner from public.posts where id = p_post_id;
  if v_owner is null then raise exception 'post_not_found'; end if;
  insert into public.moderation_actions
    (post_id, actor_id, action, target, reason)
  values (p_post_id, auth.uid(),
          case when p_hidden then 'hide' else 'restore' end,
          'post', p_reason);
  perform public.write_audit('moderation.post', 'post', p_post_id::text,
    jsonb_build_object('hidden', p_hidden, 'owner', v_owner::text, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_toggle_post_status(uuid, boolean, text) from public;
grant execute on function public.admin_toggle_post_status(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- BOLHA FLUTUANTE: posição + visibilidade persistidas em user_settings.
-- Campos podem existir sem que o app use — a UI lê/grava via RLS owner.
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column if not exists bubble_enabled boolean not null default true;
alter table public.user_settings
  add column if not exists bubble_x real not null default 0;
alter table public.user_settings
  add column if not exists bubble_y real not null default 0;