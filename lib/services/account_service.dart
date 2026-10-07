import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_models.dart';
import 'experience_settings.dart';
import 'supabase_service.dart';

/// Sacar das Configurações/Conta.
class AccountSettings {
  final bool notifyCurtidas;
  final bool notifyComentarios;
  final bool notifyNovosSeguidores;
  final bool notifyMensagens;
  final bool notifyLive;
  final bool notifyOutras;
  final bool autoPlay;
  final bool wifiOnly;
  final String videoQuality;
  final bool saveData;
  final bool backgroundPlay;
  final bool accountPrivate;
  final bool allowComments;
  final String allowMessages;
  final bool securityConfirmActions;
  final bool onboardingDone;

  const AccountSettings({
    this.notifyCurtidas = true,
    this.notifyComentarios = true,
    this.notifyNovosSeguidores = true,
    this.notifyMensagens = true,
    this.notifyLive = true,
    this.notifyOutras = true,
    this.autoPlay = true,
    this.wifiOnly = false,
    this.videoQuality = 'auto',
    this.saveData = false,
    this.backgroundPlay = false,
    this.accountPrivate = false,
    this.allowComments = true,
    this.allowMessages = 'everyone',
    this.securityConfirmActions = true,
    this.onboardingDone = false,
  });

  AccountSettings copyWith({
    bool? notifyCurtidas,
    bool? notifyComentarios,
    bool? notifyNovosSeguidores,
    bool? notifyMensagens,
    bool? notifyLive,
    bool? notifyOutras,
    bool? autoPlay,
    bool? wifiOnly,
    String? videoQuality,
    bool? saveData,
    bool? backgroundPlay,
    bool? accountPrivate,
    bool? allowComments,
    String? allowMessages,
    bool? securityConfirmActions,
    bool? onboardingDone,
  }) {
    return AccountSettings(
      notifyCurtidas: notifyCurtidas ?? this.notifyCurtidas,
      notifyComentarios: notifyComentarios ?? this.notifyComentarios,
      notifyNovosSeguidores:
          notifyNovosSeguidores ?? this.notifyNovosSeguidores,
      notifyMensagens: notifyMensagens ?? this.notifyMensagens,
      notifyLive: notifyLive ?? this.notifyLive,
      notifyOutras: notifyOutras ?? this.notifyOutras,
      autoPlay: autoPlay ?? this.autoPlay,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      videoQuality: videoQuality ?? this.videoQuality,
      saveData: saveData ?? this.saveData,
      backgroundPlay: backgroundPlay ?? this.backgroundPlay,
      accountPrivate: accountPrivate ?? this.accountPrivate,
      allowComments: allowComments ?? this.allowComments,
      allowMessages: allowMessages ?? this.allowMessages,
      securityConfirmActions:
          securityConfirmActions ?? this.securityConfirmActions,
      onboardingDone: onboardingDone ?? this.onboardingDone,
    );
  }

  Map<String, dynamic> toRow() => {
    'notify_curtidas': notifyCurtidas,
    'notify_comentarios': notifyComentarios,
    'notify_novos_seguidores': notifyNovosSeguidores,
    'notify_mensagens': notifyMensagens,
    'notify_live': notifyLive,
    'notify_outras': notifyOutras,
    'auto_play': autoPlay,
    'wifi_only': wifiOnly,
    'video_quality': videoQuality,
    'save_data': saveData,
    'background_play': backgroundPlay,
    'account_private': accountPrivate,
    'allow_comments': allowComments,
    'allow_messages': allowMessages,
    'security_confirm_actions': securityConfirmActions,
    'onboarding_done': onboardingDone,
  };

  /// Espelho das preferências de reprodução → experiência real do app.
  KlaykExperience toExperience() => KlaykExperience(
    autoPlay: autoPlay,
    wifiOnly: wifiOnly,
    saveData: saveData,
    videoQuality: videoQuality,
  );
}

