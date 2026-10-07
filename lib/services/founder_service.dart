import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Painel do Fundador — camada de dados.
///
/// TODAS as chamadas passam por RPCs `security definer` que re-validam
/// `is_klayk_admin()` / `is_klayk_founder()` no backend. Um usuário comum
/// recebe `not_admin`/erro, mesmo que tente chamar as funções diretamente.
class FounderService {
  FounderService._();

  static final FounderService instance = FounderService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  /// Backend injetável APENAS em testes locais (sem rede): quando definido,
  /// substitui a chamada `rpc` do Supabase por um fake. Nunca é atribuído em
  /// produção — apenas os testes definem/limpam para verificar o contrato.
  @visibleForTesting
  static Future<dynamic> Function(String name, Map<String, dynamic> params)?
  rpcOverride;

  Future<dynamic> _rpc(
    String name, [
    Map<String, dynamic> params = const {},
  ]) async {
    final override = rpcOverride;
    if (override != null) return override(name, params);
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
    return res;
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

  Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(await _rpc('admin_stats'));

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
    await _db.rpc(
      'admin_set_verified',
      params: {'p_user_id': userId, 'p_verified': verified},
    );
  }

  Future<void> setAdmin(String userId, bool admin) async {
    await _db.rpc(
      'admin_set_admin',
      params: {'p_user_id': userId, 'p_admin': admin},
    );
  }

  Future<Map<String, dynamic>> storeStats() async =>
      Map<String, dynamic>.from(await _rpc('admin_store_stats'));

  Future<Map<String, dynamic>> giftStats() async =>
      Map<String, dynamic>.from(await _rpc('admin_gift_stats'));

