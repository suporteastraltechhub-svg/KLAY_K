import 'dart:convert';
import 'dart:io';

/// Erro de upload cancelado pelo usuário (stream fechado antes do fim).
class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelado.';
}

/// Sobe [file] para o bucket via upload padrão do Supabase Storage
/// (`POST /storage/v1/object/{bucket}/{path}` com corpo binário), lendo o
/// arquivo em fluxo — NUNCA carrega o vídeo inteiro na memória como o
/// multipart do `storage_client` (`readAsBytesSync`).
///
/// [onProgress] recebe o progresso real (0.0 a 1.0) à medida que os bytes são
/// gravados no socket. Se [isCancelled] retornar `true` durante o envio, o
/// fluxo é interrompido (upload abortado sem publicar nada).
Future<String> streamUploadFile({
  required String supabaseUrl,
  required String anonKey,
  required String accessToken,
  required String bucket,
  required String objectPath,
  required File file,
  String contentType = 'application/octet-stream',
  void Function(double progress)? onProgress,
  bool Function()? isCancelled,
}) async {
  final total = await file.length();
  final client = HttpClient();
  try {
    final request = await client.postUrl(_objectUri(supabaseUrl, bucket, objectPath));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.headers.set(HttpHeaders.cacheControlHeader, '3600');
    request.headers.set('apikey', anonKey);
    request.headers.set('x-upsert', 'false');
    request.contentLength = total;

    await request.addStream(
      _progressOf(file.openRead(), total, onProgress, isCancelled),
    );
    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = await utf8.decoder.bind(response).join();
      throw HttpException(
        'Upload falhou (HTTP ${response.statusCode})${body.isEmpty ? '' : ': $body'}',
        uri: request.uri,
      );
    }
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
  return objectPath;
}

Uri _objectUri(String supabaseUrl, String bucket, String objectPath) {
  final encoded = objectPath.split('/').map(Uri.encodeComponent).join('/');
  final base = supabaseUrl.endsWith('/')
      ? supabaseUrl.substring(0, supabaseUrl.length - 1)
      : supabaseUrl;
  return Uri.parse('$base/storage/v1/object/$bucket/$encoded');
}

/// Converte o stream do arquivo em um stream que conta bytes enviados,
/// reporta [onProgress] (0..1) por faixa de 1% (evita setState a cada chunk)
/// e aborta quando [isCancelled] retornar `true`.
Stream<List<int>> _progressOf(
  Stream<List<int>> source,
  int total,
  void Function(double progress)? onProgress,
  bool Function()? isCancelled,
) async* {
  var sent = 0;
  var lastPct = -1;
  await for (final chunk in source) {
    if (isCancelled?.call() ?? false) throw const UploadCancelledException();
    sent += chunk.length;
    final pct = total <= 0 ? 100 : ((sent * 100) / total).floor();
    if (pct != lastPct) {
      lastPct = pct;
      onProgress?.call(total <= 0 ? 1 : (sent / total).clamp(0.0, 1.0).toDouble());
    }
    yield chunk;
  }
  onProgress?.call(1);
}