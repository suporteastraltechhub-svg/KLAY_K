import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Resultado de uma limpeza real, com os bytes efetivamente liberados.
class CacheCleanResult {
  /// Bytes removidos do cache de imagens do Flutter.
  final int imageCacheBytes;

  /// Bytes removidos do diretório temporário do app.
  final int tempBytes;

  /// Pastas/arquivos que não puderam ser removidos (em uso, sem permissão).
  final List<String> skipped;

  const CacheCleanResult({
    this.imageCacheBytes = 0,
    this.tempBytes = 0,
    this.skipped = const [],
  });

  int get totalBytes => imageCacheBytes + tempBytes;

  bool get removedAnything => totalBytes > 0;
}

/// Manutenção do armazenamento local do KLAY K.
///
/// Só mexe em cache e arquivos temporários do próprio aparelho. **Nunca**
/// apaga dados de conta, vídeos, mensagens ou qualquer coisa do servidor —
/// "Reiniciar configurações" restaura apenas preferências locais.
class MaintenanceService {
  MaintenanceService._();

  static final MaintenanceService instance = MaintenanceService._();

  /// Mede o uso real do cache de imagens do Flutter e do diretório
  /// temporário. Não inventa números: se não conseguir medir, devolve null.
  Future<({int images, int cache, int temp})?> measure() async {
    try {
      final images = await _dirSize(await _imageCacheDir());
      final cache = await _dirSize(await _appCacheDir());
      final temp = await _dirSize(await _tempDir());
      return (images: images, cache: cache, temp: temp);
    } catch (_) {
      return null;
    }
  }

  /// Limpa cache de imagens, cache do app e temporários.
  Future<CacheCleanResult> clearCache() async {
    var imageBytes = 0;
    var tempBytes = 0;
    final skipped = <String>[];

    final imageCache = PaintingBinding.instance.imageCache;
    imageBytes = _safeSize(imageCache.currentSizeBytes);
    imageCache.clear();
    imageCache.clearLiveImages();

    Future<void> wipe(Directory dir) async {
      try {
        if (!await dir.exists()) return;
        await for (final e in dir.list(followLinks: false)) {
          try {
            final size = e is File
                ? await e.length()
                : (e is Directory ? _dirSizeSync(e) : 0);
            await e.delete(recursive: true);
            if (e is File) tempBytes += size;
          } catch (_) {
            skipped.add(e.path.split('/').last);
          }
        }
      } catch (_) {
        skipped.add(dir.path.split('/').last);
      }
    }

    await wipe(await _tempDir());
    try {
      await wipe(await _imageCacheDir());
    } catch (_) {}

    return CacheCleanResult(
      imageCacheBytes: imageBytes,
      tempBytes: tempBytes,
      skipped: skipped,
    );
  }

  Future<Directory> _tempDir() => getTemporaryDirectory();

  Future<Directory> _appCacheDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/cache');
  }

  Future<Directory> _imageCacheDir() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/flutter_cache');
  }

  Future<int> _dirSize(Directory d) async {
    if (!await d.exists()) return 0;
    var total = 0;
    try {
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  int _dirSizeSync(Directory d) {
    var total = 0;
    try {
      for (final e in d.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  static int _safeSize(int? v) => v ?? 0;

  /// Formata bytes em unidade legível.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    final digits = value >= 100 || i <= 1 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[i]}';
  }
}