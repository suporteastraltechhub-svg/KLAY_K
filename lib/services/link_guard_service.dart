import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Confirmação de links externos.
///
/// Antes de abrir qualquer link fora do KLAY K, o app mostra "Você está saindo
/// do KLAY K" e o domínio de destino. Só abre se o usuário confirmar. Não
/// altera nenhum fluxo existente: basta trocar `launchUrl` por
/// [LinkGuard.openExternal] onde já há abertura de link.
class LinkGuard {
  LinkGuard._();

  static final LinkGuard instance = LinkGuard._();

  /// Abre [url] fora do app após confirmação. Retorna true se abriu.
  Future<bool> openExternal(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final confirmed = await confirm(context, uri);
    if (!confirmed) return false;
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Mostra o diálogo de confirmação. Retorna false se o usuário cancelar.
  Future<bool> confirm(BuildContext context, Uri uri) async {
    final domain = uri.host.isEmpty ? 'destino externo' : uri.host;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFFB794FF)),
        title: const Text(
          'Você está saindo do KLAY K',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Este link abre um site ou aplicativo externo. O KLAY K não é '
              'responsável pelo conteúdo de destinos externos.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.language_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    domain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB794FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
