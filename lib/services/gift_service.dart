import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gift_models.dart';
import 'supabase_service.dart';

/// Serviço do catálogo de presentes virtuais do KLAY K.
///
/// Regras:
///   * Leituras do catálogo usam o cliente (RLS permite leitura pública de
///     presentes ativos). Paginação + lazy loading: NUNCA carrega tudo.
///   * Favoritos/histórico/wallet são do próprio usuário (RLS).
///   * ENVIO é SEMPRE via Edge Function `send-gift` (service role), que valida
///     saldo e regras no backend — o cliente jamais altera créditos.
///   * Se o backend não estiver acessível, os métodos LANÇAM, e a UI exibe um
///     estado vazio/of-line honesto (sem dados falsos).
class GiftService {
  GiftService._();

  static final GiftService instance = GiftService._();

  SupabaseService get _db => SupabaseService.instance;

  SupabaseClient get _client => _db.client;

  final Map<String, List<GiftCategory>> _categoryCache = {};
  final Map<String, List<GiftRarity>> _rarityCache = {};
  DateTime _cacheTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _cacheTtl = Duration(minutes: 5);

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Categorias e raridades (pequenas, cacheáveis)
  // ---------------------------------------------------------------------
  Future<List<GiftCategory>> fetchCategories() async {
    if (!_ready) throw StateError('Backend não configurado.');
    if (_categoryCache.isNotEmpty &&
        DateTime.now().difference(_cacheTime) < _cacheTtl) {
      return _categoryCache.entries.first.value;
    }
    final res = await _client
        .from('gift_categories')
        .select('id,name,emoji,order,active')
        .eq('active', true)
        .order('order');
    final list = (res as List)
        .whereType<Map<dynamic, dynamic>>()
        .map((r) => GiftCategory.fromJson(
            r.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
    _categoryCache.clear();
    _categoryCache['default'] = list;
    _cacheTime = DateTime.now();
    return list;
  }

  Future<List<GiftRarity>> fetchRarities() async {
    if (!_ready) throw StateError('Backend não configurado.');
    if (_rarityCache.isNotEmpty &&
        DateTime.now().difference(_cacheTime) < _cacheTtl) {
      return _rarityCache.entries.first.value;
    }
    final res = await _client
        .from('gift_rarities')
        .select('id,name,emoji,order,color,active')
        .eq('active', true)
        .order('order');
    final list = (res as List)
        .whereType<Map<dynamic, dynamic>>()
        .map((r) => GiftRarity.fromJson(
            r.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
    _rarityCache.clear();
    _rarityCache['default'] = list;
    _cacheTime = DateTime.now();
    return list;
  }

  // ---------------------------------------------------------------------
  // Catálogo (paginação + lazy loading)
  // ---------------------------------------------------------------------
  static const String _giftSelect =
      '*, gift_categories(name, emoji), gift_rarities(name, emoji, color), gift_usage_stats(sent_count)';

  Future<List<Gift>> fetchGifts({
    String? categoryId,
    String? rarityId,
    String? query,
    int page = 0,
    int pageSize = 40,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    var q = _client.from('gifts').select(_giftSelect).eq('status', 'active');
    if (categoryId != null && categoryId.isNotEmpty) {
      q = q.eq('category_id', categoryId);
    }
    if (rarityId != null && rarityId.isNotEmpty) {
      q = q.eq('rarity_id', rarityId);
    }
    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }
    final res = await q
        .order('sort_order')
        .order('id')
        .range(page * pageSize, (page + 1) * pageSize - 1);
    return _parseGiftRows(res);
  }

  Future<int> fetchGiftCount({
    String? categoryId,
    String? rarityId,
  }) async {
    if (!_ready) return 0;
    var q = _client
        .from('gifts')
        .select('id')
        .eq('status', 'active');
    if (categoryId != null && categoryId.isNotEmpty) {
      q = q.eq('category_id', categoryId);
    }
    if (rarityId != null && rarityId.isNotEmpty) {
      q = q.eq('rarity_id', rarityId);
    }
    final res = await q.count(CountOption.exact);
    return res.count;
  }

  List<Gift> _parseGiftRows(dynamic res) {
    if (res is! List) return [];
    return res.whereType<Map<dynamic, dynamic>>().map((row) {
      final m = Map<String, dynamic>.from(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      return Gift.fromJson(m);
    }).toList();
  }

  Future<List<Gift>> fetchFeatured({int limit = 40}) =>
      _fetchBy('is_featured', true, limit: limit);

  Future<List<Gift>> fetchExclusives({int limit = 60}) =>
      _fetchBy('is_exclusive', true, limit: limit);

  Future<List<Gift>> fetchPopular({int limit = 50}) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final res = await _client
        .from('gifts')
        .select(_giftSelect)
        .eq('status', 'active')
        .order('gift_usage_stats(sent_count)', ascending: false)
        .limit(limit);
    return _parseGiftRows(res);
  }

  Future<List<Gift>> fetchTrending({int limit = 50}) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final res = await _client
        .from('gifts')
        .select(_giftSelect)
        .eq('status', 'active')
        .order('gift_usage_stats(last_sent_at)', ascending: false)
        .limit(limit);
    return _parseGiftRows(res);
  }

  Future<List<Gift>> fetchNewest({int limit = 50}) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final res = await _client
        .from('gifts')
        .select(_giftSelect)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(limit);
    return _parseGiftRows(res);
  }

  Future<List<Gift>> _fetchBy(
    String column,
    bool value, {
    int limit = 50,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final q = _client
        .from('gifts')
        .select(_giftSelect)
        .eq('status', 'active')
        .eq(column, value);
    final res = await q.order('sort_order').limit(limit);
    return _parseGiftRows(res);
  }

  Future<List<Gift>> fetchRecommended({
    String? categoryId,
    int limit = 40,
  }) async {
    // Recomendados: destaque + excluvos + populares (dados reais do backend).
    if (!_ready) throw StateError('Backend não configurado.');
    var q = _client
        .from('gifts')
        .select(_giftSelect)
        .eq('status', 'active')
        .or('is_featured.eq.true,is_exclusive.eq.true');
    if (categoryId != null && categoryId.isNotEmpty) {
      q = q.eq('category_id', categoryId);
    }
    final res = await q.order('sort_order').limit(limit);
    return _parseGiftRows(res);
  }

  // ---------------------------------------------------------------------
  // Favoritos
  // ---------------------------------------------------------------------
  Future<List<String>> fetchFavoriteIds() async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client
        .from('gift_favorites')
        .select('gift_id')
        .eq('user_id', _client.auth.currentUser!.id);
    return (res as List)
        .whereType<Map<dynamic, dynamic>>()
        .map((r) => (r['gift_id'] ?? '') as String)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Gift>> fetchFavoriteGifts() async {
    final ids = await fetchFavoriteIds();
    if (ids.isEmpty) return [];
    final res = await _client
        .from('gifts')
        .select(_giftSelect)
        .inFilter('id', ids);
    return _parseGiftRows(res);
  }

  Future<void> toggleFavorite(String giftId) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final uid = _client.auth.currentUser!.id;
    final existing = await _client
        .from('gift_favorites')
        .select('gift_id')
        .eq('user_id', uid)
        .eq('gift_id', giftId)
        .maybeSingle();
    if (existing == null) {
      await _client.from('gift_favorites').insert({
        'user_id': uid,
        'gift_id': giftId,
      });
    } else {
      await _client
          .from('gift_favorites')
          .delete()
          .eq('user_id', uid)
          .eq('gift_id', giftId);
    }
  }

  // ---------------------------------------------------------------------
  // Wallet / créditos
  // ---------------------------------------------------------------------
  Future<int> fetchWallet() async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client
        .from('user_wallets')
        .select('credits')
        .eq('user_id', _client.auth.currentUser!.id)
        .maybeSingle();
    if (res == null) return 0;
    return (res['credits'] as num?)?.toInt() ?? 0;
  }

  /// Saldos reais de todas as moedas do usuário (RPC `my_wallet` — leitura
  /// segura no backend). Usado pelo painel premium para mostrar cada abraço
  /// sem confiar no cliente. Cache curto evita refetch a cada troca de aba.
  Map<String, dynamic>? _walletCache;
  DateTime _walletCacheAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _walletCacheTtl = Duration(seconds: 20);

  Future<Map<String, dynamic>> fetchWalletCurrencies() async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    if (_walletCache != null &&
        DateTime.now().difference(_walletCacheAt) < _walletCacheTtl) {
      return _walletCache!;
    }
    final res = await _client.rpc('my_wallet');
    final map = res is Map
        ? Map<String, dynamic>.from(res)
        : const <String, dynamic>{};
    _walletCache = map;
    _walletCacheAt = DateTime.now();
    return map;
  }

