/// Modelos de Criadores em Ascensão do KLAY K.
/// Descobrimento de criadores com maior momentum (não magnitude) nos últimos
/// 7 dias, derivado de dados reais do backend (RPC `rising_creators`).
library;

/// Criador com pontuação de ascensão e métricas de 7 dias.
class RisingCreator {
  final String creatorId;
  final int likes7d;
  final int followers7d;
  final int posts7d;
  final int score;

  final String displayName;
  final String username;
  final String avatarUrl;
  final bool isVerified;

  const RisingCreator({
    required this.creatorId,
    this.likes7d = 0,
    this.followers7d = 0,
    this.posts7d = 0,
    this.score = 0,
    this.displayName = '',
    this.username = '',
    this.avatarUrl = '',
    this.isVerified = false,
  });

  factory RisingCreator.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> profile = const {};
    if (json['profiles'] is Map) {
      profile = Map<String, dynamic>.from(
        (json['profiles'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return RisingCreator(
      creatorId: json['creator_id']?.toString() ?? '',
      likes7d: (json['likes_7d'] as num?)?.toInt() ?? 0,
      followers7d: (json['followers_7d'] as num?)?.toInt() ?? 0,
      posts7d: (json['posts_7d'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      displayName: profile['display_name']?.toString() ?? '',
      username: profile['username']?.toString() ?? '',
      avatarUrl: profile['avatar_url']?.toString() ?? '',
      isVerified: profile['is_verified'] == true,
    );
  }

  /// Nome de exibição preferido (fallback: username / 'Usuário').
  String get name {
    final n = displayName.trim();
    if (n.isNotEmpty) return n;
    final u = username.trim();
    return u.isNotEmpty ? '@$u' : 'Usuário';
  }

  String get handle => username.trim().isNotEmpty ? '@$username' : '';

  /// Resumo legível do momentum (ex.: "+120 em 7d").
  String get momentumLabel => '+$score em 7 dias';

  /// Resumo das métricas de destaque.
  String get statsLabel {
    final parts = <String>[
      if (likes7d > 0) '$likes7d curtidas',
      if (followers7d > 0) '$followers7d seguidores',
      if (posts7d > 0) '$posts7d posts',
    ];
    return parts.isEmpty ? 'Sem atividade nos últimos 7 dias' : parts.join(' · ');
  }
}