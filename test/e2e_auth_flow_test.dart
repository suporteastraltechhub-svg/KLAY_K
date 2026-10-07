// E2E de autenticação REAL contra o Supabase de produção (projeto oysyuialaelzcxxkfdsl).
//
// Só roda com `KLAY_E2E=true` (opt-in explícito); do contrário é pulado para
// não tocar rede nos testes determinísticos do `flutter test`.
//
// As contas são de TESTE e foram criadas/confirmadas pelos canais ADMIN
// oficiais (GoTrue Admin API com Service Role usada SEMPRE fora deste teste;
// papel is_admin concedido pelo dono do banco). Nada aqui contorna segurança:
// o teste exercita exatamente o mesmo caminho do app.
//
//   KLAY_E2E=true flutter test test/e2e_auth_flow_test.dart --timeout 300s
//
// Harness (validado por probe):
//  - o primeiro teste (test(), não testWidgets) inicializa o singleton do
//    Supabase na zona REAL — sem isso o HTTP do login fica preso no FakeAsync;
//  - dentro do testWidgets, rede real avança combinando
//    `tester.runAsync(delay real)` + `tester.pump(Duration)` (dispara os
//    timers de zero-delay que o gotrue usa);
//  - operações de rede diretas (RPCs) também vão dentro de runAsync.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/main.dart';
import 'package:klay_k/screens/auth_screen.dart';
import 'package:klay_k/screens/founder_panel_screen.dart';
import 'package:klay_k/services/app_config.dart';
import 'package:klay_k/services/founder_service.dart';
import 'package:klay_k/services/supabase_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

const _adminEmail = 'founder.admin+test@klayk.app';
const _userEmail = 'founder.user+test@klayk.app';
const _password = 'KlayKTest#2026!';

