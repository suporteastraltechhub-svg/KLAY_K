-- KLAY K - Mensagens privadas (DMs): conversas, mensagens, não lidas, bloqueio
-- e integração com denúncias. RLS rígida: só os participantes da conversa
-- enxergam/inserem mensagens. Realtime via publicação RLS (supabase_realtime).

-- ---------------------------------------------------------------------------
-- Conversas (par único de usuários)
-- ---------------------------------------------------------------------------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references auth.users(id) on delete cascade,
  user_b_id uuid not null references auth.users(id) on delete cascade,
  last_message text default '',
  last_message_at timestamptz,
  last_sender_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  -- garante um único par, normalizado (a < b)
  constraint conversations_pair_unique unique (user_a_id, user_b_id),
  constraint conversations_ordered check (user_a_id < user_b_id),
  constraint conversations_distinct check (user_a_id <> user_b_id)
);

-- ---------------------------------------------------------------------------
-- Mensagens
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  read_at timestamptz,
  edited_at timestamptz,
  deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists conversations_user_a_idx on public.conversations (user_a_id, last_message_at desc);
create index if not exists conversations_user_b_idx on public.conversations (user_b_id, last_message_at desc);
create index if not exists messages_conv_idx on public.messages (conversation_id, created_at asc);
create index if not exists messages_sender_idx on public.messages (sender_id);

-- ---------------------------------------------------------------------------
-- Trigger: atualiza last_message/last_message_at da conversa
-- ---------------------------------------------------------------------------
create or replace function public.touch_conversation_last()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.conversations
    set last_message = NEW.text,
        last_message_at = NEW.created_at,
        last_sender_id = NEW.sender_id
  where id = NEW.conversation_id;
  return NEW;
end;
$$;

drop trigger if exists messages_touch_conv on public.messages;
create trigger messages_touch_conv
  after insert on public.messages
  for each row execute function public.touch_conversation_last();

-- ---------------------------------------------------------------------------
-- Helper: o usuário é participante da conversa?
-- ---------------------------------------------------------------------------
create or replace function public.is_conversation_participant(conv_id uuid, uid uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = conv_id and (c.user_a_id = uid or c.user_b_id = uid)
  );
$$;

-- ---------------------------------------------------------------------------
-- Permite denunciar mensagem (alarga o check de target_type de reports)
-- ---------------------------------------------------------------------------
alter table public.reports drop constraint if exists reports_target_type_check;
alter table public.reports add constraint reports_target_type_check
  check (target_type in ('user','post','live','comment','chat','message','conversation'));

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- conversas: participantes leem/inserem (inserir cria conversa consigo mesmo não,
-- valida participante envolve o próprio uid); não criar quando houver bloqueio
drop policy if exists "conv_select_participant" on public.conversations;
drop policy if exists "conv_insert_participant" on public.conversations;
drop policy if exists "conv_update_participant" on public.conversations;

create policy "conv_select_participant" on public.conversations
  for select using (user_a_id = auth.uid() or user_b_id = auth.uid());

create policy "conv_insert_participant" on public.conversations
  for insert with check (
    (user_a_id = auth.uid() or user_b_id = auth.uid())
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = user_a_id and b.blocked_id = user_b_id)
         or (b.blocker_id = user_b_id and b.blocked_id = user_a_id)
    )
  );

create policy "conv_update_participant" on public.conversations
  for update using (user_a_id = auth.uid() or user_b_id = auth.uid());

-- mensagens: participantes leem; remetente insere; remetente pode apagar
drop policy if exists "msg_select_participant" on public.messages;
drop policy if exists "msg_insert_participant" on public.messages;
drop policy if exists "msg_update_owner" on public.messages;

create policy "msg_select_participant" on public.messages
  for select using (
    exists (select 1 from public.conversations c
            where c.id = conversation_id and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid()))
  );

create policy "msg_insert_participant" on public.messages
  for insert with check (
    sender_id = auth.uid()
    and exists (select 1 from public.conversations c
                where c.id = conversation_id and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid()))
    and not exists (
      select 1 from public.blocked_users b
      join public.conversations c on c.id = conversation_id
      where (b.blocker_id = c.user_a_id and b.blocked_id = c.user_b_id)
         or (b.blocker_id = c.user_b_id and b.blocked_id = c.user_a_id)
    )
  );

create policy "msg_update_owner" on public.messages
  for update using (sender_id = auth.uid());

-- Marcar lida: os políticas de update permitem apenas o remetente (sender_id = uid).
-- Para "ler" mensagens do outro, o app usa uma RPC security definer (mark_messages_read).
create or replace function public.mark_messages_read(conv_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_conversation_participant(conv_id, auth.uid()) then
    raise exception 'not_participant';
  end if;
  update public.messages
    set read_at = now()
  where conversation_id = conv_id
    and sender_id <> auth.uid()
    and read_at is null;
end;
$$;

revoke all on function public.mark_messages_read(uuid) from public, anon, authenticated;
grant execute on function public.mark_messages_read(uuid) to authenticated;

-- Helper público para contagem de não lidas de um usuário (somente as próprias)
create or replace function public.unread_message_count()
returns bigint
language sql
security definer set search_path = public
as $$
  select count(*)::bigint
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
    and m.sender_id <> auth.uid()
    and m.read_at is null
    and m.deleted = false;
$$;

grant execute on function public.unread_message_count() to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime (RLS-aware): participantes recebem apenas o que lhes pertence
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;
