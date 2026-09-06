import 'package:flutter/material.dart' show IconData, Icons, immutable;

/// Modos de leitura de comentários pelo Live Bot.
enum LiveBotCommentMode {
  all('all', 'Ler todos', 'Lê todos os comentários do chat.',
      Icons.chat_bubble_outline_rounded),
  selected('selected', 'Comentários selecionados', 'Lê apenas comentários escolhidos.',
      Icons.push_pin_rounded),
  questions('questions', 'Ler perguntas', 'Lê comentários que parecem perguntas.',
      Icons.help_outline_rounded),
  highlighted('highlighted', 'Apenas destacados', 'Lê comentários destacados pelo criador.',
      Icons.star_border_rounded);

  const LiveBotCommentMode(this.value, this.label, this.description, this.icon);
  final String value;
  final String label;
  final String description;
  final IconData icon;

  static LiveBotCommentMode fromValue(String? v) =>
      LiveBotCommentMode.values.firstWhere(
        (m) => m.value == v,
        orElse: () => LiveBotCommentMode.selected,
      );
}

/// Prioridade da fila de fala (1 = mais urgente).
enum LiveBotSpeechPriority {
  warnings(1, '🚨', 'Aviso'),
  moderation(2, '🛡️', 'Moderação'),
  selectedComment(3, '📌', 'Comentário'),
  autoReply(4, '🤖', 'Resposta'),
  announcement(5, '📢', 'Anúncio');

  const LiveBotSpeechPriority(this.rank, this.icon, this.label);
  final int rank;
  final String icon;
  final String label;
}

/// Configurações de voz do bot (enviadas ao backend / bot).
@immutable
class LiveBotVoiceSettings {
  final String? voice; // identificador da voz (vazio = automática)
  final String? voiceType; // 'auto' | 'female' | 'male'
  final String language; // 'pt-BR' (fixo nesta versão)
  final double speed; // 0.0..1.0+ (ex.: 0.5 = normal)
  final double volume; // 0.0..1.0

