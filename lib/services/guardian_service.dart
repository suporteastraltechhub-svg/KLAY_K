import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Janela de manutenção ativa (visão pública via `guardian_status`).
class GuardianWindow {
  final String? id;
  final String feature;
  final String mode;
  final String message;
  final DateTime? startedAt;
  final bool isEmergency;

  const GuardianWindow({
    this.id,
    required this.feature,
    required this.mode,
    this.message = '',
    this.startedAt,
    this.isEmergency = false,
  });

  bool get isGlobal => feature == 'all';

  factory GuardianWindow.fromJson(Map<String, dynamic> json) {
    return GuardianWindow(
      id: json['id']?.toString(),
      feature: (json['feature'] as String?) ?? 'all',
      mode: (json['mode'] as String?) ?? 'low',
      message: (json['message'] as String?) ?? '',
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)?.toLocal()
          : null,
      isEmergency: json['is_emergency'] == true,
    );
  }
}

/// Camada de dados do KLAY GUARDIAN.
///
/// TODO: o acesso administrativo é validado NO BACKEND (RPCs `security
/// definer` com `has_perm(...)`/`roles`). O app nunca decide por e-mail — ele
/// apenas expõe a tela conforme `my_caps()` e o servidor revalida cada chamada.
class GuardianService {
  GuardianService._();

  static final GuardianService instance = GuardianService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<dynamic> _rpc(String name, [Map<String, dynamic> params = const {}]) {
    return _db.rpc(name, params: params);
  }

  /// Status público de manutenção (disponível para qualquer usuário logado).
  Future<List<GuardianWindow>> status() async {
    try {
      final r = await _rpc('guardian_status');
      if (r is List) {
        return r
            .map((e) => GuardianWindow.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      // Silencioso: sem manutenção não devemos bloquear o app.
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  // Manutenção (staff com cap `guardian`)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listMaintenance() async {
    final r = await _rpc('guardian_list_maintenance');
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<Map<String, dynamic>> setMaintenance({
    required String mode,
    required String feature,
    String message = '',
  }) async {
    final r = await _rpc('guardian_set_maintenance', {
      'p_mode': mode,
      'p_feature': feature,
      'p_message': message,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<Map<String, dynamic>> endMaintenance({
    required String windowId,
    String reason = '',
  }) async {
    final r = await _rpc('guardian_end_maintenance', {
      'p_window_id': windowId,
      'p_reason': reason,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<Map<String, dynamic>> emergency({String message = ''}) async {
    final r = await _rpc('guardian_emergency', {'p_message': message});
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Motor de regras & alertas
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> runRules() async {
    final r = await _rpc('guardian_run_rules');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> listAlerts({
    String? status,
    String? severity,
    int limit = 100,
  }) async {
    final r = await _rpc('guardian_list_alerts', {
      if (status != null) 'p_status': status,
      if (severity != null) 'p_severity': severity,
      'p_limit': limit,
    });
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<Map<String, dynamic>> resolveAlert({
    required String alertId,
    String note = '',
  }) async {
    final r = await _rpc('guardian_resolve_alert', {
      'p_alert_id': alertId,
      'p_note': note,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Regras & recomendações (staff)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listRules() async {
    final r = await _rpc('guardian_list_rules');
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<Map<String, dynamic>> toggleRule({
    required String ruleId,
    required bool enabled,
  }) async {
    final r = await _rpc('guardian_toggle_rule', {
      'p_rule_id': ruleId,
      'p_enabled': enabled,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> listRecommendations() async {
    final r = await _rpc('guardian_list_recommendations');
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  // ---------------------------------------------------------------------------
  // Health (métricas reais do banco)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> health() async {
    final r = await _rpc('guardian_health');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  /// Mensagem amigável de erro de autorização do backend.
  String friendlyError(Object? error) {
    final raw = error?.toString() ?? '';
    if (raw.contains('founder_only')) return 'Apenas o fundador pode fazer isso.';
    if (raw.contains('already_active')) return 'Já existe manutenção global ativa.';
    if (raw.contains('not_active')) return 'Janela de manutenção não está ativa.';
    if (raw.contains('rule_not_found')) return 'Regra não encontrada.';
    if (raw.contains('not_open')) return 'Este alerta já foi tratado.';
    if (raw.contains('not_admin') || raw.contains('forbidden')) {
      return 'Permissão negada pelo servidor.';
    }
    return 'Falha de rede ou ação não autorizada.';
  }
}