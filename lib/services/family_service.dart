import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Estado do limite de tempo de um membro.
class FamilyTimeLimit {
  const FamilyTimeLimit({
    required this.limitado,
    this.dailyMinutes,
    this.usedMinutes = 0,
    this.remainingMinutes,
    this.windowStart,
    this.windowEnd,
    this.note,
  });

  final bool limitado;
  final int? dailyMinutes;
  final int usedMinutes;
  final int? remainingMinutes;
  final String? windowStart;
  final String? windowEnd;
  final String? note;

  bool get exceeded =>
      limitado && remainingMinutes != null && remainingMinutes! <= 0;

  double get ratio {
    if (!limitado || dailyMinutes == null || dailyMinutes == 0) return 0;
    return (usedMinutes / dailyMinutes!).clamp(0.0, 1.0);
  }

  factory FamilyTimeLimit.fromJson(Map<String, dynamic> j) => FamilyTimeLimit(
    limitado: j['limitado'] == true,
    dailyMinutes: (j['daily_minutes'] as num?)?.toInt(),
    usedMinutes: (j['used_minutes'] as num?)?.toInt() ?? 0,
    remainingMinutes: (j['remaining_minutes'] as num?)?.toInt(),
    windowStart: j['window_start'] as String?,
    windowEnd: j['window_end'] as String?,
    note: j['note'] as String?,
  );
}

/// Relatório de atividade de um membro, visto por um responsável.
class FamilyActivityReport {
  const FamilyActivityReport({
    required this.days,
    this.posts = 0,
    this.comments = 0,
    this.likesGiven = 0,
    this.liveViews = 0,
    this.postViews = 0,
    this.minutesUsedToday = 0,
    this.newFollowers = 0,
    this.pendingFollowRequests = 0,
  });

  final int days;
  final int posts;
  final int comments;
  final int likesGiven;
  final int liveViews;
  final int postViews;
  final int minutesUsedToday;
  final int newFollowers;
  final int pendingFollowRequests;

  /// Atividade somada — o número que resume o uso da conta.
  int get totalActivity =>
      posts +
      comments +
      likesGiven +
      liveViews +
      postViews;

  factory FamilyActivityReport.fromJson(Map<String, dynamic> j) =>
      FamilyActivityReport(
        days: (j['days'] as num?)?.toInt() ?? 7,
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        likesGiven: (j['likes_given'] as num?)?.toInt() ?? 0,
        liveViews: (j['live_views'] as num?)?.toInt() ?? 0,
        postViews: (j['post_views'] as num?)?.toInt() ?? 0,
        minutesUsedToday: (j['minutes_used_today'] as num?)?.toInt() ?? 0,
        newFollowers: (j['new_followers'] as num?)?.toInt() ?? 0,
        pendingFollowRequests:
            (j['pending_follow_requests'] as num?)?.toInt() ?? 0,
      );
}

