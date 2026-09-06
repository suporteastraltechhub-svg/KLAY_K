/// Modelos da Loja do KLAY K: categorias, produtos, carrinho e pedidos.
library;

/// Formata um número como moeda BRL: `formatPrice(1234.5)` → `"R$ 1.234,50"`.
String formatPrice(num value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final dec = parts.length > 1 ? parts[1] : '00';
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return 'R\$ $buf,$dec';
}

/// Lista de status exibível para pedidos.
const Map<String, String> kStoreOrderStatusLabel = {
  'pendente': 'Pendente',
  'pago': 'Pago',
  'enviado': 'Enviado',
  'concluido': 'Concluído',
  'cancelado': 'Cancelado',
};

/// Categoria de produto.
class StoreCategory {
  final String id;
  final String name;
  final String icon;
  final String slug;
  final int sortOrder;

  const StoreCategory({
    required this.id,
    required this.name,
    this.icon = '📦',
    this.slug = '',
    this.sortOrder = 0,
  });

  factory StoreCategory.fromJson(Map<String, dynamic> json) => StoreCategory(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icon: json['icon'] as String? ?? '📦',
        slug: json['slug'] as String? ?? '',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// Produto anunciado por um vendedor.
class StoreProduct {
  final String id;
  final String sellerId;
  final String title;
  final String description;
  final double price;
  final String imageUrl;
  final String? categoryId;
  final int stock;
  final bool featured;
  final bool isActive;
  final DateTime createdAt;

  const StoreProduct({
    required this.id,
    required this.sellerId,
    required this.title,
    this.description = '',
    this.price = 0,
    this.imageUrl = '',
    this.categoryId,
    this.stock = 0,
    this.featured = false,
    this.isActive = true,
    required this.createdAt,
  });

  bool get outOfStock => stock <= 0;

  factory StoreProduct.fromJson(Map<String, dynamic> json) => StoreProduct(
        id: json['id'] as String? ?? '',
        sellerId: json['seller_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        imageUrl: json['image_url'] as String? ?? '',
        categoryId: json['category_id'] as String?,
        stock: (json['stock'] as num?)?.toInt() ?? 0,
        featured: json['featured'] == true,
        isActive: json['is_active'] != false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'seller_id': sellerId,
        'title': title,
        'description': description,
        'price': price,
        'image_url': imageUrl,
        if (categoryId != null) 'category_id': categoryId,
        'stock': stock,
        'featured': featured,
        'is_active': isActive,
      };
}

/// Item do carrinho com o produto embutido.
class CartItem {
  final String id;
  final String productId;
  final int quantity;
  final StoreProduct? product;

  const CartItem({
    required this.id,
    required this.productId,
    this.quantity = 1,
    this.product,
  });

  double get subtotal =>
      (product?.price ?? 0) * quantity;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productJson =
        json['product'] != null && json['product'] is Map
            ? Map<String, dynamic>.from(
                (json['product'] as Map).map((k, v) => MapEntry(k.toString(), v)))
            : null;
    return CartItem(
      id: json['id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      product: productJson == null ? null : StoreProduct.fromJson(productJson),
    );
  }
}

/// Pedido (agrupado por vendedor) com dados de comprador/vendedor.
class StoreOrder {
  final String id;
  final String userId;
  final String sellerId;
  final double total;
  final String status;
  final String shippingName;
  final String shippingPhone;
  final String shippingAddress;
  final DateTime createdAt;
  final String sellerUsername;
  final String sellerDisplayName;
  final String buyerUsername;
  final String buyerDisplayName;

  const StoreOrder({
    required this.id,
    required this.userId,
    required this.sellerId,
    this.total = 0,
    this.status = 'pendente',
    this.shippingName = '',
    this.shippingPhone = '',
    this.shippingAddress = '',
    required this.createdAt,
    this.sellerUsername = '',
    this.sellerDisplayName = '',
    this.buyerUsername = '',
    this.buyerDisplayName = '',
  });

  bool get cancellable => status == 'pendente';

  factory StoreOrder.fromJson(Map<String, dynamic> json) => StoreOrder(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        sellerId: json['seller_id'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'pendente',
        shippingName: json['shipping_name'] as String? ?? '',
        shippingPhone: json['shipping_phone'] as String? ?? '',
        shippingAddress: json['shipping_address'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        sellerUsername: json['seller_username'] as String? ?? '',
        sellerDisplayName: json['seller_display_name'] as String? ?? '',
        buyerUsername: json['buyer_username'] as String? ?? '',
        buyerDisplayName: json['buyer_display_name'] as String? ?? '',
      );
}

/// Item de um pedido (snapshot do produto no momento da compra).
class StoreOrderItem {
  final String id;
  final String orderId;
  final String? productId;
  final String title;
  final String imageUrl;
  final double unitPrice;
  final int quantity;

  const StoreOrderItem({
    required this.id,
    required this.orderId,
    this.productId,
    this.title = '',
    this.imageUrl = '',
    this.unitPrice = 0,
    this.quantity = 1,
  });

  factory StoreOrderItem.fromJson(Map<String, dynamic> json) =>
      StoreOrderItem(
        id: json['id'] as String? ?? '',
        orderId: json['order_id'] as String? ?? '',
        productId: json['product_id'] as String?,
        title: json['title'] as String? ?? '',
        imageUrl: json['image_url'] as String? ?? '',
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );
}