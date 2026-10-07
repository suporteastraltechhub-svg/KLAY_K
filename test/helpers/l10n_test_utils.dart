import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:klay_k/l10n/app_localizations.dart';

/// Envolve um widget em MaterialApp com localizações do KLAY K (pt-BR, o
/// idioma padrão do app) para testes de widgets sensíveis a i18n.
Widget l10nWrap(Widget child) => l10nApp(home: Scaffold(body: child));

/// MaterialApp com as mesmas localizações e idioma padrão do app real
/// (`main.dart` sempre registra `AppLocalizations.localizationsDelegates`).
/// Telas que fazem `AppLocalizations.of(context)!` quebram com
/// "Null check operator used on a null value" num MaterialApp sem esses
/// delegates, então harnesses de widget devem usar este helper.
Widget l10nApp({required Widget home, ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    locale: const Locale('pt'),
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
