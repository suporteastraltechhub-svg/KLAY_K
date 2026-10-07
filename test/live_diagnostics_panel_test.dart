import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/widgets/live_diagnostics_panel.dart';

void main() {
  testWidgets('mostra itens e executa teste rápido', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveDiagnosticsPanel(
            snapshotBuilder: () => const [
              LiveDiagnosticItem(
                label: 'Conexão',
                value: 'conectado',
                icon: Icons.cloud_done_rounded,
                status: LiveDiagnosticStatus.healthy,
              ),
            ],
            recentEvents: const ['evento recente'],
            quickTests: [
              LiveDiagnosticQuickTest(
                label: 'Executar',
                callback: () async {
                  calls++;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('KLAY K LIVE DIAGNOSTICS'), findsOneWidget);
    expect(find.text('Conexão'), findsOneWidget);
    expect(find.text('evento recente'), findsOneWidget);

    await tester.tap(find.text('Executar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, 1);
    expect(find.text('Passed'), findsOneWidget);
  });
}
