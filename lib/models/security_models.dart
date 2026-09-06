// Modelos do módulo KLAY K Security Max.
//
// Os campos espelham fielmente o que as RPCs security definer do backend
// retornam (sessões reais do GoTrue, perfil de segurança, denúncias, flags
// de perfil e resultados de varredura de spam). Nunca inventam permissão:
// o backend é a fonte canônica de cada verificação.

DateTime? _dt(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String _str(dynamic v, [String fallback = '']) =>
    v == null || v.toString().isEmpty ? fallback : v.toString();

/// Sessão real de auth (lida de `auth.sessions` exposta por `auth_list_sessions`).
class AccountSession {
  final String id;
  final String userAgent;
  final String ip;
  final String aal;
  final DateTime? createdAt;
  final DateTime? refreshedAt;

  const AccountSession({
    required this.id,
    this.userAgent = '',
    this.ip = '',
    this.aal = '',
    this.createdAt,
    this.refreshedAt,
  });

  factory AccountSession.fromJson(Map<String, dynamic> j) => AccountSession(
        id: _str(j['id']),
        userAgent: _str(j['user_agent']),
        ip: _str(j['ip']),
        aal: _str(j['aal'], 'aal1'),
        createdAt: _dt(j['created_at']),
        refreshedAt: _dt(j['refreshed_at']),
      );

  /// "Chrome em Android" simplificado: primeiro segmento + "em " + dispositivo.
  String get deviceLabel {
    final ua = userAgent.isNotEmpty ? userAgent : 'Navegador';
    if (ua.contains('okhttp')) return 'App KLAY K';
    if (ua.contains('Dart/')) {
      final m = RegExp(r'Dart/([0-9.]+)').firstMatch(ua);
      return 'App KLAY K${m != null ? ' · Dart ${m.group(1)}' : ''}';
    }
    final first = ua.split('/').first.trim();
    return first.isEmpty ? 'Dispositivo' : first;
  }

  bool get isMobile =>
      userAgent.toLowerCase().contains('mobile') ||
      userAgent.toLowerCase().contains('android') ||
      userAgent.toLowerCase().contains('iphone');
}

/// Dados honestos da própria conta (`my_account`), vindos do auth real.
class AccountInfo {
  final String email;
  final bool emailConfirmed;
  final DateTime? lastSignInAt;
  final DateTime? accountCreatedAt;
  final List<String> providers;

  const AccountInfo({
    this.email = '',
    this.emailConfirmed = false,
    this.lastSignInAt,
    this.accountCreatedAt,
    this.providers = const [],
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) {
    final raws = j['providers'];
    return AccountInfo(
      email: _str(j['email']),
      emailConfirmed: j['email_confirmed'] == true,
      lastSignInAt: _dt(j['last_sign_in_at']),
      accountCreatedAt: _dt(j['account_created_at']),
      providers: raws is List ? raws.whereType<String>().toList() : const [],
    );
  }
}

/// Perfil de segurança do usuário (`my_safety_profile`).
class SafetyProfile {
  final DateTime? birthDate;
  final int? age;
  final bool youthMode;
  final bool adultContentOk;

  const SafetyProfile({
    this.birthDate,
    this.age,
    this.youthMode = false,
    this.adultContentOk = false,
  });

  factory SafetyProfile.fromJson(Map<String, dynamic> j) => SafetyProfile(
        birthDate: _dt(j['birth_date']),
        age: (j['age'] as num?)?.toInt(),
        youthMode: j['youth_mode'] == true,
        adultContentOk: j['adult_content_ok'] == true,
      );

  bool get hasProvenAge => age != null;
  bool get isProvenMinor => hasProvenAge && (age ?? 99) < 18;
}

/// Denúncia do próprio usuário (`my_reports`).
class ReportEntry {
  final String id;
  final String targetType;
  final String targetId;
  final String reason;
  final String details;
  final String status;
  final String resolution;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const ReportEntry({
    required this.id,
    this.targetType = '',
    this.targetId = '',
    this.reason = '',
    this.details = '',
    this.status = 'pending',
    this.resolution = '',
    this.createdAt,
    this.reviewedAt,
  });

  factory ReportEntry.fromJson(Map<String, dynamic> j) => ReportEntry(
        id: _str(j['id']),
        targetType: _str(j['target_type']),
        targetId: _str(j['target_id']),
        reason: _str(j['reason']),
        details: _str(j['details']),
        status: _str(j['status'], 'pending'),
        resolution: _str(j['resolution']),
        createdAt: _dt(j['created_at']),
        reviewedAt: _dt(j['reviewed_at']),
      );

  String get targetLabel {
    switch (targetType) {
      case 'user':
        return 'Usuário';
      case 'post':
        return 'Post';
      case 'live':
        return 'Live';
      case 'comment':
        return 'Comentário';
      case 'chat':
        return 'Chat de live';
      default:
        return targetType;
    }
  }
}

/// Flag de perfil (Fake Profile) para a área de moderação (`admin_list_profile_flags`).
class ProfileFlagEntry {
  final String id;
  final String flaggedUserId;
  final String flaggerId;
  final String source;
  final String reason;
  final String decision;
  final String note;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const ProfileFlagEntry({
    required this.id,
    this.flaggedUserId = '',
    this.flaggerId = '',
    this.source = '',
    this.reason = '',
    this.decision = '',
    this.note = '',
    this.createdAt,
    this.resolvedAt,
  });

  factory ProfileFlagEntry.fromJson(Map<String, dynamic> j) => ProfileFlagEntry(
        id: _str(j['id']),
        flaggedUserId: _str(j['flagged_user_id']),
        flaggerId: _str(j['flagger_id']),
        source: _str(j['source']),
        reason: _str(j['reason']),
        decision: _str(j['decision']),
        note: _str(j['note']),
        createdAt: _dt(j['created_at']),
        resolvedAt: _dt(j['resolved_at']),
      );

  bool get isOpen => decision == '';
}

/// Perfil suspeito sugerido pela heurística (`admin_suspect_profiles`).
class SuspectProfile {
  final String id;
  final String username;
  final String displayName;
  final int accountAgeDays;
  final bool hasAvatar;
  final bool hasBio;
  final bool isDefaultUsername;
  final int openFlags;

  const SuspectProfile({
    required this.id,
    this.username = '',
    this.displayName = '',
    this.accountAgeDays = 0,
    this.hasAvatar = false,
    this.hasBio = false,
    this.isDefaultUsername = false,
    this.openFlags = 0,
  });

  factory SuspectProfile.fromJson(Map<String, dynamic> j) => SuspectProfile(
        id: _str(j['id']),
        username: _str(j['username']),
        displayName: _str(j['display_name']),
        accountAgeDays: (j['account_age_days'] as num?)?.toInt() ?? 0,
        hasAvatar: j['has_avatar'] == true,
        hasBio: j['has_bio'] == true,
        isDefaultUsername: j['is_default_username'] == true,
        openFlags: (j['open_flags'] as num?)?.toInt() ?? 0,
      );

  bool get suspicious =>
      !hasAvatar || !hasBio || isDefaultUsername || openFlags > 0;
}

/// Resultado da varredura de spam (`scan_spam`) — prevê sem escrever nada.
class SpamScanResult {
  final String scope;
  final String action;
  final List<String> matches;
  final bool blocked;
  final bool flagged;

  const SpamScanResult({
    this.scope = 'all',
    this.action = 'ok',
    this.matches = const [],
    this.blocked = false,
    this.flagged = false,
  });

  factory SpamScanResult.fromJson(Map<String, dynamic> j) {
    final raws = j['matches'];
    return SpamScanResult(
      scope: _str(j['scope'], 'all'),
      action: _str(j['action'], 'ok'),
      matches: raws is List ? raws.whereType<String>().toList() : const [],
      blocked: j['blocked'] == true,
      flagged: j['flagged'] == true,
    );
  }
}

/// Erro de negócio do módulo de segurança (codifica o erro do backend).
class SecurityException implements Exception {
  final String message;
  final String? code;
  const SecurityException(this.message, {this.code});
  @override
  String toString() => message;
}