import 'package:supabase_flutter/supabase_flutter.dart';

/// Comunidade do KLAY K: espaço temático com membros, moderadores e posts.
class Community {
  final String id;
  final String name;
  final String slug;
  final String description;
  final String icon;
  final String? coverUrl;
  final String category;
  final String? createdBy;
  final int memberCount;
  final int postCount;
  final bool isPublic;
  final String rules;
  final DateTime createdAt;

  const Community({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
    this.icon = '',
    this.coverUrl,
    this.category = '',
    this.createdBy,
    this.memberCount = 0,
    this.postCount = 0,
    this.isPublic = true,
    this.rules = '',
    required this.createdAt,
  });

  factory Community.fromJson(Map<String, dynamic> json) {
    final createdBy = json['created_by'];
    return Community(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      coverUrl: json['cover_url']?.toString(),
      category: json['category']?.toString() ?? '',
      createdBy: createdBy is List
          ? (createdBy.isNotEmpty ? (createdBy.first as Map)['id']?.toString() : null)
          : createdBy?.toString(),
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
      isPublic: json['is_public'] as bool? ?? true,
      rules: json['rules']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  /// Emoji padrão de categoria, usado como fallback visual no feed.
  String get categoryIcon {
    final c = category.toLowerCase();
    if (c.contains('game') || c.contains('jogo')) return '🎮';
    if (c.contains('music') || c.contains('música')) return '🎵';
    if (c.contains('tech')) return '💻';
    if (c.contains('sport') || c.contains('esport')) return '⚽';
    if (c.contains('humor')) return '😂';
    if (c.contains('entretenimento')) return '🎬';
    return icon.isNotEmpty ? icon : '👥';
  }
}

/// Assinatura do usuário atual dentro de uma comunidade.
class CommunityMembership {
  final String communityId;
  final String userId;
  final String role; // member | moderator | admin
  final DateTime joinedAt;

  const CommunityMembership({
    required this.communityId,
    required this.userId,
    this.role = 'member',
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isModerator => role == 'moderator' || role == 'admin';

  factory CommunityMembership.fromJson(Map<String, dynamic> json) =>
      CommunityMembership(
        communityId: json['community_id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        role: json['role']?.toString() ?? 'member',
        joinedAt: DateTime.tryParse(json['joined_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

/// Post / discussão dentro de uma comunidade, com autor embutido.
class CommunityPost {
  final String id;
  final String communityId;
  final String userId;
  final String content;
  final String mediaUrl;
  final String mediaType; // '' | image | video
  final int likesCount;
  final int commentsCount;
  final bool pinned;
  final DateTime createdAt;
  // Autor (join)
  final String authorName;
  final String authorUsername;
  final String? authorAvatar;
  final bool authorVerified;

  const CommunityPost({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.content,
    this.mediaUrl = '',
    this.mediaType = '',
    this.likesCount = 0,
    this.commentsCount = 0,
    this.pinned = false,
    required this.createdAt,
    this.authorName = '',
    this.authorUsername = '',
    this.authorAvatar,
    this.authorVerified = false,
  });

  String get authorDisplay =>
      authorName.isNotEmpty ? authorName : (authorUsername.isNotEmpty ? authorUsername : 'Membro');

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final author = json['profiles'];
    String aName = '', aUser = '', aAvatar = '';
    var aVerified = false;
    if (author is Map) {
      aName = author['display_name']?.toString() ?? '';
      aUser = author['username']?.toString() ?? '';
      aAvatar = author['avatar_url']?.toString() ?? '';
      aVerified = author['is_verified'] == true;
    }
    return CommunityPost(
      id: json['id']?.toString() ?? '',
      communityId: json['community_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      mediaUrl: json['media_url']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? '',
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      authorName: aName,
      authorUsername: aUser,
      authorAvatar: aAvatar.isEmpty ? null : aAvatar,
      authorVerified: aVerified,
    );
  }
}

/// Comentário num post de comunidade.
class CommunityComment {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final String authorName;
  final String authorUsername;
  final String? authorAvatar;

  const CommunityComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.authorName = '',
    this.authorUsername = '',
    this.authorAvatar,
  });

  String get authorDisplay =>
      authorName.isNotEmpty ? authorName : (authorUsername.isNotEmpty ? authorUsername : 'Membro');

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final author = json['profiles'];
    String aName = '', aUser = '', aAvatar = '';
    if (author is Map) {
      aName = author['display_name']?.toString() ?? '';
      aUser = author['username']?.toString() ?? '';
      aAvatar = author['avatar_url']?.toString() ?? '';
    }
    return CommunityComment(
      id: json['id']?.toString() ?? '',
      postId: json['post_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      authorName: aName,
      authorUsername: aUser,
      authorAvatar: aAvatar.isEmpty ? null : aAvatar,
    );
  }
}

/// Categoria com contagem (usado para filtrar exploração).
class CommunityCategory {
  final String name;
  final int count;

  const CommunityCategory({required this.name, required this.count});
}

extension CommunityPostLikeCheck on SupabaseClient {
  bool isPostLiked(Map<String, dynamic> json) => json['liked_by_me'] == true;
}