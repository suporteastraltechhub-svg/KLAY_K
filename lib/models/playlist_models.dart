/// Modelos de Playlists do KLAY K (território Playlists).
/// Listas públicas curadas pelo próprio criador com seus vídeos publicados,
/// navegáveis por qualquer pessoa. Mapeiam o schema `public.playlists` +
/// `public.playlist_posts`, com parses RLS-safe.
library;

/// Uma playlist do criador (com métricas de conteúdo).
class KlayKPlaylist {
  final String id;
  final String creatorId;
  final String name;
  final String description;
  final String coverUrl;
  final bool isPublic;
  final DateTime createdAt;

  final String creatorDisplayName;
  final String creatorUsername;
  final String? creatorAvatarUrl;
  final bool creatorVerified;

  final int postCount;
  final bool isMine;

  const KlayKPlaylist({
    required this.id,
    required this.creatorId,
    required this.name,
    this.description = '',
    this.coverUrl = '',
    this.isPublic = true,
    required this.createdAt,
    this.creatorDisplayName = '',
    this.creatorUsername = '',
    this.creatorAvatarUrl,
    this.creatorVerified = false,
    this.postCount = 0,
    this.isMine = false,
  });

  factory KlayKPlaylist.fromJson(Map<String, dynamic> json, {String? myId}) {
    Map<String, dynamic> profile = const {};
    if (json['profiles'] is Map) {
      profile = Map<String, dynamic>.from(
        (json['profiles'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final creatorId = json['creator_id']?.toString() ?? '';
    return KlayKPlaylist(
      id: json['id']?.toString() ?? '',
      creatorId: creatorId,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      coverUrl: json['cover_url']?.toString() ?? '',
      isPublic: json['is_public'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      creatorDisplayName: profile['display_name']?.toString() ?? '',
      creatorUsername: profile['username']?.toString() ?? '',
      creatorAvatarUrl: profile['avatar_url']?.toString(),
      creatorVerified: profile['is_verified'] == true,
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
      isMine: myId != null && myId.isNotEmpty && myId == creatorId,
    );
  }

  String get creatorName {
    final n = creatorDisplayName.trim();
    if (n.isNotEmpty) return n;
    final u = creatorUsername.trim();
    return u.isNotEmpty ? '@$u' : 'Usuário';
  }
}

/// Um vídeo dentro de uma playlist.
class PlaylistPostItem {
  final String playlistPostId;
  final String postId;
  final int position;

  const PlaylistPostItem({
    required this.playlistPostId,
    required this.postId,
    this.position = 0,
  });

  factory PlaylistPostItem.fromJson(Map<String, dynamic> json) =>
      PlaylistPostItem(
        playlistPostId: json['id']?.toString() ?? '',
        postId: json['post_id']?.toString() ?? '',
        position: (json['position'] as num?)?.toInt() ?? 0,
      );
}
