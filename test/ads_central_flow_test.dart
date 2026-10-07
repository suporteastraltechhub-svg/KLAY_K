import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/screens/ad_create_screen.dart';
import 'package:klay_k/screens/ads_central_screen.dart';

import 'helpers/l10n_test_utils.dart';

void main() {
  group('Central de Anúncios -> Criar anúncio (fluxo real)', () {
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('AdsCentralScreen abre sem exceção (sem backend configurado)', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(l10nWrap(const AdsCentralScreen()));
      await tester.pump();

      expect(find.text('Central de Anúncios'), findsOneWidget);
      expect(find.byType(AdsCentralScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Criar anúncio abre AdCreateScreen sem tela preta', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(l10nWrap(const AdsCentralScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(AdsCentralScreen), findsOneWidget);
    });

    testWidgets('Passo 1 -> passo 2 (Campanha) sem exceção', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(l10nWrap(const AdCreateScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Conteúdo'), findsWidgets);
      expect(find.text('Título do anúncio'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Do que se trata?'),
        'Oferta de verão',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Destino do anúncio (URL)'),
        'https://klayk.app/oferta',
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Nome da campanha'), findsOneWidget);
      expect(find.text('Orçamento (KLAY\$)'), findsOneWidget);
    });

    testWidgets('Passo 2 -> passo 3 (Revisar) sem exceção', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(l10nWrap(const AdCreateScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Do que se trata?'),
        'Oferta de verão',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Destino do anúncio (URL)'),
        'https://klayk.app/oferta',
      );
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Ex.: Lançamento de primavera'),
        'Camp primeiriza',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Revisar anúncio'), findsWidgets);
      expect(find.text('Assim seu anúncio será visto'), findsOneWidget);
    });
  });
}
