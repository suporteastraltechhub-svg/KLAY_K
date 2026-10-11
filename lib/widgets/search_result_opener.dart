import 'package:flutter/material.dart';

import '../models/klayk_live_models.dart';
import '../services/content_service.dart';
import '../services/live_kit_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../screens/hashtag_screen.dart';
import '../screens/live_room_screen.dart';
import '../screens/profile/video_preview_screen.dart';

/// Abre o conteúdo de um resultado de busca.
///
/// Hoje as duas telas de busca (a delegate do feed e o Descobrir) tinham
/// `post` e `live` sem nenhuma ação — tocar não abria nada. Este é o único
/// lugar que resolve os quatro tipos, para as duas UIs compartilharem o
/// mesmo comportamento em vez de duplicar a lógica em cada uma.
Future<void> openSearchResult(BuildContext context, SearchResult result) async {
  switch (result.type) {
    case 'post':
      await _openPost(context, result.id);
    case 'live':
      await _openLive(context, result.id);
    case 'hashtag':
      await openHashtag(
        context,
        result.subtitle.isNotEmpty ? result.subtitle : result.title,
      );
    case 'user':
      // Quem chama decide o destino do usuário (perfil). Mantido fora daqui de
      // propósito: abrir perfil depende do contexto de navegação da tela.
      break;
  }
}

/// Abre a página de uma hashtag com o texto que a busca devolveu.
Future<void> openHashtag(BuildContext context, String rawTag) async {
  final tag = rawTag.trim().replaceAll('#', '');
  if (tag.isEmpty) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => HashtagScreen(tag: tag)));
}

Future<void> _openPost(BuildContext context, String postId) async {
  if (postId.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final post = await ContentService.instance.fetchPostById(postId);
  if (!context.mounted) return;
  if (post == null) {
    _toast(messenger, 'Vídeo não disponível.');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => VideoPreviewScreen(post: post)),
  );
}

Future<void> _openLive(BuildContext context, String liveId) async {
  if (liveId.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final row = await SupabaseService.instance.client
        .from('lives')
        .select(
          '*, profiles:streamer_id(display_name, username, avatar_url, is_verified)',
        )
        .eq('id', liveId)
        .maybeSingle();
    if (!context.mounted) return;
    if (row == null) {
      _toast(messenger, 'Live não disponível.');
      return;
    }
    final live = RealLive.fromJson(
      Map<String, dynamic>.from(
        (row as Map).map((k, v) => MapEntry(k.toString(), v)),
      ),
    );
    if (!context.mounted) return;
    if (live.status != 'live') {
      _toast(messenger, 'Esta Live já terminou.');
      return;
    }
    final isOwner =
        SupabaseService.instance.client.auth.currentUser?.id == live.streamerId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomScreen(
          live: live,
          role: isOwner ? LiveRole.streamer : LiveRole.viewer,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) _toast(messenger, 'Não foi possível abrir a Live.');
  }
}

void _toast(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
