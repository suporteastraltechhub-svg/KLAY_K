import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/store_models.dart';
import 'supabase_service.dart';

/// Erro de domínio da Loja, com uma mensagem já pronta para a tela.
///
/// O servidor é quem valida preço, estoque, título e transições de status
/// (via `store_publish_product` e pelos triggers), então o app quase sempre
/// recebe um código de erro em vez de descobrir o problema sozinho.
class StoreException implements Exception {
  StoreException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

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

    // -------------------------------------------------------------------------
    // Marketplace
    // -------------------------------------------------------------------------

    /// Traduz os erros do servidor para algo compreensível.
    ///
    /// As exceções vêm do `store_publish_product`, que valida preço, estoque,
    /// título e categoria no backend — o cliente NÃO decide isso.
    StoreException _traduz(Object e) {
      final msg = e is PostgrestException ? e.message.trim() : '$e';
      if (msg.contains('auth_required')) {
        return StoreException('auth', 'Entre na sua conta para usar a Loja.');
      }
      if (msg.contains('bad_title')) {
        return StoreException(
          'title',
          'O nome do produto precisa ter entre 1 e 120 caracteres.',
        );
      }
      if (msg.contains('bad_price')) {
        return StoreException('price', 'Informe um preço válido em reais.');
      }
      if (msg.contains('bad_stock')) {
        return StoreException('stock', 'Informe uma quantidade válida.');
      }
      if (msg.contains('bad_condition')) {
        return StoreException('condition', 'Escolha se o produto é novo ou usado.');
      }
      if (msg.contains('bad_category')) {
        return StoreException('category', 'A categoria escolhida não existe mais.');
      }
      if (msg.contains('invalid_transition')) {
        return StoreException(
          'status',
          'Esse pedido não pode mudar para esse estado agora.',
        );
      }
      if (msg.contains('payment_status_readonly')) {
        return StoreException(
          'payment',
          'O pagamento só pode ser confirmado pelo sistema de pagamentos.',
        );
      }
      if (msg.contains('insufficient_stock')) {
        return StoreException(
          'stock',
          'Estoque insuficiente para um dos itens do pedido.',
        );
      }
      return StoreException('unknown', 'Não foi possível concluir. Tente de novo.');
    }

    /// Caminhos aceitos para upload de imagem do marketplace.
    static const int maxPhotoBytes = 5 * 1024 * 1024;
    static const int maxPhotos = 6;

