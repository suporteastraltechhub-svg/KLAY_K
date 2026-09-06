-- ============================================================================
-- KLAY K — EDIÇÃO DE CHAT AO VIVO + COMENTÁRIOS
-- Adiciona `edited_at` em `live_chat` e `comments`, política UPDATE só-dono e
-- RPCs `live_edit_chat` / `edit_comment` (security definer, valida backend).
-- Princípio: NENHUM usuário edita a mensagem de outro.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Chat ao vivo: coluna edited_at + UPDATE policy do dono + RPC.
-- ---------------------------------------------------------------------------
alter table public.live_chat add column if not exists edited_at timestamptz;

-- Política: apenas o autor da mensagem pode atualizá-la (e só a coluna de
-- edição/conteúdo; created_at e ids ficam intocados pelo RPC security definer).
drop policy if exists "live_chat_update_own" on public.live_chat;
create policy "live_chat_update_own" on public.live_chat
  for update using (user_id = auth.uid());

-- RPC de edição: valida autenticação, posse, tamanho e inspira a mesma
-- disciplina do live_send_chat (o cliente NÃO faz update direto).
create or replace function public.live_edit_chat(
  p_message_id uuid,
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
  v_row public.live_chat%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_msg = '' then raise exception 'empty_message'; end if;
  if length(v_msg) > 240 then raise exception 'message_too_long'; end if;

  select * into v_row from public.live_chat where id = p_message_id;
  if not found then raise exception 'message_not_found'; end if;
  if v_row.user_id <> v_uid then raise exception 'not_owner'; end if;

  update public.live_chat
    set message = left(v_msg, 240), edited_at = now()
  where id = p_message_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'message', v_row.message,
    'edited_at', to_char(v_row.edited_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$$;

revoke all on function public.live_edit_chat(uuid, text) from public, anon;
grant execute on function public.live_edit_chat(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Comentários: coluna edited_at + UPDATE policy do dono + RPC.
-- ---------------------------------------------------------------------------
alter table public.comments add column if not exists edited_at timestamptz;

drop policy if exists "comments_update_own" on public.comments;
create policy "comments_update_own" on public.comments
  for update using (user_id = auth.uid());

create or replace function public.edit_comment(
  p_comment_id uuid,
  p_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_text text := trim(coalesce(p_text, ''));
  v_row public.comments%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_text = '' then raise exception 'empty_text'; end if;
  if length(v_text) > 2000 then raise exception 'text_too_long'; end if;

  select * into v_row from public.comments where id = p_comment_id;
  if not found then raise exception 'comment_not_found'; end if;
  if v_row.user_id <> v_uid then raise exception 'not_owner'; end if;

  update public.comments
    set text = v_text, edited_at = now()
  where id = p_comment_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'text', v_row.text,
    'edited_at', to_char(v_row.edited_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$$;

revoke all on function public.edit_comment(uuid, text) from public, anon;
grant execute on function public.edit_comment(uuid, text) to authenticated;
