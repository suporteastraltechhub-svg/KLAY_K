import 'package:supabase_flutter/supabase_flutter.dart';

import 'founder_service.dart';
import 'supabase_service.dart';

/// Camada de dados do sistema administrativo/comunitário do KLAY K.
///
/// Todo acesso administrativo é validado NO BACKEND (RPCs `security definer`
/// com `has_perm(...)`). O app nunca decide permissão por e-mail/flag — ele
/// apenas expõe tabs conforme `my_caps()` e o servidor revalida cada chamada.
class AdminService {
  AdminService._();

  static final AdminService instance = AdminService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<String> _uid() async {
    final u = await SupabaseService.instance.ensureAuthenticated();
    if (u.id.isEmpty) throw StateError('Não autenticado.');
    return u.id;
  }

  Future<dynamic> _rpc(String name, [Map<String, dynamic> params = const {}]) {
    return _db.rpc(name, params: params);
  }

  // ---------------------------------------------------------------------------
  // Role & capabilities (espelho do backend; nenhuma decisão local)
  // ---------------------------------------------------------------------------

  Future<String> myRole() async {
    try {
      final r = await _rpc('my_role');
      return r?.toString() ?? 'user';
    } catch (_) {
      return 'user';
    }
  }

  Future<List<String>> myCaps() async {
    try {
      final r = await _rpc('my_caps');
      if (r is List) {
        return r
            .whereType<dynamic>()
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> hasPerm(String cap) async {
    try {
      return await _rpc('has_perm', {'p_cap': cap}) == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isStaff() async {
    try {
      return await _rpc('is_klayk_staff') == true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Carteira multi-moeda
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> myWallet() async {
    final r = await _rpc('my_wallet');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> myTransactions({int limit = 30}) async {
    final uid = await _uid();
    final res = await _db
        .from('credit_transactions')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // Catálogo de moedas é estático → cache curto (evita refetch ao abrir a
  // carteira várias vezes / nas abas do painel).
  List<Map<String, dynamic>>? _currenciesCache;
  DateTime _currenciesCacheAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _currenciesTtl = Duration(minutes: 10);

  Future<List<Map<String, dynamic>>> currencies() async {
    final now = DateTime.now();
    if (_currenciesCache != null &&
        now.difference(_currenciesCacheAt) < _currenciesTtl) {
      return _currenciesCache!;
    }
    final res = await _db
        .from('currencies')
        .select()
        .order('sort_order')
        .limit(10);
    final list = (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _currenciesCache = list;
    _currenciesCacheAt = now;
    return list;
  }

  // ---------------------------------------------------------------------------
  // Baús (usuário)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> claimDailyChest() async {
    final r = await _rpc('claim_daily_chest');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<Map<String, dynamic>> openChest(String userChestId) async {
    final r = await _rpc('open_chest', {'p_user_chest_id': userChestId});
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> myChests() async {
    final uid = await _uid();
    final res = await _db
        .from('user_chests')
        .select()
        .eq('user_id', uid)
        .order('obtained_at', ascending: false);
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> myChestOpens({int limit = 20}) async {
    final uid = await _uid();
    final res = await _db
        .from('chest_opens')
        .select()
        .eq('user_id', uid)
        .order('opened_at', ascending: false)
        .limit(limit);
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> chestCatalog() async {
    final res = await _db
        .from('chests')
        .select()
        .eq('status', 'active')
        .order('sort_order');
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Missões / progresso (nível + XP + tarefas)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> myProgress() async {
    final r = await _rpc('my_progress');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Verificação (admin)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> adminListVerifications(
      [String? status]) async {
    final r = await _rpc('admin_list_verifications', {
      if (status != null) 'p_status': status,
    });
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<Map<String, dynamic>> adminReviewVerification(
    String requestId, {
    required bool approve,
    String note = '',
  }) async {
    final r = await _rpc('admin_review_verification', {
      'p_request_id': requestId,
      'p_approve': approve,
      'p_note': note,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Suporte / tickets (admin)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> adminListTickets([String? status]) async {
    final r = await _rpc('admin_list_tickets', {
      if (status != null) 'p_status': status,
    });
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<Map<String, dynamic>> adminReplyTicket(
    String ticketId, {
    required String status,
    String reply = '',
  }) async {
    final r = await _rpc('admin_reply_ticket', {
      'p_ticket_id': ticketId,
      'p_status': status,
      'p_reply': reply,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Economia (admin)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> adminEconomyStats() async {
    final r = await _rpc('admin_economy_stats');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<Map<String, dynamic>> adminGrantCurrency(
    String userId, {
    required String currency,
    required int amount,
    String note = '',
  }) async {
    final r = await _rpc('admin_grant_currency', {
      'p_user_id': userId,
      'p_currency': currency,
      'p_amount': amount,
      'p_note': note,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Baús (admin)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> adminChestStats() async {
    final r = await _rpc('admin_chest_stats');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Future<List<Map<String, dynamic>>> adminListChests() async {
    final r = await _rpc('admin_list_chests');
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<Map<String, dynamic>> adminGrantChest(
    String userId, {
    required String chestId,
    required String source,
  }) async {
    final r = await _rpc('admin_grant_chest', {
      'p_user_id': userId,
      'p_chest_id': chestId,
      'p_source': source,
    });
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  // ---------------------------------------------------------------------------
  // Equipe & roles (admin/founder)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> adminListStaff() async {
    final r = await _rpc('admin_list_staff');
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  Future<void> adminSetRole(
    String userId, {
    required String role,
    String reason = '',
  }) async {
    await _rpc('admin_set_role', {
      'p_user_id': userId,
      'p_role': role,
      'p_reason': reason,
    });
  }

  // ---------------------------------------------------------------------------
  // Profissões (admin)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listProfessions() async {
    final r = await _rpc('list_professions');
    return r is List
        ? r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  Future<bool> setMyProfession(String profession) async {
    return await _rpc('set_my_profession', {'p_profession': profession}) == true;
  }

  Future<List<Map<String, dynamic>>> adminListProfessions() async {
    final r = await _rpc('admin_list_professions');
    return r is List
        ? r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  Future<bool> adminUpsertProfession({
    String? id,
    required String name,
    String icon = '',
    String category = 'geral',
    String status = 'active',
    int sortOrder = 0,
  }) async {
    return await _rpc('admin_upsert_profession', {
      if (id != null) 'p_id': id,
      'p_name': name,
      'p_icon': icon,
      'p_category': category,
      'p_status': status,
      'p_sort_order': sortOrder,
    }) == true;
  }

  Future<bool> adminSetProfessionStatus(String id, String status) async {
    return await _rpc('admin_set_profession_status', {
      'p_id': id,
      'p_status': status,
    }) == true;
  }

  Future<bool> adminDeleteProfession(String id) async {
    return await _rpc('admin_delete_profession', {'p_id': id}) == true;
  }

  Future<bool> adminSetUserProfession(String userId, String profession) async {
    return await _rpc('admin_set_user_profession', {
      'p_user_id': userId,
      'p_profession': profession,
    }) == true;
  }

  Future<bool> adminClearUserProfession(String userId) =>
      adminSetUserProfession(userId, '');

  // ---------------------------------------------------------------------------
  // Bots (admin)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> adminListBots() async {
    final r = await _rpc('admin_list_bots');
    return r is List
        ? r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  Future<bool> adminUpsertBot({
    String? id,
    required String name,
    String avatar = '',
    String bio = '',
    String botRole = 'support',
    String status = 'inactive',
    Map<String, dynamic> permissions = const {},
  }) async {
    return await _rpc('admin_upsert_bot', {
      if (id != null) 'p_id': id,
      'p_name': name,
      'p_avatar': avatar,
      'p_bio': bio,
      'p_bot_role': botRole,
      'p_status': status,
      'p_permissions': permissions,
    }) == true;
  }

  Future<bool> adminSetBotStatus(String id, String status) async {
    return await _rpc('admin_set_bot_status', {
      'p_id': id,
      'p_status': status,
    }) == true;
  }

  Future<bool> adminDeleteBot(String id) async {
    return await _rpc('admin_delete_bot', {'p_id': id}) == true;
  }

  // ---------------------------------------------------------------------------
  // Auditoria (admin)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> adminAuditList({int limit = 100}) async {
    final r = await _rpc('admin_audit_list', {'p_limit': limit});
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
  }

  // ---------------------------------------------------------------------------
  // Bolha flutuante (user_settings — persistência por RLS owner)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> fetchBubbleSettings() async {
    final uid = await _uid();
    try {
      final res = await _db
          .from('user_settings')
          .select('bubble_enabled, bubble_x, bubble_y')
          .eq('user_id', uid)
          .maybeSingle();
      if (res == null) return const {'bubble_enabled': true, 'bubble_x': 0.0, 'bubble_y': 0.0};
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      return const {'bubble_enabled': true, 'bubble_x': 0.0, 'bubble_y': 0.0};
    }
  }

  Future<void> saveBubbleSettings({
    required bool enabled,
    required double x,
    required double y,
  }) async {
    final uid = await _uid();
    await _db.from('user_settings').upsert({
      'user_id': uid,
      'bubble_enabled': enabled,
      'bubble_x': x,
      'bubble_y': y,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// Mensagem amigável para uma exceção de autorização de backend.
  String friendlyError(Object? error) {
    final raw = error?.toString() ?? '';
    if (error is AdminAccessDeniedException) {
      return 'Acesso restrito ao Painel do Fundador.';
    }
    if (raw.contains('not_admin') ||
        raw.contains('not_founder') ||
        raw.contains('not_staff') ||
        raw.contains('not_support')) {
      return 'Permissão negada pelo servidor.';
    }
    if (raw.contains('already_opened')) return 'Este baú já foi aberto.';
    if (raw.contains('rate_limited')) return 'Muitas aberturas por hora/dia. Vá com calma!';
    if (raw.contains('already_reviewed')) return 'Este pedido já foi analisado.';
    if (raw.contains('insufficient_funds') ||
        raw.contains('bad_amount')) {
      return 'Saldo insuficiente ou valor inválido.';
    }
    if (raw.contains('PGRST116') || raw.contains('request_not_found')) {
      return 'Registro não encontrado.';
    }
    return 'Falha de rede ou ação não autorizada.';
  }
}