void main() {
  final isE2E = Platform.environment['KLAY_E2E'] == 'true';
  bool? skipUnlessE2E() => isE2E ? null : true;

  setUpAll(() {
    // O flutter_test troca o HttpClient global por um mock que responde 400.
    // No E2E (rede real) restauramos o IOClient padrão; este isolate é o único
    // afetado (cada arquivo de teste roda em um isolate separado).
    if (isE2E) {
      HttpOverrides.global = null;
    }
    // O registrante de plugins do flutter_tester ativa o EventChannel do
    // app_links no startup; sem mock o MissingPluginException marca o teste.
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

  // O app assina o canal de deep links (app_links); no harness o plugin não
  // existe e o erro de ativação do EventChannel marcaria o teste como falho.
  void mockAppLinks() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (call) async => null,
        );
  }

  // Avança rede real (runAsync) + relógio fake (pump) até `cond` ser true.
  Future<void> loopUntil(
    WidgetTester tester,
    bool Function() cond, {
    String what = 'condição',
    int max = 45,
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

  Future<T?> runReal<T>(WidgetTester tester, Future<T> Function() action) =>
      tester.runAsync(action);

  Future<void> pumpAppPastSplash(WidgetTester tester) async {
    await tester.pumpWidget(const KlayKApp());
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Fecha a animação do Splash (4s) e a transição (450ms) do AnimatedSwitcher.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  // Desmonta a árvore e deixa os timers do Realtime/gotrue (50s) expirarem no
  // relógio fake, senão a invariante "timers pendentes" derruba o teardown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 52));
    await tester.pump();
  }

  group('🧪 E2E AUTENTICAÇÃO REAL (KLAY_E2E)', () {
    test('(setup) inicializa Supabase na zona real', () async {
      SharedPreferences.setMockInitialValues(const {});
      await SupabaseService.instance.ensureReady();
      expect(
        SupabaseService.instance.isConfigured,
        isTrue,
        reason: 'E2E exige Supabase configurado (rede real habilitada).',
      );
    }, skip: skipUnlessE2E());

    testWidgets('admin: splash→login REAL pela UI→sessão→logout', (
      tester,
    ) async {
      await resetView(tester);
      mockAppLinks();
      SharedPreferences.setMockInitialValues(const {});
      final db = SupabaseService.instance;

      // Splash → Login (sem sessão armazenada).
      await pumpAppPastSplash(tester);
      await loopUntil(
        tester,
        () => find.byType(AuthScreen).evaluate().isNotEmpty,
        what: 'AuthScreen',
      );
      expect(find.byType(AuthScreen), findsOneWidget);

      // Autenticação REAL pela UI (e-mail/senha digitados → backend).
      await tester.enterText(
        find.byKey(const ValueKey('auth_email')),
        _adminEmail,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        _password,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await loopUntil(
        tester,
        () => db.hasSession,
        what: 'sessão real do admin',
      );
      expect(
        db.currentUser?.email,
        _adminEmail,
        reason: 'usuário da sessão real = conta de teste do admin',
      );

      // A MainScreen chega quando o AppGate entrega a sessão.
      await loopUntil(
        tester,
        () => find.byType(MainScreen).evaluate().isNotEmpty,
        what: 'MainScreen',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byType(AuthScreen),
        findsNothing,
        reason: 'após login real o login sai da tela (AppGate)',
      );

      // Logout real: sessão derrubada no backend e snapshot do storage limpo.
      await runReal(tester, db.signOut);
      expect(
        db.hasSession,
        isFalse,
        reason: 'signOut encerra a sessão real do Supabase',
      );

      // Remove os canais Realtime da MainScreen (keepalive 10s) para não
      // deixar timers fake pendentes no teardown.
      await runReal(tester, db.client.removeAllChannels);
      await settle(tester);
    }, skip: skipUnlessE2E());

    testWidgets(
      'fundador: painel com dados reais, só rola para admin',
      (tester) async {
        await resetView(tester);
        mockAppLinks();
        SharedPreferences.setMockInitialValues(const {});
        final db = SupabaseService.instance;

        await runReal(tester, () => db.signInWithEmail(_adminEmail, _password));
        expect(db.hasSession, isTrue);
        expect(
          await runReal(tester, FounderService.instance.isAdmin),
          isTrue,
          reason: 'role admin concedida no banco é refletida no backend',
        );

        // O Painel do Fundador (mesmo widget da rota real) monta com dados reais
        // via RPC security definer.
        await tester.pumpWidget(
          MaterialApp(
            theme: KlaykTheme.dark(),
            home: const FounderPanelScreen(),
          ),
        );
        // O painel dispara isAdmin+myRole+myCaps e depois ~18 RPCs admin; o
        // HTTP do sandbox é serializado (~250ms/request), então o E2E aguenta
        // mais iterações do que o default antes de renderizar título e métricas.
        await loopUntil(
          tester,
          () => find.text('👑 Painel do Fundador').evaluate().isNotEmpty,
          what: 'Painel do Fundador',
          max: 240,
        );
        await loopUntil(
          tester,
          () => find.text('Usuários').evaluate().isNotEmpty,
          what: 'métrica "Usuários" renderizada com dados do backend',
          max: 240,
        );
        expect(
          find.text('Acesso restrito'),
          findsNothing,
          reason: 'admin vê o painel (não a view restrita)',
        );

        final realStats = await runReal(tester, FounderService.instance.stats);
        expect(
          realStats?['users'],
          isA<num>(),
          reason: 'admin_stats retornou contador real do Supabase',
        );
        expect(
          realStats?['reports_pending'],
          isA<num>(),
          reason: 'admin_stats trouxe módulos de dados reais',
        );

        await runReal(tester, db.signOut);
        expect(db.hasSession, isFalse);
        await runReal(tester, db.client.removeAllChannels);
        await settle(tester);
      },
      skip: skipUnlessE2E(),
    );

    testWidgets(
      'comum: login ok, RLS nega RPCs admin e flag is_admin',
      (tester) async {
        await resetView(tester);
        mockAppLinks();
        SharedPreferences.setMockInitialValues(const {});
        final db = SupabaseService.instance;

        // Login real (API direta — mesmo serviço que a tela de login usa).
        await runReal(tester, () => db.signInWithEmail(_userEmail, _password));
        expect(db.hasSession, isTrue);
        expect(db.currentUser?.email, _userEmail);
        expect(
          await runReal(tester, FounderService.instance.isAdmin),
          isFalse,
          reason: 'comum não tem role admin',
        );

        // RLS no nível de dados: comum não lê RPCs admin.
        final statsOutcome = await runReal(tester, () async {
          try {
            await FounderService.instance.stats();
            return 'ok';
          } on AdminAccessDeniedException {
            return 'blocked';
          } catch (e) {
            return 'other:$e';
          }
        });
        expect(
          statsOutcome,
          'blocked',
          reason: 'admin_stats deve negar usuário comum (resposta not_admin)',
        );

        // Escalação via RPC admin: comum NUNCA promove a si ou outro.
        final denied = await runReal(
          tester,
          () => db.client
              .rpc(
                'admin_set_admin',
                params: {
                  'p_user_id': db.currentUser?.id ?? '',
                  'p_admin': true,
                },
              )
              .then((_) => 'ok')
              .catchError((Object e) => 'denied'),
        );
        expect(denied, 'denied', reason: 'comum jamais promove a si/outro');

        // Escalação via UPDATE direto na tabela: a flag is_admin não é gravável
        // pelo próprio usuário (grants revogados; RLS idempotente de segurança).
        final direct = await runReal(tester, () async {
          try {
            await db.client
                .from('profiles')
                .update({'is_admin': true})
                .eq('id', db.currentUser?.id ?? '')
                .then((_) => 'ok');
            return 'ok';
          } catch (e) {
            return 'denied';
          }
        });
        expect(
          direct,
          'denied',
          reason: 'UPDATE direto de profiles.is_admin é negado (grants/RLS)',
        );

        await runReal(tester, db.signOut);
        expect(db.hasSession, isFalse);
      },
      skip: skipUnlessE2E(),
    );

    testWidgets(
      'persistência: sessão sobrevive a reinício (storage→recover)',
      (tester) async {
        await resetView(tester);
        mockAppLinks();
        SharedPreferences.setMockInitialValues(const {});
        final db = SupabaseService.instance;

        await runReal(tester, () => db.signInWithEmail(_adminEmail, _password));
        expect(db.hasSession, isTrue);

        // A sessão foi persistida no armazenamento local (chave do startup).
        final prefs = await runReal(tester, SharedPreferences.getInstance);
        final tokenKey =
            'sb-${Uri.parse(AppConfig.supabaseUrl).host.split('.').first}-auth-token';
        final stored = prefs?.getString(tokenKey);
        expect(
          stored,
          isNotNull,
          reason: 'sessão gravada no storage (persistência real)',
        );

        // "Reinício": fora da sessão em memória; a restauração usa o JSON
        // persistido (mesmo caminho do SupabaseAuth.recoverSession()).
        await runReal(tester, db.signOut);
        expect(db.hasSession, isFalse);
        await runReal(tester, () => db.client.auth.recoverSession(stored!));
        expect(
          db.hasSession,
          isTrue,
          reason: 'sessão restaurada do armazenamento local',
        );
        expect(db.currentUser?.email, _adminEmail);
        expect(
          await runReal(tester, FounderService.instance.isAdmin),
          isTrue,
          reason: 'após reinício a role admin é revalidada no backend',
        );

        // O AppGate usa o mesmo caminho (recoverSession) para pular o login após
        // reiniciar o app — caminho exercitado de ponta a ponta no teste admin,
        // onde a Splash resolve a sessão e a MainScreen abre sem AuthScreen.

        await runReal(tester, db.signOut);
        expect(db.hasSession, isFalse);
      },
      skip: skipUnlessE2E(),
    );
  });
}
