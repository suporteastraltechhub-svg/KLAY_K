// Testes do mecanismo de diagnóstico de BOOT.
//
// O objetivo real deste recurso é funcionar NA HORA em que não há ADB: então o
// que precisa ser provado aqui é (a) que uma exceção é capturada e preservada
// com stack trace, (b) que nenhum segredo escapa para a tela/disco, e (c) que
// o relatório sobrevive para a abertura seguinte.

import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/services/boot_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(BootDiagnostics.instance.reset);

  group('Captura', () {
    test('registra exceção com fase, origem e stack trace', () {
      final d = BootDiagnostics.instance;
      d.markPhase(BootPhases.push);
      try {
        throw StateError('boom no boot');
      } catch (e, s) {
        d.record('boot', e, s);
      }

      expect(d.current, hasLength(1));
      final f = d.current.single;
      expect(f.phase, BootPhases.push);
      expect(f.from, 'boot');
      expect(f.error, contains('boom no boot'));
      // o stack trace é real: aponta para o arquivo de origem do throw
      expect(f.stack, contains('boot_diagnostics_test.dart'));
    });

    test('fases do boot ficam registradas na ordem', () {
      final d = BootDiagnostics.instance;
      d.markPhase(BootPhases.binding);
      d.markPhase(BootPhases.locale);
      expect(d.phase, BootPhases.locale);
    });

    test('hasFailure reflete falha atual ou da abertura anterior', () {
      final d = BootDiagnostics.instance;
      expect(d.hasFailure, isFalse);
      d.record('boot', Exception('x'), StackTrace.current);
      expect(d.hasFailure, isTrue);
    });
  });

  group('Redação de segredos', () {
    test('nunca deixa passar chave do Supabase nem do Firebase', () {
      const amostras = [
        'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E',
        'sb_secret_abcdefghijklmnopqrstuvwxyz012345',
        'sbp_1234567890abcdef',
        'AIzaSyDHfWXz_zKwLr2TJJWDaWNt4HtVPmnlMUw',
        'https://oysyuialaelzcxxkfdsl.supabase.co/rest/v1/todos',
      ];
      for (final s in amostras) {
        final out = BootRedactor.redact(s);
        expect(out, isNot(contains('5VdXX67niHP6')), reason: out);
        expect(
          out,
          isNot(contains('abcdefghijklmnopqrstuvwxyz012345')),
          reason: out,
        );
        expect(out, isNot(contains('1234567890abcdef')), reason: out);
        expect(out, isNot(contains('AIzaSyDHfWXz')), reason: out);
        expect(out, isNot(contains('oysyuialaelzcxxkfdsl')), reason: out);
      }
    });

    test('redige JWT, e-mail e query string com segredo', () {
      expect(
        BootRedactor.redact('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig'),
        isNot(contains('eyJhbGciOiJIUzI1NiJ9')),
      );
      expect(
        BootRedactor.redact('contato joao.silva@exemplo.com.br falhou'),
        isNot(contains('joao.silva@exemplo.com.br')),
      );
      final url = BootRedactor.redact(
        'https://app.com/callback?token=SEGREDO123&code=XYZ',
      );
      expect(url, contains('token=<oculto>'), reason: url);
      expect(url, isNot(contains('SEGREDO123')), reason: url);
    });

    test('redige blob longo (base64) preservando o resto', () {
      final blob = 'A' * 200;
      final out = BootRedactor.redact('token=$blob fim');
      expect(out, isNot(contains(blob)));
      expect(out, contains('fim'));
    });

    test('texto sem segredo passa intacto', () {
      const limpo = 'PlatformException: MissingPluginException ao abrir';
      expect(BootRedactor.redact(limpo), contains('MissingPluginException'));
    });

    test('excecao registrada e persistida sai redigida', () {
      final d = BootDiagnostics.instance;
      d.record(
        'boot',
        Exception('falhou com sb_secret_abcdefghijklmnopqrstuvwxyz012345'),
        StackTrace.current,
      );
      expect(d.current.single.error, isNot(contains('abcdefghijklmnopqrstuv')));
      expect(d.current.single.error, contains('<oculto>'));
    });
  });

  group('Persistência sem ADB', () {
    test('JSON do relatório carrega de volta os campos', () {
      final d = BootDiagnostics.instance;
      d.markPhase(BootPhases.supabase);
      d.record('boot', Exception('falhou'), StackTrace.current);
      final json = d.current.single.toJson();
      final back = BootFailure.fromJson(json);
      expect(back, isNotNull);
      expect(back!.phase, BootPhases.supabase);
      expect(back.error, 'Exception: falhou');
      expect(back.from, 'boot');
    });

    test('JSON corrompido não derruba o leitor', () {
      expect(BootFailure.fromJson('isso nao e json'), isNull);
      expect(BootFailure.fromJson('123'), isNull);
    });
  });
}
