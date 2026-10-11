import 'dart:convert';

/// Modelos reais do conteúdo do KLAY K (feed/posts, comentários, curtidas,
/// salvos, notificações e seguidores). Todos mapeiam as tabelas do Supabase
/// criadas em `20260828020000_content.sql` / `20260828000000_fix_follows.sql`.

/// Perfil resumido de um autor (join `profiles:user_id(...)`).
class PostAuthor {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;

  const PostAuthor({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });

  String get name => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : (username ?? 'Usuário');

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
    id: json['id'] as String? ?? '',
    username: json['username'] as String?,
    displayName: json['display_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isVerified: json['is_verified'] == true,
  );
}

/// Um post/vídeo do feed. Mapeia `public.posts` + join de autor + estados do
/// usuário atual (curtiu/salvou).
class FeedPost {
  final String id;
  final String userId;
  final String videoUrl;
  final String? coverUrl;
  final String description;
  final String? audioName;
  final List<String> hashtags;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final DateTime createdAt;
  final PostAuthor? author;

  /// Estado do usuário atual (preenchido no cliente).
  final bool liked;
  final bool saved;
  final bool following;

  const FeedPost({
    required this.id,
    required this.userId,
    required this.videoUrl,
    this.coverUrl,
    this.description = '',
    this.audioName,
    this.hashtags = const [],
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    required this.createdAt,
    this.author,
    this.liked = false,
    this.saved = false,
    this.following = false,
  });

  FeedPost copyWith({
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    bool? liked,
    bool? saved,
    bool? following,
    FeedPost? author,
  }) {
    return FeedPost(
      id: id,
      userId: userId,
      videoUrl: videoUrl,
      coverUrl: coverUrl,
      description: description,
      audioName: audioName,
      hashtags: hashtags,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      createdAt: createdAt,
      author: this.author,
      liked: liked ?? this.liked,
      saved: saved ?? this.saved,
      following: following ?? this.following,
    );
  }

  /// Constrói um [FeedPost] a partir de uma linha `posts` que inclua o join
  /// `profiles:user_id(...)`.
  static FeedPost fromJson(
    Map<String, dynamic> json, {
    bool liked = false,
    bool saved = false,
    bool following = false,
  }) {
    Map<String, dynamic> authorJson = const {};
    final rawAuthor = json['profiles'];
    if (rawAuthor is Map) {
      authorJson = Map<String, dynamic>.from(
        rawAuthor.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final hashtags = <String>[];
    final rawTags = json['hashtags'];
    if (rawTags is List) {
      hashtags.addAll(rawTags.whereType<String>());
    }

    return FeedPost(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      coverUrl: json['cover_url'] as String?,
      description: json['description'] as String? ?? '',
      audioName: json['audio_name'] as String?,
      hashtags: hashtags,
      likesCount: _asInt(json['likes_count']),
      commentsCount: _asInt(json['comments_count']),
      sharesCount: _asInt(json['shares_count']),
      createdAt: _asDateTime(json['created_at']),
      author: authorJson.isEmpty ? null : PostAuthor.fromJson(authorJson),
      liked: liked,
      saved: saved,
      following: following,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return v == null ? 0 : int.tryParse(v.toString()) ?? 0;
  }

  static DateTime _asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
    return DateTime.now();
  }
}

/// Comentário real mapeando `public.comments` + join autor.
class PostComment {
  final String id;
  final String postId;
  final String? userId;
  final String? parentId;
  final String text;
  final DateTime createdAt;
  final DateTime? editedAt;

  /// Curtidas do comentário. A coluna é mantida por trigger no banco, então o
  /// contador fica sempre consistente com a tabela `comment_likes`.
  final int likesCount;

  /// Se quem está vendo já curtiu este comentário.
  final bool likedByMe;

  final PostAuthor? author;

  const PostComment({
    required this.id,
    required this.postId,
    this.userId,
    this.parentId,
    required this.text,
    required this.createdAt,
    this.editedAt,
    this.likesCount = 0,
    this.likedByMe = false,
    this.author,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> authorJson = const {};
    final rawAuthor = json['profiles'];
    if (rawAuthor is Map) {
      authorJson = Map<String, dynamic>.from(
        rawAuthor.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return PostComment(
      id: json['id'] as String? ?? '',
      postId: json['post_id'] as String? ?? '',
      userId: json['user_id'] as String?,
      parentId: json['parent_id'] as String?,
      text: json['text'] as String? ?? '',
      createdAt: json['created_at'] is DateTime
          ? (json['created_at'] as DateTime).toLocal()
          : DateTime.tryParse(
                  json['created_at']?.toString() ?? '',
                )?.toLocal() ??
                DateTime.now(),
      editedAt: json['edited_at'] is DateTime
          ? (json['edited_at'] as DateTime).toLocal()
          : DateTime.tryParse(json['edited_at']?.toString() ?? '')?.toLocal(),
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['liked_by_me'] == true,
      author: authorJson.isEmpty ? null : PostAuthor.fromJson(authorJson),
    );
  }
}

/// Notificação real mapeando `public.notifications`.
class AppNotification {
  final String id;
  final String userId;
  final String? actorId;
  final String type;
  final String? refId;
  final String message;
  final bool read;
  final DateTime createdAt;
  final PostAuthor? actor;

  const AppNotification({
    required this.id,
    required this.userId,
    this.actorId,
    required this.type,
    this.refId,
    required this.message,
    this.read = false,
    required this.createdAt,
    this.actor,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> actorJson = const {};
    final rawActor = json['actor'];
    if (rawActor is Map) {
      actorJson = Map<String, dynamic>.from(
        rawActor.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return AppNotification(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      actorId: json['actor_id'] as String?,
      type: json['type'] as String? ?? '',
      refId: json['ref_id'] as String?,
      message: json['message'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: json['created_at'] is DateTime
          ? (json['created_at'] as DateTime).toLocal()
          : DateTime.tryParse(
                  json['created_at']?.toString() ?? '',
                )?.toLocal() ??
                DateTime.now(),
      actor: actorJson.isEmpty ? null : PostAuthor.fromJson(actorJson),
    );
  }
}

/// Perfil detalhado para a tela de CreatorProfile / Profile.
class CreatorProfile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final int totalLikes;
  final int postsCount;
  final bool isFollowing;
  final bool isSelf;

  const CreatorProfile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
    this.totalLikes = 0,
    this.postsCount = 0,
    this.isFollowing = false,
    this.isSelf = false,
  });

  String get name => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : (username ?? 'Usuário');

  CreatorProfile copyWith({
    int? followersCount,
    int? followingCount,
    int? totalLikes,
    int? postsCount,
    bool? isFollowing,
    String? avatarUrl,
    String? bio,
  }) {
    return CreatorProfile(
      id: id,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      totalLikes: totalLikes ?? this.totalLikes,
      postsCount: postsCount ?? this.postsCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isSelf: isSelf,
    );
  }
}

/// Utilidades de serialização JSON p/ payloads de notificações (opcional).
String encodeHashtags(List<String> tags) => jsonEncode(tags);
