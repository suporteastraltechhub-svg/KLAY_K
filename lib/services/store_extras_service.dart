import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/store_extras_models.dart';
import 'supabase_service.dart';

/// Favoritos, endereços, métodos de pagamento e privacidade de compras.
///
/// Tabelas de `20260929120000_store_favorites_addresses_payments.sql`, todas
/// com RLS por `user_id = auth.uid()`: o usuário só enxerga os próprios dados.
///
/// Nada aqui é escrita em `store_orders`: o checkout (`checkout_cart`) continua
/// exatamente como estava. Esta classe apenas guarda preferências e dados de
/// apoio.
class StoreExtrasService {
  StoreExtrasService._();

  static final StoreExtrasService instance = StoreExtrasService._();

  SupabaseService get _db => SupabaseService.instance;
  SupabaseClient get _client => _db.client;

  bool get isConfigured {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _strMap(Map<dynamic, dynamic> m) =>
      m.map((k, v) => MapEntry(k.toString(), v));

  /// A migration ainda não foi aplicada?
  static bool _isMissing(Object e) {
    if (e is PostgrestException) {
      if (e.code == 'PGRST202' || e.code == '42P01' || e.code == '42703') {
        return true;
      }
      final msg = '${e.message} ${e.details}';
      return msg.contains('does not exist') ||
          msg.contains('Could not find the function') ||
          msg.contains('schema cache');
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Favoritos
  // -------------------------------------------------------------------------

  /// Lista de favoritos com os dados do produto (RPC `my_store_favorites`).
  Future<List<StoreFavorite>> fetchFavorites() async {
    if (!isConfigured) return const [];
    try {
      final r = await _client.rpc('my_store_favorites');
      return r
          .whereType<Map>()
          .map((e) => StoreFavorite.fromRow(_strMap(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// IDs favoritados, para marcar o coração nos produtos sem chamar N vezes.
  Future<Set<String>> fetchFavoriteIds() async {
    if (!isConfigured) return <String>{};
    try {
      final r = await _client
          .from('store_favorites')
          .select('product_id')
          .limit(1000);
      return r
          .whereType<Map>()
          .map((e) => e['product_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<bool> isFavorite(String productId) async {
    if (!isConfigured) return false;
    try {
      final r = await _client
          .from('store_favorites')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Alterna o favorito e devolve o estado final. `true` = agora é favorito.
  Future<bool> toggleFavorite(String productId) async {
    if (!isConfigured || productId.isEmpty) return false;
    try {
      final existing = await _client
          .from('store_favorites')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      if (existing.isNotEmpty) {
        await _client
            .from('store_favorites')
            .delete()
            .eq('id', existing.first['id']);
        return false;
      }
      await _client.from('store_favorites').insert({
        'product_id': productId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> removeFavorite(String productId) async {
    if (!isConfigured) return;
    try {
      await _client.from('store_favorites').delete().eq('product_id', productId);
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Endereços
  // -------------------------------------------------------------------------

  Future<List<StoreAddress>> fetchAddresses() async {
    if (!isConfigured) return const [];
    try {
      final r = await _client
          .from('store_addresses')
          .select()
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return r
          .whereType<Map>()
          .map((e) => StoreAddress.fromRow(_strMap(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Endereço marcado como padrão (ou o primeiro, se nenhum estiver marcado).
  Future<StoreAddress?> fetchDefaultAddress() async {
    final all = await fetchAddresses();
    if (all.isEmpty) return null;
    for (final a in all) {
      if (a.isDefault) return a;
    }
    return all.first;
  }

  /// Salva um endereço novo. Devolve o id, ou null se falhar.
  Future<String?> saveAddress(StoreAddress address) async {
    if (!isConfigured) return null;
    // O trigger do servidor garante um único padrão; não enviamos `user_id`.
    final row = address.toRow();
    if (address.isDefault) row['is_default'] = true;
    try {
      final r = await _client.from('store_addresses').insert(row).select('id');
      if (r.isNotEmpty) return r.first['id']?.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateAddress(StoreAddress address) async {
    if (!isConfigured || address.id.isEmpty) return false;
    final row = address.toRow();
    if (address.isDefault) row['is_default'] = true;
    try {
      await _client
          .from('store_addresses')
          .update(row)
          .eq('id', address.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteAddress(String id) async {
    if (!isConfigured || id.isEmpty) return false;
    try {
      await _client.from('store_addresses').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDefaultAddress(String id) async {
    if (!isConfigured || id.isEmpty) return false;
    try {
      // O trigger desliga os outros; aqui só ligamos este.
      await _client
          .from('store_addresses')
          .update({'is_default': true})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Métodos de pagamento
  // -------------------------------------------------------------------------

  Future<List<StorePaymentMethod>> fetchPaymentMethods() async {
    if (!isConfigured) return const [];
    try {
      final r = await _client
          .from('store_payment_methods')
          .select()
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return r
          .whereType<Map>()
          .map((e) => StorePaymentMethod.fromRow(_strMap(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> savePaymentMethod(StorePaymentMethod method) async {
    if (!isConfigured) return null;
    final row = method.toRow();
    if (method.isDefault) row['is_default'] = true;
    try {
      final r = await _client
          .from('store_payment_methods')
          .insert(row)
          .select('id');
      if (r.isNotEmpty) return r.first['id']?.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updatePaymentMethod(StorePaymentMethod method) async {
    if (!isConfigured || method.id.isEmpty) return false;
    final row = method.toRow();
    if (method.isDefault) row['is_default'] = true;
    try {
      await _client
          .from('store_payment_methods')
          .update(row)
          .eq('id', method.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deletePaymentMethod(String id) async {
    if (!isConfigured || id.isEmpty) return false;
    try {
      await _client.from('store_payment_methods').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDefaultPaymentMethod(String id) async {
    if (!isConfigured || id.isEmpty) return false;
    try {
      await _client
          .from('store_payment_methods')
          .update({'is_default': true})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Privacidade de compras
  // -------------------------------------------------------------------------

  Future<StorePrivacy> fetchPrivacy() async {
    if (!isConfigured) return const StorePrivacy();
    try {
      final r = await _client.rpc('my_store_privacy');
      if (r is Map) return StorePrivacy.fromMap(_strMap(r));
    } catch (_) {}
    return const StorePrivacy();
  }

  Future<StorePrivacy> savePrivacy(StorePrivacy privacy) async {
    if (!isConfigured) return privacy;
    try {
      final r = await _client.rpc(
        'save_store_privacy',
        params: {
          'p_show_purchases_on_profile': privacy.showPurchasesOnProfile,
          'p_show_orders_publicly': privacy.showOrdersPublicly,
        },
      );
      if (r is Map) return StorePrivacy.fromMap(_strMap(r));
    } catch (e) {
      if (_isMissing(e)) return privacy;
    }
    return privacy;
  }
}