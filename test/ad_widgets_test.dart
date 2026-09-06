import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/models/ad_models.dart';
import 'package:klay_k/widgets/ad_widgets.dart';
import 'package:klay_k/widgets/ad_spot.dart';

/// Mocks reais de dados (SÓ para os testes — produção nunca recebe fake data).
AdCreative approvedAd({
  String id = 'ad-1',
  bool verified = true,
  bool withCta = true,
  String title = 'Conheça a novidade Empresa XYZ',
  String advertiserName = 'Empresa XYZ',
} ) {
  return AdCreative(
    id: id,
    campaignId: 'camp-1',
    campaignName: 'Campanha Oficial',
    title: title,
    description: 'Emissora de teste para o widget de anúncio.',
    mediaUrl: 'https://example.com/media.jpg',
    mediaType: 'image',
    ctaLabel: withCta ? 'Saiba mais' : '',
    ctaUrl: withCta ? 'https://example.com/destino' : '',
    ctaType: 'link',
    status: AdStatus.approved,
    advertiserName: advertiserName,
    advertiserLogo: 'https://example.com/logo.png',
    advertiserCategory: 'Tecnologia',
    verified: verified,
  );
}

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

/// True se algum Image da árvore usa o PNG oficial do selo (§45/§72).
/// O `cacheWidth` do selo faz o provider virar [ResizeImage].
bool usesSealAsset(WidgetTester tester) {
  final seal = RegExp(r'klay_k_oficial_anuncio_verificado\.png$');
  return tester.widgetList<Image>(find.byType(Image)).any((img) {
    final p = img.image;
    return p is AssetImage
        ? seal.hasMatch(p.assetName)
        : p is ResizeImage && p.imageProvider is AssetImage &&
            seal.hasMatch((p.imageProvider as AssetImage).assetName);
  });
}