  /// Invalida o cache de saldo (ex.: após um envio de presente bem-sucedido).
  void invalidateWalletCache() {
    _walletCache = null;
  }

  // ---------------------------------------------------------------------
  // Histórico financeiro de envios/recebimentos
  // ---------------------------------------------------------------------
  Future<List<GiftTransaction>> fetchHistory({
    GiftHistoryDirection direction = GiftHistoryDirection.sent,
    int limit = 50,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final me = _client.auth.currentUser!.id;
    final q = direction == GiftHistoryDirection.sent
        ? _client
            .from('gift_transactions')
            .select('*')
            .eq('user_id', me)
        : _client
            .from('gift_transactions')
            .select('*')
            .eq('receiver_id', me);
    final res = await q.order('created_at', ascending: false).limit(limit);
    return (res as List)
        .whereType<Map<dynamic, dynamic>>()
        .map((r) => GiftTransaction.fromJson(
            r.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Envio seguro (via Edge Function; o backend valida saldo e regras)
  // ---------------------------------------------------------------------

  /// Envia um presente de forma idempotente. O cliente gera um `requestId`
  /// (UUID) único por envio; se a rede falhar e o usuário tentar de novo com
  /// o MESMO id, o backend reaproveita a transação original (`duplicate:
  /// true`) e NÃO debita em dobro. Em envio simultâneo o backend responde
  /// `duplicate_in_progress` (409) — o chamador deve gerar um novo id e
  /// tentar novamente.
  Future<GiftSendResult> sendGift({
    required Gift gift,
    required int amount,
    String? liveId,
    String? receiverId,
    String? requestId,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    Map<String, dynamic> res = const {};
    try {
      res = await _db.invoke('send-gift', body: {
        'gift_id': gift.id,
        'amount': amount,
        if (liveId != null) 'live_id': liveId,
        if (receiverId != null) 'receiver_id': receiverId,
        if (requestId != null && requestId.length >= 8) 'request_id': requestId,
      });
    } on StateError catch (e) {
      if (e.message.contains('409') &&
          e.message.toLowerCase().contains('duplicate_in_progress')) {
        throw GiftDuplicateInProgressException(
          e.message,
          transactionId: _extractPendingTransactionId(res),
        );
      }
      rethrow;
    }
    if (res['ok'] != true) {
      throw StateError(res['error']?.toString() ?? 'Falha ao enviar presente.');
    }
    final duplicate = res['duplicate'] == true;
    return GiftSendResult(
      transactionId: res['transaction_id'] as String?,
      gift: gift,
      amount: (res['amount'] as num?)?.toInt() ?? amount,
      creditsSpent: (res['credits_spent'] as num?)?.toInt() ?? 0,
      balance: (res['balance'] as num?)?.toInt() ?? 0,
      duplicate: duplicate,
      unlimited: res['unlimited'] == true,
    );
  }

  String? _extractPendingTransactionId(Map<String, dynamic> res) =>
      res['transaction_id'] as String?;
}

enum GiftHistoryDirection { sent, received }
