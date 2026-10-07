// Modelos da Loja virtual do KLAY K (fonte: tabelas `shop_items`,
// `user_items` e `user_equipped` do backend). Nenhum dado é mockado.

/// Tipo do item virtual: equipáveis (frame/entry_effect/badge) e de posse
/// (boost/community).
enum ShopItemKind { frame, entryEffect, badge, boost, community }

ShopItemKind shopItemKindFrom(String? key) {
  switch (key) {
    case 'frame':
      return ShopItemKind.frame;
    case 'entry_effect':
      return ShopItemKind.entryEffect;
    case 'badge':
      return ShopItemKind.badge;
    case 'boost':
      return ShopItemKind.boost;
    default:
      return ShopItemKind.community;
  }
}

/// Moedas aceitas no pagamento de itens da loja (wallet real).
enum ShopCurrency {
  credits,
  diamonds,
  crystals;

  static ShopCurrency fromName(String? key) {
    switch (key) {
      case 'diamonds':
        return ShopCurrency.diamonds;
      case 'crystals':
        return ShopCurrency.crystals;
      default:
        return ShopCurrency.credits;
    }
  }

  /// Localização amigável do código da moeda na wallet.
  String get walletKey {
    switch (this) {
      case ShopCurrency.credits:
        return 'credits';
      case ShopCurrency.diamonds:
        return 'diamonds';
      case ShopCurrency.crystals:
        return 'crystals';
    }
  }

  String get emoji {
    switch (this) {
      case ShopCurrency.credits:
        return '🪙';
      case ShopCurrency.diamonds:
        return '💎';
      case ShopCurrency.crystals:
        return '🔮';
    }
  }
}

/// Um item do catálogo da loja (`shop_items`).
class ShopItem {
  final String id;
  final ShopItemKind kind;
  final String name;
  final String description;
  final String icon;
  final String rarity;
  final int priceUnits;
  final ShopCurrency priceCurrency;
  final bool isFeatured;
  final int sortOrder;

  const ShopItem({
    required this.id,
    required this.kind,
    required this.name,
    this.description = '',
    this.icon = '🛍️',
    this.rarity = 'comum',
    required this.priceUnits,
    required this.priceCurrency,
    this.isFeatured = false,
    this.sortOrder = 0,
  });

  factory ShopItem.fromJson(Map<String, dynamic> json) => ShopItem(
    id: json['id'] as String? ?? '',
    kind: shopItemKindFrom(json['kind'] as String?),
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    icon: json['icon'] as String? ?? '🛍️',
    rarity: json['rarity'] as String? ?? 'comum',
    priceUnits: (json['price_units'] as num?)?.toInt() ?? 0,
    priceCurrency: ShopCurrency.fromName(json['price_currency'] as String?),
    isFeatured: json['is_featured'] as bool? ?? false,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );

  /// Cosmético equipável? Só frame/entry_effect/badge usam slot.
  bool get equippable {
    switch (kind) {
      case ShopItemKind.frame:
      case ShopItemKind.entryEffect:
      case ShopItemKind.badge:
        return true;
      case ShopItemKind.boost:
      case ShopItemKind.community:
        return false;
    }
  }

  /// Nome do slot equivale ao `kind` para equipáveis.
  String? get slot {
    if (!equippable) return null;
    switch (kind) {
      case ShopItemKind.frame:
        return 'frame';
      case ShopItemKind.entryEffect:
        return 'entry_effect';
      case ShopItemKind.badge:
        return 'badge';
      case ShopItemKind.boost:
      case ShopItemKind.community:
        return null;
    }
  }
}

/// Um item possuído pelo usuário (`user_items`).
class UserItem {
  final String itemId;
  final int quantity;
  final String source;

  const UserItem({
    required this.itemId,
    required this.quantity,
    this.source = 'purchase',
  });

  factory UserItem.fromJson(Map<String, dynamic> json) => UserItem(
    itemId: json['item_id'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? 'purchase',
  );
}

/// Resultado da compra de um item da loja (decidido no backend).
class ShopPurchaseResult {
  final int balance;
  final ShopCurrency currency;
  final bool duplicate;

  const ShopPurchaseResult({
    required this.balance,
    required this.currency,
    this.duplicate = false,
  });
}

/// Envio simultâneo com o mesmo `request_id` (backend respondeu
/// `duplicate_in_progress`): o chamador deve gerar um novo id e tentar de novo.
class ShopDuplicateInProgressException implements Exception {
  final String message;
  const ShopDuplicateInProgressException(this.message);

  @override
  String toString() => message;
}