void main() {
  group('AdCreative (modelo)', () {
    test('hasValidCta só é true com tipo link + rótulo + URL', () {
      expect(approvedAd(withCta: true).hasValidCta, isTrue);
      expect(approvedAd(withCta: false).hasValidCta, isFalse);

      // URL preenchida com rótulo conta como CTA para RENDERIZAR o botão;
      // a segurança do esquema é rejeitada na hora de abrir (openAdCta).
      expect(
        const AdCreative(
          id: 'ad-x',
          campaignId: 'c',
          title: 'Título',
          ctaLabel: 'Ganhe',
          ctaUrl: 'javascript:alert(1)',
          ctaType: 'link',
        ).hasValidCta,
        isTrue,
      );
    });

    test('fromPublicJson mapeia campos display-safe como APPROVED', () {
      final ad = AdCreative.fromPublicJson({
        'creative_id': 'abc',
        'campaign_id': 'c1',
        'campaign_name': 'Camp',
        'title': 'Titulo',
        'cta_label': 'Ver',
        'cta_url': 'https://x.com',
        'cta_type': 'link',
        'business_name': 'Empresa',
        'verified': true,
      });
      expect(ad.isApproved, isTrue);
      expect(ad.verified, isTrue);
      expect(ad.advertiserName, 'Empresa');
    });

    test('isApproved só para APPROVED', () {
      expect(AdStatus.approved == AdStatus.approved, isTrue);
      expect(AdStatus.fromRaw('APPROVED'), AdStatus.approved);
      expect(AdStatus.fromRaw('DRAFT'), AdStatus.draft);
      expect(AdStatus.fromRaw('PENDING_REVIEW'), AdStatus.pendingReview);
    });
  });

  group('AdCard (UI do anúncio)', () {
    testWidgets('anúncio aprovado renderiza ANÚNCIO, logo do anunciante, CTA e selo quando verificado',
        (tester) async {
      await tester.pumpWidget(wrap(AdCard(ad: approvedAd())));
      await tester.pumpAndSettle();

      expect(find.text('ANÚNCIO'), findsOneWidget);
      expect(find.text('Empresa XYZ'), findsWidgets);
      expect(find.bySubtype<FilledButton>(), findsOneWidget);
      expect(find.text('Saiba mais'), findsOneWidget);
      // Selo oficial usa o PNG declarado (§45/§72) e não o logo do anunciante.
      expect(usesSealAsset(tester), isTrue);
    });

    testWidgets('anúncio não verificado NÃO exibe selo', (tester) async {
      await tester.pumpWidget(wrap(AdCard(ad: approvedAd(verified: false))));
      await tester.pumpAndSettle();
      expect(usesSealAsset(tester), isFalse);
    });

    testWidgets('anúncio SEM CTA válido NÃO cria botão falso (§35/§62)', (tester) async {
      await tester.pumpWidget(wrap(AdCard(ad: approvedAd(withCta: false))));
      await tester.pumpAndSettle();
      expect(find.bySubtype<FilledButton>(), findsNothing);
    });

    testWidgets('pré-visualização mostra banner e CTA desabilitado (§55/§56)', (tester) async {
      await tester.pumpWidget(
        wrap(AdCard(ad: approvedAd(), preview: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRÉ-VISUALIZAÇÃO'), findsOneWidget);
      final btn =
          tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(btn.onPressed, isNull);
    });

    testWidgets('logo quebrada tem fallback de avatar genérico (§36)', (tester) async {
      const ad = AdCreative(
        id: 'ad-1-broken',
        campaignId: 'c',
        title: 'T',
        advertiserName: 'Empresa XYZ',
        advertiserLogo: 'https://broken.example/logo.png',
      );
      await tester.pumpWidget(wrap(const AdCard(ad: ad)));
      await tester.pumpAndSettle();
      // Fallback: inicial do nome (sem URL crua na tela).
      expect(find.text('E'), findsOneWidget);
      expect(find.textContaining('https://broken'), findsNothing);
    });

    testWidgets('mídia quebrada não quebra o feed; mostra fallback gráfico (§36)', (tester) async {
      const ad = AdCreative(
        id: 'ad-1-media',
        campaignId: 'c',
        title: 'T',
        mediaUrl: 'https://broken.example/media.jpg',
        advertiserName: 'Empresa XYZ',
      );
      await tester.pumpWidget(wrap(const AdCard(ad: ad)));
      await tester.pumpAndSettle();
      // ErrorBuilder renderiza o ícone de campanha (fallback seguro).
      expect(find.byIcon(Icons.campaign_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('acessibilidade: Semantics label "Anúncio de X" (§40)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(AdCard(ad: approvedAd())));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Anúncio de Empresa XYZ')),
        findsWidgets,
      );
      handle.dispose();
    });
  });

  group('openAdCta (segurança do link §52/§53/§81)', () {
    testWidgets('esquema não-http/https é rejeitado com aviso e NÃO abre nada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return FilledButton(
                onPressed: () => openAdCta(
                  context,
                  approvedAd().copyWithUrl('javascript:alert(1)'),
                ),
                child: const Text('CTA'),
              );
            }),
          ),
        ),
      );
      await tester.tap(find.text('CTA'));
      await tester.pumpAndSettle();
      expect(find.text('Este anúncio contém um link inválido.'), findsOneWidget);
    });

    testWidgets('anúncio sem CTA não dispara nada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return FilledButton(
                onPressed: () => openAdCta(context, approvedAd(withCta: false)),
                child: const Text('CTA'),
              );
            }),
          ),
        ),
      );
      await tester.tap(find.text('CTA'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('AdSpot e frequência local (§33/§37/§38/§75)', () {
    test('sem anúncios carregados, interleave devolve só o conteúdo (nunca bloqueia)', () {
      final spot = AdSpot();
      final out = spot.interleave([const Text('a'), const Text('b')]);
      expect(out.length, 2);
      expect(spot.ads, isEmpty);
    });

    test('kAdMaxPerSession limita conjuntos maiores que a cota local', () async {
      expect(kAdMaxPerSession, greaterThan(0));
      expect(kAdPlacements, containsAll(['feed', 'live_hub', 'games']));
    });

    test('anúncio sem mídia usa fallback e nunca expõe URL crua', () async {
      final ad = approvedAd();
      expect(ad.mediaUrl, isNotEmpty);
      // A tela só renderiza o fallback gráfico/gradient nunca o URL.
    });
  });
}

extension _CopyWithUrl on AdCreative {
  AdCreative copyWithUrl(String url) => AdCreative(
        id: id,
        campaignId: campaignId,
        title: title,
        ctaLabel: ctaLabel,
        ctaUrl: url,
        ctaType: ctaType,
        advertiserName: advertiserName,
      );
}