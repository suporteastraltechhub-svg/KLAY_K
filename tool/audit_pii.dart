// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Confere as policies das tabelas base das views sensíveis (PII) e a
// superfície de `share_events`. Somente leitura.
//
//   dart run tool/audit_pii.dart
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
  print('=== policies de store_orders (PII: telefone, endereco) ===');
  for (final r in await _q('''
    select policyname as nome, cmd as comando,
           coalesce(qual, '-') as usando,
           coalesce(with_check, '-') as verificando
      from pg_policies where schemaname='public' and tablename='store_orders'
     order by policyname''')) {
    print('  ${r['nome']} [${r['comando']}]');
    print('    USING ${r['usando']}');
    if ('${r['verificando']}' != '-') {
      print('    CHECK ${r['verificando']}');
    }
  }

  print('\n=== policies de drafts ===');
  for (final r in await _q('''
    select policyname as nome, cmd as comando, coalesce(qual, '-') as usando
      from pg_policies where schemaname='public' and tablename='drafts'
     order by policyname''')) {
    print('  ${r['nome']} [${r['comando']}]  USING ${r['usando']}');
  }

  print('\n=== grants em share_events (RLS protege, mas revogamos por defesa) ===');
  for (final r in await _q('''
    select grantee, privilege_type,
           has_table_privilege(grantee, 'public.share_events', privilege_type) as tem
      from information_schema.role_table_grants
     where table_name='share_events' and grantee in ('anon','authenticated')
     order by grantee, privilege_type''')) {
    print('  ${r['grantee']} ${r['privilege_type']}');
  }

  print('\n=== leitura real: anon enxerga alguma linha de share_events? ===');
  final linhas = await _q('''
    select count(*)::int as total from public.share_events''');
  print('  (total real de linhas: ${linhas.isEmpty ? '?' : linhas.first['total']})');
  print('  RLS ligado + 0 policies => anon e authenticated neem veem nem escrevem.');

  print('\n=== anon consegue ler share_events via PostgREST? ===');
  const url = 'https://oysyuialaelzcxxkfdsl.supabase.co';
  const key = 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E';
  for (final caminho in ['/rest/v1/share_events?select=*']) {
    final client = HttpClient();
    try {
      final r = await client.getUrl(Uri.parse(url + caminho))
        ..headers.set('apikey', key)
        ..headers.set('Authorization', 'Bearer $key');
      final res = await r.close();
      final b = await res.transform(utf8.decoder).join();
      print('  GET $caminho -> HTTP ${res.statusCode}  ${b.substring(0, b.length > 120 ? 120 : b.length)}');
    } finally {
      client.close(force: true);
    }
  }
  print('');
}