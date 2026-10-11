// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Aplica as migrations E roda os testes comportamentais na MESMA transação,
// que termina em ROLLBACK. Nada persiste no banco.
//
//   dart run tool/dryrun_marketplace_family.dart
//
// Serve para validar a lógica antes de pedir autorização de aplicar.
import 'dart:convert';
import 'dart:io';

const _ref = 'oysyuialaelzcxxkfdsl';

const _migrations = [
  'supabase/migrations/20261017120000_family_controls.sql',
  'supabase/migrations/20261017130000_marketplace.sql',
];
const _testes = 'supabase/tests/marketplace_family_rls_test.sql';

Future<void> main() async {
  final sql = StringBuffer()
    ..writeln("begin; set local lock_timeout='8s'; set local statement_timeout='180s';");

  for (final m in _migrations) {
    sql
      ..writeln('-- ==== MIGRATION $m')
      ..writeln(File(m).readAsStringSync());
  }

  // corpo dos testes, sem o begin/rollback próprios (já estamos numa transação)
  final corpo = File(_testes)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith(RegExp(r'\\')))
      .where((l) => !RegExp(r'^\s*(begin|rollback)\s*;\s*$', caseSensitive: false)
          .hasMatch(l))
      .join('\n');
  sql
    ..writeln('-- ==== TESTES')
    ..writeln(corpo)
    ..writeln('rollback;');

  final client = HttpClient();
  try {
    final r = await client
        .postUrl(Uri.parse('https://api.supabase.com/v1/projects/$_ref/database/query'))
      ..headers.set(
          'Authorization', 'Bearer ${Platform.environment['SUPABASE_ACCESS_TOKEN']}')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'query': sql.toString()}));
    final res = await r.close();
    final body = await res.transform(utf8.decoder).join();

    if (res.statusCode >= 400) {
      File('/tmp/dr.txt').writeAsStringSync('ERRO: $body');
      exit(1);
    }

    final out = StringBuffer();
    for (final m in RegExp(
            r'\{"cenario":"([^"]*)","ok":(true|false)(?:,"detalhe":"([^"]*)")?\}')
        .allMatches(body)) {
      out.writeln('  [${m.group(2) == 'true' ? 'PASS' : 'FALHOU'}] ${m.group(1)}'
          '${(m.group(3) ?? '').isEmpty ? '' : '  (${m.group(3)})'}');
    }
    final linhas = out.toString().trim().split('\n').where((l) => l.isNotEmpty).toList();
    if (linhas.isEmpty) {
      File('/tmp/dr.txt').writeAsStringSync('Sem resultado. Corpo:\n$body');
      exit(1);
    }
    final falhas = linhas.where((l) => l.contains('FALHOU')).length;
    File('/tmp/dr.txt').writeAsStringSync(
        '${linhas.join('\n')}\n\n  TOTAL=${linhas.length}  FALHAS=$falhas');
    exit(0);
  } finally {
    client.close(force: true);
  }
}