// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Antes de revogar o SELECT de admin_roles, confirma que nada no app depende
// de LER a tabela direto pelo PostgREST — e sim por RPC.
//
//   dart run tool/audit_admin_roles_usage.dart
import 'dart:convert';
import 'dart:io';

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
  final s = StringBuffer();

  s.writeln('=== quem LE admin_roles dentro do banco (funcoes/policies) ===');
  for (final r in await _q('''
    with src as (
      select p.proname as obj, 'funcao' as tipo,
             pg_get_functiondef(p.oid) as def
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
      union all
      select policyname, 'policy', coalesce(qual,'') || ' ' || coalesce(with_check,'')
        from pg_policies where schemaname = 'public'
    )
    select obj, tipo from src
     where def ilike '%admin_roles%'
     order by tipo, obj''')) {
    s.writeln('  [${r['tipo']}] ${r['obj']}');
  }

  s.writeln('\n=== definicao de has_perm / my_caps (como o app resolve permissao) ===');
  for (final nome in ['has_perm', 'my_caps', 'is_klayk_admin']) {
    for (final r in await _q('''
      select pg_get_functiondef(p.oid) as def from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname='$nome' limit 1''')) {
      s.writeln('  --- $nome');
      s.writeln('      ${(r['def'] ?? '').toString().replaceAll('\n', '\n      ')}');
    }
  }

  File('/tmp/u.txt').writeAsStringSync(s.toString());
  exit(0);
}