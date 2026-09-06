import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/security_models.dart';
import 'supabase_service.dart';

/// Serviço do KLAY K Security Max.
///
/// Toda autorização/verificação vive no backend (RPCs security definer +
/// edge `account-guard`). Este serviço apenas traduz o contrato do backend
/// para os modelos/screens do app — nunca inventa permissão no cliente e
/// nunca esconde erros reais (as exceções preservam o `code` do backend).
class SecurityService {
  SecurityService._();

  static final SecurityService instance = SecurityService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<String> _uid() async {
    final u = await SupabaseService.instance.ensureAuthenticated();
    if (u.id.isEmpty) throw const SecurityException('Não autenticado.');
    return u.id;
  }

  String? _rpcCode(Object error) {
    if (error is PostgrestException) return error.message.trim();
    return null;
  }

  SecurityException _exception(Object error, String fallback) {
    final code = _rpcCode(error);
    return SecurityException(_friendly(code ?? fallback, fallback), code: code);
  }

  String _friendly(String code, String fallback) {
    switch (code) {
      case 'auth_required':
        return 'Você precisa estar autenticado.';
      case 'not_admin':
        return 'Sem permissão para essa ação.';
      case 'bad_target_type':
      case 'bad_target':
        return 'Denúncia inválida: alvo desconhecido.';
      case 'bad_reason':
        return 'Descreva o motivo (pelo menos 3 caracteres).';
      case 'duplicate_report':
        return 'Você já denunciou isso recentemente (aguarde 24h).';
      case 'report_rate_limited':
        return 'Muitas denúncias em pouco tempo — tente mais tarde.';
      case 'session_not_found':
        return 'Sessão não encontrada (pode já ter sido encerrada).';
      case 'bad_refresh_token':
        return 'Sessão atual inválida para essa operação.';
      case 'bad_birth_date':
        return 'Data de nascimento inválida.';
      case 'bad_decision':
        return 'Decisão inválida.';
      case 'flag_not_found':
        return 'Sinalização não encontrada.';
      case 'invalid_target':
        return 'Alvo inválido.';
      case 'unauthorized':
        return 'Não autorizado.';
      case 'bad_action':
        return 'Ação desconhecida.';
      case 'current_password_required':
        return 'Informe a senha atual.';
      case 'wrong_password':
        return 'Senha atual incorreta.';
      case 'password_too_short':
        return 'A nova senha precisa ter pelo menos 8 caracteres.';
      case 'same_password':
        return 'A nova senha deve ser diferente da atual.';
      case 'update_failed':
        return 'Não foi possível atualizar a senha. Tente novamente.';
      case 'account_lookup_failed':
        return 'Não foi possível verificar sua conta.';
      default:
        return fallback;
    }
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT GUARD — sessões reais + senha (via edge com auth admin)
  // ---------------------------------------------------------------------------

  Future<List<AccountSession>> authListSessions() async {
    await _uid();
    try {
      final res = await _db.rpc('auth_list_sessions', params: const {});
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => AccountSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível listar as sessões.');
    }
  }

  Future<void> authRevokeSession(String sessionId) async {
    await _uid();
    try {
      await _db.rpc('auth_revoke_session', params: {'p_session_id': sessionId});
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível encerrar a sessão.');
    }
  }

  Future<void> authRevokeOtherSessions() async {
    await _uid();
    final refresh = _db.auth.currentSession?.refreshToken ?? '';
    try {
      await _db.rpc('auth_revoke_other_sessions', params: {
        'p_refresh_token': refresh,
      });
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível encerrar as outras sessões.');
    }
  }

  Future<AccountInfo> myAccount() async {
    await _uid();
    try {
      final res = await _db.rpc('my_account', params: const {});
      return AccountInfo.fromJson(
        res is Map ? Map<String, dynamic>.from(res) : const {},
      );
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível consultar sua conta.');
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _uid();
    final refresh = _db.auth.currentSession?.refreshToken ?? '';
    try {
      final res = await _db.functions.invoke('account-guard', body: {
        'action': 'change_password',
        'current_password': currentPassword,
        'new_password': newPassword,
        'refresh_token': refresh,
      });
      final data = res.data;
      if (data is Map && data['ok'] != true) {
        final code = data['error']?.toString() ?? 'update_failed';
        throw SecurityException(_friendly(code, 'Falha ao trocar a senha.'),
            code: code);
      }
    } on FunctionException catch (e) {
      throw SecurityException(
        _functionError(e, 'Falha ao trocar a senha.'),
        code: _functionCode(e),
      );
    } on SecurityException {
      rethrow;
    }
  }

  String _functionCode(FunctionException e) {
    try {
      final data = Map<String, dynamic>.from(
          Map.from(jsonDecode(e.details) as Map));
      return data['error']?.toString() ?? 'update_failed';
    } catch (_) {
      return e.status.toString();
    }
  }

  String _functionError(FunctionException e, String fallback) {
    final code = _functionCode(e);
    return _friendly(code, fallback);
  }

  // ---------------------------------------------------------------------------
  // YOUTH SHIELD — idade provada, modo jovem e consentimento
  // ---------------------------------------------------------------------------

  Future<void> setBirthDate(DateTime? date) async {
    await _uid();
    try {
      final iso = date != null
          ? '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}'
          : null;
      await _db.rpc('set_birth_date', params: {'p_date': iso});
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível salvar sua data de nascimento.');
    }
  }

  Future<void> setYouthMode(bool on) async {
    await _uid();
    try {
      await _db.rpc('set_youth_mode', params: {'p_on': on});
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível atualizar o Modo Jovem.');
    }
  }

  Future<void> setAdultContentOk(bool on) async {
    await _uid();
    try {
      await _db.rpc('set_adult_content_ok', params: {'p_on': on});
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível salvar o consentimento.');
    }
  }

  Future<SafetyProfile> mySafetyProfile() async {
    await _uid();
    try {
      final res = await _db.rpc('my_safety_profile', params: const {});
      return SafetyProfile.fromJson(
        res is Map ? Map<String, dynamic>.from(res) : const {},
      );
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível consultar seu perfil de segurança.');
    }
  }

  Future<bool> liveViewAllowed(String liveId) async {
    await _uid();
    try {
      return await _db.rpc('live_view_allowed', params: {'p_live_id': liveId}) ==
          true;
    } on Exception catch (_) {
      return true;
    }
  }

  Future<void> setLiveAgeRestricted(String liveId, bool on) async {
    await _uid();
    try {
      await _db.rpc('set_live_age_restricted', params: {
        'p_live_id': liveId,
        'p_on': on,
      });
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível atualizar a faixa etária da live.');
    }
  }

  // ---------------------------------------------------------------------------
  // REPORT CENTER — denúncia com anti-abuso + histórico real
  // ---------------------------------------------------------------------------

  Future<void> fileReport({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    await _uid();
    try {
      await _db.rpc('file_report', params: {
        'p_target_type': targetType,
        'p_target_id': targetId,
        'p_reason': reason,
        'p_details': details,
      });
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível enviar a denúncia.');
    }
  }

  Future<List<ReportEntry>> myReports() async {
    await _uid();
    try {
      final res = await _db.rpc('my_reports', params: const {});
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => ReportEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível consultar suas denúncias.');
    }
  }

  // ---------------------------------------------------------------------------
  // SCAN SPAM — pré-visualização SEM escrever (comentário, chat ou tudo)
  // ---------------------------------------------------------------------------

  Future<SpamScanResult> scanSpam(String text, {String scope = 'comment'}) async {
    await _uid();
    try {
      final res =
          await _db.rpc('scan_spam', params: {'p_text': text, 'p_scope': scope});
      if (res is Map) {
        return SpamScanResult.fromJson(Map<String, dynamic>.from(res));
      }
      if (res is String) {
        final decoded = jsonDecode(res);
        if (decoded is Map) {
          return SpamScanResult.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
      return const SpamScanResult();
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível verificar o texto.');
    }
  }

  // ---------------------------------------------------------------------------
  // MODERAÇÃO SECURITY MAX (has_perm('moderation') no backend)
  // ---------------------------------------------------------------------------

  Future<List<SuspectProfile>> adminSuspectProfiles({int recencyDays = 3}) async {
    await _uid();
    try {
      final res = await _db.rpc('admin_suspect_profiles', params: {
        'p_recency_days': recencyDays,
      });
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => SuspectProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível consultar perfis suspeitos.');
    }
  }

  Future<List<ProfileFlagEntry>> adminListProfileFlags({String? status}) async {
    await _uid();
    try {
      final res = await _db.rpc('admin_list_profile_flags', params: {
        'p_status': status,
      });
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => ProfileFlagEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível consultar as sinalizações.');
    }
  }

  Future<void> adminFlagProfile(String userId, String reason) async {
    await _uid();
    try {
      await _db.rpc('admin_flag_profile', params: {
        'p_user_id': userId,
        'p_reason': reason,
      });
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível sinalizar o perfil.');
    }
  }

  Future<void> adminResolveProfileFlag({
    required String flagId,
    required String decision,
    String note = '',
  }) async {
    await _uid();
    try {
      await _db.rpc('admin_resolve_profile_flag', params: {
        'p_flag_id': flagId,
        'p_decision': decision,
        'p_note': note,
      });
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível resolver a sinalização.');
    }
  }

  Future<void> adminCommentHide(String commentId, {required bool hidden, String reason = ''}) async {
    await _uid();
    try {
      await _db.rpc('admin_comment_hide', params: {
        'p_comment_id': commentId,
        'p_hidden': hidden,
        'p_reason': reason,
      });
    } on Exception catch (e) {
      throw _exception(e, 'Não foi possível ocultar o comentário.');
    }
  }
}