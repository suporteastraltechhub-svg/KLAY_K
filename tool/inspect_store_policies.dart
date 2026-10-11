// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Verifica as policies de INSERT/UPDATE da loja: em policy de INSERT o que
// restringe e' WITH CHECK (USING e' ignorado). Se o WITH CHECK estiver vazio,
// qualquer usuario autenticado consegue criar produto em nome de outro.
//
//   dart run tool/inspect_store_policies.dart
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
  final s = StringBuffer();

  s.writeln('\n=== policies de escrita da loja (WITH CHECK e o que importa) ===');
  for (final r in await _q('''
    select tablename, policyname, cmd,
           coalesce(qual, 'NULL') as usando,
           coalesce(with_check, 'NULL') as check_
      from pg_policies
     where schemaname='public'
       and tablename in ('store_products','store_orders','store_order_items',
                         'store_cart_items','store_favorites')
     order by tablename, cmd, policyname''')) {
    s.writeln('  ${r['tablename']}.${r['policyname']} [${r['cmd']}]');
    s.writeln('      USING     = ${r['usando']}');
    s.writeln('      WITH CHECK= ${r['check_']}');
    if (r['cmd'] == 'INSERT' && '${r['check_']}' == 'NULL') {
      s.writeln('      >>> INSERT SEM WITH CHECK: nao restringe seller_id!');
    }
  }

  s.writeln('\n=== status atual dos pedidos (valores em uso) ===');
  for (final r in await _q('''
    select status, count(*)::int as n from store_orders group by 1 order by 1''')) {
    s.writeln('  ${r['status']}: ${r['n']}');
  }

  s.writeln('\n=== store_order_items: como guarda preco/quantidade? ===');
  final oi = await _q('''
    select pg_get_functiondef(p.oid) as def from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname like 'checkout%' limit 3''');
  if (oi.isEmpty) {
    s.writeln('  (checkout e' ' feito no cliente Dart, sem RPC)');
  } else {
    for (final r in oi) {
      s.writeln('  ${r['def']}');
    }
  }

  File('/tmp/pol.txt').writeAsStringSync(s.toString());
  exit(0);
}