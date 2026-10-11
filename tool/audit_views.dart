// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Investiga as duas "views" que a auditoria marcou com RLS desligada.
// Somente leitura.
//
//   dart run tool/audit_views.dart
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
  const nomes = ['drafts_active_view', 'store_orders_view'];

  print('=== tipo real dos objetos ===');
  for (final r in await _q('''
    select c.relname as nome, c.relkind as tipo,
           case c.relkind
             when 'r' then 'table'
             when 'v' then 'view'
             when 'm' then 'matview'
             else c.relkind::text end as descricao,
           c.relrowsecurity as rls,
           pg_get_userbyid(c.relowner) as dono,
           (select count(*)::int from pg_trigger t
             where t.tgrelid = c.oid and not t.tgisinternal) as triggers
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname in ('drafts_active_view','store_orders_view')
     order by 1''')) {
    print('  ${r['nome']}: ${r['descricao']} (relkind=${r['tipo']})  '
        'RLS=${r['rls']}  dono=${r['dono']}  triggers=${r['triggers']}');
  }

  print('\n=== definicao ===');
  for (final nome in nomes) {
    final r = await _q("select pg_get_viewdef('$nome'::regclass, true) as def");
    if (r.isEmpty) {
      print('  $nome: (nao encontrado ou nao e view)');
      continue;
    }
    print('  --- $nome');
    print('      ${(r.first['def'] ?? '').toString().replaceAll('\n', '\n      ')}');
  }

  print('\n=== propagacao de RLS (security_invoker?) ===');
  for (final nome in nomes) {
    final r = await _q('''
      select (select count(*)::int from pg_rewrite w
               join pg_class v on v.oid = w.ev_class
               join pg_namespace n on n.oid = v.relnamespace
               where n.nspname='public' and v.relname='$nome'
                 and (w.ev_qual is not null)) as tem_regra,
             (select reloptions from pg_class c
               join pg_namespace n on n.oid=c.relnamespace
               where n.nspname='public' and c.relname='$nome') as opcoes''');
    if (r.isEmpty) continue;
    final opcoes = r.first['opcoes'];
    final invoker = (opcoes is List) && opcoes.any((o) => '$o'.contains('security_invoker=true'));
    print('  $nome: security_invoker=${invoker ? "SIM (RLS do usuario vale)" : "NAO <<< roda como dono"}'
        '  opcoes=${opcoes ?? '-'}');
  }

  print('\n=== a view expoe dados sensiveis? ===');
  for (final nome in nomes) {
    final cols = await _q('''
      select string_agg(column_name, ', ' order by ordinal_position) as c
        from information_schema.columns
       where table_schema='public' and table_name='$nome' ''');
    print('  $nome: ${cols.isEmpty ? 'sem colunas' : cols.first['c']}');
  }
  print('');
}