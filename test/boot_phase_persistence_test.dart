// Testes do marcador de FASE do boot.
//
// Objetivo: se o app morrer sem lançar exceção (abort nativo, SIGKILL, falha
// de AOT), a próxima abertura tem que dizer até onde ele chegou. Isso
// responde "em qual etapa o Release parou" sem ADB e sem logcat.

import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/services/boot_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(BootDiagnostics.instance.reset);

  group('Fases do boot', () {
    test('cada markPhase substitui a fase corrente', () {
      final d = BootDiagnostics.instance;
      for (final p in [
        BootPhases.binding,
        BootPhases.handlers,
        BootPhases.supabase,
        BootPhases.push,
        BootPhases.locale,
        BootPhases.runApp,
      ]) {
        d.markPhase(p);
        expect(d.phase, p);
      }
    });

    test('sem prepare() nada e escrito (nao quebra)', () {
      // markPhase antes de ter caminho de arquivo é um no-op seguro.
      expect(
        () => BootDiagnostics.instance.markPhase(BootPhases.binding),
        returnsNormally,
      );
    });
  });

  group('Agrupamento por causa', () {
    BootFailure f(String error, String stack, {String phase = '9-runApp'}) =>
        BootFailure(
          phase: phase,
          error: error,
          stack: stack,
          at: DateTime.now(),
          from: 'boot',
        );

    test('40 repeticoes da MESMA excecao viram 1 causa', () {
      final all = List.generate(
        40,
        (i) => f(
          'setState() or markNeedsBuild() called during build.',
          '#1 State.setState (file:///lib/main.dart:191)\n'
              '#2 _FeedScreenState (file:///lib/main.dart:1704)',
        ),
      );
      final groups = BootDiagnostics.groupFailures(all);
      expect(groups, hasLength(1), reason: 'mesma causa nao sao 40 problemas');
      expect(groups.single.count, 40);
    });

    test('causas diferentes sao separadas', () {
      final all = [
        f('Exception A', '#1 a (file:///a.dart:1)'),
        f('Exception B', '#1 b (file:///b.dart:2)'),
        f('Exception A', '#1 a (file:///a.dart:1)'),
      ];
      final groups = BootDiagnostics.groupFailures(all);
      expect(groups, hasLength(2));
      // a mais frequente vem primeiro
      expect(groups.first.count, 2);
    });

    test('agrupamento ignora variacao do frame #0 do framework', () {
      final all = [
        f(
          'X',
          '#0 debugCheckZone (file:///framework.dart:1)\n#1 real (file:///a.dart:9)',
        ),
        f(
          'X',
          '#0 outraCoisa (file:///framework.dart:2)\n#1 real (file:///a.dart:9)',
        ),
      ];
      // frames #0 diferentes nao devem separar a mesma causa de origem
      expect(BootDiagnostics.groupFailures(all), hasLength(1));
    });

    test('grouped() combina sessão atual e anterior', () {
      final d = BootDiagnostics.instance;
      d.record('boot', Exception('mesma'), StackTrace.current);
      expect(d.grouped(), isNotEmpty);
    });
  });
}