  const LiveBotVoiceSettings({
    this.voice,
    this.voiceType,
    this.language = 'pt-BR',
    this.speed = 0.5,
    this.volume = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'voice': voice,
        'voice_type': voiceType,
        'language': language,
        'speed': speed,
        'volume': volume,
      };

  LiveBotVoiceSettings copyWith({
    String? voice,
    String? voiceType,
    String? language,
    double? speed,
    double? volume,
  }) {
    return LiveBotVoiceSettings(
      voice: voice ?? this.voice,
      voiceType: voiceType ?? this.voiceType,
      language: language ?? this.language,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
    );
  }

  static LiveBotVoiceSettings fromJson(Map<String, dynamic>? j) {
    if (j == null) return const LiveBotVoiceSettings();
    return LiveBotVoiceSettings(
      voice: j['voice']?.toString(),
      voiceType: j['voice_type']?.toString(),
      language: j['language']?.toString() ?? 'pt-BR',
      speed: (j['speed'] as num?)?.toDouble() ?? 0.5,
      volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Resposta automática configurada pelo criador.
@immutable
class LiveBotAutoReply {
  final String question;
  final String answer;

  const LiveBotAutoReply({required this.question, required this.answer});

  Map<String, dynamic> toJson() => {'question': question, 'answer': answer};

  static LiveBotAutoReply fromJson(Map<String, dynamic> j) =>
      LiveBotAutoReply(
        question: j['question']?.toString() ?? '',
        answer: j['answer']?.toString() ?? '',
      );
}

/// Configurações completas do Live Bot para uma live.
@immutable
class LiveBotSettings {
  final bool enabled;
  final LiveBotVoiceSettings voice;
  final LiveBotCommentMode commentMode;
  final bool commentsEnabled;
  final bool autoRepliesEnabled;
  final List<LiveBotAutoReply> autoReplies;
  final bool announcementsEnabled;
  final int announcementsIntervalSeconds;
  final bool moderationEnabled;

  const LiveBotSettings({
    this.enabled = false,
    this.voice = const LiveBotVoiceSettings(),
    this.commentMode = LiveBotCommentMode.selected,
    this.commentsEnabled = true,
    this.autoRepliesEnabled = false,
    this.autoReplies = const [],
    this.announcementsEnabled = true,
    this.announcementsIntervalSeconds = 120,
    this.moderationEnabled = false,
  });

  LiveBotSettings copyWith({
    bool? enabled,
    LiveBotVoiceSettings? voice,
    LiveBotCommentMode? commentMode,
    bool? commentsEnabled,
    bool? autoRepliesEnabled,
    List<LiveBotAutoReply>? autoReplies,
    bool? announcementsEnabled,
    int? announcementsIntervalSeconds,
    bool? moderationEnabled,
  }) {
    return LiveBotSettings(
      enabled: enabled ?? this.enabled,
      voice: voice ?? this.voice,
      commentMode: commentMode ?? this.commentMode,
      commentsEnabled: commentsEnabled ?? this.commentsEnabled,
      autoRepliesEnabled: autoRepliesEnabled ?? this.autoRepliesEnabled,
      autoReplies: autoReplies ?? this.autoReplies,
      announcementsEnabled: announcementsEnabled ?? this.announcementsEnabled,
      announcementsIntervalSeconds:
          announcementsIntervalSeconds ?? this.announcementsIntervalSeconds,
      moderationEnabled: moderationEnabled ?? this.moderationEnabled,
    );
  }

  LiveBotSettings copyWithVoiceType(String voiceType) =>
      copyWith(voice: voice.copyWith(voiceType: voiceType));

  LiveBotSettings copyWithSpeed(double speed) =>
      copyWith(voice: voice.copyWith(speed: speed));

  LiveBotSettings copyWithVolume(double volume) =>
      copyWith(voice: voice.copyWith(volume: volume));

  LiveBotSettings copyWithCommentMode(LiveBotCommentMode mode) =>
      copyWith(commentMode: mode);

  LiveBotSettings copyWithCommentsEnabled(bool v) => copyWith(commentsEnabled: v);

  LiveBotSettings copyWithModerationEnabled(bool v) =>
      copyWith(moderationEnabled: v);

  LiveBotSettings copyWithAnnouncementsEnabled(bool v) =>
      copyWith(announcementsEnabled: v);

  LiveBotSettings copyWithAutoRepliesEnabled(bool v) =>
      copyWith(autoRepliesEnabled: v);

  factory LiveBotSettings.fromRpc(Map<String, dynamic>? j) {
    if (j == null || j.isEmpty) return const LiveBotSettings();
    final ar = (j['auto_replies'] as List?) ?? const [];
    return LiveBotSettings(
      enabled: j['enabled'] == true,
      voice: LiveBotVoiceSettings.fromJson(
        j['voice_settings'] is Map
            ? Map<String, dynamic>.from((j['voice_settings'] as Map))
            : null,
      ),
      commentMode: LiveBotCommentMode.fromValue(j['comment_reading_mode']?.toString()),
      commentsEnabled: j['comments_enabled'] != false,
      autoRepliesEnabled: j['auto_replies_enabled'] == true,
      autoReplies: [
        for (final e in ar)
          if (e is Map)
            LiveBotAutoReply.fromJson(Map<String, dynamic>.from(e)),
      ],
      announcementsEnabled: j['announcements_enabled'] != false,
      announcementsIntervalSeconds:
          (j['announcements_interval_seconds'] as num?)?.toInt() ?? 120,
      moderationEnabled: j['moderation_enabled'] == true,
    );
  }
}

/// Item da fila de fala.
@immutable
class LiveBotSpeechItem {
  final String text;
  final LiveBotSpeechPriority priority;
  final String? commentAuthor;
  final String id;

  const LiveBotSpeechItem({
    required this.text,
    this.priority = LiveBotSpeechPriority.announcement,
    this.commentAuthor,
    String? id,
  }) : id = id ?? '';

  String get display => commentAuthor != null
      ? '$commentAuthor disse: $text'
      : text;
}

/// Um anúncio salvo no backend.
@immutable
class LiveBotAnnouncement {
  final String id;
  final String liveId;
  final String message;
  final int intervalSeconds;
  final bool enabled;

  const LiveBotAnnouncement({
    required this.id,
    required this.liveId,
    required this.message,
    required this.intervalSeconds,
    required this.enabled,
  });

  factory LiveBotAnnouncement.fromJson(Map<String, dynamic> j) =>
      LiveBotAnnouncement(
        id: j['id']?.toString() ?? '',
        liveId: j['live_id']?.toString() ?? '',
        message: j['message']?.toString() ?? '',
        intervalSeconds:
            (j['interval_seconds'] as num?)?.toInt() ?? 120,
        enabled: j['enabled'] != false,
      );
}
