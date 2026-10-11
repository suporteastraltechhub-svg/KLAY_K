// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Auditoria de permissões e proteções do KLAY K no Supabase.
// Somente leitura. Não altera nada.
//
//   dart run tool/audit_security.dart
//
// Requer SUPABASE_ACCESS_TOKEN no ambiente.
import 'dart:convert';
import 'dart:io';

const _ref = 'oysyuialaelzcxxkfdsl';

Future<List<Map<String, dynamic>>> _q(String sql) async {
  final client = HttpClient();
  try {
    final r = await client
        .postUrl(Uri.parse('https://api.supabase.com/v1/projects/$_ref/database/query'))
      ..headers.set(
          'Authorization', 'Bearer ${Platform.environment['SUPABASE_ACCESS_TOKEN']}')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'query': sql}));
    final res = await r.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      print('  ERRO na consulta: $body');
      exit(1);
    }
    return (jsonDecode(body) as List)
        .cast<Map<String, dynamic>>();
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  print('\n=== 1. PROTEÇÃO DO COMPARTILHAMENTO ===');
  for (final r in await _q('''
    select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as func,
           has_function_privilege('anon',         p.oid, 'EXECUTE') as anon,
           has_function_privilege('authenticated',p.oid, 'EXECUTE') as autenticado,
           has_function_privilege('public',       p.oid, 'EXECUTE') as publico,
           p.prosecdef as definer,
           coalesce(array_to_string(p.proconfig, ','), '-') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('increment_post_share','record_post_view','prune_share_events')
     order by 1''')) {
    print('  ${r['func']}');
    print('    anon=${r['anon']}  autenticado=${r['autenticado']}  '
        'public=${r['public']}  definer=${r['definer']}  config=${r['config']}');
  }

  print('\n=== 2. PRIVACIDADE DAS PUBLICACOES ===');
  for (final r in await _q('''
    select c.relrowsecurity as rls_posts,
           (select count(*)::int from pg_trigger where tgname = 'posts_is_private_bu') as trg_bu,
           (select count(*)::int from pg_trigger where tgname = 'posts_is_private_bi') as trg_bi,
           (select count(*)::int from pg_trigger where tgname = 'profiles_is_private_au') as trg_perfil,
           (select count(*)::int from pg_policies where tablename='posts') as pol_posts,
           (select count(*)::int from pg_policies where tablename='comments') as pol_com,
           (select count(*)::int from information_schema.columns
             where table_schema='public' and table_name='posts' and column_name='is_private') as col
      from pg_class c where c.oid = 'public.posts'::regclass''')) {
    print('  posts RLS=${r['rls_posts']}  coluna is_private=${r['col']}');
    print('  triggers: bi=${r['trg_bi']} bu=${r['trg_bu']} perfil=${r['trg_perfil']}');
    print('  policies: posts=${r['pol_posts']}  comments=${r['pol_com']}');
  }

  print('\n=== 3. TABELA share_events (controle anti-abuso) ===');
  for (final r in await _q('''
    select (select count(*)::int from pg_tables
             where schemaname='public' and tablename='share_events') as existe,
           (select relrowsecurity from pg_class
             where oid='public.share_events'::regclass) as rls,
           (select count(*)::int from pg_policies
             where tablename='share_events') as policies,
           (select count(*)::int from public.share_events) as linhas,
           (select count(*)::int from information_schema.role_table_grants
             where table_name='share_events' and grantee in ('anon','authenticated')
               and privilege_type <> 'SELECT') as escritas''')) {
    print('  existe=${r['existe']}  RLS=${r['rls']}  policies=${r['policies']}  '
        'linhas=${r['linhas']}  grants de escrita anon/auth=${r['escritas']}');
  }

  print('\n=== 4. FUNCOES SECURITY DEFINER SEM search_path ===');
  final semPath = await _q('''
    select p.proname as func, p.prosecdef
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c
                        where c like 'search_path=%')
     order by 1''');
  if (semPath.isEmpty) {
    print('  nenhuma (ok)');
  } else {
    for (final r in semPath) {
      print('  SEM search_path: ${r['func']}');
    }
  }

  print('\n=== 5. FUNCOES EXECUTAVEIS POR anon (superficie de ataque) ===');
  for (final r in await _q('''
    select count(*)::int as total from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.prokind='f'
       and has_function_privilege('anon', p.oid, 'EXECUTE')''')) {
    print('  funcoes executaveis por anon: ${r['total']}');
  }

  print('\n=== 6. TABELAS COM ESCRITA PARA anon (RLS deve segurar) ===');
  for (final r in await _q('''
    select table_name as tabela,
           string_agg(distinct privilege_type, ',' order by privilege_type) as privilegios
      from information_schema.role_table_grants
     where table_schema='public' and grantee='anon'
       and privilege_type in ('INSERT','UPDATE','DELETE')
     group by table_name order by 1''')) {
    final semRls = await _q(
        "select coalesce((select relrowsecurity from pg_class c "
          "join pg_namespace n on n.oid=c.relnamespace "
          "where n.nspname='public' and c.relname='${r['tabela']}'), false) as rls");
    final tem = semRls.first['rls'] == true;
    print('  ${r['tabela']}  [${r['privilegios']}]  RLS=${tem ? "on" : "OFF <<<"}');
  }

  print('\n=== 7. pg_cron (para limpeza automatica) ===');
  for (final r in await _q('''
    select exists(select 1 from pg_available_extensions
                   where name='pg_cron') as disponivel,
           exists(select 1 from pg_extension where extname='pg_cron') as instalado,
           (select current_setting('cron.database_name', true)) as banco''')) {
    print('  disponivel=${r['disponivel']}  instalado=${r['instalado']}  '
        'cron.database_name=${r['banco']}');
  }
  print('');
}