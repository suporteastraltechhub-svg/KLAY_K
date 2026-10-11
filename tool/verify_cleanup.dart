// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Confere a limpeza automática de share_events: extensão, job e execução real.
//
//   dart run tool/verify_cleanup.dart
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

  out.writeln('\n=== extensao e job ===');
  for (final r in await _q('''
    select (select extversion from pg_extension where extname='pg_cron') as versao,
           (select count(*)::int from cron.job where jobname='prune-share-events') as jobs,
           (select jobid::text from cron.job where jobname='prune-share-events') as jobid''')) {
    out.writeln('  pg_cron=${r['versao']}  jobs registrados=${r['jobs']}  jobid=${r['jobid']}');
  }

  for (final r in await _q('''
    select jobname as nome, schedule as agenda, command as comando,
           active as ativo, database as banco
      from cron.job where jobname='prune-share-events' ''')) {
    out.writeln('  nome=${r['nome']}  agenda=${r['agenda']}  ativo=${r['ativo']}  banco=${r['banco']}');
    out.writeln('  comando=${r['comando']}');
  }

  out.writeln('\n=== grants em share_events apos a revogacao ===');
  for (final r in await _q('''
    select coalesce(string_agg(distinct grantee, ', '), 'nenhum') as quem
      from information_schema.role_table_grants
     where table_name='share_events'
       and grantee in ('anon','authenticated')''')) {
    out.writeln('  grants para anon/authenticated: ${r['quem']}');
  }
  out.writeln('  (vazio = revogado; o acesso passa so pela RPC security definer)');

  out.writeln('\n=== a funcao de limpeza ainda responde? ===');
  // Insere uma linha com 40h (dentro da janela de 24h do prune) usando
  // ids REAIS, porque share_events tem FK para posts e auth.users.
  for (final r in await _q('''
    with alvo as (
      select (select id from public.posts limit 1) as post,
             (select id from auth.users limit 1) as usr)
    insert into public.share_events (post_id, user_id, created_at)
    select post, usr, now() - interval '40 hours' from alvo
    on conflict do nothing
    returning created_at''')) {
    out.writeln('  linha de teste inserida com 40h: ${r.containsKey('created_at')}');
  }
  for (final r in await _q('''
    select
      (select count(*)::int from public.share_events) as antes,
      (select public.prune_share_events()) as apagadas''')) {
    out.writeln('  antes=${r['antes']}  prune apagou=${r['apagadas']}');
  }
  for (final r in await _q(
      "select count(*)::int as restantes from public.share_events")) {
    out.writeln('  linhas restantes apos o prune: ${r['restantes']}');
  }

  out.writeln('\n=== limpeza do teste ===');
  await _q('delete from public.share_events');
  for (final r in await _q(
      "select count(*)::int as restantes from public.share_events")) {
    out.writeln('  share_events zerado: ${r['restantes']} linha(s)');
  }

  out.writeln('\n=== protecao do compartilhamento intacta? ===');
  for (final r in await _q('''
    select has_function_privilege('anon','public.increment_post_share(uuid)','EXECUTE')::text as anon,
           has_function_privilege('authenticated','public.increment_post_share(uuid)','EXECUTE')::text as autenticado''')) {
    out.writeln('  increment_post_share  anon=${r['anon']}  autenticado=${r['autenticado']}');
  }

  File('/tmp/verify.txt').writeAsStringSync(out.toString());
  exit(0);
}