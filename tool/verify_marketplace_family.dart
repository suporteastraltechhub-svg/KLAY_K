// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Confere o estado do Marketplace e dos Controles Familiares após aplicar.
//
//   dart run tool/verify_marketplace_family.dart
import 'dart:convert';
import 'dart:io';

const _url = 'https://oysyuialaelzcxxkfdsl.supabase.co';
const _key = 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E';

Future<List<Map<String, dynamic>>> _q(String sql) async {
  final client = HttpClient();
  try {
    final r = await client
        .postUrl(Uri.parse('https://api.supabase.com/v1/projects/oysyuialaelzcxxkfdsl/database/query'))
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

Future<String> _get(String path) async {
  final client = HttpClient();
  try {
    final r = await client.getUrl(Uri.parse('$_url$path'))
      ..headers.set('apikey', _key)
      ..headers.set('Authorization', 'Bearer $_key');
    final res = await r.close();
    final b = await res.transform(utf8.decoder).join();
    return '${res.statusCode} ${b.length > 90 ? b.substring(0, 90) : b}';
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final s = StringBuffer();

  s.writeln('\n=== objetos criados ===');
  for (final r in await _q('''
    select c.relname as tabela,
           c.relrowsecurity as rls,
           (select count(*)::int from pg_policies where tablename=c.relname) as policies
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind='r'
       and c.relname in ('family_time_limits','family_usage_ticks','follow_requests')
     order by 1''')) {
    s.writeln('  ${r['tabela']}  rls=${r['rls']}  policies=${r['policies']}');
  }
  for (final r in await _q('''
    select p.proname as func,
           has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname in (
       'family_time_limit_status','family_set_time_limit','family_usage_tick',
       'family_activity_report','request_follow','respond_follow_request',
       'store_publish_product','store_toggle_favorite','prune_family_usage_ticks')
     order by 1''')) {
    s.writeln('  ${r['func']}  anon=${r['anon']}  authenticated=${r['auth']}');
  }

  s.writeln('\n=== colunas novas em store_products / store_orders / profiles ===');
  for (final r in await _q('''
    select table_name, string_agg(column_name, ', ' order by column_name) as cols
      from information_schema.columns
     where table_schema='public'
       and ((table_name='store_products' and column_name in
             ('photos','condition','delivery_options','status','sold_count','city','state'))
         or (table_name='store_orders' and column_name in
             ('payment_status','expires_at','cancel_reason'))
         or (table_name='profiles' and column_name='require_follow_approval'))
     group by 1 order by 1''')) {
    s.writeln('  ${r['table_name']}: ${r['cols']}');
  }

  s.writeln('\n=== bucket de imagens ===');
  for (final r in await _q('''
    select id, public, file_size_limit from storage.buckets where id='store-media' ''')) {
    s.writeln('  ${r['id']}  publico=${r['public']}  limite=${r['file_size_limit']} bytes');
  }

  s.writeln('\n=== superficie exposta ao anon (deve estar tudo fechado) ===');
  s.writeln('  GET  store-products   -> ${await _get('/rest/v1/store_products?select=id,title,status&limit=3')}');
  s.writeln('  GET  family-time-limits -> ${await _get('/rest/v1/family_time_limits?select=*')}');
  s.writeln('  GET  family-usage-ticks -> ${await _get('/rest/v1/family_usage_ticks?select=*')}');
  s.writeln('  GET  follow-requests  -> ${await _get('/rest/v1/follow_requests?select=*')}');

  s.writeln('\n=== os testes deixaram lixo? (tudo deve estar vazio) ===');
  for (final r in await _q('''
    select (select count(*)::int from family_time_limits) as limites,
           (select count(*)::int from family_usage_ticks) as ticks,
           (select count(*)::int from follow_requests) as pedidos,
           (select count(*)::int from auth.users where email like '%@klayk.test') as usuarios_teste''')) {
    s.writeln('  limites=${r['limites']} ticks=${r['ticks']} pedidos=${r['pedidos']} '
        'usuarios_teste=${r['usuarios_teste']}');
  }

  File('/tmp/vf.txt').writeAsStringSync(s.toString());
  exit(0);
}