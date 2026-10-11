// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
import 'dart:convert';
import 'dart:io';

/// Valida as migrations num banco REAL sem persistir nada.
///
/// COMO ISSO É SEGURO
///
/// Todo o script roda dentro de um `BEGIN ... ROLLBACK`. DDL no Postgres é
/// transacional, então tabela, coluna, function, trigger, policy e índice
/// são criados e destruídos no fim. A produção fica exatamente como estava.
///
/// As guardas evitam travar o banco de verdade:
///   * `lock_timeout = 3s` — se outro processo estiver usando a tabela, o
///     statement aborta em vez de enfileirar e segura o lock.
///   * `statement_timeout = 60s` — teto de tempo por statement.
///
/// USO
///
///   dart run tool/validate_migrations_rollback.dart [migration.sql ...]
///
/// Sem argumentos, valida as três migrations de segurança pendentes.
///
/// O token vem de `SUPABASE_ACCESS_TOKEN` no ambiente (`.env` no repo, com
/// `chmod 600` e fora do Git).
///
/// O QUE ELE PROVA
///
/// 1. Que as migrations executam sem erro de sintaxe/semântica.
/// 2. Privilégio: `anon` e `public` NÃO executam `increment_post_share`;
///    `authenticated` continua executando.
/// 3. Que o ataque de `PATCH {"is_private": false}` é bloqueado — e que a
///    edição normal do post continua funcionando.
///
/// Nenhum dado é gravado.
Future<void> main(List<String> args) async {
  const ref = 'oysyuialaelzcxxkfdsl';
  final migrations = args.isEmpty
      ? [
          'supabase/migrations/20261011120000_rls_hardening.sql',
          'supabase/migrations/20261011130000_posts_comments_privacy.sql',
          'supabase/migrations/20261012120000_fix_increment_post_share.sql',
        ]
      : args;

  final sql = StringBuffer()
    ..writeln('begin;')
    ..writeln("set local lock_timeout = '3s';")
    ..writeln("set local statement_timeout = '60s';");
  for (final f in migrations) {
    sql
      ..writeln('-- ===== $f')
      ..writeln(File(f).readAsStringSync());
  }

  // Teste comportamental do ataque, dentro da mesma transação.

  // Verificações estruturais.
  sql.writeln(r'''
select r.nome, r.valor from (values
  ('anon executa share',
    (select has_function_privilege('anon','public.increment_post_share(uuid)','EXECUTE')::text)),
  ('public executa share',
    (select has_function_privilege('public','public.increment_post_share(uuid)','EXECUTE')::text)),
  ('authenticated executa share',
    (select has_function_privilege('authenticated','public.increment_post_share(uuid)','EXECUTE')::text)),
  ('trigger BEFORE UPDATE existe',
    (select count(*)::text from pg_trigger where tgname='posts_is_private_bu')),
  ('trigger BEFORE INSERT existe',
    (select count(*)::text from pg_trigger where tgname='posts_is_private_bi')),
  ('trigger profiles existe',
    (select count(*)::text from pg_trigger where tgname='profiles_is_private_au')),
  ('posts_select_visible',
    (select exists(select 1 from pg_policies where tablename='posts' and policyname='posts_select_visible')::text)),
  ('comments_select_all',
    (select exists(select 1 from pg_policies where tablename='comments' and policyname='comments_select_all')::text)),
  ('share_events',
    (select exists(select 1 from information_schema.tables where table_schema='public' and table_name='share_events')::text))
) as r(nome, valor);
''');
  sql.writeln(r'''
-- ================= cenario: dono tenta des-privatizar o proprio post
create temporary table _probe(nome text, r text) on commit drop;
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_post  uuid;
  v_antes boolean;
  v_depois boolean;
  v_perfil boolean;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                         raw_app_meta_data, aud, role)
  values (v_owner, 'sharefix_probe@klayk.test', crypt('x', gen_salt('bf')), now(),
          '{"provider":"email"}', 'authenticated', 'authenticated');

  update public.profiles set is_private = true where id = v_owner;
  v_post := gen_random_uuid();
  insert into public.posts (id, user_id, description)
  values (v_post, v_owner, 'probe');
  select is_private into v_antes from public.posts where id = v_post;

  -- simula o PATCH {"is_private": false} do dono via PostgREST
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || v_owner::text || '","iss":"supabase"}', true);
  update public.posts set is_private = false where id = v_post;

  -- e um update legitimo de outro campo, para garantir que UPDATE normal funciona
  update public.posts set description = 'editado pelo dono' where id = v_post;
  reset role;

  select is_private into v_depois from public.posts where id = v_post;
  select is_private into v_perfil from public.profiles where id = v_owner;

  insert into _probe(nome, r)
  select 'A is_private apos PATCH do dono' as nome,
         case when v_antes then 'PASS: post nasceu privado' else 'FALHOU' end as r
  union all
  select 'B PATCH is_private=false foi bloqueado',
         case when v_depois then 'PASS: continua privado' else 'FALHOU: des-privatizou' end
  union all
  select 'C perfil segue privado',
         case when v_perfil then 'PASS' else 'FALHOU' end
  union all
  select 'D UPDATE de outro campo funciona',
         case when (select description from public.posts where id = v_post) = 'editado pelo dono'
              then 'PASS: edicao normal intacta' else 'FALHOU: update comum quebrou' end;
end $$;

-- Teste comportamental da RPC de compartilhamento: quem consegue inflar
-- `shares_count` e quem não consegue.
do $$
declare
  v_post    uuid := gen_random_uuid();
  v_owner   uuid := gen_random_uuid();
  v_sessao  uuid := gen_random_uuid();
  v_r       int;
  v_total   int;
  v_msg     text;
  v_primeira int;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                         raw_app_meta_data, aud, role)
  values (v_owner,  'sharefix_real@klayk.test', crypt('x', gen_salt('bf')), now(),
          '{"provider":"email"}', 'authenticated', 'authenticated');
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                         raw_app_meta_data, aud, role, is_anonymous)
  values (v_sessao, 'sharefix_anon@klayk.test', crypt('x', gen_salt('bf')), now(),
          '{"provider":"email"}', 'authenticated', 'authenticated', true);

  insert into public.posts (id, user_id, description)
  values (v_post, v_owner, 'post para contagem de share');

  -- E1: role `anon` (sem JWT) nem consegue executar a RPC
  set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon","iss":"supabase"}', true);
  begin
    v_r := public.increment_post_share(v_post);
    v_msg := 'PASS: retornou ' || v_r || ' sem alterar nada';
  exception when insufficient_privilege then
    v_msg := 'PASS: EXECUTE negado (revogado)';
  end;
  reset role;
  select shares_count into v_total from public.posts where id = v_post;
  insert into _probe(nome, r)
  select 'E anon (role anon) nao infla shares_count',
         case when v_total = 0 then v_msg
              else 'FALHOU: contador virou ' || v_total end;

  -- E2: sessao anonima do app (is_anonymous = true) tambem nao
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || v_sessao::text || '","iss":"supabase"}', true);
  v_r := public.increment_post_share(v_post);
  reset role;
  select shares_count into v_total from public.posts where id = v_post;
  insert into _probe(nome, r)
  select 'F sessao anonima do app nao infla',
         case when v_total = 0 then 'PASS: contador intacto, retornou ' || v_r
              else 'FALHOU: contador virou ' || v_total end;

  -- E3: conta real conta uma vez
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || v_owner::text || '","iss":"supabase"}', true);
  v_primeira := public.increment_post_share(v_post);
  -- E4: e barrado pelo teto de 1/hora
  perform public.increment_post_share(v_post);
  perform public.increment_post_share(v_post);
  reset role;
  select shares_count into v_total from public.posts where id = v_post;
  insert into _probe(nome, r)
  select 'G conta real: primeiro share conta',
         case when v_primeira = 1 then 'PASS: shares_count=1'
              else 'FALHOU: retornou ' || v_primeira end;
  insert into _probe(nome, r)
  select 'H conta real: teto anti-abuso 1/hora',
         case when v_total = 1 then 'PASS: 3 chamadas -> ainda 1'
              else 'FALHOU: contador virou ' || v_total end;
end $$;

select * from _probe order by nome;
''');
  sql.writeln('rollback;');

  final r = await HttpClient()
      .postUrl(Uri.parse('https://api.supabase.com/v1/projects/$ref/database/query'))
    ..headers.set(
        'Authorization', 'Bearer ${Platform.environment['SUPABASE_ACCESS_TOKEN']}')
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({'query': sql.toString()}));
  final res = await r.close();
  print('HTTP ${res.statusCode}');
  final body = await res.transform(utf8.decoder).join();
  print(body.length > 5000 ? body.substring(0, 5000) : body);
  exit(0);
}