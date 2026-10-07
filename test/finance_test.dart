import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/l10n/app_localizations.dart';
import 'package:klay_k/screens/finance_wallet_screen.dart';
import 'package:klay_k/services/admin_service.dart';
import 'package:klay_k/services/finance_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

class _App extends StatelessWidget {
  final Widget child;
  const _App({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: KlaykTheme.dark(),
      locale: const Locale('pt'),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}

Map<String, dynamic> _pkg(
  String id,
  String name,
  int credits,
  int priceCents,
) => {
  'id': id,
  'name': name,
  'emoji': '🪙',
  'currency': 'credits',
  'credits_amount': credits,
  'price_cents': priceCents,
  'is_active': true,
  'sort_order': 1,
};

void _resetOverrides() {
  FinanceService.rpcOverride = null;
  AdminService.rpcOverride = null;
}

void main() {
  setUp(_resetOverrides);
  tearDown(_resetOverrides);

  group('FinanceService — contrato RPC', () {
    test('catalog: mapeia lista de pacotes', () async {
      FinanceService.rpcOverride = (name, _) async {
        expect(name, 'finance_catalog');
        return [_pkg('pack_500', '500 Moedas', 500, 949)];
      };
      final list = await FinanceService.instance.catalog();
      expect(list, hasLength(1));
      expect(list.first['name'], '500 Moedas');
    });

    test('catalog: resposta não-lista vira []', () async {
      FinanceService.rpcOverride = (_, __) async => null;
      expect(await FinanceService.instance.catalog(), isEmpty);
    });

    test('createCoinOrder: envia package, idempotency, method', () async {
      Map<String, dynamic>? received;
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'create_coin_order');
        received = Map<String, dynamic>.from(params);
        return {
          'ok': true,
          'order_id': 'o-1',
          'payment_id': 'p-1',
          'price_cents': 949,
          'credits_amount': 500,
          'status': 'pending',
        };
      };
      final res = await FinanceService.instance.createCoinOrder(
        'pack_500',
        idempotencyKey: 'klay-key-123',
      );
      expect(received!['p_package_id'], 'pack_500');
      expect(received!['p_idempotency_key'], 'klay-key-123');
      expect(received!['p_method'], 'card');
      expect(res['order_id'], 'o-1');
    });

    test('createCoinOrder: retry idempotente devolve duplicate', () async {
      FinanceService.rpcOverride = (_, __) async => {
        'ok': true,
        'duplicate': true,
        'order_id': 'o-1',
        'payment_id': 'p-1',
        'status': 'pending',
      };
      final res = await FinanceService.instance.createCoinOrder(
        'pack_500',
        idempotencyKey: 'klay-key-123',
      );
      expect(res['duplicate'], true);
      expect(res['payment_id'], 'p-1');
    });

    test('orderStatus: mapeia polling', () async {
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'finance_order_status');
        expect(params['p_order_id'], 'o-1');
        return {
          'order_id': 'o-1',
          'order_status': 'paid',
          'credits_delivered': 500,
          'payment_status': 'captured',
        };
      };
      final s = await FinanceService.instance.orderStatus('o-1');
      expect(s['order_status'], 'paid');
      expect(s['credits_delivered'], 500);
    });

