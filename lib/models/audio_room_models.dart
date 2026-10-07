/// Modelos de Salas de Voz (território Áudio) do KLAY K.
/// Espaços de conversa por áudio em tempo real (Clubhouse-style) via LiveKit.
/// Mapeiam o schema `public.audio_rooms`, com auxiliares de exibição
/// (categoria, contagem de participantes/falantes) e parses RLS-safe.
library;

const Map<String, String> _kAudioCategoryIcons = {
  'conversa': '🗣️',
  'conversas': '🗣️',
  'batepapo': '💬',
  'noticias': '📰',
  'news': '📰',
  'musica': '🎧',
  'música': '🎧',
  'jogos': '🎮',
  'gaming': '🎮',
  'esports': '🕹️',
  'tecnologia': '💻',
  'tech': '💻',
  'educacao': '📚',
  'educação': '📚',
  'opnioes': '⚖️',
  'opiniões': '⚖️',
  'virais': '🔥',
};

/// Uma sala de voz ativa.
class AudioRoom {
  final String id;
  final String title;
  final String slug;
  final String description;
  final String category;
  final String roomName;
  final String ownerId;
  final String ownerDisplayName;
  final String ownerUsername;
  final String? ownerAvatarUrl;
  final int participantCount;
  final int speakerCount;
  final bool isPublic;
  final bool iOwnIt;

  const AudioRoom({
    required this.id,
    required this.title,
    this.slug = '',
    this.description = '',
    this.category = '',
    required this.roomName,
    this.ownerId = '',
    this.ownerDisplayName = '',
    this.ownerUsername = '',
    this.ownerAvatarUrl,
    this.participantCount = 1,
    this.speakerCount = 1,
    this.isPublic = true,
    this.iOwnIt = false,
  });

  factory AudioRoom.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> profile = json['profiles'] is Map
        ? Map<String, dynamic>.from(
            (json['profiles'] as Map).map((k, v) => MapEntry(k.toString(), v)),
          )
        : const {};
    return AudioRoom(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      roomName: json['room_name']?.toString() ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
      ownerDisplayName: profile['display_name']?.toString() ?? '',
      ownerUsername: profile['username']?.toString() ?? '',
      ownerAvatarUrl: profile['avatar_url']?.toString(),
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 1,
      speakerCount: (json['speaker_count'] as num?)?.toInt() ?? 1,
      isPublic: json['is_public'] as bool? ?? true,
      iOwnIt: json['i_own_it'] as bool? ?? false,
    );
  }

  AudioRoom copyWith({int? participantCount, int? speakerCount}) => AudioRoom(
    id: id,
    title: title,
    slug: slug,
    description: description,
    category: category,
    roomName: roomName,
    ownerId: ownerId,
    ownerDisplayName: ownerDisplayName,
    ownerUsername: ownerUsername,
    ownerAvatarUrl: ownerAvatarUrl,
    participantCount: participantCount ?? this.participantCount,
    speakerCount: speakerCount ?? this.speakerCount,
    isPublic: isPublic,
    iOwnIt: iOwnIt,
  );

  /// Ícone por categoria (com fallback neutro).
  String get icon =>
      _kAudioCategoryIcons[category.trim().toLowerCase()] ?? '🎙️';

  /// Nome exibível do dono (fallback: username / "Usuário").
  String get ownerName {
    final n = ownerDisplayName.trim();
    if (n.isNotEmpty) return n;
    final u = ownerUsername.trim();
    return u.isNotEmpty ? '@$u' : 'Usuário';
  }

  bool get isFull => participantCount >= 500;
}

/// Categoria com a contagem real de salas ativas.
class AudioRoomCategory {
  final String name;
  final int count;

  const AudioRoomCategory({required this.name, required this.count});
}
