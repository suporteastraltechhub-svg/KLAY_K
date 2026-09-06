-- KLAY K - Corrigir trigger de criação de perfil
--
-- O template original criou `profiles.id` com FK apontando para `auth.users(id)`
-- e a triggers `handle_new_user` rodava em `BEFORE INSERT on auth.users`. Com
-- uma FK auto-referenciada, uma trigger BEFORE falha: a linha em `auth.users`
-- ainda não foi comprometida quando o `insert into public.profiles` checa a FK →
-- erro 23503 "not present in table users". Isso quebrava TODO signup (email e
-- anônimo).
--
-- Correção: rodar a trigger em `AFTER INSERT`, quando a linha em `auth.users`
-- já existe e a FK é válida. Idempotente.

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
