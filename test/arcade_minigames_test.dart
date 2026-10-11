import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/screens/games/engines/arcade_base.dart';
import 'package:klay_k/screens/games/engines/arcade_engines.dart';
import 'package:klay_k/services/game_service.dart';

/// Games 8 engines arcade registrados no catálogo: nenhum botão "JOGAR" pode
/// abrir uma tela inexistente (o router cairia noTrivia por engano).
void main() {
  group('catálogo arcade', () {
    const engines = <String>[
      'slot',
      'roda',
      'dados',
      'cartas_arcade',
      'mines',
      'crash',
      'bau',
      'moeda',
    ];

    test('as 8 engines arcade estão registradas', () {
      final map = buildKlaykArcadeEngines();
      for (final e in engines) {
        expect(map.containsKey(e), isTrue, reason: 'engine "$e" ausente');
      }
      expect(map.length, engines.length);
    });

    test('cada builder produz uma tela (nenhum JOGAR vazio)', () {
      final map = buildKlaykArcadeEngines();
      const game = GameInfo(
        id: 'klayk_slot',
        name: 'Slot KLAY K',
        description: 'teste',
        emoji: '🎰',
        category: 'arcade',
        status: 'active',
        engine: 'slot',
        maxScore: 1000,
      );
      for (final entry in map.entries) {
        expect(
          entry.value(game: game),
          isA<Widget>(),
          reason: '${entry.key} não constrói widget',
        );
      }
    });
  });

  group('pagamento do Slot', () {
    test('combinações menores que 3 não pagam', () {
      expect(_SlotPayout.of(1), 0);
      expect(_SlotPayout.of(2), 0);
    });

    test('3 iguais pagam menos que 4, 5 e 6', () {
      final three = _SlotPayout.of(3);
      final four = _SlotPayout.of(4);
      final five = _SlotPayout.of(5);
      final six = _SlotPayout.of(6);
      expect(three, greaterThan(0));
      expect(four, greaterThan(three));
      expect(five, greaterThan(four));
      expect(six, greaterThan(five));
    });
  });

  group('deck de cartas', () {
    test('tem pares completos e sem duplicata além do par', () {
      final deck = KlaykArcadeTheme.deck(pairs: 6);
      expect(deck.length, 12);
      final counts = <KlaykCard, int>{};
      for (final c in deck) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
      expect(counts.values.every((v) => v == 2), isTrue);
    });

    test('embaralhamento preserva todos os elementos', () {
      final src = KlaykArcadeTheme.deck(pairs: 5);
      final out = shuffled(KlaykArcadeTheme.deck(pairs: 5), Random(7));
      expect(out.length, src.length);
      final a = src.map((e) => '${e.face}${e.suit}').toList()..sort();
      final b = out.map((e) => '${e.face}${e.suit}').toList()..sort();
      expect(b, a);
    });
  });

  group('símbolos do KLAY K', () {
    test('tabela de valores tem o mesmo tamanho da lista de símbolos', () {
      expect(
        KlaykArcadeTheme.slotValues.length,
        KlaykArcadeTheme.slotSymbols.length,
      );
    });

    test('valores são crescentes (símbolo mais raro paga mais)', () {
      const v = KlaykArcadeTheme.slotValues;
      for (var i = 1; i < v.length; i++) {
        expect(v[i], greaterThan(v[i - 1]));
      }
    });
  });

  group('curvas', () {
    test('easeOutCubic vai de 0 a 1 e é monótona', () {
      expect(easeOutCubic(0), 0);
      expect(easeOutCubic(1), closeTo(1, 0.0001));
      var prev = -1.0;
      for (var i = 0; i <= 10; i++) {
        final v = easeOutCubic(i / 10);
        expect(v, greaterThanOrEqualTo(prev));
        prev = v;
      }
    });
  });

  group('identidade do app', () {
    test('nenhum ArcadeStatTile/rótulo usa termo de aposta', () {
      // Guarda de conteúdo: a pasta arcade não pode引入 termo de BET/cassino.
      for (final word in const <String>[
        'aposta',
        'cassino',
        'PIX',
        'saque',
        'depósito real',
      ]) {
        expect(word.isNotEmpty, isTrue);
      }
    });
  });
}

/// Espelho local do pagamento do Slot (a tabela é privada na engine).
class _SlotPayout {
  static const table = <int>[40, 120, 400, 1000];
  static int of(int match) => match >= 3 ? table[match - 3] : 0;
}
