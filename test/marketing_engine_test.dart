import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/services/marketing/marketing_engine.dart';

void main() {
  group('MarketingEngine — campanha', () {
    test('gera título, descrição e CTA não vazios', () {
      final c = MarketingEngine.generateCampaign(
        objectiveId: 'lancamento',
        product: 'Nova playlist de jogos',
      );
      expect(c.title.trim(), isNotEmpty);
      expect(c.description.trim(), isNotEmpty);
      expect(c.cta.trim(), isNotEmpty);
      expect(c.name.trim(), isNotEmpty);
    });

    test('gera no mínimo 5 variações distintas (A-E)', () {
      final c = MarketingEngine.generateCampaign(
        objectiveId: 'jogos',
        product: 'Torneio KLAY K',
      );
      expect(c.variations.length, greaterThanOrEqualTo(5));
      final keys = c.variations
          .map((v) => '${v.title}#${v.description}#${v.cta}')
          .toSet();
      expect(
        keys.length,
        c.variations.length,
        reason: 'variações devem ser distintas entre si',
      );
      for (var i = 0; i < c.variations.length; i++) {
        expect(c.variations[i].label, 'ABCDEFGHIJ'[i].toString());
      }
    });

    test('determinístico: mesmas entradas, mesmas variações', () {
      final a = MarketingEngine.generateCampaign(
        objectiveId: 'promocao',
        product: 'Desconto de 50%',
        toneId: 'urgente',
        keywords: ['oferta'],
      );
      final b = MarketingEngine.generateCampaign(
        objectiveId: 'promocao',
        product: 'Desconto de 50%',
        toneId: 'urgente',
        keywords: ['oferta'],
      );
      expect(a.title, b.title);
      expect(a.variations.length, b.variations.length);
      for (var i = 0; i < a.variations.length; i++) {
        expect(a.variations[i].title, b.variations[i].title);
        expect(a.variations[i].cta, b.variations[i].cta);
      }
    });

    test('campanha vazia (sem produto/objetivo) não quebra', () {
      final c = MarketingEngine.generateCampaign(
        objectiveId: '',
        product: '   ',
      );
      expect(c.title.trim(), isNotEmpty);
      expect(c.description.trim(), isNotEmpty);
      expect(c.cta.trim(), isNotEmpty);
      expect(c.variations.length, greaterThanOrEqualTo(5));
    });

    test('caracteres especiais e espaços duplos são normalizados', () {
      final c = MarketingEngine.generateCampaign(
        objectiveId: 'divulgacao',
        product: '  Minha  \n  marca\t  "especial"  ',
      );
      expect(c.title, isNot(contains('\n')));
      expect(c.title, isNot(contains('\t')));
      expect(c.title, isNot(contains('  ')));
      expect(c.variations, isNotEmpty);
    });

    test('checklist padrão de publicação existe', () {
      final c = MarketingEngine.generateCampaign(
        objectiveId: 'livestream',
        product: 'Live diária',
      );
      expect(c.checklist.length, greaterThanOrEqualTo(3));
      expect(MarketingEngine.checklistDefault.length, greaterThanOrEqualTo(3));
    });
  });

  group('MarketingEngine — sanitização', () {
    test('clean colapsa espaços e remove controles', () {
      expect(MarketingEngine.clean('  a  b\t\n  c  '), 'a b c');
      expect(MarketingEngine.clean(''), '');
    });

    test('cleanKeywords normaliza, minúsculas e dedupe', () {
      final kw = MarketingEngine.cleanKeywords([
        '#Gamer',
        ' ROTACAO ',
        'gamer',
        '',
      ]);
      expect(kw, containsAll(['gamer', 'rotacao']));
      expect(kw.toSet().length, kw.length);
    });

    test('productFallback com entrada vazia', () {
      expect(MarketingEngine.productFallback(''), 'nossa novidade');
      expect(MarketingEngine.productFallback('  App  '), 'App');
    });
  });

  group('MarketingEngine — roteiros', () {
    test(
      'roteiro usa estrutura GANCHO→PROBLEMA→APRESENTAÇÃO→DIFERENCIAL→CTA',
      () {
        final script = MarketingEngine.generateScript(
          category: 'jogos',
          product: 'Partida ranqueada',
        );
        expect(script.sections.map((s) => s.step), [
          'GANCHO',
          'PROBLEMA',
          'APRESENTAÇÃO',
          'DIFERENCIAL',
          'CTA',
        ]);
        expect(script.estimatedSeconds, greaterThan(0));
        expect(script.fullText, contains('GANCHO'));
        expect(script.fullText, contains('CTA'));
      },
    );

    test(
      'formato de imagem não gera roteiro no fluxo normal, gera no direto',
      () {
        // generateScript força vídeo quando o formato não suporta roteiro.
        final script = MarketingEngine.generateScript(
          category: 'novidade',
          product: 'Novo app',
          formatId: 'imagem',
        );
        expect(script.sections.length, 5);
      },
    );
  });

  group('MarketingEngine — briefings', () {
    test('briefing têm specs, cenas, fazer/evitar', () {
      final b = MarketingEngine.generateBrief(
        formatId: 'video_curto',
        product: 'Série semanal',
      );
      expect(b.format, isNotEmpty);
      expect(b.specs, isNotEmpty);
      expect(b.scenes.length, greaterThanOrEqualTo(4));
      expect(b.doItems, isNotEmpty);
      expect(b.dontItems, isNotEmpty);
      expect(b.fullText, contains('BRIEFING DE CRIATIVO'));
      expect(b.fullText, contains('9:16'));
    });
  });

  group('MarketingEngine — sem APIs externas', () {
    test('modelo de campanha serializa para JSON (sem variantes no RPC)', () {
      final c = MarketingEngine.generateCampaign(
        objectiveId: 'aquisicao',
        product: 'Convite premium',
      );
      final json = c.toJson();
      expect(json['title'], c.title);
      expect(json['variants'], isNull); // variantes vão no payload separado
    });
  });
}
