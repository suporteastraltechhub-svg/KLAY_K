-- KLAY K · curtidas em comentário + paginação de comentários
--
-- Fecha três lacunas reais encontradas na auditoria:
--
--  1. "Curtir comentário" só mudava o objeto em memória — nunca era gravado.
--     Aqui entra a tabela `comment_likes` + contador `comments.likes_count`
--     mantido por trigger (o mesmo padrão já usado em `post_likes`/`posts`).
--
--  2. Não havia paginação: `fetchComments` cortava em 200 linhas fixas.
--     A coluna não muda nada no schema, mas a query passa a aceitar
--     `offset`/`limit` no cliente (mudança só em Dart).
--
--  3. Threads: a coluna `comments.parent_id` já existia, mas a UI nunca
--     enviava o valor, então "responder" não criava vínculo. Nenhuma mudança
--     de schema é necessária aqui — só o cliente passa a enviar. O índice
--     abaixo é para a leitura de respostas por comentário.
--
-- Nenhuma escrita é liberada direto ao cliente: o usuário só insere/deleta a
-- PRÓPRIA curtida, e o contador é do trigger. Sem UPDATE liberado (ninguém
-- precisa "editar" uma curtida).

-- 1) Contador no comentário
alter table public.comments
  add column if not exists likes_count int not null default 0;

-- 2) Tabela de curtidas
create table if not exists public.comment_likes (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create index if not exists comment_likes_user_idx
  on public.comment_likes (user_id, created_at desc);

-- Leitura de "quais comentários eu já curti" no carregamento da lista
create index if not exists comment_likes_comment_idx
  on public.comment_likes (comment_id);

-- Respostas de um comentário: usa o índice do parent_id
create index if not exists comments_parent_id_idx
  on public.comments (parent_id)
  where parent_id is not null;

alter table public.comment_likes enable row level security;

-- Qualquer um pode VER curtidas (contador público, como likes de post)
drop policy if exists "comment_likes_select_all" on public.comment_likes;
create policy "comment_likes_select_all"
  on public.comment_likes for select
  using (true);

-- Só a PRÓPRIA curtida pode ser criada
drop policy if exists "comment_likes_insert_own" on public.comment_likes;
create policy "comment_likes_insert_own"
  on public.comment_likes for insert
  with check (auth.uid() = user_id);

-- Só a PRÓPRIA curtida pode ser removida
drop policy if exists "comment_likes_delete_own" on public.comment_likes;
create policy "comment_likes_delete_own"
  on public.comment_likes for delete
  using (auth.uid() = user_id);

-- 3) Trigger do contador — espelha touch_post_like_count
create or replace function public.touch_comment_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.comments
       set likes_count = likes_count + 1
     where id = new.comment_id;
    return new;
  else
    update public.comments
       set likes_count = greatest(likes_count - 1, 0)
     where id = old.comment_id;
    return old;
  end if;
end;
$$;

drop trigger if exists comment_likes_count on public.comment_likes;
create trigger comment_likes_count
  after insert or delete on public.comment_likes
  for each row execute function public.touch_comment_like_count();

-- 4) Garante que o contador nasce correto para quem já tem dados
update public.comments c
   set likes_count = coalesce(
     (select count(*) from public.comment_likes cl where cl.comment_id = c.id), 0);