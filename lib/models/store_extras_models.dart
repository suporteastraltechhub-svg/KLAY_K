/// Modelos de favoritos, endereços, métodos de pagamento e privacidade de
/// compras da Loja do KLAY K.
///
/// Mapeiam as tabelas criadas em
/// `supabase/migrations/20260929120000_store_favorites_addresses_payments.sql`.
///
/// Observação de segurança: [StorePaymentMethod] **não** guarda número de
/// cartão, CVV nem segredo. Só o rótulo, a bandeira e os 4 últimos dígitos —
/// o que a indústria permite exibir. O cartão é tokenizado pelo gateway de
/// pagamento e o token opaco nunca é usado pelo app para autorizar nada.
library;

/// Tipo do método de pagamento.
enum StorePaymentKind {
  card,
  pix,
  wallet,
  other;

  static StorePaymentKind fromRaw(String? raw) {
    switch ((raw ?? 'other').toLowerCase()) {
      case 'card':
        return StorePaymentKind.card;
      case 'pix':
        return StorePaymentKind.pix;
      case 'wallet':
        return StorePaymentKind.wallet;
      default:
        return StorePaymentKind.other;
    }
  }

  String get raw => name;
}

/// Produto favoritado, com o que a tela precisa mostrar.
class StoreFavorite {
  final String favoriteId;
  final String productId;
  final String title;
  final String description;
  final double price;
  final String imageUrl;
  final int stock;

  /// Produto desativado continua na lista, mas sinalizado — o usuário decide
  /// se quer remover o favorito.
  final bool isActive;
  final String categoryName;
  final String sellerId;
  final DateTime createdAt;

  const StoreFavorite({
    required this.favoriteId,
    required this.productId,
    this.title = '',
    this.description = '',
    this.price = 0,
    this.imageUrl = '',
    this.stock = 0,
    this.isActive = true,
    this.categoryName = '',
    this.sellerId = '',
    required this.createdAt,
  });

