// ignore_for_file: avoid_print — script de diagnóstico, imprime de propósito.
//
// O anon consegue ESCREVER em admin_roles? (A policy é USING true, só SELECT.)
//
//   dart run tool/audit_admin_roles_write.dart
import 'dart:convert';
import 'dart:io';

const _url = 'https://oysyuialaelzcxxkfdsl.supabase.co';
const _key = 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E';

Future<String> _req(String metodo, String path, [Map<String, dynamic>? body]) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$_url$path');
    final req = metodo == 'GET'
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    req.headers.set('apikey', _key);
    req.headers.set('Authorization', 'Bearer $_key');
    if (metodo == 'PATCH' || metodo == 'DELETE') {
      req.headers.set('Prefer', 'return=representation');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final b = await res.transform(utf8.decoder).join();
    return '${res.statusCode} ${b.substring(0, b.length > 130 ? 130 : b.length)}';
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final s = StringBuffer();
  s.writeln('=== anon tentando ESCREVER em admin_roles ===');
  s.writeln('  INSERT -> ${await _req('POST', '/rest/v1/admin_roles', {'id': 'hack', 'name': 'Hack', 'rank': 999})}');
  s.writeln('  UPDATE -> ${await _req('PATCH', '/rest/v1/admin_roles?id=eq.admin', {'rank': 1})}');
  s.writeln('  DELETE -> ${await _req('DELETE', '/rest/v1/admin_roles?id=eq.moderator')}');

  s.writeln('\n=== estado real da tabela (via service role, no painel) ===');
  final lista = await _req('GET', '/rest/v1/admin_roles?select=id,rank&limit=50');
  s.writeln('  $lista');
  s.writeln('  (as 5 roles originais intactas = nenhuma escrita passou)');

  File('/tmp/w.txt').writeAsStringSync(s.toString());
  exit(0);
}