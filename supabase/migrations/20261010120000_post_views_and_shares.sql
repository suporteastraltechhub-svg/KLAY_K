-- KLAY K · visualizações e compartilhamentos reais
--
-- Fecha duas lacunas encontradas na auditoria do feed:
--
--  1. VISUALIZAÇÕES NUNCA ERAM GRAVADAS
--     `posts.views_count` existe desde `20260828100000_levels_missions.sql` mas
--     não havia trigger nem chamada: o número não subia. `SocialService
--     .recordHistory` existia e não era chamada por ninguém. O Creator Dashboard
--     lia a coluna e ficava sempre em zero.
--
--  2. COMPARTILHAMENTO ERA VOLÁTIL
--     `posts.shares_count` não tem trigger. O app fazia
--     `setState(() => video.shares++)` — só mudava o objeto em memória e
--     sumia ao sair da tela. `likes_count` e `comments_count` já eram mantidos
--     por trigger; aqui o compartilhamento passa a ter o mesmo tratamento.
--
-- Semântica da visualização: UMA visualização por pessoa por vídeo.
-- `user_history` já tem `unique (user_id, post_id, live_id, ref_type)`, então
-- reassistir não infla o número — e ninguém consegue maquiar o contador
-- pulando o mesmo vídeo mil vezes.
--
-- ATENÇÃO ao schema: `public.posts` NÃO tem coluna `status` (conferido em
-- `20260828020000_content.sql` e nos `alter table` posteriores), por isso as
-- funções não filtram por status — só pelo id, que já é a chave do post.
--
-- Ambas são `security definer`: o cliente nunca escreve direto em `posts` e a
-- RLS de escrita da tabela continua fechada.

-- ---------------------------------------------------------------------------
-- 1) Visualização
-- ---------------------------------------------------------------------------
create or replace function public.record_post_view(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_author uuid;
  v_seen boolean := false;
begin
  -- Visitante anônimo: não grava histórico nem stat. Evita inflar o número
  -- sem identidade, já que `user_history.user_id` é obrigatório.
  if v_user is null then
    return;
  end if;

  select user_id into v_author
    from public.posts
   where id = p_post_id;

  if v_author is null then
    return;
  end if;

  select exists (
    select 1 from public.user_history
     where user_id = v_user and post_id = p_post_id and ref_type = 'post'
  ) into v_seen;

  if v_seen then
    -- Reassistiu: só refresca quando viu, não conta de novo.
    update public.user_history
       set watched_at = now()
     where user_id = v_user and post_id = p_post_id and ref_type = 'post';
    return;
  end if;

  insert into public.user_history (user_id, post_id, ref_type, watched_at)
  values (v_user, p_post_id, 'post', now())
  on conflict (user_id, post_id, live_id, ref_type) do update
    set watched_at = now();

  update public.posts
     set views_count = views_count + 1
   where id = p_post_id;

  -- Stat do AUTOR do vídeo (coluna `total_views` de `user_stats`).
  update public.user_stats
     set total_views = total_views + 1
   where user_id = v_author;
end;
$$;

grant execute on function public.record_post_view(uuid) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 2) Compartilhamento
-- ---------------------------------------------------------------------------
create or replace function public.increment_post_share(p_post_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if not exists (select 1 from public.posts where id = p_post_id) then
    return 0;
  end if;

  update public.posts
     set shares_count = shares_count + 1
   where id = p_post_id
  returning shares_count into v_count;

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.increment_post_share(uuid) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 3) Índice do histórico por vídeo
-- ---------------------------------------------------------------------------
-- `record_post_view` consulta o histórico por (usuário, vídeo); sem este índice
-- cada visualização vira uma varredura da tabela.
create index if not exists user_history_post_idx
  on public.user_history (post_id)
  where ref_type = 'post';