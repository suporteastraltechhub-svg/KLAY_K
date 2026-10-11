// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Lista as funções SECURITY DEFINER de public que o papel `anon` consegue
// executar. São as que BYPASSAM RLS — a superfície que mais importa.
//
//   dart run tool/audit_definer.dart
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

  out.writeln('\n=== SECURITY DEFINER executaveis por anon ===');
  final rows = await _q('''
    select p.proname as func,
           pg_get_function_identity_arguments(p.oid) as args,
           coalesce(array_to_string(p.proconfig, ','), 'SEM search_path') as config,
           l.lanname as linguagem
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and p.prosecdef
       and p.prokind = 'f'
       and has_function_privilege('anon', p.oid, 'EXECUTE')
     order by p.proname''');
  if (rows.isEmpty) {
    out.writeln('  nenhuma');
  } else {
    for (final r in rows) {
      out.writeln('  ${r['func']}(${r['args']})  [${r['config']}]  ${r['linguagem']}');
    }
  }
  out.writeln('  total: ${rows.length}');

  out.writeln('\n=== dessas, quais tem guarda de auth.uid()? ===');
  for (final r in rows) {
    final body = await _q(
        "select pg_get_functiondef(p.oid) as def from pg_proc p "
        "join pg_namespace n on n.oid=p.pronamespace "
        "where n.nspname='public' and p.proname='${r['func']}' limit 1");
    final def = (body.isEmpty ? '' : '${body.first['def']}');
    final temUid = def.contains('auth.uid()') || def.contains('current_user');
    final temRole = def.contains('is_klayk_admin') || def.contains('is_service_role');
    out.writeln('  ${r['func']}: '
        '${temUid ? "chega a checar identidade" : "<<< NAO checa auth.uid()"}'
        '${temRole ? " + checa admin/service_role" : ""}');
  }

  out.writeln('\n=== total de funcoes executaveis por anon (com RLS por tras) ===');
  for (final r in await _q('''
    select count(*)::int as total from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.prokind='f'
       and has_function_privilege('anon', p.oid, 'EXECUTE')''')) {
    out.writeln('  ${r['total']} funções');
  }

  File('/tmp/def.txt').writeAsStringSync(out.toString());
  exit(0);
}