import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Preferências de notificação do usuário (espelho da tabela
/// `notification_preferences` — RPCs security definer no backend).
class NotificationPrefs {
  final bool likes;
  final bool comments;
  final bool follows;
  final bool messages;
  final bool live;
  final bool missions;
  final bool rewards;
  final bool pushEnabled;

  const NotificationPrefs({
    this.likes = true,
    this.comments = true,
    this.follows = true,
    this.messages = true,
    this.live = true,
    this.missions = true,
    this.rewards = true,
    this.pushEnabled = false,
  });

  NotificationPrefs copyWith({
    bool? likes,
    bool? comments,
    bool? follows,
    bool? messages,
    bool? live,
    bool? missions,
    bool? rewards,
    bool? pushEnabled,
  }) =>
      NotificationPrefs(
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        follows: follows ?? this.follows,
        messages: messages ?? this.messages,
        live: live ?? this.live,
        missions: missions ?? this.missions,
        rewards: rewards ?? this.rewards,
        pushEnabled: pushEnabled ?? this.pushEnabled,
      );

  factory NotificationPrefs.fromMap(Map<String, dynamic> json) =>
      NotificationPrefs(
        likes: json['likes'] as bool? ?? true,
        comments: json['comments'] as bool? ?? true,
        follows: json['follows'] as bool? ?? true,
        messages: json['messages'] as bool? ?? true,
        live: json['live'] as bool? ?? true,
        missions: json['missions'] as bool? ?? true,
        rewards: json['rewards'] as bool? ?? true,
        pushEnabled: json['push_enabled'] as bool? ?? false,
      );
}

/// Serviço de preferências de notificação. Toda leitura/escrita via RPC
/// security definer do backend; o cliente nunca acessa a tabela diretamente.
class NotifPrefsService {
  NotifPrefsService._();

  static final NotifPrefsService instance = NotifPrefsService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<NotificationPrefs> fetch() async {
    try {
      final r = await _db.rpc('my_notification_prefs');
      if (r is Map) {
        return NotificationPrefs.fromMap(_stringMap(r));
      }
    } catch (_) {}
    return const NotificationPrefs();
  }

  Future<NotificationPrefs> save(NotificationPrefs prefs) async {
    try {
      final r = await _db.rpc('save_notification_prefs', params: {
        'p_likes': prefs.likes,
        'p_comments': prefs.comments,
        'p_follows': prefs.follows,
        'p_messages': prefs.messages,
        'p_live': prefs.live,
        'p_missions': prefs.missions,
        'p_rewards': prefs.rewards,
        'p_push_enabled': prefs.pushEnabled,
      });
      if (r is Map) {
        return NotificationPrefs.fromMap(_stringMap(r));
      }
    } catch (_) {}
    return prefs;
  }

  Map<String, dynamic> _stringMap(Map<dynamic, dynamic> m) => m.map(
        (k, v) => MapEntry(k.toString(), v),
      );
}