import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// ============================================================================
/// Preferências de EXPERIÊNCIA do KLAY K (performáticas e realmente funcionais)
///
/// Estado global em memória + persistência em `user_settings` (RLS owner).
/// Consumido por players, animações e transições — todas as opções aqui têm
/// efeito real (auto-play, economia de dados, reduzir animações, qualidade).
/// ============================================================================

@immutable
class KlaykExperience {
  final bool reduceAnimations;
  final bool reduceEffects;
  final bool autoPlay;
  final bool wifiOnly;
  final bool saveData;
  final String videoQuality; // 'auto' | 'hd' | 'sd'
  final bool showReactions;

  const KlaykExperience({
    this.reduceAnimations = false,
    this.reduceEffects = false,
    this.autoPlay = true,
    this.wifiOnly = false,
    this.saveData = false,
    this.videoQuality = 'auto',
    this.showReactions = true,
  });

  KlaykExperience copyWith({
    bool? reduceAnimations,
    bool? reduceEffects,
    bool? autoPlay,
    bool? wifiOnly,
    bool? saveData,
    String? videoQuality,
    bool? showReactions,
  }) {
    return KlaykExperience(
      reduceAnimations: reduceAnimations ?? this.reduceAnimations,
      reduceEffects: reduceEffects ?? this.reduceEffects,
      autoPlay: autoPlay ?? this.autoPlay,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      saveData: saveData ?? this.saveData,
      videoQuality: videoQuality ?? this.videoQuality,
      showReactions: showReactions ?? this.showReactions,
    );
  }

  factory KlaykExperience.fromSettings(Map<String, dynamic>? s) {
    if (s == null) return const KlaykExperience();
    bool b(dynamic v, bool d) => v is bool ? v : d;
    return KlaykExperience(
      reduceAnimations: b(s['reduce_animations'], false),
      reduceEffects: b(s['reduce_effects'], false),
      autoPlay: b(s['auto_play'], true),
      wifiOnly: b(s['wifi_only'], false),
      saveData: b(s['save_data'], false),
      videoQuality: s['video_quality']?.toString() ?? 'auto',
      showReactions: b(s['show_reactions'], true),
    );
  }

  Map<String, dynamic> toSettings() => {
    'reduce_animations': reduceAnimations,
    'reduce_effects': reduceEffects,
    'auto_play': autoPlay,
    'wifi_only': wifiOnly,
    'save_data': saveData,
    'video_quality': videoQuality,
    'show_reactions': showReactions,
  };
}

class ExperienceSettings {
  ExperienceSettings._();

  static final ExperienceSettings instance = ExperienceSettings._();

  final ValueNotifier<KlaykExperience> prefs = ValueNotifier(
    const KlaykExperience(),
  );

  bool _dirty = false;

  KlaykExperience get value => prefs.value;

  bool get reduceAnimations => prefs.value.reduceAnimations;
  bool get reduceEffects => prefs.value.reduceEffects;
  bool get autoPlay => prefs.value.autoPlay;
  bool get wifiOnly => prefs.value.wifiOnly;
  bool get saveData => prefs.value.saveData;
  String get videoQuality => prefs.value.videoQuality;

  /// Carrega preferências de experiência de `user_settings` (RLS owner).
  Future<void> load() async {
    if (!SupabaseService.instance.isConfigured) return;
    try {
      final uid = SupabaseService.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final res = await SupabaseService.instance.client
          .from('user_settings')
          .select(
            'reduce_animations,reduce_effects,auto_play,wifi_only,save_data,video_quality,show_reactions',
          )
          .eq('user_id', uid)
          .maybeSingle();
      prefs.value = KlaykExperience.fromSettings(res);
    } catch (_) {
      prefs.value = const KlaykExperience();
    }
  }

  Future<void> update(KlaykExperience next) async {
    prefs.value = next;
    _dirty = true;
    _persistSoon();
  }

  /// Atualiza apenas em memória (usado quando outra tela já persiste a mesma
  /// linha, evitando gravações duplicadas).
  void syncInMemory(KlaykExperience next) {
    prefs.value = next;
  }

  void _persistSoon() {
    // Persistência assíncrona sem bloquear a UI; múltiplas mudanças rápidas
    // são coalescidas pelo próprio notifier (último valor vence).
    if (!SupabaseService.instance.isConfigured) return;
    Future<dynamic>.delayed(const Duration(milliseconds: 300), () async {
      if (!_dirty) return;
      _dirty = false;
      try {
        final s = prefs.value.toSettings();
        final uid = SupabaseService.instance.client.auth.currentUser?.id;
        if (uid == null) return;
        await SupabaseService.instance.client.from('user_settings').upsert({
          'user_id': uid,
          ...s,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id');
      } catch (_) {}
    });
  }
}
