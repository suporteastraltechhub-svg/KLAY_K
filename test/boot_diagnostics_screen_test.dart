// Teste de widget da tela de diagnóstico de BOOT.
//
// Prova o requisito central: quando o app falha ao abrir, o usuário VÊ a
// exceção na própria tela (sem ADB e sem logcat), com botão para seguir para o
// app — ou seja, a falha não vira "o app simplesmente fechou".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/screens/boot_diagnostics_screen.dart';
import 'package:klay_k/services/boot_diagnostics.dart';
import 'package:klay_k/theme/klayk_theme.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: KlaykTheme.dark(),
  localizationsDelegates: KlaykLocalizationsStub.delegates,
  home: child,
);

/// Delegates vazios: a tela não depende de string traduzida.
class KlaykLocalizationsStub {
  static const delegates = <LocalizationsDelegate<dynamic>>[];
}

void main() {
  setUp(BootDiagnostics.instance.reset);

  testWidgets('mostra a exceção e o botão Continuar', (tester) async {
    final d = BootDiagnostics.instance;
    d.markPhase(BootPhases.push);
    try {
      throw StateError('firebase nao inicializou');
    } catch (e, s) {
      d.record('boot', e, s);
    }

    await tester.pumpWidget(wrap(const BootDiagnosticsScreen()));
    await tester.pumpAndSettle();

    // o texto da exceção aparece na tela
    expect(find.textContaining('firebase nao inicializou'), findsOneWidget);
    // a fase do boot aparece
    expect(find.textContaining(BootPhases.push), findsWidgets);
    // e existe caminho para seguir usando o app
    expect(find.text('Continuar para o app'), findsOneWidget);
  });

  testWidgets('nunca exibe segredo na tela', (tester) async {
    final d = BootDiagnostics.instance;
    d.record(
      'boot',
      Exception('falhou com AIzaSyDHfWXz_zKwLr2TJJWDaWNt4HtVPmnlMUw'),
      StackTrace.current,
    );

    await tester.pumpWidget(wrap(const BootDiagnosticsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('AIzaSyDHfWXz'), findsNothing);
  });

  testWidgets('sem falha mostra estado vazio, sem quebrar', (tester) async {
    await tester.pumpWidget(wrap(const BootDiagnosticsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma falha registrada.'), findsOneWidget);
    expect(find.text('Continuar para o app'), findsOneWidget);
  });

  testWidgets('onContinue é chamado ao tocar em Continuar', (tester) async {
    var called = false;
    await tester.pumpWidget(
      wrap(BootDiagnosticsScreen(onContinue: () => called = true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar para o app'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });
}
