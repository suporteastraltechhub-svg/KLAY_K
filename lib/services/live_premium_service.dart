import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Emojis permitidos nas reações de chat da live (whitelist do backend).
const List<String> kLiveReactionEmojis = ['❤️', '🔥', '😂', '👍', '🎉', '💎'];

/// Um registro de ranking real (top da live ou global por moeda).
@immutable
class LiveRankRecord {
  final int rank;
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final double value;
  final String scope;
  final bool isVerified;

  const LiveRankRecord({
    required this.rank,
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.value = 0,
    this.scope = 'global',
    this.isVerified = false,
  });

  factory LiveRankRecord.fromJson(Map<String, dynamic> json) => LiveRankRecord(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: json['user_id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        displayName: json['display_name']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
        value: (json['value'] as num?)?.toDouble() ?? 0,
        scope: json['scope']?.toString() ?? 'global',
        isVerified: json['is_verified'] == true,
      );
}

/// Preferências da bolinha flutuante premium (persistidas em `user_settings`).
@immutable
class LiveBubblePrefs {
  final bool enabled;
  final double positionX;
  final double positionY;
  final bool minimized;

  const LiveBubblePrefs({
    this.enabled = false,
    this.positionX = 0,
    this.positionY = 0,
    this.minimized = false,
  });

  factory LiveBubblePrefs.fromSettings(Map<String, dynamic>? s) {
    if (s == null) return const LiveBubblePrefs();
    bool b(dynamic v, bool d) => v is bool ? v : d;
    double d(dynamic v, double fallback) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? fallback : fallback);
    return LiveBubblePrefs(
      enabled: b(s['live_bubble_enabled'], false),
      positionX: d(s['live_bubble_x'], 0),
      positionY: d(s['live_bubble_y'], 0),
      minimized: b(s['live_bubble_minimized'], false),
    );
  }

  LiveBubblePrefs copyWith({
    bool? enabled,
    double? positionX,
    double? positionY,
    bool? minimized,
  }) =>
      LiveBubblePrefs(
        enabled: enabled ?? this.enabled,
        positionX: positionX ?? this.positionX,
        positionY: positionY ?? this.positionY,
        minimized: minimized ?? this.minimized,
      );

  Map<String, dynamic> toSettings() => {
        'live_bubble_enabled': enabled,
        'live_bubble_x': positionX,
        'live_bubble_y': positionY,
        'live_bubble_minimized': minimized,
      };
}

/// Configuração HONESTA do bot de voz da live. O app só habilita a opção se um
/// provedor real estiver configurado; jamais finge voz ou IA.
@immutable
class VoiceBotConfig {
  final bool enabled;
  final String? provider;
  final String? voice;

  const VoiceBotConfig({this.enabled = false, this.provider, this.voice});

  factory VoiceBotConfig.fromSettings(Map<String, dynamic>? s) {
    if (s == null) return const VoiceBotConfig();
    return VoiceBotConfig(
      enabled: s['voice_bot_enabled'] == true,
      provider: s['voice_bot_provider']?.toString(),
      voice: s['voice_bot_voice']?.toString(),
    );
  }

  Map<String, dynamic> toSettings() => {
        'voice_bot_enabled': enabled,
        'voice_bot_provider': provider,
        'voice_bot_voice': voice,
      };
}

/// Camada premium de lives do KLAY K: chat validado no backend, reações,
/// rankings por moeda real e preferências (bolinha/bot de voz) em
/// `user_settings` (RLS owner). Nada aqui inventa dados — tudo vem de RPCs.
class LivePremiumService {
  LivePremiumService._();

  static final LivePremiumService instance = LivePremiumService._();

  SupabaseService get _db => SupabaseService.instance;

  SupabaseClient get _client => _db.client;

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Reações no chat
  // ---------------------------------------------------------------------

