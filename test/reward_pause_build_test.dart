// Regressão do "setState() or markNeedsBuild() called during build".
//
// Cadeia do bug:
//   _FeedScreenState.didUpdateWidget  (fase de build)
//     -> _updateRewardPause()
//       -> ValueNotifier.value = ...        (notifica de forma SÍNCRONA)
//         -> _RewardFloatingButtonState._onPausedChanged()
//           -> RewardTimerController.setActive()
//             -> notifyListeners()
//               -> AnimatedBuilder.markNeedsBuild()  <-- árvore em construção
//
// A correção tem duas camadas:
//  1. o caller não notifica durante o build (sinal adiado para pós-frame);
//  2. RewardTimerController.setActive recusa notificar na fase de build e
//     adia a aplicação — garantia central, independente do caller.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/services/reward_service.dart';

void main() {
  testWidgets(
    'notificar a partir do didUpdateWidget nao quebra o AnimatedBuilder irmao',
    (tester) async {
      final controller = RewardTimerController();
      final signal = ValueNotifier<bool>(false);
      addTearDown(controller.dispose);
      addTearDown(signal.dispose);

      // Geometria real do KLAY K:
      //  - _NotifyingParent (o FeedScreen) roda o didUpdateWidget e escreve no
      //    ValueNotifier compartilhado;
      //  - _FloatingLike (o RewardFloatingButton) e IRMAO do pai — fica FORA da
      //    subarvore do alvo do build, que e a condicao para o assert de
      //    markNeedsBuild disparar;
      //  - dentro dele ha um ListenableBuilder escutando o controller, que e o
      //    AnimatedBuilder que recebia markNeedsBuild durante o build.
      Future<void> pumpApp(int tag) => tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              // O alvo do build e _TabBody: _NotifyingParent reconstroi dentro
              // dele e dispara o notifier no didUpdateWidget.
              _TabBody(
                child: _NotifyingParent(signal: signal, tag: tag),
              ),
              // A bolinha e IRMA do alvo do build: NAO e descendente dele.
              // E exatamente por isso que o assert de markNeedsBuild
              // dispara neste caso.
              _FloatingLike(signal: signal, controller: controller),
            ],
          ),
        ),
      );

      await pumpApp(1);
      await tester.pump();

      // segundo pump: o pai e reconstruido -> didUpdateWidget notifica
      await pumpApp(2);
      await tester.pump();

      // o erro original: "setState() or markNeedsBuild() called during build"
      expect(tester.takeException(), isNull);

      // a aplicacao foi adiada para o fim do frame e o valor chegou ao controller
      expect(controller.isActive, isTrue);

      controller.setActive(false);
      await tester.pump();
      expect(controller.isRunning, isFalse);
    },
  );

  testWidgets(
    'setActive chamado de dentro do build nao quebra o AnimatedBuilder',
    (tester) async {
      final controller = RewardTimerController();
      addTearDown(controller.dispose);

      // Reprodução fiel da condição original: o AnimatedBuilder constrói e, no
      // próprio build, o controller muda de valor. Sem o adiamento a
      // notificação síncrona voltaria nele como markNeedsBuild() durante o
      // build -> "setState() or markNeedsBuild() called during build".
      //
      // Só no primeiro build, como um `didUpdateWidget` faria — se reconfigurasse
      // a cada build viraria um laço e não representaria o bug original.
      var jaAplicou = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (!jaAplicou) {
                jaAplicou = true;
                controller.setActive(true);
              }
              return const Text('ok');
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ok'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // o valor foi aplicado, adiado para o fim do frame
      expect(controller.isActive, isTrue);

      // o ciclo ligou um Timer periódico: precisa ser parado antes do fim do
      // teste, senão o harness acusa "A Timer is still pending".
      controller.setActive(false);
      await tester.pump();
      expect(controller.isRunning, isFalse);
    },
  );

  testWidgets(
    'AnimatedBuilder reagindo ao controller não acusa erro de build',
    (tester) async {
      final controller = RewardTimerController();
      addTearDown(controller.dispose);

      var notified = 0;
      controller.addListener(() => notified++);

      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => const Text('ok'),
          ),
        ),
      );

      controller.setActive(true);
      await tester.pump();
      controller.setActive(false);
      await tester.pump();

      expect(find.text('ok'), findsOneWidget);
      expect(notified, greaterThanOrEqualTo(2));
    },
  );

  test('setActive nao notifica quando o valor nao muda', () {
    final controller = RewardTimerController();
    addTearDown(controller.dispose);

    var notified = 0;
    controller.addListener(() => notified++);

    controller.setActive(false); // já é o valor inicial
    expect(notified, 0, reason: 'notificação sem mudança é desperdício');

    controller.setActive(true);
    expect(notified, 1);
    controller.setActive(true);
    expect(notified, 1, reason: 'repetir o mesmo valor não deve notificar');
  });

  test('setActive após dispose é ignorado (não lança)', () {
    final controller = RewardTimerController()..dispose();
    // Não deve lançar ChangeNotifier-after-dispose.
    expect(() => controller.setActive(true), returnsNormally);
  });
}

/// Reproduz o `FeedScreen`: no `didUpdateWidget` escreve no notifier
/// compartilhado — e o que dispara toda a cadeia dentro da fase de build.
class _NotifyingParent extends StatefulWidget {
  const _NotifyingParent({required this.signal, this.tag = 1});

  final ValueNotifier<bool> signal;
  final int tag;

  @override
  State<_NotifyingParent> createState() => _NotifyingParentState();
}

class _NotifyingParentState extends State<_NotifyingParent> {
  @override
  void didUpdateWidget(covariant _NotifyingParent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag == widget.tag) return;
    // notificação síncrona durante a fase de build — o que causava o crash.
    widget.signal.value = !widget.signal.value;
  }

  @override
  Widget build(BuildContext context) => Text('pai${widget.tag}');
}

/// Reproduz o `RewardFloatingButton`: irmão do pai, escuta o mesmo notifier e
/// empurra o valor para o controller, que tem um `ListenableBuilder` abaixo.
class _FloatingLike extends StatefulWidget {
  const _FloatingLike({required this.signal, required this.controller});

  final ValueNotifier<bool> signal;
  final RewardTimerController controller;

  @override
  State<_FloatingLike> createState() => _FloatingLikeState();
}

class _FloatingLikeState extends State<_FloatingLike> {
  void _onSignal() {
    // equivale a RewardTimerController.setActive(...) vindo do RewardTimer
    if (!mounted) return;
    widget.controller.setActive(widget.signal.value);
  }

  @override
  void initState() {
    super.initState();
    widget.signal.addListener(_onSignal);
  }

  @override
  void dispose() {
    widget.signal.removeListener(_onSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Text('bolinha${widget.controller.isActive}'),
  );
}

/// Container que reconstrói (é o "alvo do build" do cenário).
class _TabBody extends StatelessWidget {
  const _TabBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: child);
}
