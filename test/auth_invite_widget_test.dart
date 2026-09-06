// Testes WIDGET offline da validação de convite na tela de cadastro.
//
// Roda no `flutter test` normal (SEM KLAY_E2E): a rede é o mock do
// flutter_test (HTTP 400). Por isso a validação do convite é INJETADA no
// AuthScreen (param `inviteChecker`) — aqui testamos o comportamento exato do
// WIDGET para cada estado (válido/inválido/verificação indisponível) de forma
// determinística, sem rede. O comportamento com o BACKEND real fica no E2E
// test/e2e_auth_invite_validation_test.dart (bloqueio no submit) e no
// teste de serviço com rede real (validação do código válido).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/screens/auth_screen.dart';
import 'package:klay_k/services/invite_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

Future<void> goToSignup(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
      theme: KlaykTheme.dark(), home: const AuthScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Criar conta'));
  await tester.pumpAndSettle();
}

// Aguarda o debounce (450ms) disparar e a checagem injetada resolver.
Future<void> settleCheck(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump();
}

InviteCheck validCheck(String code) => const InviteCheck(reachable: true,
      validation: InviteValidation(
        code: 'KLAYK-AB12CD',
        inviterId: 'u111',
        displayName: 'Amigo Teste',
        username: 'amigoteste',
        avatarUrl: '',
      ),
    );

void main() {
  testWidgets('cadastro: convite vazio mantém o texto de ajuda padrão',
      (tester) async {
    await goToSignup(tester);

    expect(
      find.text('Código do amigo que te convidou, ex.: KLAYK-AB12CD'),
      findsOneWidget,
    );
    expect(find.textContaining('Código de convite inválido'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro: código válido exibe o convidante e mantém o texto '
      'digitado (uppercase é aplicado no submit)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: KlaykTheme.dark(),
      home: AuthScreen(inviteChecker: (_) async => validCheck('KLAYK-AB12CD')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    final invite = find.byKey(const ValueKey('auth_invite_code'));
    await tester.enterText(invite, 'klayk-ab12cd');
    await settleCheck(tester);

    expect(find.text('Convite válido de @amigoteste'), findsOneWidget);
    // O texto digitado permanece; a normalização para UPPER (que o backend
    // espera) é aplicada na hora do submit.
    final field = tester.widget<TextField>(invite);
    expect(field.controller?.text, 'klayk-ab12cd');
    expect(find.textContaining('Código de convite inválido'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro: código inválido mostra mensagem clara e não some ao '
      'digitar mais', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: KlaykTheme.dark(),
      home: AuthScreen(inviteChecker: (_) async => const InviteCheck(
            reachable: true,
          )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('auth_invite_code')), 'KLAYK-ZZZZZZ');
    await settleCheck(tester);

    expect(
      find.text('Código de convite inválido. Confira com quem te convidou.'),
      findsOneWidget,
    );
    expect(find.textContaining('Convite válido de @'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro: verificação indisponível avisa mas não bloqueia '
      '(campo continua útil)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: KlaykTheme.dark(),
      home: AuthScreen(inviteChecker: (_) async => const InviteCheck(
            reachable: false,
          )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('auth_invite_code')), 'KLAYK-AB12CD');
    await settleCheck(tester);

    expect(find.text('Não foi possível verificar o código agora.'),
        findsOneWidget);
    expect(find.textContaining('Código de convite inválido'), findsNothing);

    // Limpar o campo volta ao estado normal.
    await tester.enterText(find.byKey(const ValueKey('auth_invite_code')), '');
    await tester.pump();
    expect(
      find.text('Código do amigo que te convidou, ex.: KLAYK-AB12CD'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}