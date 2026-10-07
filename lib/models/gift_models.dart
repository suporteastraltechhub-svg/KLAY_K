// Modelos do catálogo de presentes virtuais do KLAY K (fonte: backend Supabase).
// Estes tipos refletem as linhas das tabelas `gifts`, `gift_categories`,
// `gift_rarities`, `gift_effects`, `gift_events`, `gift_favorites`,
// `gift_transactions` e `user_wallets`. Nenhum dado é mockado aqui.

class GiftCategory {
  final String id;
  final String name;
  final String emoji;
  final int order;
  final bool active;

  const GiftCategory({
    required this.id,
    required this.name,
    this.emoji = '',
    this.order = 0,
    this.active = true,
  });

  factory GiftCategory.fromJson(Map<String, dynamic> json) => GiftCategory(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    emoji: json['emoji'] as String? ?? '',
    order: (json['order'] as num?)?.toInt() ?? 0,
    active: json['active'] as bool? ?? true,
  );
}

class GiftRarity {
  final String id;
  final String name;
  final String emoji;
  final int order;
  final String color;
  final bool active;

  const GiftRarity({
    required this.id,
    required this.name,
    this.emoji = '',
    this.order = 0,
    this.color = '#FFFFFF',
    this.active = true,
  });

  factory GiftRarity.fromJson(Map<String, dynamic> json) => GiftRarity(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    emoji: json['emoji'] as String? ?? '',
    order: (json['order'] as num?)?.toInt() ?? 0,
    color: json['color'] as String? ?? '#FFFFFF',
    active: json['active'] as bool? ?? true,
  );
}

class GiftEffect {
  final String id;
  final String name;
  final String kind;
  final Map<String, dynamic> params;
  final int tier;
  final bool active;

  const GiftEffect({
    required this.id,
    required this.name,
    this.kind = 'preset',
    this.params = const {},
    this.tier = 1,
    this.active = true,
  });

  factory GiftEffect.fromJson(Map<String, dynamic> json) => GiftEffect(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? 'preset',
    params: json['params'] is Map
        ? Map<String, dynamic>.from(json['params'] as Map)
        : const {},
    tier: (json['tier'] as num?)?.toInt() ?? 1,
    active: json['active'] as bool? ?? true,
  );
}

class GiftEvent {
  final String id;
  final String name;
  final String description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool active;

  const GiftEvent({
    required this.id,
    required this.name,
    this.description = '',
    this.startsAt,
    this.endsAt,
    this.active = true,
  });

  factory GiftEvent.fromJson(Map<String, dynamic> json) => GiftEvent(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    startsAt: json['starts_at'] != null
        ? DateTime.tryParse(json['starts_at'] as String)?.toLocal()
        : null,
    endsAt: json['ends_at'] != null
        ? DateTime.tryParse(json['ends_at'] as String)?.toLocal()
        : null,
    active: json['active'] as bool? ?? true,
  );
}

class Gift {
  final String id;
  final String name;
  final String categoryId;
  final String rarityId;
  final int credits;
  final String icon;
  final String glyph;
  final String animationKey;
  final Map<String, dynamic> effects;
  final String description;
  final String status;
  final int sortOrder;
  final bool isFeatured;
  final bool isExclusive;
  final bool isTemporary;
  final bool isEventGift;
  final bool isLimited;
  final bool isTradable;
  final List<String> regions;
  final String? eventId;
  final DateTime? featuredStart;
  final DateTime? featuredEnd;

  final String? categoryName;
  final String? categoryEmoji;
  final String? rarityName;
  final String? rarityEmoji;
  final String? rarityColor;
  final int? sentCount;

  const Gift({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.rarityId,
    this.credits = 0,
    this.icon = '🎁',
    this.glyph = '',
    this.animationKey = 'sparkle',
    this.effects = const {},
    this.description = '',
    this.status = 'active',
    this.sortOrder = 0,
    this.isFeatured = false,
    this.isExclusive = false,
    this.isTemporary = false,
    this.isEventGift = false,
    this.isLimited = false,
    this.isTradable = true,
    this.regions = const [],
    this.eventId,
    this.featuredStart,
    this.featuredEnd,
    this.categoryName,
    this.categoryEmoji,
    this.rarityName,
    this.rarityEmoji,
    this.rarityColor,
    this.sentCount,
  });

