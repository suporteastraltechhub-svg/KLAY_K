import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/main.dart';

/// Aplica o AppGate completo: splash animado (~4s) e transição do switcher.
Future<void> pumpKlayK(WidgetTester tester) async {
  await tester.pumpWidget(const KlayKApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 4000));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  setUp(() {
    kNavIndex.value = 0;
  });

  testWidgets('KLAY K renders feed and bottom navigation', (tester) async {
    await pumpKlayK(tester);

    expect(find.text('Para você'), findsOneWidget);
    expect(find.text('Seguindo'), findsOneWidget);
    expect(find.text('Ao vivo'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(KlayKBottomNavigation),
        matching: find.text('Jogos'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Jogo tab renders the games catalog header', (tester) async {
    await pumpKlayK(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(KlayKBottomNavigation),
        matching: find.text('Jogos'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // O catálogo abre com o título real (l10n.gameTitle) e o header premium.
    expect(find.widgetWithText(AppBar, 'Jogos'), findsOneWidget);
    expect(find.text('JOGOS KLAY K'), findsOneWidget);
    // A navegação inferior permanece visível com a aba Jogos.
    expect(find.text('Jogos'), findsWidgets);
    // Em demo/offline o catálogo vem vazio; não deve estourar layout.
    expect(tester.takeException(), isNull);
  });

  testWidgets('KLAY K has no layout overflow on a small device', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpKlayK(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Messages and Edit Profile follow the Kwai flow', (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = originalOnError;
    });

    await pumpKlayK(tester);

    await tester.tap(find.text('Mensagens'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Mensagens agora é a tela real (DMs via Supabase); em modo demo/offline
    // mostra o estado vazio em vez da UI antiga.
    expect(find.text('Nenhuma conversa ainda'), findsOneWidget);
    expect(find.text('Bate-papos'), findsNothing);

    await tester.tap(find.text('Perfil'));
    await tester.pump();
    await tester.tap(find.text('Editar perfil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Toque para alterar a foto'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
    expect(find.text('Nome de exibição'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nome de exibição'),
      'KLAY K NOVO',
    );
    await tester.pump();
    expect(find.text('KLAY K NOVO'), findsWidgets);

    // Fecha a edição pelo "X" da barra superior (nova tela de edição).
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Toque para alterar a foto'), findsNothing);
    expect(find.text('Editar perfil'), findsOneWidget);
  });

  testWidgets('Feed mostra as 4 categorias e a aba Ao vivo funciona', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = originalOnError;
    });

    await pumpKlayK(tester);

    // A faixa superior mostra as 5 chips do feed, na ordem definida por
    // _FeedTopBar.tabTitles: Ao vivo, Para você, Seguindo, Loja, Jogos.
    //
    // Este teste antes exigia `Loja findsNothing`: ele travava o defeito de a
    // aba existir no código mas não ter chip, ou seja, ser inalcançável por
    // toque. Agora a Loja é um chip de verdade e o feed segue mostrando vídeos.
    expect(find.text('Seguindo'), findsOneWidget);
    expect(find.text('Para você'), findsOneWidget);
    expect(find.text('Ao vivo'), findsOneWidget);
    expect(find.text('Jogos'), findsWidgets);
    expect(find.text('Loja'), findsOneWidget);
    // A aba antiga de Destaques continua sem chip (não entra em tabTitles).
    expect(find.text('Destaques'), findsNothing);

    // Ordem dos chips: a primeira posição é "Ao vivo".
    final chips = <Offset>[];
    for (final label in <String>['Ao vivo', 'Para você', 'Loja']) {
      final box = tester.getRect(find.text(label).first);
      chips.add(box.topLeft);
    }
    expect(chips[0].dx, lessThan(chips[1].dx));
    expect(chips[1].dx, lessThan(chips[2].dx));

    await tester.ensureVisible(find.text('Ao vivo'));
    await tester.pump();
    await tester.tap(find.text('Ao vivo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('O que você quer fazer hoje?'), findsOneWidget);
    expect(find.text('Vídeo'), findsWidgets);
    expect(find.text('Áudio'), findsWidgets);
    expect(find.text('Amigos'), findsWidgets);
    expect(find.text('Filmes'), findsWidgets);
    expect(find.text('Jogos'), findsWidgets);
    expect(find.text('Ao vivo agora'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
