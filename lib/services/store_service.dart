import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/store_models.dart';
import 'supabase_service.dart';

/// Serviço da Loja do KLAY K: catálogo, carrinho, pedidos e produtos do
/// vendedor. Todo o acesso passa pelo Supabase com RLS — o cliente nunca
/// escreve em `store_orders`/`store_order_items` diretamente; checkout,
/// cancelamento e mudança de status são RPCs security definer que validam
/// comprador/vendedor no backend.
class StoreService {
  StoreService._();

  static final StoreService instance = StoreService._();

  SupabaseService get _db => SupabaseService.instance;
  SupabaseClient get _client => _db.client;

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  Future<String> _me() async {
    final u = await _db.ensureAuthenticated();
    return u.id;
  }

  // -------------------------------------------------------------------------
  // Catálogo
  // -------------------------------------------------------------------------

  Future<List<StoreCategory>> fetchCategories() async {
    if (!_ready) throw StateError('Backend não configurado.');
    final res = await _client
        .from('store_categories')
        .select('*')
        .eq('active', true)
        .order('sort_order');
    return (res as List)
        .whereType<Map>()
        .map((r) => StoreCategory.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Lista produtos ativos (ou do próprio vendedor mesmo inativos).
  Future<List<StoreProduct>> fetchProducts({
    String? categoryId,
    String? query,
    String? sellerId,
    bool includeMine = false,
  }) async {
    if (!_ready) throw StateError('Backend não configurado.');
    var builder = _client.from('store_products').select('*');
    if (categoryId != null && categoryId.isNotEmpty) {
      builder = builder.eq('category_id', categoryId);
    }
    if (query != null && query.trim().isNotEmpty) {
      builder = builder.ilike('title', '%${query.trim()}%');
    }
    if (sellerId != null && sellerId.isNotEmpty) {
      builder = builder.eq('seller_id', sellerId);
    }
    if (!includeMine) {
      builder = builder.eq('is_active', true);
    }
    final res = await builder.order('created_at', ascending: false).limit(60);
    return (res as List)
        .whereType<Map>()
        .map((r) => StoreProduct.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Produtos do meu anúncio (inclusive inativos).
  Future<List<StoreProduct>> fetchMyProducts() async {
    final me = await _me();
    return fetchProducts(sellerId: me, includeMine: true);
  }

  // -------------------------------------------------------------------------
  // Carrinho
  // -------------------------------------------------------------------------

  Future<List<CartItem>> fetchCart() async {
    if (!_ready) throw StateError('Backend não configurado.');
    final me = await _me();
    final res = await _client
        .from('store_cart_items')
        .select('*, product:product_id(*)')
        .eq('user_id', me)
        .order('created_at');
    return (res as List)
        .whereType<Map>()
        .map((r) => CartItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<int> cartCount() async {
    try {
      final me = await _me();
      final res = await _client
          .from('store_cart_items')
          .select('quantity')
          .eq('user_id', me);
      return (res as List).fold<int>(0, (sum, r) {
        final q = (r as Map)['quantity'] as num?;
        return sum + (q?.toInt() ?? 0);
      });
    } catch (_) {
      return 0;
    }
  }

  /// Adiciona (ou incrementa) um produto no carrinho.
  Future<void> addToCart(String productId, {int quantity = 1}) async {
    final me = await _me();
    final existing = await _client
        .from('store_cart_items')
        .select('id, quantity')
        .eq('user_id', me)
        .eq('product_id', productId)
        .maybeSingle();
    if (existing != null) {
      final current = (existing as Map)['quantity'] as num? ?? 0;
      await _client
          .from('store_cart_items')
          .update({'quantity': current.toInt() + quantity})
          .eq('id', existing['id']);
    } else {
      await _client.from('store_cart_items').insert({
        'user_id': me,
        'product_id': productId,
        'quantity': quantity,
      });
    }
  }

  Future<void> updateCartQuantity(String itemId, int quantity) async {
    if (quantity < 1) {
      await removeFromCart(itemId);
      return;
    }
    await _client
        .from('store_cart_items')
        .update({'quantity': quantity})
        .eq('id', itemId);
  }

  Future<void> removeFromCart(String itemId) async {
    await _client.from('store_cart_items').delete().eq('id', itemId);
  }

  Future<void> clearCart() async {
    final me = await _me();
    await _client.from('store_cart_items').delete().eq('user_id', me);
  }

  // -------------------------------------------------------------------------
  // Pedidos
  // -------------------------------------------------------------------------

  /// Gera os pedidos (um por vendedor) com os dados de entrega e limpa o
  /// carrinho. Retorna a quantidade de pedidos criados.
  Future<int> checkout({
    required String shippingName,
    required String shippingPhone,
    required String shippingAddress,
  }) async {
    final res = await _client.rpc(
      'checkout_cart',
      params: {
        'p_shipping_name': shippingName.trim(),
        'p_shipping_phone': shippingPhone.trim(),
        'p_shipping_address': shippingAddress.trim(),
      },
    );
    final map = res is Map
        ? Map<String, dynamic>.from(res)
        : <String, dynamic>{};
    return (map['count'] as num?)?.toInt() ?? 0;
  }

  /// Pedidos dos quais sou participante (compra ou venda), do mais recente.
  Future<List<StoreOrder>> fetchOrders() async {
    final me = await _me();
    final res = await _client
        .from('store_orders_view')
        .select('*')
        .or('user_id.eq.$me,seller_id.eq.$me')
        .order('created_at', ascending: false)
        .limit(100);
    return (res as List)
        .whereType<Map>()
        .map((r) => StoreOrder.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<StoreOrderItem>> fetchOrderItems(String orderId) async {
    final res = await _client
        .from('store_order_items')
        .select('*')
        .eq('order_id', orderId);
    return (res as List)
        .whereType<Map>()
        .map((r) => StoreOrderItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<bool> updateOrderStatus(String orderId, String status) async {
    final ok = await _client.rpc(
      'update_order_status',
      params: {'p_order_id': orderId, 'p_status': status},
    );
    return ok == true;
  }

  Future<bool> cancelOrder(String orderId) async {
    final ok = await _client.rpc(
      'cancel_order',
      params: {'p_order_id': orderId},
    );
    return ok == true;
  }

  // -------------------------------------------------------------------------
  // Vendedor: gestão de produtos
  // -------------------------------------------------------------------------

  Future<StoreProduct> createProduct({
    required String title,
    String description = '',
    required double price,
    String? categoryId,
    String imageUrl = '',
    int stock = 0,
  }) async {
    final me = await _me();
    final res = await _client
        .from('store_products')
        .insert({
          'seller_id': me,
          'title': title.trim(),
          'description': description.trim(),
          'price': price,
          if (categoryId != null && categoryId.isNotEmpty)
            'category_id': categoryId,
          'image_url': imageUrl,
          'stock': stock,
        })
        .select()
        .single();
    return StoreProduct.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> updateProduct({
    required String id,
    required String title,
    required String description,
    required double price,
    String? categoryId,
    required String imageUrl,
    required int stock,
    required bool isActive,
  }) async {
    await _client
        .from('store_products')
        .update({
          'title': title.trim(),
          'description': description.trim(),
          'price': price,
          if (categoryId != null && categoryId.isNotEmpty)
            'category_id': categoryId,
          'image_url': imageUrl,
          'stock': stock,
          'is_active': isActive,
        })
        .eq('id', id);
  }

  Future<void> toggleProductActive(String id, bool active) async {
    await _client
        .from('store_products')
        .update({'is_active': active})
        .eq('id', id);
  }

  Future<void> deleteProduct(String id) async {
    await _client.from('store_products').delete().eq('id', id);
  }
}
