/// Modelos de Momentos (território Momentos) do KLAY K.
/// Publicações efêmeras (texto + imagen opcional) que expi­ran tras um tempo.
/// Mapean el schema `public.moments`, con parses RLS-safe.
library;

/// Un momento efímero.
class KlayKMoment {
  final String id;
  final String userId;
  final String text;
  final String imageUrl;
  final String sticker;
  final DateTime createdAt;
  final DateTime? expiresAt;

  final String authorDisplayName;
  final String authorUsername;
  final String? authorAvatarUrl;
  final bool authorVerified;

  final bool isMine;

  const KlayKMoment({
    required this.id,
    required this.userId,
    this.text = '',
    this.imageUrl = '',
    this.sticker = '',
    required this.createdAt,
    this.expiresAt,
    this.authorDisplayName = '',
    this.authorUsername = '',
    this.authorAvatarUrl,
    this.authorVerified = false,
    this.isMine = false,
  });

  factory KlayKMoment.fromJson(Map<String, dynamic> json, {String? myId}) {
    DateTime dt(Object? v) {
      final parsed = DateTime.tryParse(v?.toString() ?? '');
      return parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    Map<String, dynamic> profile = const {};
    if (json['profiles'] is Map) {
      profile = Map<String, dynamic>.from(
        (json['profiles'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final uid = json['user_id']?.toString() ?? '';
    return KlayKMoment(
      id: json['id']?.toString() ?? '',
      userId: uid,
      text: json['text']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      sticker: json['sticker']?.toString() ?? '',
      createdAt: dt(json['created_at']),
      expiresAt: DateTime.tryParse(
        json['expires_at']?.toString() ?? '',
      )?.toLocal(),
      authorDisplayName: profile['display_name']?.toString() ?? '',
      authorUsername: profile['username']?.toString() ?? '',
      authorAvatarUrl: profile['avatar_url']?.toString(),
      authorVerified: profile['is_verified'] == true,
      isMine: myId != null && myId.isNotEmpty && myId == uid,
    );
  }

  /// Nome exibible del autor (fallback: username / "Usuario").
  String get authorName {
    final n = authorDisplayName.trim();
    if (n.isNotEmpty) return n;
    final u = authorUsername.trim();
    return u.isNotEmpty ? '@$u' : 'Usuario';
  }

  /// Tiempo restante legible (p. ej. "2 h restantes") o nulo si ya expiró.
  String? get remainingLabel {
    final e = expiresAt;
    if (e == null) return null;
    final diff = e.difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min restantes';
    if (diff.inHours < 24) return '${diff.inHours} h restantes';
    return '${diff.inDays} d restantes';
  }
}
