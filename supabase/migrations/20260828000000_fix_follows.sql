-- KLAY K - Corrigir estrutura da tabela `follows`
--
-- O projeto já veio com uma tabela `follows` (colunas follower_id,
-- following_id, created_at) SEM coluna `id`. Esta migration corrige a estrutura
-- adicionando `id uuid` como chave primária e demais reforços — tudo de forma
-- idempotente e sem descartar dados existentes.

create extension if not exists pgcrypto;

do $$
declare
  has_id boolean;
  has_pk boolean;
  has_unique boolean;
begin
  -- 1) Coluna `id uuid` apenas se ainda não existir.
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'follows' and column_name = 'id'
  ) into has_id;

  if not has_id then
    execute 'alter table public.follows add column id uuid';
    execute 'update public.follows set id = gen_random_uuid() where id is null';
    execute 'alter table public.follows alter column id set not null';
  end if;

  -- 2) Primary key sobre `id` apenas se a tabela ainda não tiver uma.
  select exists (
    select 1 from pg_constraint
    where conrelid = 'public.follows'::regclass and contype = 'p'
  ) into has_pk;

  if not has_pk then
    execute 'alter table public.follows add constraint follows_pkey primary key (id)';
  end if;

  -- 3) Índices para consultas por quem segue / quem é seguido.
  execute 'create index if not exists follows_follower_idx on public.follows (follower_id)';
  execute 'create index if not exists follows_following_idx on public.follows (following_id)';

  -- 4) Remove apenas duplicatas exatas de seguidor/seguido (mantém o primeiro)
  --    para permitir a constraint única sem quebrar dados.
  execute 'delete from public.follows a using public.follows b
           where a.ctid < b.ctid
             and a.follower_id is not distinct from b.follower_id
             and a.following_id is not distinct from b.following_id';

  -- 5) Garante que cada par (follower_id, following_id) seja único.
  select exists (
    select 1 from pg_constraint
    where conrelid = 'public.follows'::regclass and contype = 'u'
  ) into has_unique;

  if not has_unique then
    execute 'alter table public.follows
             add constraint follows_follower_following_key unique (follower_id, following_id)';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Row Level Security para a tabela follows
-- ---------------------------------------------------------------------------
alter table public.follows enable row level security;

drop policy if exists "follows_select_all" on public.follows;
drop policy if exists "follows_insert_owner" on public.follows;
drop policy if exists "follows_delete_owner" on public.follows;

create policy "follows_select_all" on public.follows for select using (true);
create policy "follows_insert_owner" on public.follows for insert
  with check (auth.uid() = follower_id);
create policy "follows_delete_owner" on public.follows for delete
  using (auth.uid() = follower_id);