-- SEGURANÇA (ajuste): os grants de `public.profiles` são em NÍVEL DE TABELA
-- (via default privileges do Supabase). Revogar apenas colunas (is_admin/
-- is_verified) não vence o privilégio de tabela — o próprio usuário conseguia
-- `PATCH .../profiles` com {"is_admin": true} (escalação comprovada em E2E).
--
-- Aqui: revoga-se INSERT/UPDATE/DELETE de tabela para anon/authenticated e
-- reconcede-se APENAS as colunas que o APP realmente grava no perfil.
-- SELECT continua integral (leitura pública do perfil). Flags sensíveis
-- (is_admin, is_verified, counts) ficam restritas a RPCs security definer.

revoke insert, update, delete on table public.profiles from anon, authenticated;
revoke insert, update, delete on table public.profiles from public;

grant select on table public.profiles to anon, authenticated;

-- Colunas de INSERT usadas pelo app (ex.: _syncIdentity no primeiro login).
grant insert (
  id, display_name, username, avatar_url, avatar_path, bio, is_private
) on table public.profiles to authenticated;

-- Colunas de UPDATE usadas por "Editar perfil" / identidade (NUNCA flags).
grant update (
  display_name, username, avatar_url, avatar_path, bio, is_private
) on table public.profiles to authenticated;

-- Manutenção da column-level revoke (documental; o gate real é o acima).
revoke update (is_admin) on table public.profiles from anon, authenticated;
revoke insert (is_admin) on table public.profiles from anon, authenticated;
revoke update (is_verified) on table public.profiles from anon, authenticated;
revoke insert (is_verified) on table public.profiles from anon, authenticated;