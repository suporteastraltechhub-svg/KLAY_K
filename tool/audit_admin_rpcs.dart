// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// Testa EMPIRICAMENTE se as funções administrativas realmente bloqueiam o
// papel `anon`, chamando-as pelo PostgREST como faria um atacante.
//
// Não altera dados: nas funções que escrevem, o alvo é um UUID inexistente,
// então mesmo que a guarda falhe o efeito é nulo.
//
//   dart run tool/audit_admin_rpcs.dart
import 'dart:convert';
import 'dart:io';

const _url = 'https://oysyuialaelzcxxkfdsl.supabase.co';
const _key = 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E';

Future<String> _post(String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final r = await client
        .postUrl(Uri.parse('$_url/rest/v1/rpc/$path'))
      ..headers.set('apikey', _key)
      ..headers.set('Authorization', 'Bearer $_key')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    final res = await r.close();
    return '${res.statusCode} ${await res.transform(utf8.decoder).join()}';
  } finally {
    client.close(force: true);
  }
}

Future<String> _get(String path) async {
  final client = HttpClient();
  try {
    final r = await client.getUrl(Uri.parse('$_url/rest/v1/$path'))
      ..headers.set('apikey', _key)
      ..headers.set('Authorization', 'Bearer $_key');
    final res = await r.close();
    return '${res.statusCode} ${await res.transform(utf8.decoder).join()}';
  } finally {
    client.close(force: true);
  }
}

/// 401/403 = barrado (bom). 200 = passou (ruim, se vazou dado).
String _julga(String resposta) {
  final code = resposta.split(' ').first;
  if (code == '200') return '*** VAZOU ***';
  if (code == '401' || code == '403') return 'barrado';
  if (code == '404') return 'inexistente';
  if (code == '400' || code == '405') return 'barrado (param/erro)';
  return 'http $code';
}

const _uuidFalso = '00000000-0000-0000-0000-000000000000';

Future<void> main() async {
  final out = StringBuffer();
  var vazamentos = 0;

  out.writeln('\n=== funcoes de LEITURA administrativas, chamada como anon ===');
  final leituras = <String, Map<String, dynamic>>{
    'admin_list_staff': {},
    'admin_audit_list': {'p_limit': 1},
    'admin_economy_stats': {},
    'admin_finance_stats': {},
    'admin_finance_orders': {'p_limit': 1},
    'admin_list_tickets': {'p_status': 'aberto'},
    'admin_list_verifications': {'p_status': 'pending'},
    'admin_chest_stats': {},
    'admin_list_payouts': {'p_limit': 1},
    'admin_ads_reports': {},
    'admin_ads_list': {'p_status': null, 'p_advertiser_name': null, 'p_category': null},
    'my_finance_history': {'p_limit': 1},
    'my_wallet': {},
    'my_caps': {},
    'my_role': {},
  };
  for (final e in leituras.entries) {
    final r = await _post(e.key, e.value);
    final j = _julga(r);
    if (j.startsWith('***')) vazamentos++;
    final corpo = r.length > 90 ? r.substring(0, 90) : r;
    out.writeln('  ${e.key.padRight(26)} $j   $corpo');
  }

  out.writeln('\n=== funcoes de ESCRITA administrativa, alvo inexistente ===');
  final escritas = <String, Map<String, dynamic>>{
    'admin_set_role': {'p_user_id': _uuidFalso, 'p_role': 'admin', 'p_reason': 'teste'},
    'admin_grant_currency': {'p_user_id': _uuidFalso, 'p_currency': 'KLAYK', 'p_amount': 1, 'p_note': 'teste'},
    'admin_grant_chest': {'p_user_id': _uuidFalso, 'p_chest_id': 'x', 'p_source': 'teste'},
    'grant_initial_credits': {},
    'sync_is_admin_from_role': {},
  };
  for (final e in escritas.entries) {
    final r = await _post(e.key, e.value);
    final j = _julga(r);
    if (j.startsWith('***')) vazamentos++;
    final corpo = r.length > 90 ? r.substring(0, 90) : r;
    out.writeln('  ${e.key.padRight(26)} $j   $corpo');
  }

  out.writeln('\n=== leitura direta de tabelas sensiveis via PostgREST (anon) ===');
  final tabelas = <String>[
    'user_wallets',
    'credit_transactions',
    'financial_orders',
    'financial_payments',
    'admin_roles',
    'audit_logs',
    'store_orders',
    'verification_requests',
    'security_scores',
    'founder_blocked_ips',
  ];
  for (final t in tabelas) {
    final r = await _get('$t?select=*&limit=1');
    final j = _julga(r);
    // 200 com [] é aceitavel (RLS filtrou tudo). 200 com objeto e vazamento.
    final vazouDados = r.startsWith('200') && !r.contains('[]');
    if (vazouDados) vazamentos++;
    final corpo = r.length > 80 ? r.substring(0, 80) : r;
    out.writeln('  ${t.padRight(24)} ${vazouDados ? '*** VAZOU ***' : j}   $corpo');
  }

  out.writeln('\n=== leitura de share_events (deve estar bloqueada) ===');
  final sr = await _get('share_events?select=*&limit=1');
  out.writeln('  $sr');

  out.writeln('\n=== resumo ===');
  out.writeln('  pontos de vazamento encontrados: $vazamentos');

  File('/tmp/rpc.txt').writeAsStringSync(out.toString());
  exit(0);
}