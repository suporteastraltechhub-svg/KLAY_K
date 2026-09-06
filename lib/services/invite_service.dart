import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Dados de um convite registrado (convidado xxx por mim).
class InviteRecord {
  final String id;
  final String invitedUserId;
  final String inviteCode;
  final String status;
  final DateTime? validatedAt;

  const InviteRecord({
    required this.id,
    required this.invitedUserId,
    required this.inviteCode,
    required this.status,
    this.validatedAt,
  });

  bool get isRewarded => status == 'rewarded';
  bool get isValidated => status == 'validated';

  factory InviteRecord.fromRpc(Map<String, dynamic> json) => InviteRecord(
        id: json['id']?.toString() ?? '',
        invitedUserId: json['invited_user_id']?.toString() ?? '',
        inviteCode: json['invite_code']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        validatedAt: json['validated_at'] != null
            ? DateTime.tryParse(json['validated_at'].toString())
            : null,
      );
}

/// Resumo do programa de convites do usuário (código + contadores).
class InviteSummary {
  final String code;
  final int invited;
  final int validated;
  final int rewarded;
  final int pendingRewards;

  const InviteSummary({
    this.code = '',
    this.invited = 0,
    this.validated = 0,
    this.rewarded = 0,
    this.pendingRewards = 0,
  });

  factory InviteSummary.fromMap(Map<String, dynamic> json) => InviteSummary(
        code: json['code']?.toString() ?? '',
        invited: (json['invited'] as num?)?.toInt() ?? 0,
        validated: (json['validated'] as num?)?.toInt() ?? 0,
        rewarded: (json['rewarded'] as num?)?.toInt() ?? 0,
        pendingRewards: (json['pending_rewards'] as num?)?.toInt() ?? 0,
      );
}

/// Resultado da validação de um código de convite (antes do cadastro).
class InviteValidation {
  final String code;
  final String inviterId;
  final String displayName;
  final String username;
  final String avatarUrl;

  const InviteValidation({
    required this.code,
    required this.inviterId,
    required this.displayName,
    required this.username,
    this.avatarUrl = '',
  });

  factory InviteValidation.fromMap(Map<String, dynamic> json) =>
      InviteValidation(
        code: json['code']?.toString() ?? '',
        inviterId: json['inviter_id']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString() ?? '',
      );
}

/// Resposta da verificação de um código: distingue a resposta DEFINITIVA do
/// backend ("código inexistente") de uma falha de verificação ("tente de novo").
class InviteCheck {
  final bool reachable;
  final InviteValidation? validation;

  const InviteCheck({required this.reachable, this.validation});

  /// Código confirmado como válido pelo backend.
  bool get isValid => validation != null;

  /// Não foi possível obter resposta do backend (rede/erro).
  bool get isUnknown => !reachable;

  /// Resposta definitiva: o código NÃO existe.
  bool get isInvalid => reachable && validation == null;
}

/// Serviço de convites — toda regra é validada no backend (RPCs security
/// definer). O cliente apenas chama; código/contadores vêm do servidor.
class InviteService {
  InviteService._();

  static final InviteService instance = InviteService._();

  SupabaseService get _supabase => SupabaseService.instance;

  SupabaseClient get _db => _supabase.client;

  Future<dynamic> _rpc(String name, [Map<String, dynamic> params = const {}]) {
    return _db.rpc(name, params: params);
  }

  /// Asegura que o usuário do app tem um código de convite (gera se faltar).
  Future<InviteSummary> ensure() async {
    try {
      final r = await _rpc('invite_summary');
      final m = _asMap(r);
      if (m.isEmpty || (m['code']?.toString() ?? '').isEmpty) {
        return const InviteSummary();
      }
      m['code'] = m['code'].toString().toUpperCase();
      return InviteSummary.fromMap(m);
    } catch (_) {
      return const InviteSummary();
    }
  }

  /// Resumo atual do programa de convites do usuário.
  Future<InviteSummary> summary() async {
    try {
      final r = await _rpc('invite_summary');
      final m = _asMap(r);
      if (m['code']?.toString().isEmpty ?? true) {
        await _rpc('ensure_invite_code');
        final r2 = await _rpc('invite_summary');
        final m2 = _asMap(r2);
        m2['code'] = m2['code'].toString().toUpperCase();
        return InviteSummary.fromMap(m2);
      }
      m['code'] = m['code'].toString().toUpperCase();
      return InviteSummary.fromMap(m);
    } catch (_) {
      return const InviteSummary();
    }
  }

  /// Lista de convidados que cadastraram com o meu código.
  Future<List<InviteRecord>> invites() async {
    try {
      final r = await _rpc('my_invites');
      if (r is! List) return const [];
      return r
          .whereType<Map>()
          .map((m) => InviteRecord.fromRpc(_stringMap(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Valida um código digitado (ex.: tela de cadastro). Retorna null se inválido.
  Future<InviteValidation?> validate(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final r = await _rpc('validate_invite_code', {'p_code': code.trim()});
      if (r == null) return null;
      final m = _asMap(r);
      if (m['inviter_id'] == null) return null;
      return InviteValidation.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  /// Verificação que separa "código NÃO existe (resposta definitiva do
  /// backend)" de "não consegui verificar agora (falha de rede/backend)".
  /// A tela de cadastro usa isso para bloquear códigos inválidos SEM travar o
  /// fluxo quando a verificação está indisponível — a validação definitiva
  /// continua sendo do backend no momento do redeem.
  Future<InviteCheck> validateStatus(String code) async {
    if (code.trim().isEmpty) return const InviteCheck(reachable: true);
    try {
      final r = await _rpc('validate_invite_code', {'p_code': code.trim()});
      if (r == null) return const InviteCheck(reachable: true);
      final m = _asMap(r);
      if ((m['inviter_id'] ?? '').toString().isEmpty) {
        return const InviteCheck(reachable: true);
      }
      return InviteCheck(
        reachable: true,
        validation: InviteValidation.fromMap(m),
      );
    } catch (_) {
      return const InviteCheck(reachable: false);
    }
  }

  /// Registra o convite após cadastro do convidado (idempotente).
  Future<InviteSummary?> redeem(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final r = await _rpc('redeem_invite', {'p_code': code.trim()});
      final m = _asMap(r);
      if (m.isEmpty) return null;
      m['code'] = m['code'].toString().toUpperCase();
      return InviteSummary.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  /// Reivindica cristais por convidados validados.
  Future<({int claimed, int crystals})?> claimRewards() async {
    try {
      final r = await _rpc('claim_invite_rewards');
      final m = _asMap(r);
      if (m.isEmpty) return null;
      return (
        claimed: (m['claimed'] as num?)?.toInt() ?? 0,
        crystals: (m['crystals'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Monta um convite compartilhável (texto + link).
  String shareText(String code, String username) =>
      '🎉 Vem pro KLAY K! Use meu convite: $code\nTe esperando lá pra gente trocar ideia! 🚀';

  Map<String, dynamic> _asMap(dynamic r) {
    if (r == null) return const {};
    if (r is Map) {
      return r.map((k, v) => MapEntry(k.toString(), v));
    }
    if (r is String) {
      try {
        return _stringMap(jsonDecode(r));
      } catch (_) {}
    }
    return const {};
  }

  Map<String, dynamic> _stringMap(Map<dynamic, dynamic> m) => m.map(
        (k, v) => MapEntry(k.toString(), v),
      );
}