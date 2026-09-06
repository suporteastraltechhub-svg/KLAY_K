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
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Jogo'), findsOneWidget);
  });

  testWidgets('Jogo tab renders the games catalog header', (tester) async {
    await pumpKlayK(tester);

    await tester.tap(find.text('Jogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Jogos'), findsOneWidget);
    expect(find.text('Divirta-se e ganhe cristais'), findsOneWidget);
    // Em demo/offline o catálogo vem vazio; não deve estourar layout.
    expect(tester.takeException(), isNull);
  });

  testWidgets('KLAY K has no layout overflow on a small device',
      (tester) async {
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

  testWidgets('Feed shows Live and Destaques tabs and keeps Loja', (tester) async {
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

    expect(find.text('Para você'), findsOneWidget);
    expect(find.text('Destaques'), findsOneWidget);
    expect(find.text('Loja'), findsOneWidget);

    await tester.ensureVisible(find.text('Live'));
    await tester.pump();
    await tester.tap(find.text('Live'));
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

    await tester.ensureVisible(find.text('Destaques'));
    await tester.pump();
    await tester.tap(find.text('Destaques'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Vídeos em alta'), findsOneWidget);
    expect(find.text('Criadores em alta'), findsOneWidget);
    expect(find.text('Jogos'), findsWidgets);
    expect(find.text('Transmissões ao vivo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Loja'));
    await tester.pump();
    await tester.tap(find.text('Loja'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Para você'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}