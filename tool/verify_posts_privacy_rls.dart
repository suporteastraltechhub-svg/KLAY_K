// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
// Verificação de COMPORTAMENTO da privacidade de posts/comments no Supabase.
//
// Usa a chave pública do app (anon) e, quando houver variáveis de ambiente,
// sessões reais para os cenários autenticados.
//
//   dart run tool/verify_posts_privacy_rls.dart
//
// Variáveis opcionais (para os cenários autenticados):
//   KLAYK_OWNER_SESSION     -> post privado + sessão do dono
//   KLAYK_FOLLOWER_SESSION  -> sessão de quem segue o dono
//   KLAYK_STRANGER_SESSION  -> sessão de quem não segue
//
// Sem essas variáveis, só o cenário anonimo roda — e ele sozinho já detecta
// a falha principal: post privado vazando para leitura pública.
import 'dart:convert';
import 'dart:io';

const url = 'https://oysyuialaelzcxxkfdsl.supabase.co';
const anonKey = 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E';

Future<(int, String)> get(String path, {String? token}) async {
  final c = HttpClient();
  final req = await c.getUrl(Uri.parse('$url/rest/v1/$path'));
  req.headers.set('apikey', anonKey);
  req.headers.set('Authorization', 'Bearer ${token ?? anonKey}');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  c.close();
  return (res.statusCode, body);
}

String _erro(String body) {
  if (body.isEmpty) return 'sem corpo';
  try {
    final m = jsonDecode(body);
    if (m is Map && m['message'] != null) return m['message'].toString();
  } catch (_) {}
  return body.substring(0, body.length < 100 ? body.length : 100);
}

Future<void> cenarioAnonimo() async {
  print('\n== cenario anonimo ==');
  final (st, body) = await get('posts?select=id,is_private&limit=100');
  if (st != 200) {
    print('  HTTP $st  migration NAO APLICADA: ${_erro(body)}');
    print('  RESULTADO: inconclusivo — rode após `supabase db push`.');
    return;
  }
  final rows = jsonDecode(body) as List;
  final privados = rows.where((r) => (r as Map)['is_private'] == true).length;
  print('  anonimo enxergou ${rows.length} posts, $privados privados');
  print(
    privados == 0
        ? '  OK: nenhum post privado visivel para anonimo'
        : '  FALHA: $privados post(s) privado(s) vazando',
  );
}

Future<void> cenarioAutenticado(String nome, String? env) async {
  final token = Platform.environment[env];
  print('\n== cenario $nome ==');
  if (token == null || token.isEmpty) {
    print('  PULADO: variavel $env nao definida');
    return;
  }
  final (st, body) = await get(
    'posts?select=id,is_private&limit=100',
    token: token,
  );
  if (st != 200) {
    print('  HTTP $st  inconclusivo: ${_erro(body)}');
    return;
  }
  final rows = body.startsWith('[') ? (jsonDecode(body) as List) : <dynamic>[];
  final privados = rows.where((r) => (r as Map)['is_private'] == true).length;
  print('  HTTP $st  total=${rows.length}  privados visiveis=$privados');
  print('  (dono/seguidor devem ver privado; estranho deve ver 0)');
}

Future<void> cenarioComentarios() async {
  print('\n== cenario comentarios de post privado ==');
  final (st, body) = await get('comments?select=id,post_id&limit=200');
  print(
    '  HTTP $st  ${body.substring(0, body.length < 120 ? body.length : 120)}',
  );
  if (st != 200) {
    print('  HTTP $st  inconclusivo: ${_erro(body)}');
    return;
  }
  final rows = body.startsWith('[') ? (jsonDecode(body) as List) : <dynamic>[];
  final ids = rows
      .map((r) => (r as Map)['post_id'].toString())
      .toSet()
      .toList();
  if (ids.isEmpty) {
    print('  sem comentarios no banco para cruzar');
    return;
  }
  final (st2, body2) = await get(
    'posts?select=id&is_private=eq.true&id=in.(${ids.join(',')})',
  );
  final privados = body2.startsWith('[')
      ? (jsonDecode(body2) as List).length
      : 0;
  print('  comentarios visiveis=${rows.length}  de posts privados=$privados');
  print(
    privados == 0
        ? '  OK: nenhum comentario de post privado visivel'
        : '  FALHA: $privados comentario(s) de post privado vazando',
  );
}

Future<void> main() async {
  print('Verificacao RLS de privacidade — $url');
  await cenarioAnonimo();
  await cenarioAutenticado('dono', 'KLAYK_OWNER_SESSION');
  await cenarioAutenticado('seguidor', 'KLAYK_FOLLOWER_SESSION');
  await cenarioAutenticado('nao_seguidor', 'KLAYK_STRANGER_SESSION');
  await cenarioComentarios();
  exit(0);
}
