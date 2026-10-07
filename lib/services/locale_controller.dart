import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// Controle de IDIOMA do KLAY K.
///
/// - Preferência persistida localmente (SharedPreferences) — sobrevive a
///   fechar/reabrir o app (não depende de conta, sessão ou backend).
/// - Primeira execução: detecta o idioma do aparelho; se não for suportado,
///   usa Português (Brasil), o padrão.
/// - Troca em tempo real via [notifyListeners] — a UI é reconstruída sem
///   reinstalar, sem logout e sem perder o estado da navegação.
/// - Apenas idiomas suportados pela localização (ARBs em `lib/l10n`) são
///   aceitos; qualquer outro código cai no padrão pt-BR.
/// ============================================================================

class AppLanguageController extends ChangeNotifier {
  AppLanguageController._();

  static final AppLanguageController instance = AppLanguageController._();

  /// Códigos suportados. `pt` = Português (Brasil), o idioma padrão.
  static const List<String> supportedCodes = [
    'pt',
    'en',
    'es',
    'fr',
    'ja',
    'ko',
    'zh',
  ];

  static const Locale defaultLocale = Locale('pt');
  static const String _prefsKey = 'app_language';

  Locale _locale = defaultLocale;
  bool _initialized = false;

  /// Idioma ativo. Começa como pt-BR até [initialize] restaurar a escolha.
  Locale get locale => _locale;

  /// `true` depois que [initialize] terminou.
  bool get initialized => _initialized;

  /// Restaura a preferência salva (ou detecta o idioma do aparelho na
  /// primeira execução). Deve ser chamado uma única vez, antes do `runApp`.
  ///
  /// [deviceLocales] é injetável para testes; por padrão usa a lista real de
  /// idiomas do aparelho (`platformDispatcher.locales`).
  Future<void> initialize({Iterable<Locale>? deviceLocales}) async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && supportedCodes.contains(saved)) {
      _locale = Locale(saved);
    } else {
      final locales =
          deviceLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
      _locale = _match(locales);
      await prefs.setString(_prefsKey, _locale.languageCode);
    }
    notifyListeners();
  }

  /// Define o idioma, persiste e notifica a UI imediatamente.
  Future<void> setLocale(Locale next) async {
    if (!_initialized) await initialize();
    if (!supportedCodes.contains(next.languageCode)) return;
    if (_locale.languageCode == next.languageCode) return;
    _locale = Locale(next.languageCode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _locale.languageCode);
  }

  /// Primeiro idioma da lista do aparelho que o app suporta; senão, pt-BR.
  Locale _match(Iterable<Locale> locales) {
    for (final l in locales) {
      if (supportedCodes.contains(l.languageCode)) {
        return Locale(l.languageCode);
      }
    }
    return defaultLocale;
  }

  /// Restaura o estado para o padrão (usado por testes).
  @visibleForTesting
  void resetForTests() {
    _locale = defaultLocale;
    _initialized = false;
  }
}