/// Pedido de seguir alguém que exige aprovação.
class FollowRequest {
  const FollowRequest({
    required this.id,
    required this.followerId,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String followerId;
  final String status;
  final DateTime? createdAt;

  bool get pendente => status == 'pendente';

  factory FollowRequest.fromJson(Map<String, dynamic> j) => FollowRequest(
    id: j['id'] as String? ?? '',
    followerId: j['follower_id'] as String? ?? '',
    status: j['status'] as String? ?? 'pendente',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
  );
}

/// Resultado de `request_follow`: o app precisa saber se virou vínculo direto
/// ou se ficou esperando o dono do perfil.
class FollowOutcome {
  const FollowOutcome({required this.status, required this.requerAprovacao});

  final String status;
  final bool requerAprovacao;

  bool get seguindo => status == 'ja_segue' || status == 'seguindo';

  bool get pendente => status == 'pendente';

  factory FollowOutcome.fromJson(Map<String, dynamic> j) => FollowOutcome(
    status: j['status'] as String? ?? '',
    requerAprovacao: j['requer_aprovacao'] == true,
  );
}

/// Erro dos recursos familiares, com mensagem pronta para a tela.
class FamilyException implements Exception {
  FamilyException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Controles familiares: limite de tempo, relatório de atividade e aprovação
/// de seguidores.
///
/// Tudo passa por funções `security definer` que validam, no servidor, se quem
/// chama é o próprio membro ou um responsável ATIVO registrado em
/// `family_links`. O app não decide autorização nenhuma.
class FamilyService {
  FamilyService._();

  static final FamilyService instance = FamilyService._();

  SupabaseService get _db => SupabaseService.instance;
  SupabaseClient get _c => _db.client;

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  FamilyException _traduz(Object e) {
    final m = e is PostgrestException ? e.message.trim() : '$e';
    return switch (m) {
      'auth_required' => FamilyException(
        'auth',
        'Entre na sua conta para usar os controles familiares.',
      ),
      'forbidden' => FamilyException(
        'forbidden',
        'Você não é responsável ativo por esta conta.',
      ),
      'bad_minutes' => FamilyException(
        'minutes',
        'Informe minutos entre 0 e 1440.',
      ),
      _ => FamilyException(
        'unknown',
        'Não foi possível concluir. Tente de novo.',
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // 1) Limite de tempo
  // ---------------------------------------------------------------------------

  /// Status do limite de um membro. Sem `p_member`, consulta o próprio.
  Future<FamilyTimeLimit> timeLimitStatus({String? memberId}) async {
    if (!_ready) throw FamilyException('offline', 'Backend não configurado.');
    try {
      final r = await _c.rpc(
        'family_time_limit_status',
        params: {'p_member': memberId},
      );
      return FamilyTimeLimit.fromJson(
        Map<String, dynamic>.from((r ?? const {}) as Map),
      );
    } catch (e) {
      throw _traduz(e);
    }
  }

  /// Define (ou troca) o limite diário. Só um responsável ativo pode.
  Future<void> setTimeLimit({
    required String memberId,
    required int dailyMinutes,
    String? windowStart,
    String? windowEnd,
    bool active = true,
    String? note,
  }) async {
    if (!_ready) throw FamilyException('offline', 'Backend não configurado.');
    try {
      await _c.rpc('family_set_time_limit', params: {
        'p_member': memberId,
        'p_daily_minutes': dailyMinutes,
        'p_window_start': (windowStart?.isEmpty ?? true) ? null : windowStart,
        'p_window_end': (windowEnd?.isEmpty ?? true) ? null : windowEnd,
        'p_active': active,
        'p_note': (note?.isEmpty ?? true) ? null : note,
      });
    } catch (e) {
      throw _traduz(e);
    }
  }

  /// Heartbeat de uso. Só grava se existe um limite ativo — sem limite, o app
  /// não precisa gastar chamada.
  Future<void> usageTick() async {
    if (!_ready) return;
    try {
      await _c.rpc('family_usage_tick');
    } catch (_) {
      // Falha de heartbeat não pode travar o app.
    }
  }

  // ---------------------------------------------------------------------------
  // 2) Relatório de atividade
  // ---------------------------------------------------------------------------

  /// Relatório real de um membro. Recusa se o chamador não for responsável
  /// ativo — a checagem é no servidor.
  Future<FamilyActivityReport> activityReport({
    required String memberId,
    int days = 7,
  }) async {
    if (!_ready) throw FamilyException('offline', 'Backend não configurado.');
    try {
      final r = await _c.rpc(
        'family_activity_report',
        params: {'p_member': memberId, 'p_days': days},
      );
      return FamilyActivityReport.fromJson(
        Map<String, dynamic>.from((r ?? const {}) as Map),
      );
    } catch (e) {
      throw _traduz(e);
    }
  }

  // ---------------------------------------------------------------------------
  // 3) Aprovação de seguidores
  // ---------------------------------------------------------------------------

  /// Pede seguir alguém. Se o alvo exigir aprovação, vira pendência.
  Future<FollowOutcome> requestFollow(String followingId) async {
    if (!_ready) throw FamilyException('offline', 'Backend não configurado.');
    try {
      final r = await _c.rpc(
        'request_follow',
        params: {'p_following_id': followingId},
      );
      return FollowOutcome.fromJson(
        Map<String, dynamic>.from((r ?? const {}) as Map),
      );
    } catch (e) {
      throw _traduz(e);
    }
  }

  /// Pedidos recebidos pelo meu perfil.
  Future<List<FollowRequest>> myIncomingRequests() async {
    if (!_ready) return const [];
    final me = _c.auth.currentUser?.id;
    if (me == null) return const [];
    final res = await _c
        .from('follow_requests')
        .select('*')
        .eq('following_id', me)
        .eq('status', 'pendente')
        .order('created_at', ascending: false);
    return (res as List)
        .whereType<Map>()
        .map((r) => FollowRequest.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Aprova ou rejeita um pedido. Só o dono do perfil decide.
  Future<void> respondRequest(String requestId, bool accept) async {
    if (!_ready) throw FamilyException('offline', 'Backend não configurado.');
    try {
      await _c.rpc(
        'respond_follow_request',
        params: {'p_request_id': requestId, 'p_aceitar': accept},
      );
    } catch (e) {
      throw _traduz(e);
    }
  }

  /// Liga/desliga a exigência de aprovação no próprio perfil.
  Future<void> setRequireFollowApproval(bool value) async {
    if (!_ready) throw FamilyException('offline', 'Backend não configurado.');
    try {
      final me = _c.auth.currentUser?.id;
      if (me == null) {
        throw FamilyException('auth', 'Entre na sua conta.');
      }
      await _c
          .from('profiles')
          .update({'require_follow_approval': value})
          .eq('id', me);
    } catch (e) {
      throw _traduz(e);
    }
  }

  Future<bool> requireFollowApproval() async {
    if (!_ready) return false;
    final me = _c.auth.currentUser?.id;
    if (me == null) return false;
    final res = await _c
        .from('profiles')
        .select('require_follow_approval')
        .eq('id', me)
        .maybeSingle();
    return res?['require_follow_approval'] == true;
  }
}