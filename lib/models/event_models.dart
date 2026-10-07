/// Modelos de Eventos públicos do KLAY K (shows, maratonas, campeonatos...).
/// Mapeiam o schema `public.events` + `public.event_rsvps`, com auxiliares
/// de exibição (ícone por categoria, formatação de data) e parses RLS-safe.
library;

const Map<String, String> _kCategoryIcons = {
  'musica': '🎤',
  'música': '🎤',
  'ia': '🤖',
  'jogos': '🎮',
  'gaming': '🎮',
  'esports': '🕹️',
  'esportes': '🏆',
  'virais': '🔥',
  'encontros': '🤝',
  'entretenimento': '🎬',
  'tecnologia': '💻',
};

/// Tipo (data estática p/ parse e exibição).
class KlayKEvent {
  final String id;
  final String title;
  final String slug;
  final String description;
  final String category;
  final String location;
  final String bannerUrl;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String organizerId;
  final int participantCount;
  final bool isPublic;
  final DateTime createdAt;
  final bool iAmGoing;

  const KlayKEvent({
    required this.id,
    required this.title,
    this.slug = '',
    this.description = '',
    this.category = '',
    this.location = '',
    this.bannerUrl = '',
    this.startsAt,
    this.endsAt,
    this.organizerId = '',
    this.participantCount = 0,
    this.isPublic = true,
    required this.createdAt,
    this.iAmGoing = false,
  });

  factory KlayKEvent.fromJson(Map<String, dynamic> json) {
    DateTime? dt(Object? v) =>
        v != null ? DateTime.tryParse(v.toString())?.toLocal() : null;
    return KlayKEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      bannerUrl: json['banner_url']?.toString() ?? '',
      startsAt: dt(json['starts_at']),
      endsAt: dt(json['ends_at']),
      organizerId: json['organizer_id']?.toString() ?? '',
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 0,
      isPublic: json['is_public'] as bool? ?? true,
      createdAt:
          dt(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      iAmGoing: json['i_am_going'] as bool? ?? false,
    );
  }

  KlayKEvent copyWith({bool? iAmGoing, int? participantCount}) => KlayKEvent(
    id: id,
    title: title,
    slug: slug,
    description: description,
    category: category,
    location: location,
    bannerUrl: bannerUrl,
    startsAt: startsAt,
    endsAt: endsAt,
    organizerId: organizerId,
    participantCount: participantCount ?? this.participantCount,
    isPublic: isPublic,
    createdAt: createdAt,
    iAmGoing: iAmGoing ?? this.iAmGoing,
  );

  /// Ícone por categoria (com fallback neutro).
  String get icon => _kCategoryIcons[category.trim().toLowerCase()] ?? '📅';

  /// Label legível de data/hora de início.
  String get whenLabel {
    final s = startsAt;
    if (s == null) return 'Data a definir';
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    final h = s.hour.toString().padLeft(2, '0');
    final m = s.minute.toString().padLeft(2, '0');
    return '${s.day.toString().padLeft(2, '0')} ${months[s.month - 1]} · $h:$m';
  }

  /// Se o evento ainda não terminou.
  bool get isUpcoming {
    final e = endsAt ?? startsAt;
    return e == null || e.isAfter(DateTime.now());
  }
}

/// Categoria com a contagem real de eventos.
class KlayKEventCategory {
  final String name;
  final int count;

  const KlayKEventCategory({required this.name, required this.count});
}
