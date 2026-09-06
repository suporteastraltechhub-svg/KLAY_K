import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Painel do Fundador — camada de dados.
///
/// TODAS as chamadas passam por RPCs `security definer` que re-validam
/// `is_klayk_admin()` no backend. Um usuário comum recebe `not_admin`/erro,
/// mesmo que tente chamar as funções diretamente.
class FounderService {
  FounderService._();

  static final FounderService instance = FounderService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<Map<String, dynamic>> _rpc(String name, [Map<String, dynamic> params = const {}]) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    if (user.id.isEmpty) {
      throw StateError('Não autenticado.');
    }
    final res = await _db.rpc(name, params: params);
    if (res is Map) {
      final m = Map<String, dynamic>.from(res);
      if (m['not_admin'] == true) {
        throw const AdminAccessDeniedException();
      }
      return m;
    }
    return {};
  }

  Future<bool> isAdmin() async {
    try {
      final me = SupabaseService.instance.currentUser?.id;
      if (me == null) return false;
      final res = await _db
          .from('profiles')
          .select('is_admin')
          .eq('id', me)
          .maybeSingle();
      return res?['is_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> stats() async => _rpc('admin_stats');

  Future<List<Map<String, dynamic>>> listUsers() async {
    final res = await _db.rpc('admin_list_users', params: {});
    return List<Map<String, dynamic>>.from(
      (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
  }

  Future<List<Map<String, dynamic>>> listAdmins() async {
    final res = await _db.rpc('admin_list_admins', params: {});
    return List<Map<String, dynamic>>.from(
      (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
  }

  Future<void> setVerified(String userId, bool verified) async {
    await _db.rpc('admin_set_verified', params: {
      'p_user_id': userId,
      'p_verified': verified,
    });
  }

  Future<void> setAdmin(String userId, bool admin) async {
    await _db.rpc('admin_set_admin', params: {
      'p_user_id': userId,
      'p_admin': admin,
    });
  }

  Future<Map<String, dynamic>> storeStats() async => _rpc('admin_store_stats');

  Future<Map<String, dynamic>> giftStats() async => _rpc('admin_gift_stats');

  Future<Map<String, dynamic>> liveStats() async => _rpc('admin_live_stats');

  Future<List<Map<String, dynamic>>> listOrders() async {
    final res = await _db.rpc('admin_list_orders', params: {});
    return List<Map<String, dynamic>>.from(
      (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
  }

  // ---------------------------------------------------------------------------
  // Conversão/resgate de moedas (gestão admin/fundador)
  // ---------------------------------------------------------------------------

  /// Pedidos de conversão pendentes. Admins/fundador leem todos via RLS
  /// (policy `economy_has_admin`) — nunca dados de terceiros para usuário comum.
  Future<List<Map<String, dynamic>>> pendingConversions() async {
    final res = await _db
        .from('currency_conversion_requests')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(50);
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Aprova/rejeita um pedido de conversão. O backend credita a moeda destino
  /// (aprovar) ou reembolsa a reserva na origem (rejeitar), numa única
  /// transação — sem double-spend nem perda de saldo.
  Future<Map<String, dynamic>> decideConversion(
    String requestId, {
    required bool approve,
    String note = '',
  }) async {
    return _rpc('admin_conversion_decision', {
      'p_request_id': requestId,
      'p_approve': approve,
      'p_note': note,
    });
  }

  /// Salva/atualiza uma regra de conversão (config do catálogo).
  Future<Map<String, dynamic>> saveConversionSettings({
    required String id,
    required String name,
    required String fromCurrency,
    required String toCurrency,
    required double rate,
    required int min,
    required int max,
    required double feePercent,
    required String status,
    required String method,
    String description = '',
  }) async {
    return _rpc('admin_conversion_settings', {
      'p_id': id,
      'p_name': name,
      'p_from_currency': fromCurrency,
      'p_to_currency': toCurrency,
      'p_rate': rate,
      'p_min': min,
      'p_max': max,
      'p_fee_percent': feePercent,
      'p_status': status,
      'p_method': method,
      'p_description': description,
    });
  }
}

class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();

  @override
  String toString() => 'Acesso restrito ao Painel do Fundador.';
}