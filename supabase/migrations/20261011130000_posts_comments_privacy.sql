-- KLAY K · privacidade de publicações e comentários
--
-- Migration INDEPENDENTE e idempotente. Contém SOMENTE a correção de
-- visibilidade de `posts` e `comments` — não toca notificações, silêncios,
-- carteira, moedas, pagamentos, pedidos nem qualquer outra tabela.
--
-- A parte de notificações/`muted_users` continua isolada em
-- `20261011120000_rls_hardening.sql`, que pode ser aplicada depois.
--
-- ===========================================================================
-- O QUE ESTAVA ERRADO
-- ===========================================================================
--
-- `posts_select_all` foi criada em `20260828020000_content.sql` como
--   for select using (true)
-- ou seja, TODO post era legível por qualquer pessoa, inclusive por
-- anônimo. A opção "conta privada" grava em `profiles.is_private`
-- (`20260828040000`, linha 8) e é sincronizada por
-- `AccountService.saveSettings` (account_service.dart:308) — mas nunca foi
-- consultada em nenhuma policy. O botão existia e não fazia nada.
--
-- `comments_select_all` foi redefinida em `20260831010000_klay_security_max`
-- (linha 213) apenas para esconder comentários com `hidden`:
--   using (not (hidden and not public.has_perm('moderation')))
-- Ela não considerava a privacidade do post, então comentário de post privado
-- continuava legível.
--
-- ===========================================================================
-- MODELO DE VISIBILIDADE (o mesmo do aplicativo)
-- ===========================================================================
--
-- O KLAY K **não tem pedido de seguimento**: `follows` é direto, criado no
-- follow e removido no unfollow, com unique em `(follower_id, following_id)`
-- (`20260828000000_fix_follows`). Não existe `follow_requests`, nem estado
-- `pending`/`accepted` para respeitar. Logo, "seguidor" = existe linha em
-- `follows`, e é isso que a policy consulta.
--
--   público ............ todo mundo lê, inclusive anônimo
--   privado + dono ...... o próprio autor lê
--   privado + seguidor .. quem tem linha em `follows` lê
--   privado + terceiros . ninguém lê
--
-- ===========================================================================
-- 1) COLUNA DENORMALIZADA
-- ===========================================================================
--
-- `posts` é a tabela mais lida do app (feed, perfil, busca, hashtag). Uma
-- policy com subselect em `profiles` por linha custaria caro em toda leitura
-- de feed, então a privacidade é copiada para `posts.is_private` e mantida por
-- trigger. Assim a policy lê uma coluna indexada, sem N+1 em SQL.

alter table public.posts
  add column if not exists is_private boolean not null default false;

-- ===========================================================================
-- 2) SINCRONIZAÇÃO
-- ===========================================================================
--
-- BEFORE INSERT: o valor gravado é SEMPRE o de `profiles`, nunca o que o
-- cliente enviou. Sem isso, um post publicado enquanto a conta já é privada
-- nasceria `false` e vazaria. `security definer` para ler `profiles`
-- independentemente da RLS de quem publica.

create or replace function public.sync_post_is_private()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(p.is_private, false) into new.is_private
    from public.profiles p
   where p.id = new.user_id;

  if new.is_private is null then
    new.is_private := false;
  end if;

  return new;
end;
$$;

drop trigger if exists posts_is_private_bi on public.posts;
create trigger posts_is_private_bi
  before insert on public.posts
  for each row execute function public.sync_post_is_private();

-- BEFORE UPDATE: mesma ideia, mas para o caminho de escrita.
--
-- POR QUE UM TRIGGER E NÃO SÓ `REVOKE UPDATE (is_private)`:
--
-- O `revoke` de coluna NÃO é suficiente em `posts`, e isso é verificável no
-- banco. O ACL das duas tabelas é diferente:
--
--   profiles: authenticated=rDxtm    (sem 'w' — não há UPDATE de tabela)
--   posts:    authenticated=arwdDxtm (com 'w' — há UPDATE de tabela)
--
-- No Postgres, um GRANT de privilégio no nível da TABELA implica o privilégio
-- em todas as colunas, e um `REVOKE` no nível da COLUNA não o remove. Como
-- `posts` tem UPDATE de tabela, `revoke update (is_private)` deixa a coluna
-- gravável — confirmado com `has_column_privilege(...,'is_private','UPDATE')`,
-- que continua devolvendo `true` depois do revoke.
--
-- (É por isso que `20260829120000_revoke_admin_flags.sql` funciona em
-- `profiles`: lá não existe UPDATE de tabela, só concessões por coluna, então
-- o revoke de coluna realmente remove o privilégio.)
--
-- Trigger BEFORE UPDATE não depende de ACL: ele roda para qualquer papel e só
-- o dono da tabela pode desabilitá-lo. É o que realmente fecha a brecha.
--
-- Não há recursão: `new.is_private` é sobrescrito a partir de `profiles`, e
-- `profiles` não é alterado por este trigger.

create or replace function public.sync_post_is_private_on_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_private boolean;
begin
  select coalesce(p.is_private, false) into v_profile_private
    from public.profiles p
   where p.id = new.user_id;

  if new.is_private is distinct from v_profile_private then
    new.is_private := v_profile_private;
  end if;

  return new;
end;
$$;

