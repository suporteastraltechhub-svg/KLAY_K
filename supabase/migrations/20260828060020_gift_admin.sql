-- KLAY K - Campo de administrador no perfil (controle de acesso ao catálogo).
-- O guardião de acesso é o próprio banco/backend: só usuários com is_admin = true
-- têm permissão executar operações de escrita do catálogo (obrigatoriamente via
-- Edge Function gift-admin, que valida este flag com o service role).
alter table public.profiles
  add column if not exists is_admin boolean not null default false;
