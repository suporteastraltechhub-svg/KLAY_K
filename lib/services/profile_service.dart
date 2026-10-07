import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'account_service.dart';
import 'content_service.dart';
import 'social_service.dart';
import 'supabase_service.dart';

/// Camada de acesso do Sistema de Perfil do KLAY K.
///
/// Centraliza leitura/escrita do perfil (próprio e alheio) sobre Supabase,
/// usando a RPC [get_profile] (1 round-trip) com fallback para as consultas
/// clássicas quando a migration ainda não foi aplicada. Não interfere no fluxo
/// de autenticação (o login/cadastro continua via [SupabaseService]).
class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  static final RegExp _usernameRe = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  SupabaseClient get _db => SupabaseService.instance.client;

  /// Id do usuário autenticado ou `null` (sem sessão / supabase desligado).
  String? get myId => SupabaseService.instance.currentUser?.id;

  bool get _configured => SupabaseService.instance.isConfigured;

  // ---------------------------------------------------------------------------
  // Leitura
  // ---------------------------------------------------------------------------

  /// Carrega o perfil completo (dados + agregados + relação) de `userId`.
  Future<UserProfile?> fetchProfile(String userId) async {
    if (!_configured || userId.isEmpty) {
      return _offlineProfile(userId);
    }
    try {
      final res = await _db.rpc('get_profile', params: {'p_user_id': userId});
      if (res == null) return null;
      return UserProfile.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      // Migration não aplicada / rede: degrada para as consultas legadas.
      return _legacyProfile(userId);
    }
  }

  /// Perfil completo do usuário atual (e sincroniza a identidade global).
  Future<UserProfile?> fetchMyProfile() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final profile = await fetchProfile(user.id);
    if (profile != null) {
      kAppIdentity.displayName = profile.name;
      if (profile.username != null && profile.username!.isNotEmpty) {
        kAppIdentity.username = '@${profile.username}';
      }
      if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
        kAppIdentity.avatarUrl = profile.avatarUrl;
      }
    }
    return profile;
  }

  /// Seguidores de `userId` (lista de perfis resumidos).
  Future<List<UserProfile>> fetchFollowers(String userId) =>
      _fetchRelationList('profile_followers', userId);

  /// Quem `userId` segue (lista de perfis resumidos).
  Future<List<UserProfile>> fetchFollowing(String userId) =>
      _fetchRelationList('profile_following', userId);

  Future<List<UserProfile>> _fetchRelationList(
    String rpc,
    String userId,
  ) async {
    if (!_configured || userId.isEmpty) return const [];
    try {
      final res = await _db.rpc(rpc, params: {'p_user_id': userId});
      final rows = res as List? ?? const [];
      return rows
          .whereType<Map>()
          .map(
            (r) => UserProfile.fromJson(
              Map<String, dynamic>.from(
                r.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Sugestões reais de amizade (2º grau do grafo de follows + seguidores que
  /// o usuário ainda não segue de volta), priorizando conexões em comum.
  Future<List<UserProfile>> fetchFriendSuggestions() async {
    final uid = myId;
    if (!_configured || uid == null || uid.isEmpty) return const [];
    try {
      final res = await _db.rpc(
        'friend_suggestions',
        params: {'p_user_id': uid},
      );
      return _toUserProfiles(res);
    } catch (_) {
      return const [];
    }
  }

  /// Amigos reais (relação recíproca: você segue e ela segue você de volta).
  Future<List<UserProfile>> fetchMutualFriends() async {
    final uid = myId;
    if (!_configured || uid == null || uid.isEmpty) return const [];
    try {
      final res = await _db.rpc('mutual_friends', params: {'p_user_id': uid});
      return _toUserProfiles(res);
    } catch (_) {
      return const [];
    }
  }

  /// Contagens do hub de Amizades (seguindo, seguidores, amigos, convites).
  Future<Map<String, int>> fetchFriendCounts() async {
    final uid = myId;
    if (!_configured || uid == null || uid.isEmpty) return const {};
    try {
      final res = await _db.rpc('friend_counts', params: {'p_user_id': uid});
      final row = (res is List && res.isNotEmpty) ? res.first : res;
      if (row is! Map) return const {};
      int n(Object? v) => v is num ? v.toInt() : 0;
      return {
        'following': n(row['following']),
        'followers': n(row['followers']),
        'friends': n(row['friends']),
        'invitees': n(row['invitees']),
      };
    } catch (_) {
      return const {};
    }
  }

  List<UserProfile> _toUserProfiles(Object? res) {
    final rows = res is List ? res : const <Object>[];
    return rows
        .whereType<Map>()
        .map(
          (r) => UserProfile.fromJson(
            Map<String, dynamic>.from(
              r.map((k, v) => MapEntry(k.toString(), v)),
            ),
          ),
        )
        .toList();
  }

  /// Busca de usuários (reusa a busca combinada do app, escopo 'user').
  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];
    try {
      final results = await SocialService.instance.search(query, scope: 'user');
      return results
          .where((r) => r.type == 'user')
          .take(limit)
          .map(
            (r) => UserProfile(
              id: r.id,
              username: r.subtitle.isNotEmpty ? r.subtitle : r.title,
              displayName: r.title,
              avatarUrl: r.avatarUrl,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Escrita
  // ---------------------------------------------------------------------------

  /// Atualiza os campos editáveis do perfil do usuário autenticado.
  ///
  /// Persiste em `public.profiles` (mesmas colunas já liberadas por grants de
  /// UPDATE) e espelha nome/usuário em `auth.users.raw_user_meta_data` para que
  /// o fluxo de login/cadastro continue consistente.
  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    String? website,
    String? location,
    String? pronouns,
    String? avatarUrl,
    String? bannerUrl,
    bool? isPrivate,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    if (username != null) {
      final clean = username.trim().replaceFirst(RegExp(r'^@'), '');
      if (!_usernameRe.hasMatch(clean)) {
        throw const ProfileValidationException(
          'Usuário: 3 a 20 caracteres (letras, números e _).',
        );
      }
      username = clean;
    }

    final patch = <String, dynamic>{
      if (displayName != null) 'display_name': displayName.trim(),
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio.trim(),
      if (website != null) 'website': _cleanUrl(website),
      if (location != null) 'location': location.trim(),
      if (pronouns != null) 'pronouns': pronouns.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (bannerUrl != null) 'banner_url': bannerUrl,
      if (isPrivate != null) 'is_private': isPrivate,
    };
    if (patch.isNotEmpty) {
      await _db.from('profiles').update(patch).eq('id', user.id);
    }

    // Espelha identidade no Auth (login/cadastro futuros e kAppIdentity).
    final meta = <String, dynamic>{
      if (displayName != null) 'full_name': displayName.trim(),
      if (username != null) 'username': username,
    };
    if (meta.isNotEmpty) {
      try {
        await _db.auth.updateUser(UserAttributes(data: meta));
      } catch (_) {
        // O perfil é a fonte de verdade; metadata é um espelho opcional.
      }
    }
    if (displayName != null) kAppIdentity.displayName = displayName.trim();
    if (username != null) kAppIdentity.username = '@$username';
    if (avatarUrl != null) kAppIdentity.avatarUrl = avatarUrl;
  }

  static String? _cleanUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      return 'https://$v';
    }
    return v;
  }

  /// Envia uma nova foto de avatar (bucket público `avatars`) e a aplica no
  /// perfil. Retorna a URL pública.
  Future<String> uploadAvatar(File file, {String? mime}) async {
    final url = await AccountService.instance.uploadAvatar(file, mime: mime);
    await updateProfile(avatarUrl: url);
    return url;
  }

  /// Envia uma nova imagem de capa (bucket público `covers`) e a aplica no
  /// perfil. Retorna a URL pública.
  Future<String> uploadBanner(File file, {String? mime}) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final ext = _ext(file.path);
    final path =
        '${user.id}/banner-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage
        .from('covers')
        .upload(
          path,
          file,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: mime ?? _mimeFor(file.path),
            upsert: false,
          ),
        );
    final url = _db.storage.from('covers').getPublicUrl(path);
    await updateProfile(bannerUrl: url);
    return url;
  }

  /// Alterna o estado de "seguir" e retorna o novo estado. Não segue a si
  /// mesmo. Usa a tabela `follows` (RLS: só o dono insere/exclui).
  Future<bool> toggleFollow(String userId) async {
    if (userId.isEmpty || userId == myId) return false;
    final wasFollowing = await isFollowing(userId);
    if (wasFollowing) {
      await ContentService.instance.unfollowUser(userId);
      return false;
    }
    await ContentService.instance.followUser(userId);
    return true;
  }

  Future<bool> isFollowing(String userId) async {
    final me = myId;
    if (!_configured || me == null || me == userId) return false;
    try {
      return await ContentService.instance.isFollowing(userId);
    } catch (_) {
      return false;
    }
  }

  /// Perfil sintético para o modo demo (Supabase desligado) a partir da
  /// identidade global [`kAppIdentity`].
  UserProfile offlineProfile(String userId) {
    return UserProfile(
      id: userId,
      username: kAppIdentity.username.replaceFirst(RegExp(r'^@'), ''),
      displayName: kAppIdentity.displayName,
      avatarUrl: kAppIdentity.avatarUrl,
      isSelf: userId.isNotEmpty && userId == myId,
    );
  }

  // ---------------------------------------------------------------------------
  // Fallbacks
  // ---------------------------------------------------------------------------

  /// Degradação para o modo demo (Supabase desligado): perfil sintético.
  UserProfile _offlineProfile(String userId) => offlineProfile(userId);

  /// Fallback quando a RPC `get_profile` não existe (migration pendente).
  Future<UserProfile?> _legacyProfile(String userId) async {
    try {
      final creator = await ContentService.instance.fetchCreatorProfile(userId);
      return UserProfile(
        id: creator.id,
        username: creator.username,
        displayName: creator.displayName,
        avatarUrl: creator.avatarUrl,
        bio: creator.bio,
        followersCount: creator.followersCount,
        followingCount: creator.followingCount,
        postsCount: creator.postsCount,
        totalLikes: creator.totalLikes,
        isFollowing: creator.isFollowing,
        isSelf: creator.isSelf,
      );
    } catch (_) {
      final cached = await SupabaseService.instance.profileFor(userId);
      if (cached != null) {
        return UserProfile(
          id: userId,
          username: cached['username']?.toString(),
          displayName: cached['display_name']?.toString(),
          avatarUrl: cached['avatar_url']?.toString(),
          isSelf: userId == myId,
        );
      }
      return _offlineProfile(userId);
    }
  }

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase().replaceAll('heic', 'jpg');
    return ext.isEmpty ? 'jpg' : ext;
  }

  static String _mimeFor(String path) {
    final ext = _ext(path);
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }
}

/// Erro de validação amigável do sistema de perfil.
class ProfileValidationException implements Exception {
  final String message;
  const ProfileValidationException(this.message);

  @override
  String toString() => message;
}
