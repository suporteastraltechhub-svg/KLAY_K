import 'package:supabase_flutter/supabase_flutter.dart';

/// Perfil completo de usuário do KLAY K.
///
/// Corresponde à linha de `public.profiles` enriquecida pelos agregados que a
/// RPC `get_profile` devolve (contadores, curtidas totais e a relação do
/// usuário atual). Usado tanto no perfil do próprio usuário quanto na
/// visualização de perfis alheios.
class UserProfile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? bio;
  final String? website;
  final String? location;
  final String? pronouns;
  final bool isPrivate;
  final bool isVerified;
  final bool isAdmin;
  final String? role;
  final String? profession;
  final DateTime? birthDate;
  final DateTime createdAt;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final int totalLikes;
  final bool isFollowing;
  final bool isSelf;

  UserProfile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.bannerUrl,
    this.bio,
    this.website,
    this.location,
    this.pronouns,
    this.isPrivate = false,
    this.isVerified = false,
    this.isAdmin = false,
    this.role,
    this.profession,
    this.birthDate,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.totalLikes = 0,
    this.isFollowing = false,
    this.isSelf = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Nome de exibição preferido (fallback: usuário).
  String get name => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!.trim()
      : (username?.isNotEmpty == true ? username! : 'Usuário');

  /// Handle completo com `@`, ex.: `@klaykoficial`.
  String get handle => (username != null && username!.isNotEmpty)
      ? '@$username'
      : '@usuario';

  /// É o fundador oficial da plataforma (role do banco, nunca client-side).
  bool get isFounder => role == 'founder';

  /// É o próprio fundador OU um admin/super_admin (selo 👑 mais forte).
  bool get isFounderOrAdmin =>
      role == 'founder' || role == 'super_admin' || role == 'admin';

  bool get hasVerifiedBadge => isVerified || isFounder;

  factory UserProfile.fromJson(Map<String, dynamic> json, {String? myId}) {
    // Aceita tanto payload plano (RPC get_profile) quanto um row da tabela
    // `profiles` nidificado sob a chave `profiles` (joins do PostgREST).
    final base = json['profiles'] is Map
        ? Map<String, dynamic>.from(json['profiles'] as Map)
        : json;

    final rawId = base['id']?.toString() ?? json['id']?.toString() ?? '';

    int count(Object? value) => (value is num) ? value.toInt() : 0;
    bool flag(Object? value) => value == true;

    return UserProfile(
      id: rawId,
      username: base['username']?.toString(),
      displayName: base['display_name']?.toString(),
      avatarUrl: base['avatar_url']?.toString(),
      bannerUrl: base['banner_url']?.toString(),
      bio: base['bio']?.toString(),
      website: base['website']?.toString(),
      location: base['location']?.toString(),
      pronouns: base['pronouns']?.toString(),
      isPrivate: flag(base['is_private']),
      isVerified: flag(base['is_verified']),
      isAdmin: flag(base['is_admin']),
      role: base['role']?.toString(),
      profession: base['profession']?.toString(),
      birthDate: _parseDate(base['birth_date']),
      createdAt: _parseDate(base['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      followersCount: count(base['followers_count']),
      followingCount: count(base['following_count']),
      postsCount: count(base['posts_count']),
      totalLikes: count(base['total_likes']),
      isFollowing: flag(base['is_following']),
      isSelf: rawId.isNotEmpty
          ? rawId == (myId ?? _rpcMyId(json))
          : flag(base['is_self']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Id do usuário logado, quando disponível (só para derivar `isSelf`).
  static String? _rpcMyId(Map<String, dynamic> _) {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user?.id;
    } catch (_) {
      return null;
    }
  }

  UserProfile copyWith({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bannerUrl,
    String? bio,
    String? website,
    String? location,
    String? pronouns,
    int? followersCount,
    int? followingCount,
    int? postsCount,
    int? totalLikes,
    bool? isFollowing,
    bool? isPrivate,
    bool? isVerified,
    String? profession,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      bio: bio ?? this.bio,
      website: website ?? this.website,
      location: location ?? this.location,
      pronouns: pronouns ?? this.pronouns,
      role: role,
      profession: profession ?? this.profession,
      isPrivate: isPrivate ?? this.isPrivate,
      isVerified: isVerified ?? this.isVerified,
      isAdmin: isAdmin,
      birthDate: birthDate,
      createdAt: createdAt,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount,
      totalLikes: totalLikes ?? this.totalLikes,
      isFollowing: isFollowing ?? this.isFollowing,
      isSelf: isSelf,
    );
  }

  /// Descrição de data de nascimento em formato amigável (pt-BR).
  String? get birthDateLabel {
    final d = birthDate;
    if (d == null) return null;
    final dt = d.toLocal();
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$day/$m/$y';
  }
}