-- KLAY K - Corrigir DEFAULT de `follows.id` para permitir INSERT do app.
--
-- A migration 20260828000000_fix_follows.sql adicionou `id uuid` com PK e
-- NOT NULL, mas SEM `default gen_random_uuid()`. Resultado: qualquer INSERT
-- na tabela `follows` (seguir usuário pelo app) falha com
--   null value in column "id" of relation "follows" violates not-null constraint
-- corrigido aqui de forma idempotente.
alter table public.follows
  alter column id set default gen_random_uuid();