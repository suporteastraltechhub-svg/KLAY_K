// E2E da validação de convite na tela de cadastro, contra o Supabase REAL
// (projeto oysyuialaelzcxxkfdsl). Só roda com `KLAY_E2E=true` (opt-in
// explícito), igual ao e2e_auth_flow_test.dart.
//
//   KLAY_E2E=true flutter test test/e2e_auth_invite_validation_test.dart --timeout 300s
//
// Cobre o requisito da UI:
//  - widget: código INEXISTENTE => mensagem clara + CADASTRO BLOQUEADO antes
//    de criar a conta (caminho de segurança, rede real através da UI);
//  - serviço (zona real): o código REAL do admin resolve como VÁLIDO com o
//    @username do convidante (o corpo jsonb com objeto retorna no harness só
//    fora do fake-async do testWidgets — por isso a verificação "válido"
//    fica aqui e o caso "válido" do widget, determinístico, no
//    test/auth_invite_widget_test.dart com stub injetado).
// O teste nunca finaliza um cadastro (sem criar contas no banco).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/screens/auth_screen.dart';
import 'package:klay_k/services/invite_service.dart';
import 'package:klay_k/services/supabase_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

const _adminEmail = 'founder.admin+test@klayk.app';
const _password = 'KlayKTest#2026!';

void main() {
  final isE2E = Platform.environment['KLAY_E2E'] == 'true';
  bool? skipUnlessE2E() => isE2E ? null : true;

  // Código de convite REAL do admin, recuperado no backend no primeiro teste.
  String? realAdminCode;

  setUpAll(() {
    if (isE2E) {
      HttpOverrides.global = null;
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (call) async => null,
        );
  });

  Future<void> resetView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // Avança rede real (runAsync) + relógio fake (pump) até `cond` ser true.
  Future<void> loopUntil(
    WidgetTester tester,
    bool Function() cond, {
    String what = 'condição',
    int max = 60,
  }) async {
    for (var i = 0; i < max; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (cond()) return;
    }
    fail('E2E: "$what" não aconteceu em $max iterações.');
  }

  Future<void> openSignup(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: KlaykTheme.dark(), home: const AuthScreen()),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Criar conta'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 52));
    await tester.pump();
  }

  group('🧪 E2E VALIDAÇÃO DE CONVITE NA TELA DE CADASTRO (KLAY_E2E)', () {
    test(
      '(setup) inicializa Supabase real e recupera o código do admin',
      () async {
        SharedPreferences.setMockInitialValues(const {});
        await SupabaseService.instance.ensureReady();
        expect(SupabaseService.instance.isConfigured, isTrue);

        final db = SupabaseService.instance;
        await db.signInWithEmail(_adminEmail, _password);
        expect(db.hasSession, isTrue);
        final r = await db.client.rpc('invite_summary', params: const {});
        final m = (r is Map)
            ? r.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        realAdminCode = (m['code']?.toString() ?? '').toUpperCase();
        expect(
          realAdminCode,
          matches(RegExp(r'^KLAYK-[A-Z0-9]{6}$')),
          reason: 'código de convite real do admin recuperado do backend',
        );
        await db.signOut();
        expect(db.hasSession, isFalse);
      },
      skip: skipUnlessE2E(),
    );

    test('serviço: código real do admin valida como VÁLIDO com @username '
        '(mesmo caminho que a tela usa)', () async {
      expect(
        realAdminCode,
        isNotNull,
        reason: 'código real veio do teste de setup',
      );
      final check = await InviteService.instance.validateStatus(realAdminCode!);
      expect(
        check.isValid,
        isTrue,
        reason: 'código real do admin resolve como válido (backend)',
      );
      expect(check.reachable, isTrue);
      expect(
        check.validation?.inviterId,
        isNotEmpty,
        reason: 'validação traz o inviter_id real',
      );
      expect(
        check.validation?.username,
        isNotEmpty,
        reason: 'validação traz o @username real do convidante',
      );
      expect(
        check.validation?.code,
        realAdminCode,
        reason: 'validação ecoa o código normalizado',
      );
    }, skip: skipUnlessE2E());

    testWidgets('widget: código inexistente bloqueia o cadastro na UI com '
        'mensagem clara', (tester) async {
      await resetView(tester);
      SharedPreferences.setMockInitialValues(const {});
      final db = SupabaseService.instance;

      await openSignup(tester);
      expect(find.byType(AuthScreen), findsOneWidget);

      final invite = find.byKey(const ValueKey('auth_invite_code'));
      await tester.enterText(invite, 'klayk-xxxxxx');
      await loopUntil(
        tester,
        () => find
            .text('Código de convite inválido. Confira com quem te convidou.')
            .evaluate()
            .isNotEmpty,
        what: 'mensagem de convite inválido no campo',
      );

      // Submeter com código inválido NÃO cria conta e mantém a mensagem.
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        db.hasSession,
        isFalse,
        reason: 'cadastro bloqueado: signUp NÃO foi chamado',
      );
      expect(
        find.byType(AuthScreen),
        findsOneWidget,
        reason: 'ainda na tela de cadastro (sem sessão)',
      );
      expect(
        find.textContaining('Código de convite inválido'),
        findsWidgets,
        reason: 'mensagem clara de convite inválido continua na tela',
      );

      // Deixa a verificação do submit (rede) concluir antes do teardown.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      await settle(tester);
    }, skip: skipUnlessE2E());
  });
}
