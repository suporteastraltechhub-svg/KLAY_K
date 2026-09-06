/// Modelos usados pelo sistema de lives REAL (Supabase + LiveKit).
///
/// Estes modelos representam o estado persistido no banco. Eles são
/// independentes dos modelos simulados do main.dart — o fluxo real usa apenas
/// estes tipos, mantendo a simulação intacta quando o Supabase não está
/// configurado.
class RealLive {
  final String id;
  final String roomName;
  final String streamerId;
  final String title;
  final String description;
  final String category;
  final List<String> hashtags;
  final String privacy;
  final String status;
  final DateTime startedAt;
  final int viewerCount;
  final String? gameName;
  final String? coverUrl;
  final bool ageRestricted;

  final String? streamerDisplayName;
  final String? streamerUsername;
  final String? streamerAvatar;
  final bool streamerVerified;

  bool ended;

  RealLive({
    required this.id,
    required this.roomName,
    required this.streamerId,
    required this.title,
    this.description = '',
    this.category = '',
    this.hashtags = const [],
    this.privacy = 'public',
    this.status = 'live',
    required this.startedAt,
    this.viewerCount = 0,
    this.gameName,
    this.coverUrl,
    this.ageRestricted = false,
    this.streamerDisplayName,
    this.streamerUsername,
    this.streamerAvatar,
    this.streamerVerified = false,
    this.ended = false,
  });

