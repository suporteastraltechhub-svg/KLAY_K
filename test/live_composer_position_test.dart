import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Descobre o que realmente empurra o campo para o meio da tela.
///
/// Hipótese: o `Scaffold` já tem `resizeToAvoidBottomInset: true` (padrão), ou
/// seja, ele JÁ encolhe o body inteiro pela altura do teclado. Se o composer
/// também aplica `bottom: viewInsets`, a compensação acontece duas vezes e o
/// campo sobe o dobro do necessário — caindo no meio da LIVE.
Widget _harness({
  required bool resizeToAvoidBottomInset,
  required double viewInsetsBottom,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(1080, 2400),
      viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
    ),
    child: MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            // o composer aplica o viewInsets, como no código real
            Positioned(
              left: 0,
              right: 0,
              bottom: viewInsetsBottom,
              child: SafeArea(
                top: false,
                bottom: viewInsetsBottom == 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40, child: Text('msgs')),
                    SizedBox(
                      key: const Key('composerBar'),
                      height: 56,
                      child: Row(
                        children: [
                          const Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Diga algo',
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.emoji_emotions_outlined),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  const tela = 2400.0;
  const teclado = 900.0;

  Future<void> medir(
    WidgetTester tester, {
    required bool resize,
    required double viewInsets,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(resizeToAvoidBottomInset: resize, viewInsetsBottom: viewInsets),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('resize=true + bottom:viewInsets => compensa 2x', (tester) async {
    await medir(tester, resize: true, viewInsets: teclado);
    final r = tester.getRect(find.byKey(const Key('composerBar')));
    // ignore: avoid_print
    print(
      '  [resize=true ] barra.bottom=${r.bottom}  (certo=${tela - teclado})',
    );
  });

  testWidgets('resize=false + bottom:viewInsets => acerta', (tester) async {
    await medir(tester, resize: false, viewInsets: teclado);
    final r = tester.getRect(find.byKey(const Key('composerBar')));
    // ignore: avoid_print
    print(
      '  [resize=false] barra.bottom=${r.bottom}  (certo=${tela - teclado})',
    );
    expect(r.bottom, moreOrLessEquals(tela - teclado, epsilon: 1.0));
  });

  testWidgets('resize=false, teclado fechado => borda inferior', (
    tester,
  ) async {
    await medir(tester, resize: false, viewInsets: 0);
    final r = tester.getRect(find.byKey(const Key('composerBar')));
    // ignore: avoid_print
    print('  [fechado    ] barra.bottom=${r.bottom}  (certo=$tela)');
    expect(r.bottom, moreOrLessEquals(tela, epsilon: 1.0));
  });
}
