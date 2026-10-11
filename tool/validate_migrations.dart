// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Aplica as migrations em BEGIN/ROLLBACK no banco real: valida sintaxe e
// objetos, sem persistir nada.
//
//   dart run tool/validate_migrations.dart <arquivo.sql> [...]
import 'dart:convert';
import 'dart:io';

const _ref = 'oysyuialaelzcxxkfdsl';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('informe ao menos uma migration');
    exit(1);
  }

  final sql = StringBuffer()
    ..writeln("begin; set local lock_timeout='5s'; set local statement_timeout='120s';");
  for (final f in args) {
    sql
      ..writeln('-- ===== $f')
      ..writeln(File(f).readAsStringSync());
  }
  sql.writeln('rollback;');

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
    File('/tmp/val.txt').writeAsStringSync('HTTP ${res.statusCode}\n$body');
    exit(res.statusCode >= 400 ? 1 : 0);
  } finally {
    client.close(force: true);
  }
}