  factory StoreFavorite.fromRow(Map<String, dynamic> json) {
    return StoreFavorite(
      favoriteId: json['favorite_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      imageUrl: json['image_url']?.toString() ?? '',
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      categoryName: json['category_name']?.toString() ?? '',
      sellerId: json['seller_id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Últimas 4 casas do preço, no padrão já usado na loja.
  String get priceLabel => price.toStringAsFixed(2);

  bool get unavailable => !isActive || stock <= 0;
}

/// Endereço de entrega salvo.
class StoreAddress {
  final String id;
  final String label;
  final String recipient;
  final String phone;
  final String street;
  final String number;
  final String complement;
  final String district;
  final String city;
  final String state;
  final String zipCode;
  final String country;
  final bool isDefault;

  const StoreAddress({
    required this.id,
    this.label = '',
    this.recipient = '',
    this.phone = '',
    this.street = '',
    this.number = '',
    this.complement = '',
    this.district = '',
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.country = 'BR',
    this.isDefault = false,
  });

  bool get isEmpty =>
      street.trim().isEmpty ||
      number.trim().isEmpty ||
      city.trim().isEmpty;

  /// Uma linha para a lista e para o resumo do pedido.
  String get oneLine {
    final parts = <String>[
      if (street.trim().isNotEmpty) street.trim(),
      if (number.trim().isNotEmpty) number.trim(),
      if (complement.trim().isNotEmpty) complement.trim(),
    ];
    final line = parts.join(', ');
    final tail = [
      if (district.trim().isNotEmpty) district.trim(),
      if (city.trim().isNotEmpty) city.trim(),
      if (state.trim().isNotEmpty) state.trim(),
    ].join(' · ');
    return tail.isEmpty ? line : (line.isEmpty ? tail : '$line — $tail');
  }

  factory StoreAddress.fromRow(Map<String, dynamic> json) {
    return StoreAddress(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      recipient: json['recipient']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      complement: json['complement']?.toString() ?? '',
      district: json['district']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      zipCode: json['zip_code']?.toString() ?? '',
      country: json['country']?.toString() ?? 'BR',
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toRow() => {
    'label': label.trim(),
    'recipient': recipient.trim(),
    'phone': phone.trim(),
    'street': street.trim(),
    'number': number.trim(),
    'complement': complement.trim(),
    'district': district.trim(),
    'city': city.trim(),
    'state': state.trim(),
    'zip_code': zipCode.trim(),
    'country': country.trim().isEmpty ? 'BR' : country.trim(),
  };

  StoreAddress copyWith({
    String? label,
    String? recipient,
    String? phone,
    String? street,
    String? number,
    String? complement,
    String? district,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    bool? isDefault,
  }) => StoreAddress(
    id: id,
    label: label ?? this.label,
    recipient: recipient ?? this.recipient,
    phone: phone ?? this.phone,
    street: street ?? this.street,
    number: number ?? this.number,
    complement: complement ?? this.complement,
    district: district ?? this.district,
    city: city ?? this.city,
    state: state ?? this.state,
    zipCode: zipCode ?? this.zipCode,
    country: country ?? this.country,
    isDefault: isDefault ?? this.isDefault,
  );
}

/// Método de pagamento salvo.
///
/// **Não** contém número de cartão, CVV ou qualquer segredo — só o que pode
/// ser exibido com segurança.
class StorePaymentMethod {
  final String id;
  final StorePaymentKind kind;
  final String label;
  final String brand;
  final String last4;
  final String holder;
  final int? expiryMonth;
  final int? expiryYear;
  final bool isDefault;

  const StorePaymentMethod({
    required this.id,
    this.kind = StorePaymentKind.other,
    this.label = '',
    this.brand = '',
    this.last4 = '',
    this.holder = '',
    this.expiryMonth,
    this.expiryYear,
    this.isDefault = false,
  });

  bool get isCard => kind == StorePaymentKind.card;

  /// Rótulo pronto para a lista, sem expor nada além do necessário.
  String get displayLabel {
    if (label.trim().isNotEmpty) return label.trim();
    return switch (kind) {
      StorePaymentKind.card =>
        '${brand.trim().isEmpty ? 'Cartão' : brand.trim()} ••$last4',
      StorePaymentKind.pix => 'PIX',
      StorePaymentKind.wallet => 'Carteira KLAY K',
      StorePaymentKind.other => 'Outro',
    };
  }

  /// Cartão vencido não pode ser usado como padrão — a UI desabilita.
  bool get isExpired {
    if (!isCard) return false;
    final m = expiryMonth;
    final y = expiryYear;
    if (m == null || y == null) return false;
    final now = DateTime.now();
    return y < now.year || (y == now.year && m < now.month);
  }

  factory StorePaymentMethod.fromRow(Map<String, dynamic> json) {
    return StorePaymentMethod(
      id: json['id']?.toString() ?? '',
      kind: StorePaymentKind.fromRaw(json['kind']?.toString()),
      label: json['label']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      last4: json['last4']?.toString() ?? '',
      holder: json['holder']?.toString() ?? '',
      expiryMonth: (json['expiry_month'] as num?)?.toInt(),
      expiryYear: (json['expiry_year'] as num?)?.toInt(),
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  /// Só envia o que o usuário digitou. `gateway_token` fica de fora de
  /// propósito: quem popula é o gateway, não a tela.
  Map<String, dynamic> toRow() => {
    'kind': kind.raw,
    'label': label.trim(),
    'brand': brand.trim(),
    'last4': last4.trim().length == 4 ? last4.trim() : '',
    'holder': holder.trim(),
    'expiry_month': expiryMonth,
    'expiry_year': expiryYear,
  };

  StorePaymentMethod copyWith({
    StorePaymentKind? kind,
    String? label,
    String? brand,
    String? last4,
    String? holder,
    int? expiryMonth,
    int? expiryYear,
    bool? isDefault,
  }) => StorePaymentMethod(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    brand: brand ?? this.brand,
    last4: last4 ?? this.last4,
    holder: holder ?? this.holder,
    expiryMonth: expiryMonth ?? this.expiryMonth,
    expiryYear: expiryYear ?? this.expiryYear,
    isDefault: isDefault ?? this.isDefault,
  );
}

/// Privacidade das compras. Ambos começam **falsos**: nada aparece
/// publicamente até o usuário permitir.
class StorePrivacy {
  final bool showPurchasesOnProfile;
  final bool showOrdersPublicly;

  const StorePrivacy({
    this.showPurchasesOnProfile = false,
    this.showOrdersPublicly = false,
  });

  factory StorePrivacy.fromMap(Map<String, dynamic> json) => StorePrivacy(
    showPurchasesOnProfile:
        json['show_purchases_on_profile'] as bool? ?? false,
    showOrdersPublicly: json['show_orders_publicly'] as bool? ?? false,
  );

  StorePrivacy copyWith({
    bool? showPurchasesOnProfile,
    bool? showOrdersPublicly,
  }) => StorePrivacy(
    showPurchasesOnProfile:
        showPurchasesOnProfile ?? this.showPurchasesOnProfile,
    showOrdersPublicly: showOrdersPublicly ?? this.showOrdersPublicly,
  );
}