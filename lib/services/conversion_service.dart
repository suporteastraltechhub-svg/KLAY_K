import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Camada de dados da conversão/resgate de moedas do KLAY K.
///
/// Todas as chamadas passam por RPCs `security definer` que validam saldo e
/// regras NO BACKEND:
///   * `currency_conversion_request` reserva (debita) o saldo de forma atômica
///     na hora do pedido — é impossível converter mais do que o saldo real;
///   * `cancel_conversion_request` reembolsa a reserva de um pedido próprio
///     ainda pendente;
///   * `my_conversion_settings` devolve as regras ativas (catálogo público);
///   * `my_conversion_requests` devolve o histórico de pedidos do usuário.
/// A RLS da tabela limita leitura ao próprio usuário (e admins/fundador via
/// `economy_has_admin` no servidor). O cliente nunca decide saldo/permissão.
class ConversionService {
  ConversionService._();

  static final ConversionService instance = ConversionService._();

  SupabaseService get _db => SupabaseService.instance;

  SupabaseClient get _client => _db.client;

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  Future<_Auth> _auth() async {
    final u = await _db.ensureAuthenticated();
    if (u.id.isEmpty) throw StateError('Não autenticado.');
    return _Auth(u.id);
  }

  /// Regras de conversão/resgate ativas (catálogo público do backend).
  Future<List<Map<String, dynamic>>> settings() async {
    if (!_ready) throw StateError('Backend não configurado.');
    final res = await _client.rpc('my_conversion_settings');
    if (res is List) {
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Cria um pedido de conversão/resgate. O backend RESERVA (debita) o saldo
  /// na origem de forma atômica e retorna os detalhes do pedido pendente.
  Future<Map<String, dynamic>> request({
    required String settingId,
    required int amount,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _auth();
    final res = await _client.rpc('currency_conversion_request', params: {
      'p_setting_id': settingId,
      'p_amount': amount,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Cancela um pedido PRÓPRIO ainda pendente → o backend reembolsa a reserva.
  Future<Map<String, dynamic>> cancel(String requestId) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _auth();
    final res = await _client.rpc('cancel_conversion_request', params: {
      'p_request_id': requestId,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Histórico de pedidos do próprio usuário.
  Future<List<Map<String, dynamic>>> history({int limit = 30}) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _auth();
    final res = await _client.rpc('my_conversion_requests', params: {
      'p_limit': limit,
    });
    if (res is List) {
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }
}

class _Auth {
  final String id;
  const _Auth(this.id);
}
