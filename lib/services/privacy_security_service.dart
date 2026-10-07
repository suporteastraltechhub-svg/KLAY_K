import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Nível de permissão de interação aceito pelo backend.
class InteractionScope {
  final String id;
  final String label;

  const InteractionScope(this.id, this.label);

  static const everyone = InteractionScope('everyone', 'Todos');
  static const followers = InteractionScope('followers', 'Pessoas que sigo');
  static const friends = InteractionScope('friends', 'Amigos');
  static const none = InteractionScope('none', 'Ninguém');

  static const all = <InteractionScope>[everyone, followers, friends, none];

  static InteractionScope fromId(String? id) =>
      all.firstWhere((s) => s.id == id, orElse: () => everyone);
}

/// Bloco de privacidade persistido em `user_settings` (RPC save/my_privacy).
class PrivacySettings {
  final bool accountPrivate;
  final String allowMessages;
  final bool allowComments;
  final String allowMentions;
  final String allowTags;
  final String allowShares;
  final String allowFollows;
  final bool allowVideoDownloads;
  final bool showOnlineStatus;
  final bool viewHistoryEnabled;
  final bool sensitiveContentFilter;
  final List<String> blockedWords;

  const PrivacySettings({
    this.accountPrivate = false,
    this.allowMessages = 'everyone',
    this.allowComments = true,
    this.allowMentions = 'everyone',
    this.allowTags = 'everyone',
    this.allowShares = 'everyone',
    this.allowFollows = 'everyone',
    this.allowVideoDownloads = true,
    this.showOnlineStatus = true,
    this.viewHistoryEnabled = true,
    this.sensitiveContentFilter = false,
    this.blockedWords = const [],
  });