    test('history: mapeia extrato (ordem preservada)', () async {
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'my_finance_history');
        expect(params['p_limit'], 60);
        return [
          {'kind': 'order', 'status': 'paid', 'credits': 500},
          {'kind': 'refund', 'status': 'processed', 'credits': -100},
        ];
      };
      final h = await FinanceService.instance.history(limit: 60);
      expect(h, hasLength(2));
      expect(h.first['kind'], 'order');
    });

    test('creatorBalance: mapeia saldo criador', () async {
      FinanceService.rpcOverride = (_, __) async => {
        'available_credits': 320,
        'pending_credits': 40,
        'withdrawn_credits': 0,
      };
      final b = await FinanceService.instance.creatorBalance();
      expect(b['available_credits'], 320);
      expect(b['pending_credits'], 40);
    });

    test('requestPayout: envia amount e mapeia ok', () async {
      Map<String, dynamic>? received;
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'creator_payout_request');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'request_id': 'r-1', 'amount_credits': 300};
      };
      final res = await FinanceService.instance.requestPayout(300);
      expect(received!['p_amount_credits'], 300);
      expect(res['ok'], true);
    });

    test('adminFinanceStats: mapeia agregados', () async {
      FinanceService.rpcOverride = (_, __) async => {
        'orders_total': 12,
        'revenue_cents': 9900.0,
      };
      final s = await FinanceService.instance.adminFinanceStats();
      expect(s['orders_total'], 12);
    });

    test('adminPriceUpdate: envia price_cents + reason', () async {
      Map<String, dynamic>? received;
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'admin_price_update');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'old_price_cents': 949, 'new_price_cents': 799};
      };
      final res = await FinanceService.instance.adminPriceUpdate(
        'pack_500',
        newPriceCents: 799,
        reason: 'promo',
      );
      expect(received!['p_package_id'], 'pack_500');
      expect(received!['p_new_price_cents'], 799);
      expect(res['new_price_cents'], 799);
    });

    test('financeRefund: envia payment_id + reason', () async {
      Map<String, dynamic>? received;
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'finance_refund');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'status': 'refunded', 'credits_refunded': 500};
      };
      final res = await FinanceService.instance.financeRefund(
        'p-1',
        reason: 'estorno',
      );
      expect(received!['p_payment_id'], 'p-1');
      expect(res['credits_refunded'], 500);
    });

    test('financeIntegrityCheck: mapeia anomalias', () async {
      FinanceService.rpcOverride = (_, __) async => {
        'ok': true,
        'anomalies': [
          {'type': 'PARTIAL_DELIVERY'},
        ],
        'integrity': 'FINANCIAL_INTEGRITY_ALERT',
      };
      final res = await FinanceService.instance.financeIntegrityCheck();
      expect(res['integrity'], 'FINANCIAL_INTEGRITY_ALERT');
      expect((res['anomalies'] as List), hasLength(1));
    });

    test('adminPayoutDecision: aprova com params corretos', () async {
      Map<String, dynamic>? received;
      FinanceService.rpcOverride = (name, params) async {
        expect(name, 'admin_payout_decision');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'status': 'paid', 'amount_credits': 400};
      };
      final res = await FinanceService.instance.adminPayoutDecision(
        'r-1',
        approve: true,
        note: 'ok',
      );
      expect(received!['p_request_id'], 'r-1');
      expect(received!['p_approve'], true);
      expect(res['status'], 'paid');
    });

    test('friendlyError: erros específicos são mapeados', () {
      expect(
        FinanceService.friendlyError('insufficient_balance'),
        'Saldo insuficiente ou valor inválido.',
      );
      expect(
        FinanceService.friendlyError('package_not_found'),
        'Pacote indisponível.',
      );
      expect(
        FinanceService.friendlyError('bad_signature'),
        'Assinatura de pagamento inválida.',
      );
      expect(
        FinanceService.friendlyError('not_admin'),
        'Permissão negada pelo servidor.',
      );
      expect(
        FinanceService.friendlyError('amount_mismatch'),
        'Valor do pagamento não confere.',
      );
    });

    test('newIdempotencyKey: gera chaves únicas', () {
      final a = FinanceService.newIdempotencyKey();
      final b = FinanceService.newIdempotencyKey();
      expect(a, isNotEmpty);
      expect(a.length, greaterThanOrEqualTo(8));
      expect(a, isNot(b));
    });
  });

  group('FinanceWalletScreen — UI', () {
    Future<void> pumpFinance(WidgetTester tester) async {
      await tester.pumpWidget(const _App(child: FinanceWalletScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('vazio mostra "Sem dados disponíveis"', (tester) async {
      FinanceService.rpcOverride = (name, _) async {
        if (name == 'finance_catalog' ||
            name == 'my_finance_history' ||
            name == 'my_creator_earnings') {
          return [];
        }
        return {
          'available_credits': 0,
          'pending_credits': 0,
          'withdrawn_credits': 0,
        };
      };
      AdminService.rpcOverride = (_, __) async => {'credits': 0};

      await pumpFinance(tester);
      expect(find.text('Sem dados disponíveis'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erro de rede mostra botão Tentar novamente', (tester) async {
      FinanceService.rpcOverride = (_, __) async => throw StateError('net');
      AdminService.rpcOverride = (_, __) async => throw StateError('net');

      await tester.pumpWidget(const _App(child: FinanceWalletScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar a carteira.'),
        findsOneWidget,
      );
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza pacotes do catálogo com preço e botão Comprar', (
      tester,
    ) async {
      FinanceService.rpcOverride = (name, _) async {
        if (name == 'finance_catalog') {
          return [
            _pkg('pack_100', '100 Moedas', 100, 199),
            _pkg('pack_500', '500 Moedas', 500, 949),
          ];
        }
        if (name == 'my_finance_history' || name == 'my_creator_earnings') {
          return [];
        }
        return {
          'available_credits': 0,
          'pending_credits': 0,
          'withdrawn_credits': 0,
        };
      };
      AdminService.rpcOverride = (_, __) async => {'credits': 42};

      await pumpFinance(tester);

      expect(find.text('100 Moedas'), findsOneWidget);
      expect(find.text('500 Moedas'), findsOneWidget);
      expect(find.text('Comprar'), findsNWidgets(2));
      // NumberFormat pt_BR usa espaço não separável entre R$ e o número.
      expect(find.text('R\$\u00A01,99'), findsOneWidget);
      expect(find.text('R\$\u00A09,49'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filtro Compras mostra apenas pedidos', (tester) async {
      FinanceService.rpcOverride = (name, _) async {
        if (name == 'finance_catalog' || name == 'my_creator_earnings') {
          return [];
        }
        if (name == 'my_finance_history') {
          return [
            {
              'kind': 'order',
              'status': 'paid',
              'credits': 500,
              'price_cents': 949,
            },
            {'kind': 'earning', 'status': 'available', 'credits': 120},
            {'kind': 'refund', 'status': 'processed', 'credits': -500},
          ];
        }
        return {
          'available_credits': 0,
          'pending_credits': 0,
          'withdrawn_credits': 0,
        };
      };
      AdminService.rpcOverride = (_, __) async => {'credits': 0};

      await pumpFinance(tester);

      // Filter 3 = Compras (kind == 'order')
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();

      expect(find.text('Compra de moedas'), findsOneWidget);
      expect(find.text('Reembolso'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filtro Reembolsos mostra apenas reembolsos', (tester) async {
      FinanceService.rpcOverride = (name, _) async {
        if (name == 'finance_catalog' || name == 'my_creator_earnings') {
          return [];
        }
        if (name == 'my_finance_history') {
          return [
            {
              'kind': 'order',
              'status': 'paid',
              'credits': 500,
              'price_cents': 949,
            },
            {'kind': 'refund', 'status': 'processed', 'credits': -500},
          ];
        }
        return {
          'available_credits': 0,
          'pending_credits': 0,
          'withdrawn_credits': 0,
        };
      };
      AdminService.rpcOverride = (_, __) async => {'credits': 0};

      await pumpFinance(tester);

      // Filter 5 = Reembolsos (kind == 'refund')
      await tester.tap(find.text('Reembolsos'));
      await tester.pumpAndSettle();

      expect(find.text('Reembolso'), findsOneWidget);
      expect(find.text('Compra de moedas'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fluxo de compra cria pedido, verifica, confirma', (
      tester,
    ) async {
      var orderCreated = false;
      const createdOrderId = 'o-abc';
      FinanceService.rpcOverride = (name, _) async {
        if (name == 'finance_catalog') {
          return [_pkg('pack_100', '100 Moedas', 100, 199)];
        }
        if (name == 'create_coin_order') {
          orderCreated = true;
          return {
            'ok': true,
            'order_id': createdOrderId,
            'payment_id': 'p-1',
            'price_cents': 199,
            'credits_amount': 100,
            'status': 'pending',
          };
        }
        if (name == 'finance_order_status') {
          return {
            'order_id': createdOrderId,
            'order_status': 'paid',
            'credits_delivered': 100,
            'payment_status': 'captured',
          };
        }
        if (name == 'my_finance_history' || name == 'my_creator_earnings') {
          return [];
        }
        return {
          'available_credits': 0,
          'pending_credits': 0,
          'withdrawn_credits': 0,
        };
      };
      AdminService.rpcOverride = (_, __) async => {'credits': 0};

      await pumpFinance(tester);

      // Tap "Comprar" on the first package
      await tester.tap(find.text('Comprar').first);
      await tester.pump(); // cria pedido (createCoinOrder)
      // Não usar pumpAndSettle aqui: o dialog tem spinner infinito, que
      // mantém o relógio fake avançando além do poll de 1.6s e fecha o dialog.
      await tester.pump(const Duration(milliseconds: 100));

      // Dialog with processing title is visible
      expect(find.text('Verificando transação...'), findsOneWidget);
      expect(orderCreated, isTrue);

      // Advance past the first poll interval (1.6s) → backend says paid
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(); // orderStatus resolve → pop + reload
      await tester.pumpAndSettle();

      // Snackbar shows success
      expect(
        find.text('Pagamento confirmado! Moedas entregues.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
