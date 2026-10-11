-- KLAY K · `record_post_view` deixa de ser executável por `anon`
--
-- Mesma classe de correção aplicada em `increment_post_share`
-- (`20261012120000`), que já revogou `anon` e `public`.
--
-- `record_post_view` é `security definer` e TEM guarda de `auth.uid()`:
--
--   v_user uuid := auth.uid();
--   if v_user is null then return; end if;
--
-- Então o papel `anon` nunca conseguiu alterar nada — a chamada só retornava
-- cedo. Ainda assim, deixar uma função `security definer` (que ignora RLS)
-- na lista de executáveis do `anon` é superfície que não precisa existir: um
-- `security definer` executável por papel anônimo é o tipo de coisa que vira
-- brecha quando alguém edita a função sem olhar os privilégios.
--
-- Nenhuma functionality se perde:
--   * O app KLAY K sempre tem sessão: `ensureAuthenticated()` faz
--     `signInAnonymously()`, ou seja, o visitante sem cadastro tem role
--     `authenticated` com JWT válido — não é `anon`.
--   * `ContentService.recordPostView` engole a exceção
--     (`try { ... } catch (_) {}`) e retorna void, então mesmo uma falha de
--     permissão não vira erro visível nem crash.
--   * `public` também perde o privilégio, fechando o EXECUTABLE BY PUBLIC que
--     o Postgres cria por padrão.

revoke execute on function public.record_post_view(uuid) from anon;
revoke execute on function public.record_post_view(uuid) from public;
grant execute on function public.record_post_view(uuid) to authenticated;