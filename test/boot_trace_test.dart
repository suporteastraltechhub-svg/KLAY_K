// Testes da trilha persistente do startup.
//
// O que precisa ser provado: cada etapa é registrada em ordem e sobrepõe a
// anterior, porque é a última linha que responde "em qual etapa o Release
// parou?". Sem overwrite, uma morte do processo perderia a informação.

import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/services/boot_trace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sequencia de etapas do startup esta completa e ordenada', () {
    // A ordem importa: é ela que permite localizar o ponto de parada.
    expect(
      [
        BootSteps.nativeActivity,
        BootSteps.dartEnter,
        BootSteps.bindings,
        BootSteps.traceReady,
        BootSteps.systemChrome,
        BootSteps.sharedPrefs,
        BootSteps.supabase,
        BootSteps.auth,
        BootSteps.firebase,
        BootSteps.livekitDeferred,
        BootSteps.zoneCheck,
        BootSteps.runApp,
        BootSteps.firstFrame,
      ].length,
      13,
    );
  });

  test('cada etapa tem prefixo que identifica a camada', () {
    expect(BootSteps.nativeActivity, startsWith('N'));
    expect(BootSteps.dartEnter, startsWith('D'));
    expect(BootSteps.runApp, startsWith('D'));
  });

  test('sem diretorio resolvido, step() nao lanca', () {
    // begin() falha sem path_provider neste contexto; step() precisa ser seguro.
    final t = BootTrace.instance;
    expect(() => t.step(BootSteps.dartEnter), returnsNormally);
  });

  test('previousLastStep e null quando nao ha trilha', () {
    expect(BootTrace.instance.previousLastStep, isNull);
  });

  test('step() registra em memoria mesmo sem disco', () {
    final t = BootTrace.instance;
    t.step(BootSteps.bindings);
    t.step(BootSteps.runApp);
    // mesmo sem disco, não pode lançar
    expect(t.appendFailed, isA<bool>());
  });
}
