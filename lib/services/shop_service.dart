import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shop_models.dart';
import 'supabase_service.dart';

/// Serviço da Loja virtual do KLAY K.
///
/// Regras:
///   * Catálogo (`shop_items`) é leitura pública (RLS) — jamais carrega tudo.
///   * Inventário/equipados são do próprio usuário (RLS owner).
///   * COMPRA via RPC `shop_buy_item` (security definer): preço/quantidade
///     validadas no backend, débito atômico por moeda e idempotência por
///     `request_id` — o cliente nunca escolhe valor debitado.
///   * Equipar/desequipar via RPC `shop_equip_item`/`shop_unequip_slot`
///     (valida posse e slot no backend).
///   * Sem backend acessível: os métodos LANÇAM e a UI mostra estado honesto.
class ShopService {
  ShopService._();

  static final ShopService instance = ShopService._();

  SupabaseService get _db => SupabaseService.instance;

  SupabaseClient get _client => _db.client;

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------
  Future<List<ShopItem>> fetchCatalog({
    ShopItemKind? kind,
    int limit = 120,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    var q = _client.from('shop_items').select('*').eq('is_active', true);
    if (kind != null) {
      q = q.eq('kind', _kindKey(kind));
    }
    final res = await q
        .order('is_featured', ascending: false)
        .order('sort_order')
        .limit(limit);
    return _parseShopRows(res);
  }

  String _kindKey(ShopItemKind k) {
    switch (k) {
      case ShopItemKind.frame:
        return 'frame';
      case ShopItemKind.entryEffect:
        return 'entry_effect';
      case ShopItemKind.badge:
        return 'badge';
      case ShopItemKind.boost:
        return 'boost';
      case ShopItemKind.community:
        return 'community';
    }
  }

  List<ShopItem> _parseShopRows(dynamic res) {
    if (res is! List) return [];
    return res.whereType<Map<dynamic, dynamic>>().map((row) {
      return ShopItem.fromJson(row.map((k, v) => MapEntry(k.toString(), v)));
    }).toList();
  }

  // ---------------------------------------------------------------------
  // Inventário + equipados
  // ---------------------------------------------------------------------
  Future<List<ShopItem>> fetchMyItems() async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client
        .from('user_items')
        .select('item_id,quantity,shop_items(*)')
        .gt('quantity', 0);
    final out = <ShopItem>[];
    for (final row in (res as List).whereType<Map<dynamic, dynamic>>()) {
      final nested = row['shop_items'];
      if (nested is Map) {
        out.add(
          ShopItem.fromJson(nested.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
    }
    return out;
  }

  /// Slot → id do item equipado atualmente (máx. 1 por slot).
  Future<Map<String, String>> fetchEquipped() async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client.from('user_equipped').select('slot,item_id');
    final out = <String, String>{};
    for (final row in (res as List).whereType<Map<dynamic, dynamic>>()) {
      final slot = row['slot'] as String?;
      final itemId = row['item_id'] as String?;
      if (slot != null && itemId != null) out[slot] = itemId;
    }
    return out;
  }

  Future<Map<String, dynamic>> fetchWallet() async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    final res = await _client.rpc('my_wallet');
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  // ---------------------------------------------------------------------
  // Compra (backend autoritativo)
  // ---------------------------------------------------------------------
  Future<ShopPurchaseResult> buyItem(
    ShopItem item, {
    required String requestId,
    int quantity = 1,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    try {
      final res = await _client.rpc(
        'shop_buy_item',
        params: {
          'p_item_id': item.id,
          'p_request_id': requestId,
          'p_quantity': quantity,
        },
      );
      return ShopPurchaseResult(
        balance: ((res is Map ? res['balance'] : null) as num?)?.toInt() ?? 0,
        currency: item.priceCurrency,
        duplicate: res is Map && res['duplicate'] == true,
      );
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg.contains('duplicate_in_progress')) {
        throw ShopDuplicateInProgressException(msg);
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Equipar / desequipar cosméticos
  // ---------------------------------------------------------------------
  Future<void> equip(ShopItem item) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final slot = item.slot;
    if (slot == null) throw StateError('Item não equipável.');
    await _db.ensureAuthenticated();
    await _client.rpc(
      'shop_equip_item',
      params: {'p_item_id': item.id, 'p_slot': slot},
    );
  }

  Future<void> unequip(String slot) async {
    if (!_ready) throw StateError('Backend não configurado.');
    await _db.ensureAuthenticated();
    await _client.rpc('shop_unequip_slot', params: {'p_slot': slot});
  }
}