  Future<Map<String, dynamic>> liveStats() async =>
      Map<String, dynamic>.from(await _rpc('admin_live_stats'));

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
    return Map<String, dynamic>.from(
      await _rpc('admin_conversion_decision', {
        'p_request_id': requestId,
        'p_approve': approve,
        'p_note': note,
      }),
    );
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
    return Map<String, dynamic>.from(
      await _rpc('admin_conversion_settings', {
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
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // 👑 GOD MODE — Gerenciador de Moedas (founder)
  // Cada RPC re-valida is_klayk_founder() no backend; nada é decidido no client.
  // ---------------------------------------------------------------------------

  /// Busca usuários por nome/username/ID (founder/equipe economy).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await _rpc('founder_search_users', {'p_query': query});
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Saldo completo de uma conta + identidade (founder/equipe economy).
  Future<Map<String, dynamic>> userWallet(String userId) async {
    final res = await _rpc('founder_user_wallet', {'p_user_id': userId});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Ajusta saldo de qualquer moeda (p_delta > 0 adiciona; < 0 remove).
  /// Só founder; motivo obrigatório; auditoria automática no backend.
  Future<Map<String, dynamic>> adjustCurrency({
    required String userId,
    required String currency,
    required int delta,
    required String reason,
  }) async {
    final res = await _rpc('founder_adjust_currency', {
      'p_user_id': userId,
      'p_currency': currency,
      'p_delta': delta,
      'p_reason': reason,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Últimas movimentações do fundador (histórico auditável).
  Future<List<Map<String, dynamic>>> recentAdjustments({int limit = 25}) async {
    final res = await _rpc('founder_recent_adjustments', {'p_limit': limit});
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 🛡️ GOD MODE — Segurança Máxima (Anti-Hack)
  // ---------------------------------------------------------------------------

  /// Visão consolidada: IPs/dispositivos bloqueados, scores, alertas, logins.
  Future<Map<String, dynamic>> securityOverview() async {
    final res = await _rpc('founder_security_overview');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Modo de emergência global (founder-only, cap 'roles'): trava o app e
  /// abre janela `max` com mensagem oficial. Encerrar usa GuardianScreen.
  Future<Map<String, dynamic>> activateEmergency(String message) async {
    final res = await _rpc('guardian_emergency', {'p_message': message});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  Future<void> blockIp(String ip, String reason) async {
    await _rpc('founder_block_ip', {'p_ip': ip, 'p_reason': reason});
  }

  Future<void> unblockIp(String ip) async {
    await _rpc('founder_unblock_ip', {'p_ip': ip});
  }

  Future<void> blockDevice(String deviceId, String reason) async {
    await _rpc('founder_block_device', {
      'p_device_id': deviceId,
      'p_reason': reason,
    });
  }

  Future<void> unblockDevice(String deviceId) async {
    await _rpc('founder_unblock_device', {'p_device_id': deviceId});
  }

  /// Ajusta score de suspeição (delta negativo limpa suspeita).
  Future<Map<String, dynamic>> setSecurityScore({
    required String userId,
    required int delta,
    required String reason,
  }) async {
    final res = await _rpc('founder_set_security_score', {
      'p_user_id': userId,
      'p_delta': delta,
      'p_reason': reason,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Registra tentativa de login (telemetria honesta de falha/sucesso).
  Future<void> logAuthAttempt({
    required String email,
    required bool success,
    String deviceId = '',
  }) async {
    await _rpc('log_auth_attempt', {
      'p_email': email,
      'p_success': success,
      'p_device_id': deviceId,
    });
  }

  // ---------------------------------------------------------------------------
  // 🛠️ GOD MODE — Manutenção (cap `guardian`)
  // ---------------------------------------------------------------------------

  /// Lista janelas de manutenção (histórico; cap guardian/audit/roles).
  Future<List<Map<String, dynamic>>> listMaintenance({int limit = 50}) async {
    final res = await _rpc('guardian_list_maintenance', {'p_limit': limit});
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Inicia uma janela de manutenção (cap `guardian`; audita).
  Future<Map<String, dynamic>> startMaintenance({
    required String mode,
    String feature = 'all',
    String message = '',
    bool emergency = false,
  }) async {
    final res = await _rpc('guardian_set_maintenance', {
      'p_mode': mode,
      'p_feature': feature,
      'p_message': message,
      'p_emergency': emergency,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Encerra uma janela ativa com motivo (cap `guardian`; audita).
  Future<Map<String, dynamic>> endMaintenance({
    required String windowId,
    String reason = '',
  }) async {
    final res = await _rpc('guardian_end_maintenance', {
      'p_window_id': windowId,
      'p_reason': reason,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  // ---------------------------------------------------------------------------
  // 📊 GOD MODE — Dashboard Supremo (founder)
  // ---------------------------------------------------------------------------

  /// Métricas unificadas: lives, presentes, receita de diamantes, retenção e
  /// saúde geral (agregados reais, computados sob demanda).
  Future<Map<String, dynamic>> dashboard() async {
    final res = await _rpc('founder_dashboard');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  // ---------------------------------------------------------------------------
  // 📢 GOD MODE — Notificações (cap roles/moderation/support)
  // ---------------------------------------------------------------------------

  /// Agregados de notificações (total, não lidas, hoje, broadcasts, push tokens).
  Future<Map<String, dynamic>> notificationStats() async {
    final res = await _rpc('founder_notification_stats');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Lista notificações com filtros opcionais (tipo/usuário/limite).
  Future<List<Map<String, dynamic>>> listNotifications({
    String? type,
    String? username,
    int limit = 50,
  }) async {
    final res = await _rpc('mod_list_notifications', {
      if (type != null) 'p_type': type,
      if (username != null) 'p_username': username,
      'p_limit': limit,
    });
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Transmite uma notificação oficial para todos os usuários (audita).
  Future<Map<String, dynamic>> broadcastNotification({
    required String type,
    required String message,
  }) async {
    final res = await _rpc('founder_broadcast_notification', {
      'p_type': type,
      'p_message': message,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  // ---------------------------------------------------------------------------
  // 👑 GOD MODE — Ferramentas de Rei (motor anti-hack Guardian)
  // ---------------------------------------------------------------------------

  /// Lista regras habilitáveis do Guardian (cap guardian/audit/roles).
  Future<List<Map<String, dynamic>>> kingRules() async {
    final res = await _rpc('guardian_list_rules');
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Liga/desliga uma regra de detecção (founder-only; audita).
  Future<Map<String, dynamic>> kingToggleRule({
    required String ruleId,
    required bool enabled,
  }) async {
    final res = await _rpc('guardian_toggle_rule', {
      'p_rule_id': ruleId,
      'p_enabled': enabled,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Executa a varredura das regras agora (cap guardian; audita).
  Future<Map<String, dynamic>> kingRunRules() async {
    final res = await _rpc('guardian_run_rules', {'p_limit': 200});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Lista alertas do Guardian com filtros (status/severidade/limite).
  Future<List<Map<String, dynamic>>> kingAlerts({
    String? status,
    String? severity,
    int limit = 100,
  }) async {
    final res = await _rpc('guardian_list_alerts', {
      if (status != null) 'p_status': status,
      if (severity != null) 'p_severity': severity,
      'p_limit': limit,
    });
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Resolve um alerta aberto com nota (cap guardian; audita).
  Future<Map<String, dynamic>> kingResolveAlert({
    required String alertId,
    String note = '',
  }) async {
    final res = await _rpc('guardian_resolve_alert', {
      'p_alert_id': alertId,
      'p_note': note,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  // ---------------------------------------------------------------------------
  // ⚙️ GOD MODE — Config Globais (cap roles/settings)
  // ---------------------------------------------------------------------------

  /// Retorna todas as chaves de configuração global (key → value/description).
  Future<Map<String, dynamic>> configList() async {
    final res = await _rpc('founder_get_config');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Cria/atualiza uma chave global (audita; valor em JSON).
  Future<Map<String, dynamic>> setConfig({
    required String key,
    required dynamic value,
    String description = '',
  }) async {
    final res = await _rpc('founder_set_config', {
      'p_key': key,
      'p_value': value,
      'p_description': description,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Remove uma chave global (audita).
  Future<Map<String, dynamic>> deleteConfig(String key) async {
    final res = await _rpc('founder_delete_config', {'p_key': key});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  // ---------------------------------------------------------------------------
  // 💬 Feedbacks (cap `support`; envio por qualquer usuário autenticado)
  // ---------------------------------------------------------------------------

  /// Envia feedback do usuário atual (sugestão/bug/elogio/outro + nota 1–5).
  Future<Map<String, dynamic>> submitFeedback({
    required String category,
    required int rating,
    required String message,
  }) async {
    final res = await _rpc('submit_feedback', {
      'p_category': category,
      'p_rating': rating,
      'p_message': message,
    });
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Lista feedbacks (equipe `support`); filtra por status (default: todos).
  Future<List<Map<String, dynamic>>> listFeedbacks({String? status}) async {
    final res = await _rpc('mod_list_feedbacks', {
      if (status != null) 'p_status': status,
    });
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Revisa/arquiva um feedback (cap `support`; audita).
  Future<void> updateFeedbackStatus({
    required String feedbackId,
    required String status,
    String notes = '',
  }) async {
    await _rpc('mod_update_feedback', {
      'p_feedback_id': feedbackId,
      'p_status': status,
      'p_notes': notes,
    });
  }

  /// Agregados de feedback para o painel (cap `support`).
  Future<Map<String, dynamic>> feedbackStats() async {
    final res = await _rpc('founder_feedback_stats');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }
}

class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();

  @override
  String toString() => 'Acesso restrito ao Painel do Fundador.';
}
