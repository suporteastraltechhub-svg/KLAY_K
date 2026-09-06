-- SEGURANÇA: impede escalação de privilégio via PostgREST.
--
-- As colunas `profiles.is_admin` e `profiles.is_verified` são flags de
-- confiança/role e SÓ podem ser alteradas por RPCs `security definer` (que
-- re-validam `is_klayk_admin()` no backend) ou pelo dono do banco.
--
-- Anteriormente `update`/`insert` eram concedidos a `anon`/`authenticated`,
-- e a policy `profiles_update_owner using (auth.uid() = id)` permitia que o
-- próprio usuário fizesse `PATCH .../profiles?id=eq.<seu_id>` com
-- `{"is_admin": true}` — escalação comprovada em teste E2E (status 200).
--
-- Aqui revogamos apenas essas colunas. O `SELECT` é mantido (o app lê
-- `is_admin`/`is_verified`), e a edição das demais colunas do perfil
-- (display_name, username, bio, avatar) continua permitida ao dono.

revoke update (is_admin) on table public.profiles from anon, authenticated;
revoke insert (is_admin) on table public.profiles from anon, authenticated;
revoke update (is_verified) on table public.profiles from anon, authenticated;
revoke insert (is_verified) on table public.profiles from anon, authenticated;

-- Bootstrapping do primeiro admin continua disponível apenas para o dono do
-- banco (SQL editor / Migration) ou via RPCs security definer (gift-admin,
-- admin_set_admin) que exigem is_klayk_admin().