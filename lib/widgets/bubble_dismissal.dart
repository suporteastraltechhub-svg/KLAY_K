import 'package:shared_preferences/shared_preferences.dart';

/// Gerencia o "dismiss" das bolinhas flutuantes com cooldown.
///
/// Fechar uma bolinha NÃO a desabilita para sempre: grava um instante
/// `hiddenUntil` (memória + SharedPreferences) e, depois do cooldown, a
/// bolinha volta a aparecer sozinha. Sempre que uma condição válida surgir
/// (reabrir o app, novo estado) ela pode reaparecer — nunca fica presa
/// invisível de forma permanente.
class BubbleDismissal {
  BubbleDismissal(this._key);

  final String _key;

  static const Duration defaultCooldown = Duration(hours: 4);
  static const Duration _minCooldown = Duration(minutes: 1);
  static const Duration _maxCooldown = Duration(days: 30);

  DateTime? _hiddenUntil;
  bool _initialized = false;

  /// Carrega o possível cooldown persistido (chamar no `initState`).
  Future<void> ensureLoaded() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final t = DateTime.tryParse(raw);
        if (t != null && t.isAfter(DateTime.now())) _hiddenUntil = t;
      }
    } catch (_) {}
    _initialized = true;
  }

  /// `true` enquanto a bolinha estiver no período de cooldown (oculta).
  bool isHidden() {
    final until = _hiddenUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  /// Fecha a bolinha por [cooldown] (o [defaultCooldown] é 4h). Não
  /// desabilita a funcionalidade permanentemente.
  Future<void> dismiss({Duration? cooldown}) async {
    // `Duration` não tem `clamp`: aplica o intervalo manualmente.
    var cd = cooldown ?? defaultCooldown;
    if (cd < _minCooldown) cd = _minCooldown;
    if (cd > _maxCooldown) cd = _maxCooldown;
    _hiddenUntil = DateTime.now().add(cd);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _hiddenUntil!.toIso8601String());
    } catch (_) {}
  }

  /// Cancela qualquer cooldown em andamento (bolinha visível de novo).
  Future<void> reenable() async {
    _hiddenUntil = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}