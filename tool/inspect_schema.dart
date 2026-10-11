// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Mapa do esquema existente para o Marketplace e os Controles Familiares,
// para não recriar nada que já existe.
//
//   dart run tool/inspect_schema.dart
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

  s.writeln('\n=== TABELAS DE LOJA / MARKETPLACE ===');
  for (final r in await _q('''
    select c.relname as tabela,
           (select count(*)::int from information_schema.columns
             where table_schema='public' and table_name=c.relname) as colunas,
           c.relrowsecurity as rls,
           (select count(*)::int from pg_policies
             where tablename=c.relname) as policies
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind='r' and c.relname like 'store%'
     order by 1''')) {
    s.writeln('  ${r['tabela']}  colunas=${r['colunas']} rls=${r['rls']} '
        'policies=${r['policies']}');
  }

  s.writeln('\n=== COLUNAS DE store_products ===');
  final cols = await _q('''
    select column_name, data_type, is_nullable, column_default
      from information_schema.columns
     where table_schema='public' and table_name='store_products'
     order by ordinal_position''');
  s.writeln('  ${cols.map((c) => '${c['column_name']}:${c['data_type']}').join(', ')}');

  s.writeln('\n=== COLUNAS DE store_orders / store_order_items ===');
  for (final t in ['store_orders', 'store_order_items', 'store_categories',
                   'store_favorites', 'store_addresses']) {
    final c = await _q('''
      select string_agg(column_name || ' ' ||
        case when data_type like 'character varying' then '(txt)'
             when data_type = 'uuid' then '(uuid)'
             when data_type = 'numeric' then '(num)'
             else '' end, ', ' order by ordinal_position) as cols
        from information_schema.columns
       where table_schema='public' and table_name='$t' ''');
    s.writeln('  $t: ${c.isEmpty ? 'AUSENTE' : c.first['cols']}');
  }

  s.writeln('\n=== POLICIES DE store_products ===');
  for (final r in await _q('''
    select policyname, cmd, coalesce(qual,'-') as usando
      from pg_policies where tablename='store_products' order by 1''')) {
    s.writeln('  ${r['policyname']} [${r['cmd']}]  USING ${r['usando']}');
  }

  s.writeln('\n=== CONTROLES FAMILIARES: tabelas ===');
  for (final r in await _q('''
    select c.relname as tabela,
           c.relrowsecurity as rls,
           (select count(*)::int from pg_policies where tablename=c.relname) as policies
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind='r'
       and (c.relname like 'guardian%' or c.relname like 'family%'
            or c.relname like 'youth%' or c.relname like 'follow%')
     order by 1''')) {
    s.writeln('  ${r['tabela']}  rls=${r['rls']} policies=${r['policies']}');
  }

  s.writeln('\n=== COLUNAS DE family_links / guardian_rules / follows ===');
  for (final t in ['family_links', 'guardian_rules', 'guardian_alerts', 'follows']) {
    final c = await _q('''
      select string_agg(column_name, ', ' order by ordinal_position) as cols
        from information_schema.columns
       where table_schema='public' and table_name='$t' ''');
    s.writeln('  $t: ${c.isEmpty ? 'AUSENTE' : c.first['cols']}');
  }

  s.writeln('\n=== ja existe pedido de seguimento (follow_requests)? ===');
  final fr = await _q('''
    select count(*)::int as n from pg_tables
     where schemaname='public' and tablename='follow_requests' ''');
  s.writeln('  follow_requests: ${fr.isEmpty ? '?' : fr.first['n']} '
      '(0 = nao existe)');

  s.writeln('\n=== funcoes de guardian/family ja existentes ===');
  for (final r in await _q('''
    select p.proname as func from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public'
       and (p.proname like 'guardian%' or p.proname like 'family%'
            or p.proname like '%youth%')
     order by 1''')) {
    s.writeln('  ${r['func']}');
  }

  s.writeln('\n=== buckets de storage ===');
  for (final r in await _q('''
    select id, public, (select count(*)::int from storage.objects o
                          where o.bucket_id=b.id) as arquivos
      from storage.buckets b order by 1''')) {
    s.writeln('  ${r['id']}  publico=${r['public']} arquivos=${r['arquivos']}');
  }

  File('/tmp/schema.txt').writeAsStringSync(s.toString());
  exit(0);
}