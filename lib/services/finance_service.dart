import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Camada de dados do SISTEMA FINANCEIRO CENTRAL do KLAY K (KLAY K FINANCE).
///
/// Todo valor sensível (preço, créditos, destino, taxas) é decidido NO
/// BACKEND pelas RPCs `security definer` desta feature. O app apenas envia
/// identidade e muda estados; saldo NUNCA é decidido aqui. A entrega de
/// moedas de compra/webhook é idempotente no servidor (`finance_webhook_capture`).
///
/// Dinheiro real × moeda virtual ficam separados: estas chamadas movem MOEDA
/// VIRTUAL (credits). Resgate de ganhos de criador é uma INTENÇÃO registrada;
/// a liquidação real acontece manualmente pelo fundador, fora do app.
class FinanceService {
  FinanceService._();

  static final FinanceService instance = FinanceService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<String> _uid() async {
    final u = await SupabaseService.instance.ensureAuthenticated();
    if (u.id.isEmpty) throw StateError('Não autenticado.');
    return u.id;
  }

  /// Backend injetável APENAS em testes locais (sem rede): quando definido,
  /// substitui a chamada `rpc` do Supabase por um fake. Nunca é atribuído em
  /// produção — apenas os testes definem/limpam para verificar o contrato e o
  /// fluxo da UI sem depender de instância real.
  @visibleForTesting
  static Future<dynamic> Function(String name, Map<String, dynamic> params)?
  rpcOverride;

  Future<dynamic> _rpc(String name, [Map<String, dynamic> params = const {}]) {
    final override = rpcOverride;
    if (override != null) return override(name, params);
    return _db.rpc(name, params: params);
  }

  // ---------------------------------------------------------------------------
  // Compra de moedas virtuais (pacotes)
  // ---------------------------------------------------------------------------

  /// Catálogo ativo de pacotes (preços vêm do backend — nunca do cliente).
  Future<List<Map<String, dynamic>>> catalog() async {
    final r = await _rpc('finance_catalog');
    if (r is List) {
      return r
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Cria pedido + pagamento pendente no backend. `idempotencyKey` evita
  /// pedido duplicado em retry (mesmo valor devolve o pagamento original).
  Future<Map<String, dynamic>> createCoinOrder(
    String packageId, {
    required String idempotencyKey,
    String method = 'card',
  }) async {
    final r = await _rpc('create_coin_order', {
      'p_package_id': packageId,
      'p_idempotency_key': idempotencyKey,
      'p_method': method,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  /// Status de um pedido (polling "Verificando transação...").
  Future<Map<String, dynamic>> orderStatus(String orderId) async {
    final r = await _rpc('finance_order_status', {'p_order_id': orderId});
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  /// Histórico financeiro consolidado do usuário.
  Future<List<Map<String, dynamic>>> history({int limit = 40}) async {
    final r = await _rpc('my_finance_history', {'p_limit': limit});
    if (r is List) {
      return r
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  // Ganhos de criador (presentes) + resgate
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> creatorBalance() async {
    final r = await _rpc('creator_balance');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> myCreatorEarnings({int limit = 30}) async {
    final r = await _rpc('my_creator_earnings', {'p_limit': limit});
    if (r is List) {
      return r
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Reserva ganhos disponíveis para resgate (intenção — liquidação manual).
  Future<Map<String, dynamic>> requestPayout(int amountCredits) async {
    final r = await _rpc('creator_payout_request', {
      'p_amount_credits': amountCredits,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Antifraude (nível calculado no backend)
  // ---------------------------------------------------------------------------

  Future<String> myFraudLevel() async {
    final uid = await _uid();
    try {
      final r = await _rpc('finance_classify_user', {'p_user_id': uid});
      return r?.toString() ?? 'NORMAL';
    } catch (_) {
      return 'NORMAL';
    }
  }

  // ---------------------------------------------------------------------------
  // Admin / Painel do Fundador (cap 'economy' — validado no backend)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> adminFinanceStats() async {
    final r = await _rpc('admin_finance_stats');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> adminFinanceOrders({
    int limit = 50,
  }) async {
    final r = await _rpc('admin_finance_orders', {'p_limit': limit});
    if (r is List) {
      return r
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> adminPriceUpdate(
    String packageId, {
    required double newPriceCents,
    String reason = '',
  }) async {
    final r = await _rpc('admin_price_update', {
      'p_package_id': packageId,
      'p_new_price_cents': newPriceCents,
      'p_reason': reason,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<Map<String, dynamic>> financeRefund(
    String paymentId, {
    String reason = '',
  }) async {
    final r = await _rpc('finance_refund', {
      'p_payment_id': paymentId,
      'p_reason': reason,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<Map<String, dynamic>> financeIntegrityCheck() async {
    final r = await _rpc('finance_integrity_check');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> adminListPayouts({int limit = 50}) async {
    final r = await _rpc('admin_list_payouts', {'p_limit': limit});
    if (r is List) {
      return r
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> adminPayoutDecision(
    String requestId, {
    required bool approve,
    String note = '',
  }) async {
    final r = await _rpc('admin_payout_decision', {
      'p_request_id': requestId,
      'p_approve': approve,
      'p_note': note,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  /// Mensagem amigável para erros financeiros específicos do backend.
  static String friendlyError(Object? error) {
    final raw = error?.toString() ?? '';
    if (raw.contains('not_authenticated')) return 'Faça login para continuar.';
    if (raw.contains('not_admin')) return 'Permissão negada pelo servidor.';
    if (raw.contains('package_not_found') || raw.contains('package_inactive')) {
      return 'Pacote indisponível.';
    }
    if (raw.contains('bad_idempotency_key')) {
      return 'Identificador de pedido inválido.';
    }
    if (raw.contains('insufficient_funds') ||
        raw.contains('insufficient_balance') ||
        raw.contains('amount_too_small')) {
      return 'Saldo insuficiente ou valor inválido.';
    }
    if (raw.contains('bad_signature')) {
      return 'Assinatura de pagamento inválida.';
    }
    if (raw.contains('amount_mismatch')) {
      return 'Valor do pagamento não confere.';
    }
    if (raw.contains('payment_not_found') ||
        raw.contains('order_not_found') ||
        raw.contains('payment_not_refundable') ||
        raw.contains('payment_not_capturable')) {
      return 'Pagamento/pedido não encontrado ou estado inválido.';
    }
    if (raw.contains('request_not_found') ||
        raw.contains('request_already_decided')) {
      return 'Resgate não encontrado ou já decidido.';
    }
    if (raw.contains('PGRST116')) return 'Registro não encontrado.';
    return 'Não foi possível concluir. Tente novamente.';
  }

  /// Gera um idempotency_key seguro para pedidos (usado pelo app no retry).
  static String newIdempotencyKey() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'klay-$ts-${_rand8()}';
  }

  static String _rand8() {
    final r = DateTime.now().microsecondsSinceEpoch & (0xFFFFFFFF & ~0x7);
    final hex = r.toRadixString(16).padLeft(8, '0');
    return hex.substring(hex.length - 8);
  }
}
