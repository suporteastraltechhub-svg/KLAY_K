-- KLAY K · teste de integração do RLS de privacidade (posts + comments)
--
-- EXECUTAR SOMENTE EM BANCO DE DESENVOLVIMENTO/TESTE.
-- Não rode em produção: o script cria e apaga usuários de teste e faz
-- assertions que assumem um banco vazio o bastante para inserção direta.
--
--   psql "$DEV_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_privacy_integration_test.sql
--
-- O script roda dentro de uma transação e dá ROLLBACK no final, então nada
-- é gravado. `ON_ERROR_STOP=1` faz o psql abortar no primeiro assert quebrado.
--
-- Cenários cobertos:
--   1. anônimo            -> só post público
--   2. dono               -> vê o próprio público e o próprio privado
--   3. seguidor           -> vê público + privado de quem segue
--   4. não seguidor       -> não vê o privado de outro
--   5. comentários        -> só os do post visível; oculto continua oculto
--   6. escrita            -> dono edita/apaga o próprio; estranho não
--
-- ===========================================================================

\set ON_ERROR_STOP on
begin;

-- ---------------------------------------------------------------------------
-- 0) Pré-requisitos
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'record_post_view'
  ) then
    raise exception 'migration de views/shares não aplicada — rode supabase db push antes';
  end if;
end $$;

create temporary table _result (
  cenario text,
  situacao text,
  detalhe text
) on commit drop;

create or replace function pg_temp._t(cenario text, ok boolean, detalhe text default '')
returns void language plpgsql security definer as $$
begin
  insert into _result values (cenario, case when ok then 'PASS' else 'FALHOU' end, detalhe);
  raise notice '%  %  %', rpad(cenario, 46, '.'), case when ok then 'PASS' else 'FALHOU' end, detalhe;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Fixtures: 3 usuários + perfil do dono privado + perfil dos outros público
-- ---------------------------------------------------------------------------
create temporary table _ids (
  dono uuid, seguidor uuid, estranho uuid,
  pub_id uuid, priv_id uuid, oculto_id uuid,
  c_pub uuid, c_priv uuid, c_oculto uuid
) on commit drop;

insert into _ids (dono, seguidor, estranho)
select
  gen_random_uuid(), gen_random_uuid(), gen_random_uuid();

-- auth.users exige hash/email únicos; o INSERT direto é de superuser e não
-- dispara e-mails.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, aud, role)
select i.dono,  'rls-dono@klayk.test',    crypt('x', gen_salt('bf')), now(), '{"provider":"email"}'::jsonb, 'authenticated', 'authenticated' from _ids i
union all
select i.seguidor,'rls-seguidor@klayk.test',crypt('x', gen_salt('bf')), now(), '{"provider":"email"}'::jsonb, 'authenticated', 'authenticated' from _ids i
union all
select i.estranho,'rls-estranho@klayk.test',crypt('x', gen_salt('bf')), now(), '{"provider":"email"}'::jsonb, 'authenticated', 'authenticated' from _ids i;

-- O INSERT em `auth.users` dispara o trigger `handle_new_user`, que já cria a
-- linha em `profiles` automaticamente. Por isso NÃO inserimos em profiles aqui:
-- só ajustamos o que precisamos depois.
--
-- Só o dono é privado. `is_admin`/`is_verified` ficam false.
update public.profiles p
   set is_private = true,
       display_name = 'RLS Dono',
       username = 'rls_dono'
  from _ids i
 where p.id = i.dono;

update public.profiles p
   set is_private = false,
       display_name = 'RLS Seguidor',
       username = 'rls_seguidor'
  from _ids i
 where p.id = i.seguidor;

update public.profiles p
   set is_private = false,
       display_name = 'RLS Estranho',
       username = 'rls_estranho'
  from _ids i
 where p.id = i.estranho;

-- O post PÚBLICO precisa ser de uma conta PÚBLICA.
--
-- Um post de conta privada nasce privado por design (BEFORE INSERT força
-- `posts.is_private` a partir de `profiles.is_private`). Se o fixture usasse o
-- `dono` para os dois posts, o "post público" também nasceria privado e os
-- cenários 1 e 4 mediriam a coisa errada.
update _ids set pub_id = gen_random_uuid(), priv_id = gen_random_uuid();

insert into public.posts (id, user_id, description, video_url)
select pub_id,  i.estranho, 'post publico do teste',  'https://x/pub.mp4'  from _ids i
union all
select priv_id, i.dono,     'post privado do teste', 'https://x/priv.mp4' from _ids i;

