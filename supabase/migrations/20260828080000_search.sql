-- ============================================================================
-- Busca: histórico de buscas persistido + tendências de hashtags (backend real)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- search_history: histórico real de buscas por usuário (uma linha por termo,
-- atualizada em touched_at; usado para "recentes").
-- ---------------------------------------------------------------------------
create table if not exists public.search_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  query text not null,
  result_type text not null default 'all',
  touched_at timestamptz not null default now()
);

-- índice único funcional em (user_id, lower(query), result_type)
drop index if exists search_history_user_query_key;
create unique index search_history_user_query_key
  on public.search_history (user_id, lower(query), result_type);

create index if not exists search_history_user_idx
  on public.search_history (user_id, touched_at desc);

alter table public.search_history enable row level security;

drop policy if exists "search_history_select_owner" on public.search_history;
drop policy if exists "search_history_insert_owner" on public.search_history;
drop policy if exists "search_history_delete_owner" on public.search_history;
create policy "search_history_select_owner"
  on public.search_history for select using (user_id = auth.uid());
create policy "search_history_insert_owner"
  on public.search_history for insert with check (user_id = auth.uid());
create policy "search_history_delete_owner"
  on public.search_history for delete using (user_id = auth.uid());

-- update das próprias linhas (touched_at) permitido ao dono
drop policy if exists "search_history_update_owner" on public.search_history;
create policy "search_history_update_owner"
  on public.search_history for update using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- record_search(termo, tipo): upsert do termo no histórico (seguro por user_id).
-- ---------------------------------------------------------------------------
create or replace function public.record_search(p_query text, p_type text default 'all')
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if p_query is null or length(trim(p_query)) = 0 then
    return;
  end if;
  insert into public.search_history (user_id, query, result_type, touched_at)
  values (auth.uid(), trim(p_query), coalesce(p_type, 'all'), now())
  on conflict (user_id, lower(query), result_type)
  do update set touched_at = now();
end;
$$;

revoke all on function public.record_search(text, text) from public;
grant execute on function public.record_search(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- clear_search_history(): limpa o histórico do usuário.
-- ---------------------------------------------------------------------------
create or replace function public.clear_search_history()
returns void
language sql
security definer set search_path = public
as $$
  delete from public.search_history where user_id = auth.uid();
$$;

revoke all on function public.clear_search_history() from public;
grant execute on function public.clear_search_history() to authenticated;

-- ---------------------------------------------------------------------------
-- trending_hashtags(limit): hashtags mais usadas (contagem real em posts).
-- ---------------------------------------------------------------------------
create or replace function public.trending_hashtags(p_limit int default 20)
returns table (tag text, cnt bigint)
language sql
security definer set search_path = public
as $$
  select lower(t) as tag, count(*)::bigint as cnt
  from public.posts, unnest(posts.hashtags) as t
  where t is not null and length(trim(t)) > 0
  group by lower(t)
  order by cnt desc
  limit greatest(coalesce(p_limit, 20), 1);
$$;

revoke all on function public.trending_hashtags(int) from public;
grant execute on function public.trending_hashtags(int) to anon, authenticated;
