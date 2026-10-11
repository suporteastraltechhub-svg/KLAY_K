import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'family_service.dart';

/// Preferências LOCAIS de acessibilidade e bem-estar digital.
///
/// Tudo aqui é verdadeiramente local (SharedPreferences) e funciona offline.
/// Não substitui nem duplica preferências que já têm backend
/// (`user_settings` / `notification_preferences`): o app apenas complementa
/// com o que ainda não existe no servidor. Cada valor tem efeito real —
/// [textScale] e [highContrast] são aplicados pelo `MaterialApp` (ver
/// `main.dart`); [reduceNotificationsDimmer], [pauseReminderMinutes] e
/// [dailyLimitMinutes] alimentam o painel de bem-estar digital.
class LocalPrefs {
  final double textScale;
  final bool highContrast;
  final bool reduceNotificationsDimmer;
  final int pauseReminderMinutes;
  final int dailyLimitMinutes;

  const LocalPrefs({
    this.textScale = 1,
    this.highContrast = false,
    this.reduceNotificationsDimmer = false,
    this.pauseReminderMinutes = 0,
    this.dailyLimitMinutes = 0,
  });

  LocalPrefs copyWith({
    double? textScale,
    bool? highContrast,
    bool? reduceNotificationsDimmer,
    int? pauseReminderMinutes,
    int? dailyLimitMinutes,
  }) => LocalPrefs(
    textScale: textScale ?? this.textScale,
    highContrast: highContrast ?? this.highContrast,
    reduceNotificationsDimmer:
        reduceNotificationsDimmer ?? this.reduceNotificationsDimmer,
    pauseReminderMinutes: pauseReminderMinutes ?? this.pauseReminderMinutes,
    dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
  );

  /// Restaura **todas** as preferências locais ao padrão.
  ///
  /// Usado por "Reiniciar configurações". Não toca em nada do servidor:
  /// apenas devolve uma `LocalPrefs` nova com os defaults do construtor.
  LocalPrefs copyWithReset() => const LocalPrefs();

  Map<String, dynamic> toJson() => {
    'textScale': textScale,
    'highContrast': highContrast,
    'reduceNotificationsDimmer': reduceNotificationsDimmer,
    'pauseReminderMinutes': pauseReminderMinutes,
    'dailyLimitMinutes': dailyLimitMinutes,
  };

  factory LocalPrefs.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const LocalPrefs();
    return LocalPrefs(
      textScale: (j['textScale'] as num?)?.toDouble() ?? 1,
      highContrast: j['highContrast'] == true,
      reduceNotificationsDimmer: j['reduceNotificationsDimmer'] == true,
      pauseReminderMinutes: (j['pauseReminderMinutes'] as num?)?.toInt() ?? 0,
      dailyLimitMinutes: (j['dailyLimitMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Serviço de preferências locais persistido em disco. Um único ponto de
/// verdade para acessibilidade e bem-estar; os listeners permitem reagir sem
/// recarregar a tela.
class LocalPrefsService {
  LocalPrefsService._();

  static final LocalPrefsService instance = LocalPrefsService._();

  static const _key = 'klayk.local_prefs.v1';
  static const _usageKey = 'klayk.local_usage.v1';

  final ValueNotifier<LocalPrefs> prefs = ValueNotifier(const LocalPrefs());

  /// Minutos de uso acumulados hoje (persistido localmente). Não é
  /// "tempo de tela do sistema" — é o tempo real em que o app KLAY K ficou em
  /// primeiro plano, medido pelo próprio app. É por isso que é honesto.
  final ValueNotifier<int> todayUsageMinutes = ValueNotifier(0);

  DateTime? _sessionStartedAt;
  Timer? _ticker;

  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    final stored = await _readJson(_key);
    final usage = await _readJson(_usageKey);
    final today = _dayKey(DateTime.now());
    var minutes = 0;
    if (usage != null && usage['_day'] == today) {
      minutes = (usage['minutes'] as num?)?.toInt() ?? 0;
    }
    prefs.value = LocalPrefs.fromJson(stored);
    todayUsageMinutes.value = minutes;
    _loaded = true;
  }

  Future<void> update(LocalPrefs next) async {
    prefs.value = next;
    await _writeJson(_key, next.toJson());
  }

  // ---------------------------------------------------------------------------
  // Tempo de uso (real, local, apenas tempo em primeiro plano).
  // ---------------------------------------------------------------------------

  void startSession() {
    if (_sessionStartedAt != null) return;
    _sessionStartedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _flush());
  }

  void stopSession() {
    _ticker?.cancel();
    _ticker = null;
    _flush();
  }

  Future<void> _flush() async {
    final started = _sessionStartedAt;
    if (started == null) return;
    final now = DateTime.now();
    final today = _dayKey(now);
    final stored = await _readJson(_usageKey);
    var base = 0;
    if (stored != null && stored['_day'] == today) {
      base = (stored['minutes'] as num?)?.toInt() ?? 0;
    }
    final elapsed = now.difference(started).inMinutes;
    if (elapsed <= 0) return;
    todayUsageMinutes.value = base + elapsed;
    // Recomeça a contagem a partir de agora para não somar o mesmo minuto.
    _sessionStartedAt = now;
    await _writeJson(_usageKey, {
      '_day': today,
      'minutes': todayUsageMinutes.value,
    });

    // Heartbeat para o limite de tempo dos CONTROLES FAMILIARES.
    //
    // É o MESMO minuto que já acabamos de contar localmente: quem define o
    // limite precisa enxergar o uso real, e este ticker é o único lugar do app
    // que já sabe "o usuário está há 1 minuto em primeiro plano".
    //
    // Fire-and-forget de propósito: uma falha aqui não pode interromper o
    // `_flush` nem travar o app. A RPC só grava se existir limite ativo.
    unawaited(FamilyService.instance.usageTick());
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>?> _readJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _writeJson(String key, Map<String, dynamic> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value));
    } catch (_) {}
  }
}