class VerificationRequest {
  final String id;
  final String userId;
  final String status; // pending | approved | rejected
  final String reason;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String adminNote;

  const VerificationRequest({
    required this.id,
    required this.userId,
    required this.status,
    this.reason = '',
    required this.submittedAt,
    this.reviewedAt,
    this.adminNote = '',
  });

  factory VerificationRequest.fromJson(Map<String, dynamic> json) =>
      VerificationRequest(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        reason: json['reason'] as String? ?? '',
        submittedAt:
            DateTime.tryParse(
              json['submitted_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.tryParse(json['reviewed_at'].toString())?.toLocal()
            : null,
        adminNote: json['admin_note'] as String? ?? '',
      );
}

class SupportTicket {
  final String id;
  final String userId;
  final String category;
  final String subject;
  final String message;
  final String status; // open | in_review | answered | closed
  final String adminReply;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupportTicket({
    required this.id,
    required this.userId,
    required this.category,
    required this.subject,
    required this.message,
    this.status = 'open',
    this.adminReply = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
    id: json['id'] as String? ?? '',
    userId: json['user_id'] as String? ?? '',
    category: json['category'] as String? ?? '',
    subject: json['subject'] as String? ?? '',
    message: json['message'] as String? ?? '',
    status: json['status'] as String? ?? 'open',
    adminReply: json['admin_reply'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updated_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

/// Camada de acesso real para Configurações, Central de Ajuda e Verificação.
/// Tudo persiste no Supabase respeitando RLS (o usuário só acessa os próprios
/// dados; aprovações de verificação e respostas de suporte ficam a cargo do
/// painel administrativo com service role — não existe atendimento humano
/// automático, a estrutura fica pronta).
class AccountService {
  AccountService._();

  static final AccountService instance = AccountService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // Perfil (nome, usuário, bio, avatar, privacidade)
  // ---------------------------------------------------------------------------

  /// Carrega o perfil completo do usuário atual (contas + bio + privacidade).
  Future<Map<String, dynamic>?> fetchMyProfile() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('profiles')
        .select(
          'id, username, display_name, avatar_url, bio, is_private, is_verified, is_admin',
        )
        .eq('id', user.id)
        .maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res as Map);
  }

  /// Atualiza apenas os campos informados do próprio perfil (RLS).
  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final patch = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (isPrivate != null) 'is_private': isPrivate,
    };
    if (patch.isEmpty) return;
    await _db.from('profiles').update(patch).eq('id', user.id);
  }

  /// Faz upload de uma nova foto de avatar no bucket público `avatars` e
  /// retorna a URL pública. Atualiza também o perfil.
  Future<String> uploadAvatar(File file, {String? mime}) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final ext = _ext(file.path);
    final path =
        '${user.id}/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage
        .from('avatars')
        .upload(
          path,
          file,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: mime ?? 'image/jpeg',
            upsert: false,
          ),
        );
    final url = _db.storage.from('avatars').getPublicUrl(path);
    await _db.from('profiles').update({'avatar_url': url}).eq('id', user.id);
    // Mantém a identidade em memória sincronizada.
    kAppIdentity.avatarUrl = url;
    return url;
  }

  // ---------------------------------------------------------------------------
  // Configurações persistentes
  // ---------------------------------------------------------------------------