  /// Alterna a reação do usuário na mensagem (RPC `live_toggle_reaction`).
  /// Retorna `{active, removed, total}`.
  Future<Map<String, dynamic>> toggleReaction(
    String messageId,
    String emoji,
  ) async {
    if (!_ready || !kLiveReactionEmojis.contains(emoji)) {
      return const {};
    }
    await _db.ensureAuthenticated();
    final res = await _client.rpc(
      'live_toggle_reaction',
      params: {'p_message_id': messageId, 'p_emoji': emoji},
    );
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Agregado inicial de reações da sala (`live_chat_reactions`).
  /// Retorna mapa `messageId -> (emoji -> total)`.
  Future<Map<String, Map<String, int>>> fetchRoomReactions(
    String liveId,
  ) async {
    if (!_ready) return const {};
    final res = await _client.rpc(
      'live_chat_reactions',
      params: {'p_live_id': liveId},
    );
    final out = <String, Map<String, int>>{};
    if (res is! List) return out;
    for (final row in res.whereType<Map<dynamic, dynamic>>()) {
      final mid = row['message_id']?.toString();
      final emoji = row['emoji']?.toString();
      final total = (row['total'] as num?)?.toInt() ?? 0;
      if (mid == null || emoji == null) continue;
      out.putIfAbsent(mid, () => {})[emoji] = total;
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Rankings por moeda real
  // ---------------------------------------------------------------------

  Future<List<LiveRankRecord>> fetchLiveRanking({
    required String liveId,
    required String currency,
    int limit = 20,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client.rpc(
      'live_ranking',
      params: {
        'p_live_id': liveId,
        'p_currency': currency,
        'p_limit': limit,
      },
    );
    return _parseRanking(res);
  }

  Future<List<LiveRankRecord>> fetchTopSupporters({
    required String liveId,
    int limit = 20,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client.rpc(
      'live_top_supporters',
      params: {'p_live_id': liveId, 'p_limit': limit},
    );
    return _parseRanking(res);
  }

  Future<List<LiveRankRecord>> fetchCurrencyRanking(
    String currency, {
    int limit = 20,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client.rpc(
      'currency_ranking',
      params: {'p_currency': currency, 'p_limit': limit},
    );
    return _parseRanking(res);
  }

  List<LiveRankRecord> _parseRanking(dynamic res) {
    if (res is! List) return const [];
    return res
        .whereType<Map<dynamic, dynamic>>()
        .map((r) => LiveRankRecord.fromJson(
            Map<String, dynamic>.from(r)))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Bolinha flutuante (preferências em `user_settings`)
  // ---------------------------------------------------------------------
  static const String _premiumColumns =
      'live_bubble_enabled,live_bubble_x,live_bubble_y,live_bubble_minimized,'
      'voice_bot_enabled,voice_bot_provider,voice_bot_voice';

  Future<LiveBubblePrefs> fetchBubblePrefs() async {
    if (!_ready) return const LiveBubblePrefs();
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const LiveBubblePrefs();
    try {
      final res = await _client
          .from('user_settings')
          .select(_premiumColumns)
          .eq('user_id', uid)
          .maybeSingle();
      return LiveBubblePrefs.fromSettings(res);
    } catch (_) {
      return const LiveBubblePrefs();
    }
  }

  Future<void> saveBubblePrefs(LiveBubblePrefs prefs) async {
    if (!_ready) return;
    await _db.ensureAuthenticated();
    final uid = _client.auth.currentUser!.id;
    await _client.from('user_settings').upsert({
      'user_id': uid,
      ...prefs.toSettings(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<VoiceBotConfig> fetchVoiceBot() async {
    if (!_ready) return const VoiceBotConfig();
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const VoiceBotConfig();
    try {
      final res = await _client
          .from('user_settings')
          .select(_premiumColumns)
          .eq('user_id', uid)
          .maybeSingle();
      return VoiceBotConfig.fromSettings(res);
    } catch (_) {
      return const VoiceBotConfig();
    }
  }

  Future<void> saveVoiceBot(VoiceBotConfig config) async {
    if (!_ready) return;
    await _db.ensureAuthenticated();
    final uid = _client.auth.currentUser!.id;
    await _client.from('user_settings').upsert({
      'user_id': uid,
      ...config.toSettings(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }
}