-- KLAY K · fecha `anon` nas funções novas de Marketplace e Controles Familiares
--
-- Todas essas funções já exigem sessão: cada uma começa com
--
--   if v_me is null then raise exception 'auth_required'; end if;
--
-- Então o papel `anon` (sem JWT) só consegue provoke um erro — nunca fazer
-- nada. Mas deixar `SECURITY DEFINER` executável por papel anônimo é
-- superfície que não precisa existir: é o tipo de coisa que vira brecha quando
-- alguém edita a função depois sem olhar os privilégios.
--
-- É o mesmo tratamento já aplicado em `increment_post_share`
-- (20261012120000) e `record_post_view` (20261015120000).
--
-- Nenhuma funcionalidade se perde: o app KLAY K sempre tem sessão —
-- `ensureAuthenticated()` faz `signInAnonymously()`, ou seja, o visitante sem
-- cadastro tem role `authenticated` com JWT válido, não é `anon`.

-- Controles familiares
revoke execute on function public.family_time_limit_status(uuid) from anon;
revoke execute on function public.family_set_time_limit(uuid, integer, time, time, boolean, text) from anon;
revoke execute on function public.family_usage_tick() from anon;
revoke execute on function public.family_activity_report(uuid, integer) from anon;
revoke execute on function public.request_follow(uuid) from anon;
revoke execute on function public.respond_follow_request(uuid, boolean) from anon;
revoke execute on function public.is_active_guardian_of(uuid, uuid) from anon;

-- Marketplace
revoke execute on function public.store_publish_product(text, numeric, integer, text, uuid, text[], text, text[], text, text) from anon;
revoke execute on function public.store_toggle_favorite(uuid) from anon;

-- Fecha também o EXECUTABLE BY PUBLIC, que o Postgres cria por padrão, e
-- reescreve o privilégio só para `authenticated`.
revoke execute on function public.family_time_limit_status(uuid) from public;
revoke execute on function public.family_set_time_limit(uuid, integer, time, time, boolean, text) from public;
revoke execute on function public.family_usage_tick() from public;
revoke execute on function public.family_activity_report(uuid, integer) from public;
revoke execute on function public.request_follow(uuid) from public;
revoke execute on function public.respond_follow_request(uuid, boolean) from public;
revoke execute on function public.is_active_guardian_of(uuid, uuid) from public;
revoke execute on function public.store_publish_product(text, numeric, integer, text, uuid, text[], text, text[], text, text) from public;
revoke execute on function public.store_toggle_favorite(uuid) from public;

grant execute on function public.family_time_limit_status(uuid) to authenticated;
grant execute on function public.family_set_time_limit(uuid, integer, time, time, boolean, text) to authenticated;
grant execute on function public.family_usage_tick() to authenticated;
grant execute on function public.family_activity_report(uuid, integer) to authenticated;
grant execute on function public.request_follow(uuid) to authenticated;
grant execute on function public.respond_follow_request(uuid, boolean) to authenticated;
grant execute on function public.is_active_guardian_of(uuid, uuid) to authenticated;
grant execute on function public.store_publish_product(text, numeric, integer, text, uuid, text[], text, text[], text, text) to authenticated;
grant execute on function public.store_toggle_favorite(uuid) to authenticated;
