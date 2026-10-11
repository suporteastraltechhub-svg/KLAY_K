// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Executa `supabase/tests/rls_privacy_integration_test.sql` contra um banco
// real SEM persistir nada: tudo dentro de um BEGIN ... ROLLBACK, com
// `lock_timeout` curto para não segurar lock de produção.
//
// Remove os meta-comandos do psql (`\set`, `\echo`) e injeta os timeout de
// segurança no BEGIN.
//
//   dart run tool/run_rls_integration.dart
//
// Requer SUPABASE_ACCESS_TOKEN no ambiente.
import 'dart:convert';
import 'dart:io';

const _ref = 'oysyuialaelzcxxkfdsl';
const _arquivo = 'supabase/tests/rls_privacy_integration_test.sql';

Future<String> _executar() async {
  var corpo = File(_arquivo).readAsStringSync();
  corpo = corpo
      .split('\n')
      .where((l) => !l.trimLeft().startsWith(RegExp(r'\\')))
      .join('\n');
  corpo = corpo.replaceFirst(
    RegExp(r'^\s*begin\s*;', caseSensitive: false),
    "begin;\nset local lock_timeout = '5s';\n"
        "set local statement_timeout = '90s';",
  );

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
    return '${res.statusCode}\n$body';
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final saida = await _executar();
  final partes = saida.split('\n');
  final status = partes.first;
  final body = partes.skip(1).join('\n');

  if (status != '201') {
    print('FALHA (HTTP $status): $body');
    exit(1);
  }

  // A API devolve apenas o último result set — que é o SELECT de resumo.
  final re = RegExp(
    r'\{"cenario":"([^"]*)","situacao":"([^"]*)"(?:,"detalhe":"([^"]*)")?\}',
  );
  final linhas = <String>[];
  var falhas = 0;
  for (final m in re.allMatches(body)) {
    final det = m.group(3) ?? '';
    if (m.group(2) == 'FALHOU') falhas++;
    linhas.add('  [${m.group(2)}] ${m.group(1)}${det.isEmpty ? '' : '  ($det)'}');
  }

  if (linhas.isEmpty) {
    print('  Nenhum cenario no resultado. Corpo bruto:');
    print(body);
    exit(1);
  }

  for (final l in linhas) {
    print(l);
  }
  print('');
  print(falhas == 0
      ? '  RESULTADO: ${linhas.length} cenarios, todos PASS.'
      : '  RESULTADO: $falhas de ${linhas.length} cenarios FALHARAM.');
  exit(falhas == 0 ? 0 : 1);
}