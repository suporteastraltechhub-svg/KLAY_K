-- KLAY K · Rascunhos — estados reais do fluxo de criação.
--
-- Complementa 20260831140000_growth.sql (tabela `drafts`).
--
-- A constraint antiga era: status in ('draft','published','trashed')
-- O fluxo de criação precisa de 5 estados reais:
--   draft              — salvo, ainda não finalizado
--   editing            — aberto no editor e sendo alterado
--   ready_to_publish   — passou pela revisão, aguardando publicação
--   published          — publicado (some dos rascunhos)
--   deleted            — excluído pelo usuário (era 'trashed')
--
-- Aditiva e retrocompatível:
--   * 'trashed' continua aceito na escrita e é mapeado para 'deleted', para
--     nenhum rascunho existente fique ilegível.
--   * Nenhuma linha é apagada ou alterada por esta migration.
--   * 'published' não muda de significado: continua sendo o marcador de que
--     o rascunho virou post (o app usa `post_id` para isso).

-- Valores legados precisam existir antes de trocar o CHECK.
-- 1. Amplia o domínio aceito (o legado "trashed" continua válido).
alter table public.drafts
  drop constraint if exists drafts_status_check;

alter table public.drafts
  add constraint drafts_status_check
  check (status in (
    'draft',
    'editing',
    'ready_to_publish',
    'published',
    'deleted',
    -- legado: aceito na escrita, tratado como 'deleted' na leitura
    'trashed'
  ));

comment on column public.drafts.status is
  'draft | editing | ready_to_publish | published | deleted. ''trashed'' é legado e equivale a ''deleted''.';

-- 2. Índice para os estados ativos (a tela de rascunhos lista estes).
create index if not exists drafts_user_status_idx
  on public.drafts (user_id, status, updated_at desc);

-- 3. Visão que já normaliza o legado, para o app nunca precisar lidar com
--    'trashed': published/updated saem como 'deleted'.
create or replace view public.drafts_active_view
with (security_invoker = true)
as
  select
    id,
    user_id,
    video_path,
    cover_path,
    description,
    audio_name,
    hashtags,
    location,
    duration_seconds,
    case when status = 'trashed' then 'deleted' else status end as status,
    created_at,
    updated_at
  from public.drafts
  where status <> 'published';

-- A view usa RLS da tabela porque é security_invoker: o usuário continua
-- enxergando apenas os próprios rascunhos.

-- 4. RPC para mover o estado, com validação no servidor.
--    O app nunca escreve `status` direto nem decide 'published'.
create or replace function public.set_draft_status(
  p_draft_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_status text;
begin
  if u is null then raise exception 'not_authenticated'; end if;

  -- Só rascunhos legítimos podem mudar de estado. 'published' e 'deleted'
  -- ficam de fora de propósito: publicar passa por DraftsService.publish (que
  -- valida comprador/vendedor) e apagar é local.
  v_status := case p_status
    when 'trashed' then 'deleted'
    else p_status
  end;

  if v_status not in ('draft','editing','ready_to_publish') then
    raise exception 'invalid_status';
  end if;

  update public.drafts
     set status = v_status, updated_at = now()
   where id = p_draft_id and user_id = u and status not in ('published');

  return found;
end;
$$;
revoke all on function public.set_draft_status(uuid, text) from public;
grant execute on function public.set_draft_status(uuid, text) to authenticated;