  Future<AccountSettings> fetchSettings() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('user_settings')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    if (res == null) return const AccountSettings();
    final m = Map<String, dynamic>.from(res as Map);
    bool b(String k) => m[k] as bool? ?? true;
    return AccountSettings(
      notifyCurtidas: b('notify_curtidas'),
      notifyComentarios: b('notify_comentarios'),
      notifyNovosSeguidores: b('notify_novos_seguidores'),
      notifyMensagens: b('notify_mensagens'),
      notifyLive: b('notify_live'),
      notifyOutras: b('notify_outras'),
      autoPlay: b('auto_play'),
      wifiOnly: m['wifi_only'] as bool? ?? false,
      videoQuality: m['video_quality'] as String? ?? 'auto',
      saveData: m['save_data'] as bool? ?? false,
      backgroundPlay: m['background_play'] as bool? ?? false,
      accountPrivate: m['account_private'] as bool? ?? false,
      allowComments: m['allow_comments'] as bool? ?? true,
      allowMessages: m['allow_messages'] as String? ?? 'everyone',
      securityConfirmActions: m['security_confirm_actions'] as bool? ?? true,
      onboardingDone: m['onboarding_done'] as bool? ?? false,
    );
  }

  Future<void> saveSettings(AccountSettings s) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db.from('user_settings').upsert({
      'user_id': user.id,
      ...s.toRow(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
    // Sincroniza privacidade no perfil.
    await updateProfile(isPrivate: s.accountPrivate);
  }

  /// Marca o onboarding como concluído (persistido no backend).
  Future<void> markOnboardingDone() async {
    try {
      await _db.rpc('set_onboarding_done', params: {'p_done': true});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Bloqueados
  // ---------------------------------------------------------------------------

  Future<List<String>> fetchBlockedIds() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', user.id);
      return (res as List)
          .whereType<Map>()
          .map((r) => r['blocked_id']?.toString() ?? '')
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Retorna os bloqueados com nome/foto via `profiles`.
  Future<List<PostAuthor>> fetchBlocked() async {
    final ids = await fetchBlockedIds();
    final out = <PostAuthor>[];
    for (final id in ids) {
      final p = await SupabaseService.instance.profileFor(id);
      if (p != null) {
        out.add(
          PostAuthor(
            id: id,
            username: p['username'] as String?,
            displayName: p['display_name'] as String?,
            avatarUrl: p['avatar_url'] as String?,
          ),
        );
      }
    }
    return out;
  }

  Future<void> blockUser(String blockedId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db
          .from('blocked_users')
          .insert({'blocker_id': user.id, 'blocked_id': blockedId})
          .then((_) {});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> unblockUser(String blockedId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('blocked_users')
        .delete()
        .eq('blocker_id', user.id)
        .eq('blocked_id', blockedId);
  }

  // ---------------------------------------------------------------------------
  // Central de Ajuda / Suporte
  // ---------------------------------------------------------------------------

  Future<SupportTicket> submitTicket({
    required String category,
    required String subject,
    required String message,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('support_tickets')
        .insert({
          'user_id': user.id,
          'category': category,
          'subject': subject,
          'message': message,
        })
        .select()
        .single();
    return SupportTicket.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<List<SupportTicket>> fetchMyTickets() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('support_tickets')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (res as List)
        .whereType<Map>()
        .map(
          (r) => SupportTicket.fromJson(
            Map<String, dynamic>.from(
              r.map((k, v) => MapEntry(k.toString(), v)),
            ),
          ),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Verificação de perfil
  // ---------------------------------------------------------------------------

  Future<bool> isVerified() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('profiles')
          .select('is_verified')
          .eq('id', user.id)
          .maybeSingle();
      return res?['is_verified'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Retorna a solicitação de verificação do usuário, se houver.
  Future<VerificationRequest?> fetchVerificationRequest() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('verification_requests')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (res == null) return null;
      return VerificationRequest.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// Submete uma solicitação. Falha se já existir uma pendente (1 por usuário).
  /// Criticamente: NÃO concede o selo automaticamente — cria apenas o pedido
  /// `pending` para análise por administrador (service role).
  Future<VerificationRequest> submitVerificationRequest(String reason) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('verification_requests')
        .insert({'user_id': user.id, 'reason': reason, 'status': 'pending'})
        .select()
        .single();
    return VerificationRequest.fromJson(Map<String, dynamic>.from(res as Map));
  }

  // ---------------------------------------------------------------------------
  // Sessão
  // ---------------------------------------------------------------------------

  Future<void> signOut() => SupabaseService.instance.signOut();

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase().replaceAll('heic', 'jpg');
    return ext.isEmpty ? 'jpg' : ext;
  }
}