    /// Sobe uma foto para o bucket `store-media` e devolve a URL pública.
    ///
    /// A pasta é `<user_id>/...`, e a policy do bucket só aceita escrita de quem
    /// for o dono da pasta.
    Future<String> uploadProductPhoto({
      required String userId,
      required String fileName,
      required List<int> bytes,
    }) async {
      if (!_ready) throw StoreException('offline', 'Backend não configurado.');
      if (bytes.isEmpty) {
        throw StoreException('photo', 'A imagem veio vazia.');
      }
      if (bytes.length > maxPhotoBytes) {
        throw StoreException(
          'photo',
          'A imagem passa de 5 MB. Escolha uma menor.',
        );
      }
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : 'jpg';
      final safe = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '$userId/$safe';

      await _client.storage.from('store-media').uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: 'image/$ext'),
      );
      return _client.storage.from('store-media').getPublicUrl(path);
    }

    /// Publica um anúncio pelo RPC, que valida tudo no servidor.
    Future<StoreProduct> publishProduct({
      required String title,
      required double price,
      required int stock,
      String description = '',
      String? categoryId,
      List<String> photos = const [],
      String condition = 'novo',
      List<String> deliveryOptions = const ['entrega'],
      String? city,
      String? state,
    }) async {
      if (!_ready) throw StoreException('offline', 'Backend não configurado.');
      try {
        final res = await _client.rpc(
          'store_publish_product',
          params: {
            'p_title': title,
            'p_price': price,
            'p_stock': stock,
            'p_description': description,
            'p_category_id': (categoryId?.isEmpty ?? true) ? null : categoryId,
            'p_photos': photos,
            'p_condition': condition,
            'p_delivery_options': deliveryOptions,
            'p_city': city,
            'p_state': state,
          },
        );
        final id = (res is Map ? res['id'] : null) as String?;
        if (id == null || id.isEmpty) {
          throw StoreException('unknown', 'O anúncio não foi criado.');
        }
        final row = await _client
            .from('store_products')
            .select('*')
            .eq('id', id)
            .single();
        return StoreProduct.fromJson(Map<String, dynamic>.from(row as Map));
      } catch (e) {
        if (e is StoreException) rethrow;
        throw _traduz(e);
      }
    }

    /// Edita um anúncio. Só o dono consegue (RLS por `seller_id`).
    Future<void> editProduct({
      required String id,
      required String title,
      required String description,
      required double price,
      required int stock,
      String? categoryId,
      List<String>? photos,
      String? condition,
      List<String>? deliveryOptions,
      String? city,
      String? state,
    }) async {
      if (!_ready) throw StoreException('offline', 'Backend não configurado.');
      if (title.trim().isEmpty) {
        throw StoreException('title', 'O produto precisa de um nome.');
      }
      if (price < 0) {
        throw StoreException('price', 'O preço não pode ser negativo.');
      }
      if (stock < 0) {
        throw StoreException('stock', 'A quantidade não pode ser negativa.');
      }
      try {
        await _client
            .from('store_products')
            .update({
              'title': title.trim(),
              'description': description.trim(),
              'price': price,
              'stock': stock,
              if (categoryId != null && categoryId.isNotEmpty)
                'category_id': categoryId,
              if (photos != null) 'photos': photos,
              if (photos != null && photos.isNotEmpty) 'image_url': photos.first,
              if (condition != null) 'condition': condition,
              if (deliveryOptions != null) 'delivery_options': deliveryOptions,
              if (city != null) 'city': city,
              if (state != null) 'state': state,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id);
      } catch (e) {
        throw _traduz(e);
      }
    }

    /// Pausa, retoma ou marca como vendido.
    ///
    /// `status` e `is_active` andam juntos porque as policies antigas e o
    /// `checkout_cart` já olhavam `is_active`.
    Future<void> setProductStatus(String id, String status) async {
      if (!_ready) throw StoreException('offline', 'Backend não configurado.');
      final ativo = status == 'publicado';
      try {
        await _client
            .from('store_products')
            .update({
              'status': status,
              'is_active': ativo,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id);
      } catch (e) {
        throw _traduz(e);
      }
    }

    /// Atualiza só o estoque — usado na "Minha loja".
    Future<void> updateStock(String id, int stock) async {
      if (stock < 0) {
        throw StoreException('stock', 'A quantidade não pode ser negativa.');
      }
      await _client
          .from('store_products')
          .update({
            'stock': stock,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    }

    /// Catálogo público: só produtos `publicado`, com filtros.
    Future<List<StoreProduct>> browseMarketplace({
      String? categoryId,
      String? search,
      String sort = 'recentes',
      int limit = 60,
    }) async {
      if (!_ready) throw StateError('Backend não configurado.');
      final base = _client
          .from('store_products')
          .select('*')
          .eq('status', 'publicado')
          .eq('is_active', true);

      final comCategoria = (categoryId != null && categoryId.isNotEmpty)
          ? base.eq('category_id', categoryId)
          : base;

      final t = search?.trim() ?? '';
      final comBusca = t.isEmpty
          ? comCategoria
          : comCategoria.or('title.ilike.%$t%,description.ilike.%$t%');

      final ordenado = switch (sort) {
        'populares' => comBusca.order('sold_count', ascending: false),
        'menor_preco' => comBusca.order('price', ascending: true),
        'maior_preco' => comBusca.order('price', ascending: false),
        _ => comBusca.order('created_at', ascending: false),
      };
      final res = await ordenado.limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => StoreProduct.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }

    /// Destaques: mais vendidos entre os publicados.
    Future<List<StoreProduct>> featuredProducts({int limit = 10}) async {
      if (!_ready) throw StateError('Backend não configurado.');
      final res = await _client
          .from('store_products')
          .select('*')
          .eq('status', 'publicado')
          .eq('is_active', true)
          .order('sold_count', ascending: false)
          .limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => StoreProduct.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }

    Future<StoreProduct> fetchProduct(String id) async {
      if (!_ready) throw StateError('Backend não configurado.');
      final res = await _client.from('store_products').select('*').eq('id', id).single();
      return StoreProduct.fromJson(Map<String, dynamic>.from(res as Map));
    }

    /// Alterna favorito. A RLS garante que é o próprio usuário.
    Future<bool> toggleFavorite(String productId) async {
      if (!_ready) throw StateError('Backend não configurado.');
      final res = await _client.rpc(
        'store_toggle_favorite',
        params: {'p_product_id': productId},
      );
      return (res is Map ? res['favorito'] : false) == true;
    }

    Future<bool> isFavorite(String productId) async {
      if (!_ready) return false;
      final me = _client.auth.currentUser?.id;
      if (me == null) return false;
      final res = await _client
          .from('store_favorites')
          .select('id')
          .eq('product_id', productId)
          .eq('user_id', me)
          .maybeSingle();
      return res != null;
    }

    /// Anúncios do próprio vendedor — inclui pausados e vendidos.
    Future<List<StoreProduct>> myProducts() async {
      if (!_ready) throw StateError('Backend não configurado.');
      final me = await _me();
      final res = await _client
          .from('store_products')
          .select('*')
          .eq('seller_id', me)
          .order('created_at', ascending: false);
      return (res as List)
          .whereType<Map>()
          .map((r) => StoreProduct.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }

    /// Pedidos em que o usuário é comprador.
    Future<List<StoreOrder>> myOrders({bool asSeller = false}) async {
      if (!_ready) throw StateError('Backend não configurado.');
      final me = await _me();
      final res = await _client
          .from('store_orders')
          .select('*, seller:profiles!store_orders_seller_id_fkey(username, display_name), '
              'buyer:profiles!store_orders_user_id_fkey(username, display_name)')
          .eq(asSeller ? 'seller_id' : 'user_id', me)
          .order('created_at', ascending: false);
      return _pedidos(res);
    }

    List<StoreOrder> _pedidos(dynamic res) => (res as List)
        .whereType<Map>()
        .map((r) => StoreOrder.fromJson(_achata(r)))
        .toList();

    /// Achata as junções de `profiles` que o PostgREST traz aninhadas.
    Map<String, dynamic> _achata(Map row) {
      final out = Map<String, dynamic>.from(row);
      Map<String, dynamic>? seller;
      Map<String, dynamic>? buyer;
      for (final key in ['seller', 'buyer']) {
        final v = out[key];
        if (v is List && v.isNotEmpty && v.first is Map) {
          final m = Map<String, dynamic>.from(v.first as Map);
          if (key == 'seller') {
            seller = m;
          } else {
            buyer = m;
          }
        } else if (v is Map) {
          if (key == 'seller') {
            seller = Map<String, dynamic>.from(v);
          } else {
            buyer = Map<String, dynamic>.from(v);
          }
        }
        out.remove(key);
      }
      if (seller != null) {
        out['seller_username'] = seller['username'];
        out['seller_display_name'] = seller['display_name'];
      }
      if (buyer != null) {
        out['buyer_username'] = buyer['username'];
        out['buyer_display_name'] = buyer['display_name'];
      }
      return out;
    }
  }
