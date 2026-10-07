import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/live_bot_models.dart';
import 'supabase_service.dart';

/// Camada de dados do KLAY K LIVE BOT.
///
/// Toda escrita é validada NO BACKEND por RPCs `security definer` que exigem
/// `can_moderate_live(live_id)` (dono da live ou moderador). O app nunca decide
/// permissão localmente e nunca envia chaves/segredos.
class LiveBotService {
  LiveBotService._();

  static final LiveBotService instance = LiveBotService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<dynamic> _rpc(String name, [Map<String, dynamic> params = const {}]) {
    return _db.rpc(name, params: params);
  }

  /// Obtém as configurações atuais do bot para uma live.
  Future<LiveBotSettings> getSettings(String liveId) async {
    final r = await _rpc('live_bot_get_settings', {'p_live_id': liveId});
    final map = r is Map ? Map<String, dynamic>.from(r) : null;
    return LiveBotSettings.fromRpc(map);
  }

  /// Salva as configurações (dono/moderador).
  Future<void> saveSettings(String liveId, LiveBotSettings s) async {
    await _rpc('live_bot_save_settings', {
      'p_live_id': liveId,
      'p_enabled': s.enabled,
      'p_voice_settings': s.voice.toJson(),
      'p_comment_reading_mode': s.commentMode.value,
      'p_comments_enabled': s.commentsEnabled,
      'p_auto_replies_enabled': s.autoRepliesEnabled,
      'p_auto_replies': s.autoReplies.map((e) => e.toJson()).toList(),
      'p_announcements_enabled': s.announcementsEnabled,
      'p_announcements_interval_seconds': s.announcementsIntervalSeconds,
      'p_moderation_enabled': s.moderationEnabled,
    });
  }

  /// Lista os anúncios da live.
  Future<List<LiveBotAnnouncement>> listAnnouncements(String liveId) async {
    final r = await _rpc('live_bot_list_announcements', {'p_live_id': liveId});
    final list = (r is List) ? r : const [];
    return list
        .whereType<Map>()
        .map((e) => LiveBotAnnouncement.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Cria um anúncio (dono/moderador).
  Future<void> addAnnouncement(
    String liveId,
    String message, {
    int intervalSeconds = 120,
  }) async {
    await _rpc('live_bot_add_announcement', {
      'p_live_id': liveId,
      'p_message': message,
      'p_interval_seconds': intervalSeconds,
    });
  }

  /// Ativa/desativa um anúncio (dono/moderador).
  Future<void> setAnnouncementEnabled(
    String announcementId,
    bool enabled,
  ) async {
    await _rpc('live_bot_set_announcement_enabled', {
      'p_announcement_id': announcementId,
      'p_enabled': enabled,
    });
  }

  /// Remove um anúncio (dono/moderador).
  Future<void> deleteAnnouncement(String announcementId) async {
    await _rpc('live_bot_delete_announcement', {
      'p_announcement_id': announcementId,
    });
  }

  /// Registra um log do bot.
  Future<void> log(
    String liveId, {
    String eventType = 'bot',
    String message = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _rpc('live_bot_log', {
        'p_live_id': liveId,
        'p_event_type': eventType,
        'p_message': message,
        'p_metadata': metadata,
      });
    } catch (_) {
      // Log não deve quebrar a experiência principal.
    }
  }

  // -------------------------------------------------------------------------
  // Realtime: seleção de comentário → o bot de backend lê e fala na sala.
  // -------------------------------------------------------------------------

  /// Canal de broadcast para o bot ler/selecionar comentários em tempo real.
  RealtimeChannel channel(String liveId) => _db.channel('live-bot-$liveId');

  void disposeChannel(RealtimeChannel channel) {
    _db.removeChannel(channel);
  }
}
