// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Roda `supabase/tests/marketplace_family_rls_test.sql` num BEGIN/ROLLBACK
// no banco real. Só funciona DEPOIS que as migrations estiverem aplicadas.
//
//   dart run tool/run_marketplace_family_tests.dart
import 'dart:convert';
import 'dart:io';

const _ref = 'oysyuialaelzcxxkfdsl';

Future<void> main() async {
  const arquivo = 'supabase/tests/marketplace_family_rls_test.sql';
  var corpo = File(arquivo).readAsStringSync();
  corpo = corpo
      .split('\n')
      .where((l) => !l.trimLeft().startsWith(RegExp(r'\\')))
      .join('\n');

  final client = HttpClient();
  try {
    final r = await client
        .postUrl(Uri.parse('https://api.supabase.com/v1/projects/$_ref/database/query'))
      ..headers.set(
          'Authorization', 'Bearer ${Platform.environment['SUPABASE_ACCESS_TOKEN']}')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'query': corpo}));
    final res = await r.close();
    final body = await res.transform(utf8.decoder).join();

    if (res.statusCode >= 400) {
      File('/tmp/mk.txt').writeAsStringSync('ERRO: $body');
      exit(1);
    }

    final linhas = <String>[];
    for (final m in RegExp(
            r'\{"cenario":"([^"]*)","ok":(true|false)(?:,"detalhe":"([^"]*)")?\}')
        .allMatches(body)) {
      linhas.add('  [${m.group(2) == 'true' ? 'PASS' : 'FALHOU'}] ${m.group(1)}'
          '${(m.group(3) ?? '').isEmpty ? '' : '  (${m.group(3)})'}');
    }
    if (linhas.isEmpty) {
      File('/tmp/mk.txt').writeAsStringSync('Sem resultado. Corpo:\n$body');
      exit(1);
    }
    final falhas = linhas.where((l) => l.contains('FALHOU')).length;
    File('/tmp/mk.txt').writeAsStringSync(
        '${linhas.join('\n')}\n\n  TOTAL=${linhas.length}  FALHAS=$falhas');
    exit(0);
  } finally {
    client.close(force: true);
  }
}