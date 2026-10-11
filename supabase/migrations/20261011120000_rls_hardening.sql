-- KLAY K · hardening de RLS (notificações e silêncios)
--
-- Migration INDEPENDENTE e idempotente. Contém SOMENTE:
--   1. anti-impersonação na inserção de notificações
--   2. privacidade da lista de silêncios (muted_users)
--
-- NÃO toca `posts` nem `comments` — a privacidade de publicações está isolada
-- em `20261011130000_posts_comments_privacy.sql`, que pode ser aplicada antes
-- ou depois desta.
--
-- ===========================================================================
-- AUDITORIA: o que JÁ estava correto e NÃO foi tocado
-- ===========================================================================
--
--   * `user_wallets` / `credit_transactions`: só `select` do dono +
--     `revoke insert, update, delete` (20260901020000).
--   * `financial_orders` / `financial_payments`: `select` do próprio usuário.
--   * `verification_requests`: update restrito a `service_role`
--     (20260830040000), então o app não consegue se autoaprovar.
--   * `reports`: leitura do autor + admin; update só admin
--     (20260828090000).
--   * `anti_spam_rules`: mantido legível — `SocialService.loadSpamRules`
--     (social_service.dart:797) usa as regras para filtro local no cliente.
--     Fechar isso quebraria a proteção contra spam.
--
-- ===========================================================================

-- ===========================================================================
-- 1) NOTIFICATIONS · anti-impersonação e tipos permitidos
-- ===========================================================================
--
-- `notifications_insert_service` foi criada em `20260828020000_content.sql`
-- como `for insert with check (true)`: qualquer usuário autenticado inseria
-- notificação na caixa de QUALQUER pessoa, com `actor_id` forjado. Permitia
-- falsificar "X te seguiu", "X te deu um presente" e o tipo `verification`,
-- além de inundar a caixa alheia.
--
-- Não pode ser `user_id = auth.uid()`: o app precisa notificar OUTRA pessoa
-- (curtir, comentar, seguir, mensagem). O que não pode é forjar o autor nem
-- inventar tipo. Todos os inserts reais do app passam o usuário autenticado
-- como `actor_id` — conferido nos 8 call sites (content_service:740/922/1001,
-- supabase_service:298/605, message_service:181, game_service:211/221,
-- start_live_screen:763).

drop policy if exists "notifications_insert_service" on public.notifications;
drop policy if exists "notifications_insert_own_actor" on public.notifications;

create policy "notifications_insert_own_actor"
  on public.notifications
  for insert
  with check (
    actor_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and type = any (array[
      'like', 'comment', 'comment_reply', 'mention', 'share', 'follow',
      'message', 'live', 'live_viewer', 'live_end', 'record', 'reward',
      'gift', 'sale', 'verification', 'hashtag', 'post', 'user', 'news'
    ])
    and coalesce(length(message), 0) <= 300
    and coalesce(length(ref_id), 0) <= 120
  );

-- ===========================================================================
-- 2) MUTED_USERS · "quem silenciou quem" é privado
-- ===========================================================================
--
-- `muted_select_all` era `using (true)`, expondo a lista de silenciamentos de
-- todo mundo. `SocialService.isMuted` (social_service.dart:700) consulta
-- sempre com `muter_id = usuário atual`, então restricting ao dono não quebra.

drop policy if exists "muted_select_all" on public.muted_users;
drop policy if exists "muted_select_owner" on public.muted_users;

create policy "muted_select_owner"
  on public.muted_users
  for select
  using (muter_id = auth.uid());

-- ===========================================================================
-- LIMITAÇÕES CONHECIDAS
-- ===========================================================================
--
-- * Limite de taxa em notificações não é possível em RLS puro (precisa de RPC
--   `security definer` com contagem). O que fecha aqui é a impersonação e o
--   tipo forjado; flood ainda precisa da RPC.
--
-- * Nenhuma policy aqui é `force row level security`: FORCE RLS passa a valer
--   também para o dono da tabela e quebraria funções `security definer` que
--   já existem. `service_role` já ignora RLS.