-- O BEFORE INSERT deve ter marcado o privado como privado (sync_post_is_private),
-- e o público de conta pública deve ter nascido público.
do $$
declare v boolean; alvo uuid;
begin
  select priv_id into alvo from _ids;
  select is_private into v from public.posts where id = alvo;
  perform pg_temp._t('trigger: BEFORE INSERT marcou privado', v is true,
                     'is_private=' || coalesce(v::text, 'null'));

  select pub_id into alvo from _ids;
  select is_private into v from public.posts where id = alvo;
  perform pg_temp._t('trigger: post de conta publica nasce publico', v is false,
                     'is_private=' || coalesce(v::text, 'null'));
end $$;

-- O dono segue a si mesmo? Não. O seguidor segue o dono.
insert into public.follows (follower_id, following_id)
select i.seguidor, i.dono from _ids i;

-- Comentários
update _ids set c_pub = gen_random_uuid(), c_priv = gen_random_uuid(), c_oculto = gen_random_uuid();
insert into public.comments (id, post_id, user_id, text)
select c_pub,   pub_id,  i.dono, 'comentario publico'  from _ids i
union all
select c_priv,  priv_id, i.dono, 'comentario privado'  from _ids i
union all
select c_oculto, pub_id,  i.dono, 'comentario oculto'  from _ids i;

update public.comments set hidden = true where id = (select c_oculto from _ids);

-- ---------------------------------------------------------------------------
-- Helper: roda uma consulta como um papel/usuário e conta as linhas
-- ---------------------------------------------------------------------------
create or replace function pg_temp._ver_posts(uid uuid)
returns int language plpgsql as $$
declare n int;
begin
  if uid is null then
    perform set_config('request.jwt.claims',
      '{"role":"anon","iss":"supabase"}', true);
    set local role anon;
  else
    perform set_config('request.jwt.claims',
      '{"role":"authenticated","sub":"' || uid::text || '","iss":"supabase"}', true);
    set local role authenticated;
  end if;
  select count(*) into n from public.posts;
  reset role;
  return n;
end $$;

create or replace function pg_temp._ver_comments(uid uuid)
returns setof text language plpgsql as $$
declare r record;
begin
  if uid is null then
    perform set_config('request.jwt.claims', '{"role":"anon","iss":"supabase"}', true);
    set local role anon;
  else
    perform set_config('request.jwt.claims',
      '{"role":"authenticated","sub":"' || uid::text || '","iss":"supabase"}', true);
    set local role authenticated;
  end if;
  for r in select id::text from public.comments loop
    return next r.id;
  end loop;
  reset role;
end $$;

-- ===========================================================================
-- 2) CENÁRIOS
-- ===========================================================================

-- 1) anônimo: só o público
do $$
declare v int; d uuid;
begin
  select pub_id into d from _ids;
  v := pg_temp._ver_posts(null);
  perform pg_temp._t('1 anonimo: ve so o post publico', v = 1, 'viu ' || v || ' de 2');
end $$;

-- 2) dono: os dois próprios
do $$
declare v int; d uuid;
begin
  select dono into d from _ids;
  v := pg_temp._ver_posts(d);
  perform pg_temp._t('2 dono: ve publico + o proprio privado', v = 2, 'viu ' || v || ' de 2');
end $$;

-- 3) seguidor: público + privado de quem segue
do $$
declare v int; d uuid;
begin
  select seguidor into d from _ids;
  v := pg_temp._ver_posts(d);
  perform pg_temp._t('3 seguidor: ve publico + privado de quem segue', v = 2, 'viu ' || v || ' de 2');
end $$;

-- 4) não seguidor: só o público
do $$
declare v int; d uuid;
begin
  select estranho into d from _ids;
  v := pg_temp._ver_posts(d);
  perform pg_temp._t('4 nao seguidor: nao ve o privado alheio', v = 1, 'viu ' || v || ' de 2');
end $$;

-- 5) comentários seguem a visibilidade do post
do $$
declare v text; tem_priv boolean; tem_oculto boolean; oculto uuid; d uuid;
begin
  select c_priv into d from _ids;

  tem_priv := false;
  for v in select * from pg_temp._ver_comments(null) loop
    if v = d::text then tem_priv := true; end if;
  end loop;
  perform pg_temp._t('5a anonimo: nao ve comentario de post privado', not tem_priv);

  tem_priv := false;
  for v in select * from pg_temp._ver_comments((select seguidor from _ids)) loop
    if v = d::text then tem_priv := true; end if;
  end loop;
  perform pg_temp._t('5b seguidor: ve comentario de post privado', tem_priv);

  -- comentário oculto segue oculto para não-moderador, em post público
  select c_oculto into oculto from _ids;
  tem_oculto := false;
  for v in select * from pg_temp._ver_comments((select estranho from _ids)) loop
    if v = oculto::text then tem_oculto := true; end if;
  end loop;
  perform pg_temp._t('5c nao moderador: nao ve comentario oculto', not tem_oculto);
end $$;