  factory Gift.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? cat;
    Map<String, dynamic>? rar;
    Map<String, dynamic>? stats;
    if (json['gift_categories'] is Map) {
      cat = Map<String, dynamic>.from(json['gift_categories'] as Map);
    }
    if (json['gift_rarities'] is Map) {
      rar = Map<String, dynamic>.from(json['gift_rarities'] as Map);
    }
    if (json['gift_usage_stats'] is Map) {
      stats = Map<String, dynamic>.from(json['gift_usage_stats'] as Map);
    }
    return Gift(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      categoryId: json['category_id'] as String? ?? '',
      rarityId: json['rarity_id'] as String? ?? '',
      credits: (json['credits'] as num?)?.toInt() ?? 0,
      icon: json['icon'] as String? ?? '🎁',
      glyph: json['glyph'] as String? ?? '',
      animationKey: json['animation_key'] as String? ?? 'sparkle',
      effects: json['effects'] is Map
          ? Map<String, dynamic>.from(json['effects'] as Map)
          : const {},
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isFeatured: json['is_featured'] as bool? ?? false,
      isExclusive: json['is_exclusive'] as bool? ?? false,
      isTemporary: json['is_temporary'] as bool? ?? false,
      isEventGift: json['is_event_gift'] as bool? ?? false,
      isLimited: json['is_limited'] as bool? ?? false,
      isTradable: json['is_tradable'] as bool? ?? true,
      regions:
          (json['regions'] as List?)?.whereType<String>().toList() ?? const [],
      eventId: json['event_id'] as String?,
      featuredStart: json['featured_start'] != null
          ? DateTime.tryParse(json['featured_start'] as String)?.toLocal()
          : null,
      featuredEnd: json['featured_end'] != null
          ? DateTime.tryParse(json['featured_end'] as String)?.toLocal()
          : null,
      categoryName: cat?['name'] as String?,
      categoryEmoji: cat?['emoji'] as String?,
      rarityName: rar?['name'] as String?,
      rarityEmoji: rar?['emoji'] as String?,
      rarityColor: rar?['color'] as String?,
      sentCount: stats?['sent_count'] != null
          ? (stats?['sent_count'] as num?)?.toInt()
          : null,
    );
  }
}

class GiftTransaction {
  final String id;
  final String userId;
  final String? receiverId;
  final String? liveId;
  final String giftId;
  final String giftName;
  final int amount;
  final int creditsPerUnit;
  final int creditsTotal;
  final int balanceAfter;
  final DateTime createdAt;

  const GiftTransaction({
    required this.id,
    required this.userId,
    this.receiverId,
    this.liveId,
    required this.giftId,
    required this.giftName,
    this.amount = 1,
    this.creditsPerUnit = 0,
    this.creditsTotal = 0,
    this.balanceAfter = 0,
    required this.createdAt,
  });

  factory GiftTransaction.fromJson(Map<String, dynamic> json) =>
      GiftTransaction(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        receiverId: json['receiver_id'] as String?,
        liveId: json['live_id'] as String?,
        giftId: json['gift_id'] as String? ?? '',
        giftName: json['gift_name'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 1,
        creditsPerUnit: (json['credits_per_unit'] as num?)?.toInt() ?? 0,
        creditsTotal: (json['credits_total'] as num?)?.toInt() ?? 0,
        balanceAfter: (json['balance_after'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class GiftSendResult {
  final String? transactionId;
  final Gift gift;
  final int amount;
  final int creditsSpent;
  final int balance;

  /// `true` quando o backend reaproveitou uma transação já processada com o
  /// mesmo `request_id` (envio idempotente) — nada novo foi debitado.
  final bool duplicate;

  /// `true` quando o remetente é o fundador com créditos ilimitados: o envio
  /// foi gratuito (nada debitado do saldo), decidido apenas no backend.
  final bool unlimited;

  const GiftSendResult({
    this.transactionId,
    required this.gift,
    this.amount = 1,
    this.creditsSpent = 0,
    this.balance = 0,
    this.duplicate = false,
    this.unlimited = false,
  });
}

/// Envio simultâneo do mesmo `request_id` (backend retornou 409
/// `duplicate_in_progress`). O chamador deve gerar um novo id e tentar de novo
/// apenas se este envio ainda não foi confirmado.
class GiftDuplicateInProgressException implements Exception {
  final String message;
  final String? transactionId;

  const GiftDuplicateInProgressException(this.message, {this.transactionId});

  @override
  String toString() => message;
}
