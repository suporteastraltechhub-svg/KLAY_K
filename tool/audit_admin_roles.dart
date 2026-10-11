// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Confere o achado: `admin_roles` respondeu 200 com CONTEÚDO para o papel
// anon, enquanto as outras tabelas responderam 200 [] (RLS filtrou).
//
//   dart run tool/audit_admin_roles.dart
import 'dart:convert';
import 'dart:io';

const _url = 'https://oysyuialaelzcxxkfdsl.supabase.co';
const _key = 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E';

Future<List<Map<String, dynamic>>> _q(String sql) async {
  final client = HttpClient();
  try {
    final r = await client
        .postUrl(Uri.parse(
            'https://api.supabase.com/v1/projects/oysyuialaelzcxxkfdsl/database/query'))
      ..headers.set(
          'Authorization', 'Bearer ${Platform.environment['SUPABASE_ACCESS_TOKEN']}')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'query': sql}));
    final res = await r.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      print('  ERRO: $body');
      return [];
    }
    return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final out = StringBuffer();

  out.writeln('\n=== admin_roles: RLS e policies ===');
  for (final r in await _q('''
    select c.relrowsecurity as rls,
           (select count(*)::int from pg_policies
             where tablename='admin_roles') as policies,
           (select count(*)::int from pg_tables
             where schemaname='public' and tablename='admin_roles') as existe
      from pg_class c where c.oid='public.admin_roles'::regclass''')) {
    out.writeln('  existe=${r['existe']}  RLS=${r['rls']}  policies=${r['policies']}');
  }

  out.writeln('\n=== policies (vazio = nenhuma protecao) ===');
  for (final r in await _q('''
    select policyname as nome, cmd as comando, coalesce(qual,'-') as usando
      from pg_policies where tablename='admin_roles' order by 1''')) {
    out.writeln('  ${r['nome']} [${r['comando']}]  USING ${r['usando']}');
  }
  final semPolicy = await _q('''
    select (select count(*)::int from pg_policies where tablename='admin_roles') as n''');
  if ((semPolicy.first['n'] as int) == 0) {
    out.writeln('  >>> NENHUMA POLICY: qualquer papel com GRANT ve a tabela inteira');
  }

  out.writeln('\n=== grants ===');
  for (final r in await _q('''
    select grantee, privilege_type
      from information_schema.role_table_grants
     where table_name='admin_roles' and grantee in ('anon','authenticated')
     order by grantee, privilege_type''')) {
    out.writeln('  ${r['grantee']} -> ${r['privilege_type']}');
  }

  out.writeln('\n=== o que o anon realmente enxerga hoje ===');
  final client = HttpClient();
  try {
    final r = await client
        .getUrl(Uri.parse('$_url/rest/v1/admin_roles?select=*'))
      ..headers.set('apikey', _key)
      ..headers.set('Authorization', 'Bearer $_key');
    final res = await r.close();
    final b = await res.transform(utf8.decoder).join();
    out.writeln('  HTTP ${res.statusCode}');
    out.writeln('  $b');
  } finally {
    client.close(force: true);
  }

  out.writeln('\n=== o app precisa ler admin_roles? ===');
  out.writeln('  (verificar no Dart: qualquer select em admin_roles)');

  File('/tmp/ar.txt').writeAsStringSync(out.toString());
  exit(0);
}