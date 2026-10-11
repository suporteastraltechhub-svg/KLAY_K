-- KLAY K · correção da vulnerabilidade em `increment_post_share`
--
-- ---------------------------------------------------------------------------
-- O PROBLEMA
-- ---------------------------------------------------------------------------
-- `increment_post_share` foi criada em `20261010120000_post_views_and_shares.sql`
-- como `security definer` (portanto ignora RLS) e recebeu
--
--     grant execute on function public.increment_post_share(uuid)
--       to authenticated, anon;
--
-- sem NENHUMA verificação de `auth.uid()`. Como é `security definer`, o
-- `UPDATE posts SET shares_count = shares_count + 1` escrevia em qualquer post,
-- para qualquer pessoa — inclusive visitante deslogado chamando a RPC por
-- `curl`. Bastava repetir a chamada em laço para inflar o contador de
-- compartilhamentos de qualquer vídeo.
--
-- A função irmã `record_post_view` já estava correta: tem
-- `if v_user is null then return;`. Share ficou sem o mesmo guarda.
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO
-- ---------------------------------------------------------------------------
-- 1. Guarda de autenticação: sessão anônima (role `anon` E conta
--    `auth.users.is_anonymous`) não altera nada.
-- 2. Anti-abuso no próprio banco: uma vez por usuário, por post, por hora.
--    Só o login derruba a barreira do `anon`; sem isso, qualquer conta
--    gratuita viraria bot debageador de `shares_count`.
-- 3. `anon` perde o `EXECUTE`. `revoke ... from public` cobre o default do
--    Postgres (EXECUTABLE BY PUBLIC), que é o furo mais comum.
-- 4. `search_path` já estava correto; mantido.
--
-- ---------------------------------------------------------------------------
-- IMPACTO NO APP
-- ---------------------------------------------------------------------------
-- `ContentService.incrementShare` (content_service.dart) continua igual: o
-- `_countShare` do feed já incrementa o número na TELA antes de chamar a RPC
-- (`setState(() => widget.video.shares++)`), então o visitante deslogado
-- continua vendo o número subir. O que deixa de acontecer é a gravação no banco
-- por quem não tem conta — que é o comportamento correto. Para autenticados,
-- a RPC funciona como antes, com o adicional do teto anti-abuso.
--
-- Não é regressão: nenhum recurso de UI depende do share anônimo persistido.

-- ---------------------------------------------------------------------------
-- 1) Guarda + limite de abuso
-- ---------------------------------------------------------------------------

create table if not exists public.share_events (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id, created_at)
);

-- Índice do teto: só conta os eventos da última hora.
create index if not exists share_events_hour_idx
  on public.share_events (post_id, user_id, created_at desc);

alter table public.share_events enable row level security;

-- Sem policy de select: o usuário não precisa ler nada, e a tabela existe
-- só como contador. O RPC é `security definer` e enxerga tudo.
drop policy if exists "share_events_select_all" on public.share_events;

create or replace function public.increment_post_share(p_post_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_anon_auth boolean := false;
  v_recent int;
  v_count int;
begin
  -- Bloqueio 1: role `anon` (sem JWT). Nunca grava.
  --
  -- Bloqueio 2: sessão anônima do próprio app.
  --
  -- Isto é o detalhe que faz o `revoke ... from anon` sozinho NÃO bastar:
  -- `SupabaseService.ensureAuthenticated()` chama `signInAnonymously()` para o
  -- visitante que não fez cadastro. Essa sessão tem role `authenticated` (JWT
  -- válido, `auth.uid()` não-nulo) — é exatamente a conta que o app cria para
  -- quem assiste sem login. Sem checar `auth.users.is_anonymous`, esse visitante
  -- passaria pelo bloqueio 1 e ainda poderia inflar o contador. Conferido no
  -- banco: a coluna `auth.users.is_anonymous` existe (boolean).
  --
  -- together: só conta CONTA REAL. Um compartilhamento é métrica de conteúdo;
  -- não faz sentido que uma sessão descartável a altere.
  if v_user is null then
    select coalesce(shares_count, 0) into v_count
      from public.posts
     where id = p_post_id;
    return coalesce(v_count, 0);
  end if;

  select coalesce(u.is_anonymous, false) into v_anon_auth
    from auth.users u
   where u.id = v_user;

  if v_anon_auth then
    select coalesce(shares_count, 0) into v_count
      from public.posts
     where id = p_post_id;
    return coalesce(v_count, 0);
  end if;

  if not exists (select 1 from public.posts where id = p_post_id) then
    return 0;
  end if;

  -- Teto anti-abuso: uma contagem por usuário, por post, por hora.
  select count(*) into v_recent
    from public.share_events
   where post_id = p_post_id
     and user_id = v_user
     and created_at > now() - interval '1 hour';

  if v_recent >= 1 then
    select coalesce(shares_count, 0) into v_count
      from public.posts
     where id = p_post_id;
    return coalesce(v_count, 0);
  end if;

  insert into public.share_events (post_id, user_id)
  values (p_post_id, v_user);

  update public.posts
     set shares_count = shares_count + 1
   where id = p_post_id
  returning shares_count into v_count;

  return coalesce(v_count, 0);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Privilégio de execução
-- ---------------------------------------------------------------------------

-- `anon` não executa mais.
revoke execute on function public.increment_post_share(uuid) from anon;

-- Fecha também o default do Postgres (EXECUTABLE BY PUBLIC) e reescreve
-- apenas para `authenticated`.
revoke execute on function public.increment_post_share(uuid) from public;
grant execute on function public.increment_post_share(uuid) to authenticated;

-- Limpeza de registros antigos, para a tabela não crescer sem parar.
-- Mantida em SECURITY DEFINER e sem policy: só o dono do banco agenda.
create or replace function public.prune_share_events()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  delete from public.share_events where created_at < now() - interval '24 hours';
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.prune_share_events() from public, anon, authenticated;
grant execute on function public.prune_share_events() to service_role;