  factory PrivacySettings.fromJson(Map<String, dynamic> j) => PrivacySettings(
    accountPrivate: j['account_private'] == true,
    allowMessages: j['allow_messages'] as String? ?? 'everyone',
    allowComments: j['allow_comments'] == true,
    allowMentions: j['allow_mentions'] as String? ?? 'everyone',
    allowTags: j['allow_tags'] as String? ?? 'everyone',
    allowShares: j['allow_shares'] as String? ?? 'everyone',
    allowFollows: j['allow_follows'] as String? ?? 'everyone',
    allowVideoDownloads: j['allow_video_downloads'] == true,
    showOnlineStatus: j['show_online_status'] == true,
    viewHistoryEnabled: j['view_history_enabled'] == true,
    sensitiveContentFilter: j['sensitive_content_filter'] == true,
    blockedWords:
        (j['blocked_words'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );
}

/// Evento real de login/exclusão de sessão.
class LoginAlert {
  final String id;
  final String eventType;
  final String deviceLabel;
  final String userAgent;
  final String ip;
  final String aal;
  final DateTime createdAt;

  const LoginAlert({
    required this.id,
    this.eventType = 'login',
    this.deviceLabel = '',
    this.userAgent = '',
    this.ip = '',
    this.aal = '',
    required this.createdAt,
  });

  factory LoginAlert.fromJson(Map<String, dynamic> j) => LoginAlert(
    id: j['id']?.toString() ?? '',
    eventType: j['event_type'] as String? ?? 'login',
    deviceLabel: j['device_label'] as String? ?? '',
    userAgent: j['user_agent'] as String? ?? '',
    ip: j['ip']?.toString() ?? '',
    aal: j['aal'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

/// Vínculo familiar (ajuste de preferências, sem qualquer leitura de conteúdo).
class FamilyLink {
  final String id;
  final String direction;
  final String otherId;
  final String relationship;
  final String status;
  final bool canManageSafety;

  const FamilyLink({
    required this.id,
    this.direction = '',
    this.otherId = '',
    this.relationship = '',
    this.status = 'pending',
    this.canManageSafety = true,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isGuardian => direction == 'guardian';

  factory FamilyLink.fromJson(Map<String, dynamic> j) => FamilyLink(
    id: j['id']?.toString() ?? '',
    direction: j['direction'] as String? ?? '',
    otherId: j['other_id']?.toString() ?? '',
    relationship: j['relationship'] as String? ?? '',
    status: j['status'] as String? ?? 'pending',
    canManageSafety: j['can_manage_safety'] == true,
  );
}

/// Cliente das novas capacidades de segurança/privacidade.
///
/// Todas as operações passam por RPC `security definer` com RLS — o app
/// nunca escreve tabela direto e nunca inventa estado. Quando uma função não
/// existe no backend (migration ainda não aplicada), o erro sobe honesto em
/// vez de virar um "verde" falso.
class PrivacySecurityService {
  PrivacySecurityService._();

  static final PrivacySecurityService instance = PrivacySecurityService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  String? _lastCode;

  String? get lastCode => _lastCode;

  void _capture(Object error) {
    if (error is PostgrestException) {
      _lastCode = error.message.trim();
    } else {
      _lastCode = error.toString();
    }
  }

  // ---------------------------------------------------------------------------
  // Privacidade
  // ---------------------------------------------------------------------------

  Future<PrivacySettings> fetchPrivacySettings() async {
    try {
      final res = await _db.rpc('my_privacy_settings');
      if (res is Map) {
        return PrivacySettings.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      _capture(e);
      rethrow;
    }
    throw StateError(
      'Não foi possível carregar as configurações de privacidade.',
    );
  }

  Future<PrivacySettings> savePrivacySettings({
    bool? accountPrivate,
    String? allowMessages,
    bool? allowComments,
    String? allowMentions,
    String? allowTags,
    String? allowShares,
    String? allowFollows,
    bool? allowVideoDownloads,
    bool? showOnlineStatus,
    bool? viewHistoryEnabled,
    bool? sensitiveContentFilter,
    List<String>? blockedWords,
  }) async {
    try {
      final res = await _db.rpc(
        'save_privacy_settings',
        params: {
          if (accountPrivate != null) 'p_account_private': accountPrivate,
          if (allowMessages != null) 'p_allow_messages': allowMessages,
          if (allowComments != null) 'p_allow_comments': allowComments,
          if (allowMentions != null) 'p_allow_mentions': allowMentions,
          if (allowTags != null) 'p_allow_tags': allowTags,
          if (allowShares != null) 'p_allow_shares': allowShares,
          if (allowFollows != null) 'p_allow_follows': allowFollows,
          if (allowVideoDownloads != null)
            'p_allow_video_downloads': allowVideoDownloads,
          if (showOnlineStatus != null)
            'p_show_online_status': showOnlineStatus,
          if (viewHistoryEnabled != null)
            'p_view_history_enabled': viewHistoryEnabled,
          if (sensitiveContentFilter != null)
            'p_sensitive_content_filter': sensitiveContentFilter,
          if (blockedWords != null) 'p_blocked_words': blockedWords,
        },
      );
      if (res is Map) {
        return PrivacySettings.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      _capture(e);
      rethrow;
    }
    throw StateError(
      'Não foi possível salvar as configurações de privacidade.',
    );
  }

  /// Quem pode interagir com [ownerId] numa ação — decisão do BACKEND.
  Future<bool> canInteract(String ownerId, String kind) async {
    try {
      return await _db.rpc(
            'can_interact',
            params: {'p_owner': ownerId, 'p_kind': kind},
          ) ==
          true;
    } catch (e) {
      _capture(e);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 2FA (API nativa do Supabase Auth — não depende de migration)
  // ---------------------------------------------------------------------------

  bool get mfaAvailable => true;

  /// Sessão atual já passou por 2FA (AAL2)?
  Future<bool> mfaIsProtected() async {
    try {
      final aal = _db.auth.mfa.getAuthenticatorAssuranceLevel();
      return aal.currentLevel?.name == 'aal2';
    } catch (_) {
      return false;
    }
  }

  Future<List<({String id, String friendlyName, String status})>>
  listMfaFactors() async {
    final res = await _db.auth.mfa.listFactors();
    return res.all
        .map(
          (f) => (
            id: f.id,
            friendlyName: f.friendlyName ?? 'Autenticador',
            status: f.status.name,
          ),
        )
        .toList();
  }

  /// Ativa o 2FA (TOTP). Retorna o QR/segredo para o usuário confirmar.
  Future<({String factorId, String qrCode, String secret})> enrollMfa({
    required String friendlyName,
  }) async {
    final res = await _db.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'KLAY K',
      friendlyName: friendlyName,
    );
    final v = res.totp;
    if (v == null) {
      throw StateError('O Supabase não devolveu o segredo de 2FA.');
    }
    return (factorId: res.id, qrCode: v.qrCode, secret: v.secret);
  }

  Future<void> challengeMfa(String factorId) {
    return _db.auth.mfa.challenge(factorId: factorId);
  }

  Future<void> verifyMfa(String factorId, String code) {
    return _db.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  Future<void> unenrollMfa(String factorId) => _db.auth.mfa.unenroll(factorId);

  // ---------------------------------------------------------------------------
  // Alertas de login
  // ---------------------------------------------------------------------------

  Future<List<LoginAlert>> fetchLoginAlerts({int limit = 30}) async {
    try {
      final res = await _db.rpc('my_login_alerts', params: {'p_limit': limit});
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => LoginAlert.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      _capture(e);
      rethrow;
    }
  }

  Future<void> logLoginAlert(
    String eventType, {
    String deviceLabel = '',
  }) async {
    try {
      await _db.rpc(
        'log_login_alert',
        params: {'p_event_type': eventType, 'p_device_label': deviceLabel},
      );
    } catch (e) {
      _capture(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Filtro de conteúdo / palavras bloqueadas
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> scanUserContent(
    String text, {
    String scope = 'comment',
  }) async {
    final res = await _db.rpc(
      'scan_user_content',
      params: {'p_text': text, 'p_scope': scope},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  Future<List<String>> addBlockedWords(List<String> words) async {
    final res = await _db.rpc('add_blocked_words', params: {'p_words': words});
    if (res is List) return res.map((e) => e.toString()).toList();
    return const [];
  }

  Future<List<String>> removeBlockedWords(List<String> words) async {
    final res = await _db.rpc(
      'remove_blocked_words',
      params: {'p_words': words},
    );
    if (res is List) return res.map((e) => e.toString()).toList();
    return const [];
  }

  // ---------------------------------------------------------------------------
  // Controles familiares (preferências apenas — sem vigilância)
  // ---------------------------------------------------------------------------

  Future<List<FamilyLink>> fetchFamilyLinks() async {
    try {
      final res = await _db.rpc('my_family_links');
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => FamilyLink.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      _capture(e);
      rethrow;
    }
  }

  Future<String> requestFamilyLink(
    String memberId, {
    String relationship = 'responsavel',
  }) async {
    final res = await _db.rpc(
      'request_family_link',
      params: {'p_member_id': memberId, 'p_relationship': relationship},
    );
    if (res is String && res.isNotEmpty) return res;
    throw StateError('Não foi possível criar o vínculo familiar.');
  }

  Future<void> respondFamilyLink(String linkId, bool accept) async {
    await _db.rpc(
      'respond_family_link',
      params: {'p_link_id': linkId, 'p_accept': accept},
    );
  }

  Future<void> revokeFamilyLink(String linkId) async {
    await _db.rpc('revoke_family_link', params: {'p_link_id': linkId});
  }

  /// Snapshot de SEGURANÇA do membro (nunca conteúdo privado).
  Future<Map<String, dynamic>> familySafetySnapshot(String linkId) async {
    final res = await _db.rpc(
      'family_safety_snapshot',
      params: {'p_link_id': linkId},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  Future<void> familySetSafetySettings(
    String linkId, {
    String? allowMessages,
    bool? allowComments,
    String? allowMentions,
    bool? sensitiveContentFilter,
    bool? securityConfirmActions,
  }) async {
    await _db.rpc(
      'family_set_safety_settings',
      params: {
        'p_link_id': linkId,
        if (allowMessages != null) 'p_allow_messages': allowMessages,
        if (allowComments != null) 'p_allow_comments': allowComments,
        if (allowMentions != null) 'p_allow_mentions': allowMentions,
        if (sensitiveContentFilter != null)
          'p_sensitive_content_filter': sensitiveContentFilter,
        if (securityConfirmActions != null)
          'p_security_confirm_actions': securityConfirmActions,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Exclusão da conta
  // ---------------------------------------------------------------------------

  /// Exclui a conta. Exige e-mail exato + senha atual (dupla confirmação).
  Future<void> deleteAccount({
    required String currentPassword,
    required String confirmEmail,
    String reason = '',
  }) async {
    await _db.functions.invoke(
      'delete-account',
      body: {
        'action': 'delete_account',
        'current_password': currentPassword,
        'confirm_text': confirmEmail,
        'reason': reason,
      },
    );
  }
}
