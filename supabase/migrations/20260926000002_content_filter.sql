-- ============================================================================
-- KLAY K — FILTRO DE CONTEÚDO E PALAVRAS BLOQUEADAS (aditivo)
--
-- Não altera nem substitui `public.scan_spam` / `public.spam_action` /
-- `public.tg_comment_shield` / `public.tg_message_shield`: eles continuam
-- exatamente como estão. Aqui entram funções NOVAS que combinam as regras
-- globais com as palavras bloqueadas PELO PRÓPRIO usuário.
--
-- Honestidade de escopo: o filtro do usuário sinaliza/oculta para o próprio
-- autor. Ele NÃO é censura pública e nunca bloqueia outra conta.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) scan_user_content: regras globais + palavras do usuário
-- ---------------------------------------------------------------------------
create or replace function public.scan_user_content(p_text text, p_scope text default 'comment')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_base jsonb;
  v_matches text[] := '{}';
  v_user_hits text[] := '{}';
  v_words text[] := '{}';
  w text;
  v_action text := 'ok';
  v_sensitive boolean := false;
  v_fold text := public.spam_fold(coalesce(p_text, ''));
begin
  if u is null then raise exception 'auth_required'; end if;

  v_base := public.scan_spam(p_text, p_scope);

  select coalesce(us.blocked_words, '{}'), coalesce(us.sensitive_content_filter, false)
    into v_words, v_sensitive
    from public.user_settings us
   where us.user_id = u;

  v_matches := coalesce(
    (select array_agg(x::text) from jsonb_array_elements_text(coalesce(v_base->'matches', '[]'::jsonb)) x),
    '{}'
  );

  if v_fold <> '' then
    foreach w in array v_words loop
      if w <> '' and position(public.spam_fold(w) in v_fold) > 0 then
        v_user_hits := array_append(v_user_hits, w);
        v_matches := array_append(v_matches, w);
        v_action := 'flag';
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'scope', p_scope,
    'action', v_action,
    'matches', v_matches,
    'blocked', coalesce((v_base->>'blocked')::boolean, false),
    'flagged', coalesce((v_base->>'flagged')::boolean, false) or v_action = 'flag',
    'user_words_hit', cardinality(v_user_hits) > 0,
    'user_matches', v_user_hits,
    'sensitive_filter_enabled', v_sensitive
  );
end;
$$;

revoke all on function public.scan_user_content(text, text) from public, anon;
grant execute on function public.scan_user_content(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) add_blocked_words / remove_blocked_words: manipulação pontual
--    (o app pode usar save_privacy_settings; estas facilita em lote)
-- ---------------------------------------------------------------------------
create or replace function public.add_blocked_words(p_words text[])
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  merged text[];
begin
  if u is null then raise exception 'auth_required'; end if;

  insert into public.user_settings (user_id) values (u)
    on conflict (user_id) do nothing;

  select coalesce(
    (
      select array_agg(distinct w order by w)
        from unnest(
          coalesce((select us.blocked_words from public.user_settings us where us.user_id = u), '{}')
          || coalesce(
            (select array_agg(distinct lower(btrim(x)))
               from unnest(p_words) as x
              where btrim(x) <> '' and length(btrim(x)) <= 40),
            '{}'
          )
        ) as w
      where w <> ''
    ),
    '{}'
  ) into merged;

  update public.user_settings set blocked_words = merged where user_id = u;
  return merged;
end;
$$;

revoke all on function public.add_blocked_words(text[]) from public, anon;
grant execute on function public.add_blocked_words(text[]) to authenticated;

create or replace function public.remove_blocked_words(p_words text[])
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_current text[];
  v_remove text[];
  v_kept text[];
begin
  if u is null then raise exception 'auth_required'; end if;

  select coalesce(us.blocked_words, '{}') into v_current
    from public.user_settings us where us.user_id = u;

  select coalesce(array_agg(distinct lower(btrim(x))), '{}')
    into v_remove
    from unnest(p_words) as x where btrim(x) <> '';

  select coalesce(array_agg(w order by w), '{}')
    into v_kept
    from unnest(v_current) as w
   where not (w = any (v_remove));

  update public.user_settings set blocked_words = v_kept where user_id = u;
  return v_kept;
end;
$$;

revoke all on function public.remove_blocked_words(text[]) from public, anon;
grant execute on function public.remove_blocked_words(text[]) to authenticated;

notify pgrst, 'reload schema';
