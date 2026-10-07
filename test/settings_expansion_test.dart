import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/l10n/app_localizations.dart';
import 'package:klay_k/screens/settings_screen.dart';

class _App extends StatelessWidget {
  const _App({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
Future<void> openSettings(WidgetTester tester) async {
      // A tela de Configurações tem 19 seções e mais de 120 itens. Com 2400px
      // de altura, blocos como "PRIVACIDADE AVANÇADA" e "IDIOMA E REGIÃO"
      // ficavam acima da dobra e o scroll não os alcançava em um aparelho de
      // teste. O viewport alto deixa tudo alcançável sem mudar o app.
      tester.view.physicalSize = const Size(500, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const _App(child: SettingsScreen()));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('CONTA').evaluate().isNotEmpty) return;
      }
    }

Future<void> scrollTo(WidgetTester tester, Finder target) async {
      final list = find.byType(ListView);
      // A tela de Configurações cresceu com as novas seções (Manutenção,
      // Feedback, KLAY K Labs). O scroll tem de percorrer mais espaço antes
      // de desistir, senão um bloco do fim nunca entra no viewport.
      for (var i = 0; i < 90; i++) {
        if (target.evaluate().isNotEmpty) return;
        await tester.drag(list, const Offset(0, -260));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
    }

  testWidgets('preserva as seções antigas de Configurações', (tester) async {
    await openSettings(tester);

    for (final legacy in [
      'CONTA',
      'PRIVACIDADE',
      'INTERAÇÕES',
      'NOTIFICAÇÕES',
    ]) {
      expect(find.text(legacy), findsOneWidget, reason: 'seção antiga $legacy');
    }

    expect(find.text('Sair da conta'), findsOneWidget);
    expect(find.text('Reprodução automática'), findsOneWidget);
  });

  testWidgets('mantém opções antigas após rolagem completa', (tester) async {
    await openSettings(tester);

    await scrollTo(tester, find.text('IDIOMA E REGIÃO'));
    expect(find.text('Idioma e região'), findsOneWidget);

    await scrollTo(tester, find.text('AJUDA E SUPORTE'));
    expect(find.text('Central de ajuda'), findsOneWidget);
    expect(find.text('Sobre o KLAY K'), findsOneWidget);
  });

  testWidgets('adiciona as novas seções sem remover as antigas', (
    tester,
  ) async {
    await openSettings(tester);

    expect(find.text('PRIVACIDADE AVANÇADA'), findsOneWidget);
    expect(find.text('Privacidade avançada'), findsOneWidget);
    expect(find.text('Central de privacidade'), findsOneWidget);

    await scrollTo(tester, find.text('PROTEÇÃO PARA MENORES'));
    expect(find.text('Controles familiares'), findsOneWidget);

    await scrollTo(tester, find.text('CONTROLE DE MENSAGENS E COMENTÁRIOS'));
    expect(find.text('Controle de mensagens'), findsOneWidget);
    expect(find.text('Controle de comentários'), findsOneWidget);
    expect(find.text('Proteção contra spam'), findsOneWidget);

    await scrollTo(tester, find.text('BEM-ESTAR DIGITAL'));
    expect(find.text('Bem-estar digital'), findsOneWidget);
    await scrollTo(tester, find.text('Acessibilidade'));
    expect(find.text('Acessibilidade'), findsOneWidget);

    await scrollTo(tester, find.text('KLAY K SAFETY CENTER'));
    expect(find.text('Central de Segurança'), findsOneWidget);
    expect(find.text('Segurança da LIVE'), findsOneWidget);

    await scrollTo(tester, find.text('DIAGNÓSTICO E SERVIÇOS'));
    expect(find.text('Diagnóstico KLAY K'), findsOneWidget);
  });

  testWidgets('abre a Central de Segurança preservando a navegação', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.text('Central de Segurança'));
    await tester.tap(find.text('Central de Segurança'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('KLAY K SAFETY CENTER'), findsWidgets);
    expect(find.text('VERIFICAR SEGURANÇA'), findsOneWidget);
  });
}
