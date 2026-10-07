import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/l10n/app_localizations.dart';
import 'package:klay_k/services/locale_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ctrl = AppLanguageController.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    ctrl.resetForTests();
  });

  group('AppLanguageController — detecção e padrão', () {
    test('primeira execução: detecta idioma suportado do aparelho', () async {
      await ctrl.initialize(deviceLocales: const [Locale('ja'), Locale('en')]);
      expect(ctrl.locale, const Locale('ja'));
      expect(ctrl.initialized, isTrue);
    });

    test(
      'primeira execução: idioma não suportado cai no padrão pt-BR',
      () async {
        await ctrl.initialize(
          deviceLocales: const [Locale('de'), Locale('it')],
        );
        expect(ctrl.locale, AppLanguageController.defaultLocale);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('app_language'), 'pt');
      },
    );

    test('primeira execução sem idiomas do aparelho usa pt-BR', () async {
      await ctrl.initialize(deviceLocales: const <Locale>[]);
      expect(ctrl.locale, const Locale('pt'));
    });
  });

  group('AppLanguageController — persistência e reinício', () {
    test(
      'setLocale persiste e sobrevive a reinício (ignora aparelho)',
      () async {
        await ctrl.initialize(deviceLocales: const [Locale('pt')]);
        await ctrl.setLocale(const Locale('fr'));

        expect(ctrl.locale, const Locale('fr'));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('app_language'), 'fr');

        // Simula reinício do app: aparelho agora em português, mas a
        // preferência salva (fr) deve vencer.
        ctrl.resetForTests();
        await ctrl.initialize(deviceLocales: const [Locale('pt')]);
        expect(ctrl.locale, const Locale('fr'));
      },
    );

    test('setLocale ignora códigos não suportados', () async {
      await ctrl.initialize(deviceLocales: const [Locale('en')]);
      expect(ctrl.locale, const Locale('en'));
      await ctrl.setLocale(const Locale('xx'));
      expect(ctrl.locale, const Locale('en'));
      var notified = 0;
      ctrl.addListener(() => notified++);
      await ctrl.setLocale(const Locale('xx'));
      expect(notified, 0);
    });

    test('setLocale com o mesmo idioma não notifica nem reescreve', () async {
      await ctrl.initialize(deviceLocales: const [Locale('en')]);
      var notified = 0;
      ctrl.addListener(() => notified++);
      await ctrl.setLocale(const Locale('en'));
      expect(notified, 0);
    });
  });

  group('AppLanguageController — notificação em tempo real', () {
    test('setLocale notifica listeners e atualiza o idioma', () async {
      await ctrl.initialize(deviceLocales: const [Locale('pt')]);
      var notified = 0;
      ctrl.addListener(() => notified++);
      await ctrl.setLocale(const Locale('es'));
      expect(ctrl.locale, const Locale('es'));
      expect(notified, 1);
    });

    test('lista de códigos suportados contém os 7 idiomas', () {
      expect(AppLanguageController.supportedCodes, [
        'pt',
        'en',
        'es',
        'fr',
        'ja',
        'ko',
        'zh',
      ]);
    });
  });

  group('Localizações — plurais', () {
    Future<AppLocalizations> l10n(String code) =>
        AppLocalizations.delegate.load(Locale(code));

    test('pt: gameTaps/gamePlays usam o plural correto', () async {
      final pt = await l10n('pt');
      expect(pt.gameTaps(1), '1 toque');
      expect(pt.gameTaps(3), '3 toques');
      expect(pt.gamePlays(1), '1 partida');
      expect(pt.gamePlays(5), '5 partidas');
    });

    test('en: gameTaps usa o plural correto', () async {
      final en = await l10n('en');
      expect(en.gameTaps(1), '1 tap');
      expect(en.gameTaps(10), '10 taps');
    });

    test('chaves com parâmetros interpõem valores corretamente', () async {
      final pt = await l10n('pt');
      expect(pt.engineYouScored(7, 10), contains('7'));
      expect(pt.engineYouScored(7, 10), contains('10'));
      expect(pt.gameLevel('Bronze'), 'Nível Bronze');
    });
  });

  group('Localizações — troca em tempo real na UI', () {
    testWidgets('mudar o idioma reconstrói a UI sem perder o estado', (
      tester,
    ) async {
      await ctrl.initialize(deviceLocales: const [Locale('pt')]);

      var rebuilds = 0;
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: ctrl,
          builder: (context, child) {
            rebuilds++;
            return MaterialApp(
              locale: ctrl.locale,
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: child,
            );
          },
          child: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                body: Column(
                  children: [
                    Text(l10n.gameTitle),
                    const Text('🔒'), // "estado" persistente
                    TextButton(
                      onPressed: () => ctrl.setLocale(const Locale('en')),
                      child: const Text('switch'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Jogos'), findsOneWidget);
      expect(find.text('🔒'), findsOneWidget);

      final before = rebuilds;
      await tester.tap(find.text('switch'));
      await tester.pumpAndSettle();

      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Jogos'), findsNothing);
      expect(find.text('🔒'), findsOneWidget, reason: 'estado preservado');
      expect(rebuilds, greaterThan(before), reason: 'a UI foi reconstruída');
    });
  });
}