drop trigger if exists posts_is_private_bu on public.posts;
create trigger posts_is_private_bu
  before update on public.posts
  for each row execute function public.sync_post_is_private_on_update();

-- AFTER UPDATE em profiles: mudar a conta para privada/esquecer reflete nos
-- posts já publicados. Não há recursão — o UPDATE em `posts` dispara
-- `posts_is_private_bu`, que relê `profiles`; neste ponto `profiles` JÁ está
-- com o valor novo, então o trigger confirma o mesmo valor e não há ciclo.
-- A função é `security definer`, então o UPDATE em `posts` não passa pela RLS
-- (evita o ciclo RLS → profiles → RLS).

create or replace function public.propagate_profile_is_private()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_private is distinct from old.is_private then
    update public.posts
       set is_private = new.is_private
     where user_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_is_private_au on public.profiles;
create trigger profiles_is_private_au
  after update of is_private on public.profiles
  for each row execute function public.propagate_profile_is_private();

-- Alinha o que já existe. Idempotente: rodar de novo não muda nada.
update public.posts p
   set is_private = coalesce(pr.is_private, false)
  from public.profiles pr
 where pr.id = p.user_id
   and p.is_private is distinct from coalesce(pr.is_private, false);

-- Caminho quente do feed: público, ordenado por data. Índice parcial, então
-- posts privados não inflam o índice.
create index if not exists posts_public_feed_idx
  on public.posts (created_at desc)
  where is_private = false;

-- ===========================================================================
-- 3) POLÍTICA DE LEITURA DE POSTS
-- ===========================================================================

drop policy if exists "posts_select_all" on public.posts;
drop policy if exists "posts_select_visible" on public.posts;

create policy "posts_select_visible"
  on public.posts
  for select
  using (
    is_private = false
    or user_id = auth.uid()
    or exists (
      select 1
        from public.follows f
       where f.follower_id = auth.uid()
         and f.following_id = posts.user_id
    )
  );

-- Leitura/escrita do dono continua como estava (`posts_insert_owner`,
-- `posts_update_owner`, `posts_delete_owner` em `20260828020000_content.sql`
-- e `20260901010000_content_owner_edit_delete.sql`) — esta migration não
-- altera nenhuma delas.

-- ===========================================================================
-- 4) COMMENTS HERDAM A VISIBILIDADE DO POST
-- ===========================================================================
--
-- A policy anterior continuava válida para comentários ocultos e é preservada.
-- O `exists` em `posts` reaproveita a RLS de `posts`: em Postgres a RLS da
-- tabela referenciada dentro de uma policy também vale para o usuário que
-- consulta, então comentário de post privado desaparece junto sem duplicar a
-- expressão de visibilidade (e sem um segundo subselect em `profiles`).

drop policy if exists "comments_select_all" on public.comments;

create policy "comments_select_all"
  on public.comments
  for select
  using (
    not (hidden and not public.has_perm('moderation'))
    and exists (
      select 1
        from public.posts p
       where p.id = comments.post_id
    )
  );

-- ===========================================================================
-- 5) LIMITAÇÕES CONHECIDAS
-- ===========================================================================
--
-- * O cliente Flutter (`UserProfileScreen._canSeeVideos`) também esconde os
--   vídeos na interface. Isso é conveniência, não segurança: a proteção real
--   é a policy acima. Se os dois divergirem, quem decide é o banco.
--
-- * `force row level security` NÃO foi aplicado em `posts`: FORCE RLS passa a
--   valer também para o dono da tabela e quebraria `delete_post`,
--   `admin_delete_post` e os triggers de contagem, que rodam como owner.
--
-- * RPCs `security definer` que já existiam (`delete_post`, `edit_comment`,
--   `update_post`, contadores) continuam ignorando RLS por design — é o que
--   permite ao dono apagar o próprio conteúdo.
--
-- * Perfis e listas de seguidores continuam públicos (`profiles_select_all`
--   e `follows_select_all`): ver quem segue quem é escolha de produto do
--   KLAY K, não um dado sensível. Só o CONTEÚDO da conta privada é protegido.

-- ===========================================================================
-- 7) PROTEÇÃO DA COLUNA
-- ===========================================================================
--
-- Defense in depth. ATENÇÃO: sozinho este `revoke` NÃO fecha a brecha em
-- `posts` — o ACL da tabela tem UPDATE no nível de tabela (`arwdDxtm`), e no
-- Postgres isso implica UPDATE em todas as colunas, sobrepondo o revoke de
-- coluna. O que de fato impede o `PATCH {"is_private": false}` é o trigger
-- BEFORE UPDATE `posts_is_private_bu` (seção 2).
--
-- O comando é mantido porque passa a valer se o UPDATE de tabela for removido
-- no futuro, e porque em `profiles` (que só tem UPDATE por coluna) o mesmo
-- padrão é o que realmente protege `is_admin`/`is_verified`.
--
-- Quem continua able de mudar a privacidade:
--   * `AccountService.updateProfile` / `ProfileService.saveSettings` → UPDATE em
--     `profiles.is_private` (permitido ao dono) → dispara
--     `profiles_is_private_au` → atualiza os posts.
--   * `update_post` (RPC `security definer`, revogada de public/anon) — roda
--     como dono do banco.
--
revoke update (is_private) on public.posts from anon, authenticated;