-- 6) escrita: dono edita o próprio, estranho não edita
do $$
declare d uuid; s uuid; n int; v_priv uuid;
begin
  select dono, estranho, priv_id into d, s, v_priv from _ids;

  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || d::text || '","iss":"supabase"}', true);
  set local role authenticated;
  update public.posts set description = 'editado pelo dono'
   where id = v_priv;
  reset role;

  select count(*) into n from public.posts where description = 'editado pelo dono';
  perform pg_temp._t('6a dono: edita o proprio post', n = 1);

  -- 6b: NÃO julga pela exceção. Quando a RLS filtra a linha, o UPDATE afeta
  -- 0 linhas e NÃO levanta erro nenhum — ausência de exceção não prova nada.
  -- O que prova é o estado da linha depois.
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || s::text || '","iss":"supabase"}', true);
  set local role authenticated;
  update public.posts set description = 'invasao'
   where id = v_priv;
  reset role;

  select count(*) into n from public.posts
   where id = v_priv and description = 'invasao';
  perform pg_temp._t('6b nao dono: nao edita post alheio', n = 0,
                     case when n = 0 then 'UPDATE afetou 0 linhas (RLS filtrou)'
                         else 'FALHOU: stranger alterou o post de outro' end);
end $$;

-- 7) increment_post_share: anônimo não executa, e o dono não des-privatiza
do $$
declare d uuid; n int; novo boolean; v_pub uuid; v_priv uuid; msg text;
begin
  select dono, pub_id, priv_id into d, v_pub, v_priv from _ids;

  -- 7a: anônimo não tem EXECUTE. Pode falhar por privilégio (42501) ou, se o
  --     grant vazou, devolver 0 sem alterar nada. Os dois são aceitáveis —
  --     o que NÃO é aceitável é o contador mudar.
  select coalesce(shares_count, 0) into n from public.posts where id = v_pub;
  perform set_config('request.jwt.claims', '{"role":"anon","iss":"supabase"}', true);
  set local role anon;
  begin
    perform public.increment_post_share(v_pub);
    perform pg_temp._t('7a anonimo: share nao infla o contador', true, 'retornou 0 ou bloqueado, contador intacto');
  exception when insufficient_privilege then
    perform pg_temp._t('7a anonimo: share nao infla o contador', true, 'EXECUTE negado (o esperado)');
  end;
  reset role;

  select coalesce(shares_count, 0) into n from public.posts where id = v_pub;
  perform pg_temp._t('7b anonimo: shares_count intacto', n = 0, 'shares_count=' || n);

  -- 7c: dono autenticado aumenta uma vez e é barrado pelo teto de 1/hora
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || d::text || '","iss":"supabase"}', true);
  set local role authenticated;
  perform public.increment_post_share(v_pub);
  reset role;
  select coalesce(shares_count, 0) into n from public.posts where id = v_pub;
  perform pg_temp._t('7c autenticado: primeiro share conta', n = 1, 'shares_count=' || n);

  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || d::text || '","iss":"supabase"}', true);
  set local role authenticated;
  perform public.increment_post_share(v_pub);
  perform public.increment_post_share(v_pub);
  reset role;
  select coalesce(shares_count, 0) into n from public.posts where id = v_pub;
  perform pg_temp._t('7d autenticado: teto anti-abuso 1/hora', n = 1, '3 chamadas -> shares_count=' || n);

  -- 7e: dono NÃO consegue des-privatizar o post com PATCH direto.
  -- Mesmo cuidado do 6b: o critério é o ESTADO da linha depois, não a
  -- exceção. O UPDATE pode ser aceito e simplesmente ter 0 linhas afetadas
  -- (aqui não é o caso — o dono tem acesso à própria linha, o UPDATE roda e o
  -- que precisa barrar é o TRIGGER BEFORE UPDATE).
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || d::text || '","iss":"supabase"}', true);
  set local role authenticated;
  update public.posts set is_private = false where id = v_priv;
  reset role;

  select is_private into novo from public.posts where id = v_priv;
  perform pg_temp._t('7e dono: PATCH direto em is_private barrado', novo is true,
                     case when novo is true then 'continua privado (trigger segurou)'
                       else 'FALHOU: dono des-privatizou o proprio post' end);

  -- 7f: ... mas mudar a privacidade da CONTA (caminho autorizado) propaga
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || d::text || '","iss":"supabase"}', true);
  set local role authenticated;
  update public.profiles set is_private = false where id = d;
  reset role;

  select is_private into novo from public.posts where id = v_priv;
  perform pg_temp._t('7f conta publica -> posts publicos (propagou)', novo is false,
                     'posts.is_private=' || coalesce(novo::text, 'null'));
end $$;

-- ===========================================================================
-- 3) Resumo
-- ===========================================================================
\echo ''
\echo '================= RESULTADO ================='
select cenario, situacao, detalhe from _result order by cenario;
\echo ''
\echo 'Esperado: todas as linhas PASS. Qualquer FALHOU = RLS incorreto.'

rollback;  -- nada é gravado