  factory RealLive.fromJson(Map<String, dynamic> json) {
    List<String> tags = const [];
    final rawTags = json['hashtags'];
    if (rawTags is List) {
      tags = rawTags.whereType<String>().toList();
    }
    final profile = json['profiles'];
    return RealLive(
      id: json['id'] as String,
      roomName: json['room_name'] as String,
      streamerId: json['streamer_id'] as String,
      title: json['title'] as String? ?? 'Live ao vivo',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      hashtags: tags,
      privacy: json['privacy'] as String? ?? 'public',
      status: json['status'] as String? ?? 'live',
      startedAt:
          DateTime.tryParse(json['started_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      viewerCount: json['viewer_count'] as int? ?? 0,
      gameName: json['game_name'] as String?,
      coverUrl: json['cover_url'] as String?,
      ageRestricted: json['age_restricted'] == true,
      streamerDisplayName: profile is Map
          ? profile['display_name'] as String?
          : null,
      streamerUsername:
          profile is Map ? profile['username'] as String? : null,
      streamerAvatar:
          profile is Map ? profile['avatar_url'] as String? : null,
      streamerVerified:
          profile is Map ? profile['is_verified'] == true : false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_name': roomName,
        'streamer_id': streamerId,
        'title': title,
        'description': description,
        'category': category,
        'hashtags': hashtags,
        'privacy': privacy,
        'status': status,
        'started_at': startedAt.toUtc().toIso8601String(),
        'viewer_count': viewerCount,
        if (gameName != null) 'game_name': gameName,
        if (coverUrl != null) 'cover_url': coverUrl,
        'age_restricted': ageRestricted,
      };

  RealLive copyWith({bool? ended, int? viewerCount}) => RealLive(
        id: id,
        roomName: roomName,
        streamerId: streamerId,
        title: title,
        description: description,
        category: category,
        hashtags: hashtags,
        privacy: privacy,
        status: status,
        startedAt: startedAt,
        viewerCount: viewerCount ?? this.viewerCount,
        gameName: gameName,
        coverUrl: coverUrl,
        ageRestricted: ageRestricted,
        streamerDisplayName: streamerDisplayName,
        streamerUsername: streamerUsername,
        streamerAvatar: streamerAvatar,
        streamerVerified: streamerVerified,
        ended: ended ?? this.ended,
      );
}

class LiveChatMessage {
  final String id;
  final String liveId;
  final String? userId;
  final String message;
  final DateTime createdAt;
  final DateTime? editedAt;
  final String? senderDisplayName;
  final String? senderUsername;
  final String? senderAvatar;
  final bool senderVerified;
  final bool mine;

  const LiveChatMessage({
    required this.id,
    required this.liveId,
    this.userId,
    required this.message,
    required this.createdAt,
    this.editedAt,
    this.senderDisplayName,
    this.senderUsername,
    this.senderAvatar,
    this.senderVerified = false,
    this.mine = false,
  });

  factory LiveChatMessage.fromJson(
    Map<String, dynamic> json, {
    String? myId,
  }) {
    final sender = json['sender'];
    return LiveChatMessage(
      id: json['id'] as String,
      liveId: json['live_id'] as String,
      userId: json['user_id'] as String?,
      message: json['message'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      editedAt: json['edited_at'] is DateTime
          ? (json['edited_at'] as DateTime).toLocal()
          : DateTime.tryParse(json['edited_at']?.toString() ?? '')?.toLocal(),
      senderDisplayName: sender is Map
          ? (sender['display_name'] as String? ??
              (json['username'] as String?))
          : (json['username'] as String?),
      senderUsername: sender is Map ? sender['username'] as String? : null,
      senderAvatar:
          sender is Map ? sender['avatar_url'] as String? : null,
      senderVerified:
          sender is Map ? sender['is_verified'] == true : false,
      mine: myId != null && json['user_id'] == myId,
    );
  }

  LiveChatMessage copyWith({
    String? message,
    DateTime? editedAt,
    String? senderDisplayName,
    String? senderAvatar,
    bool? senderVerified,
    bool? mine,
  }) =>
      LiveChatMessage(
        id: id,
        liveId: liveId,
        userId: userId,
        message: message ?? this.message,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        senderDisplayName: senderDisplayName ?? this.senderDisplayName,
        senderUsername: senderUsername,
        senderAvatar: senderAvatar ?? this.senderAvatar,
        senderVerified: senderVerified ?? this.senderVerified,
        mine: mine ?? this.mine,
      );
}

class LiveGift {
  final String giftId;
  final String giftName;
  final int giftAmount;
  final String senderId;
  final String? receiverId;

  const LiveGift({
    required this.giftId,
    required this.giftName,
    required this.giftAmount,
    required this.senderId,
    this.receiverId,
  });
}

class LiveEventRecord {
  final String eventType;
  final String? userId;
  final String? username;
  final Map<String, dynamic> metadata;

  const LiveEventRecord({
    required this.eventType,
    this.userId,
    this.username,
    this.metadata = const {},
  });
}

class LiveRoomEvent {
  final String type;
  final String liveId;
  final String message;
  final DateTime createdAt;
  final String? username;
  final Map<String, dynamic> metadata;

  const LiveRoomEvent({
    required this.type,
    required this.liveId,
    required this.message,
    required this.createdAt,
    this.username,
    this.metadata = const {},
  });

  factory LiveRoomEvent.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const <String, dynamic>{};
    return LiveRoomEvent(
      type: json['event_type'] as String? ?? '',
      liveId: json['live_id'] as String? ?? '',
      message: metadata['message']?.toString() ?? '',
      username: json['username'] as String?,
      metadata: metadata,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class GiftCatalogItem {
  final String id;
  final String name;
  final String emoji;

  const GiftCatalogItem({
    required this.id,
    required this.name,
    required this.emoji,
  });
}

/// Catálogo de presentes (sem cobrança real — camada de pagamento fica
/// separada para implementação posterior, como pedido).
const List<GiftCatalogItem> kGiftCatalog = [
  GiftCatalogItem(id: 'rosa', name: 'Rosa', emoji: '🌹'),
  GiftCatalogItem(id: 'coracao', name: 'Coração', emoji: '❤️'),
  GiftCatalogItem(id: 'batepapo', name: 'Bate-papo', emoji: '💬'),
  GiftCatalogItem(id: 'trofeu', name: 'Troféu', emoji: '🏆'),
  GiftCatalogItem(id: 'nota100', name: 'Nota de 100', emoji: '💵'),
  GiftCatalogItem(id: 'foguete', name: 'Foguete', emoji: '🚀'),
  GiftCatalogItem(id: 'coroa', name: 'Coroa', emoji: '👑'),
  GiftCatalogItem(id: 'pcgamer', name: 'PC Gamer', emoji: '💻'),
];