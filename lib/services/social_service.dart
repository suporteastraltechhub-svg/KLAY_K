import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_models.dart';
import '../models/rising_creator_models.dart';
import 'supabase_service.dart';

/// Resumo de resultado de busca (usuário ou vídeo ou hashtag ou live).
class SearchResult {
  final String type; // user | post | hashtag | live
  final String id;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final bool isVerified;

  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.avatarUrl,
    this.isVerified = false,
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'avatar': avatarUrl,
      };
}

/// Hashtag em tendência com a contagem real de posts.
class HashtagTrend {
  final String tag;
  final int count;

  const HashtagTrend({required this.tag, required this.count});
}

/// Coleção/favorito do usuário.
class CollectionItem {
  final String id;
  final String name;
  final String description;
  final String? coverUrl;
  final bool isPublic;
  final DateTime createdAt;

  const CollectionItem({
    required this.id,
    required this.name,
    this.description = '',
    this.coverUrl,
    this.isPublic = false,
    required this.createdAt,
  });

  factory CollectionItem.fromJson(Map<String, dynamic> json) => CollectionItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        coverUrl: json['cover_url'] as String?,
        isPublic: json['is_public'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}

/// Estatísticas agregadas do criador (painel do criador).
class CreatorStats {
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final int totalLikes;
  final int totalComments;
  final int totalViews;
  final int totalLiveViews;

  const CreatorStats({
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.totalLikes = 0,
    this.totalComments = 0,
    this.totalViews = 0,
    this.totalLiveViews = 0,
  });

  factory CreatorStats.fromJson(Map<String, dynamic> json) => CreatorStats(
        followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
        followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
        postsCount: (json['posts_count'] as num?)?.toInt() ?? 0,
        totalLikes: (json['total_likes'] as num?)?.toInt() ?? 0,
        totalComments: (json['total_comments'] as num?)?.toInt() ?? 0,
        totalViews: (json['total_views'] as num?)?.toInt() ?? 0,
        totalLiveViews: (json['total_live_views'] as num?)?.toInt() ?? 0,
      );
}

/// Conquista (catálogo).
class Achievement {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int xp;
  final String conditionType;
  final int conditionValue;
  final bool unlocked;

  const Achievement({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = '',
    this.xp = 0,
    this.conditionType = 'manual',
    this.conditionValue = 0,
    this.unlocked = false,
  });

  factory Achievement.fromJson(Map<String, dynamic> json, {bool unlocked = false}) =>
      Achievement(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        conditionType: json['condition_type'] as String? ?? 'manual',
        conditionValue: (json['condition_value'] as num?)?.toInt() ?? 0,
        unlocked: unlocked,
      );
}

/// Missão (diária/semanal) com o progresso real do usuário no período.
class MissionProgress {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String frequency;
  final int target;
  final int xpReward;
  final int progress;
  final bool completed;

  const MissionProgress({
    required this.id,
    required this.title,
    this.description = '',
    this.icon = '',
    this.frequency = 'daily',
    this.target = 1,
    this.xpReward = 0,
    this.progress = 0,
    this.completed = false,
  });

  factory MissionProgress.fromJson(Map<String, dynamic> json) =>
      MissionProgress(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        frequency: json['frequency'] as String? ?? 'daily',
        target: (json['target'] as num?)?.toInt() ?? 1,
        xpReward: (json['xp_reward'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        completed: json['completed'] == true,
      );
}

/// Resposta de `my_progress`: nível atual, XP e missões do período.
class LevelProgress {
  final int xpTotal;
  final int level;
  final String levelTitle;
  final int xpLevelStart;
  final int? xpNextLevel;
  final List<MissionProgress> missions;

  const LevelProgress({
    this.xpTotal = 0,
    this.level = 1,
    this.levelTitle = 'Novato',
    this.xpLevelStart = 0,
    this.xpNextLevel,
    this.missions = const [],
  });

  static LevelProgress empty() => const LevelProgress();

  factory LevelProgress.fromJson(Map<String, dynamic> json) {
    final rawMissions = json['missions'];
    final missions = <MissionProgress>[];
    if (rawMissions is List) {
      for (final m in rawMissions) {
        if (m is Map) {
          missions.add(MissionProgress.fromJson(
            Map<String, dynamic>.from(m.map((k, v) => MapEntry(k.toString(), v))),
          ));
        }
      }
    }
    return LevelProgress(
      xpTotal: (json['xp_total'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      levelTitle: json['level_title'] as String? ?? 'Novato',
      xpLevelStart: (json['xp_level_start'] as num?)?.toInt() ?? 0,
      xpNextLevel: (json['xp_next_level'] as num?)?.toInt(),
      missions: missions,
    );
  }

  /// Fração (0..1) do nível atual até o próximo.
  double get levelFraction {
    final next = xpNextLevel;
    if (next == null || next <= xpLevelStart) return 0;
    return ((xpTotal - xpLevelStart) / (next - xpLevelStart)).clamp(0.0, 1.0);
  }

  int get xpToNext {
    final next = xpNextLevel;
    if (next == null) return 0;
    return (next - xpTotal) < 0 ? 0 : (next - xpTotal);
  }
}

/// Entrada do ranking de níveis (RPC `level_ranking`): mais XP total primeiro.
class LevelRankEntry {
  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int level;
  final int xpTotal;
  final bool isVerified;

  const LevelRankEntry({
    required this.rank,
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarUrl,
    this.level = 1,
    this.xpTotal = 0,
    this.isVerified = false,
  });

  String get name =>
      displayName.isNotEmpty ? displayName : (username.isNotEmpty ? username : 'Usuário');

  factory LevelRankEntry.fromJson(Map<String, dynamic> json) => LevelRankEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: json['user_id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString(),
        level: (json['level'] as num?)?.toInt() ?? 1,
        xpTotal: (json['xp_total'] as num?)?.toInt() ?? 0,
        isVerified: json['is_verified'] == true,
      );
}

/// Entrada do ranking de missões (RPC `mission_ranking`): XP de missões primeiro.
class MissionRankEntry {
  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int missionsDone;
  final int xpMission;
  final bool isVerified;

  const MissionRankEntry({
    required this.rank,
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarUrl,
    this.missionsDone = 0,
    this.xpMission = 0,
    this.isVerified = false,
  });

  String get name =>
      displayName.isNotEmpty ? displayName : (username.isNotEmpty ? username : 'Usuário');

  factory MissionRankEntry.fromJson(Map<String, dynamic> json) =>
      MissionRankEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: json['user_id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString(),
        missionsDone: (json['missions_done'] as num?)?.toInt() ?? 0,
        xpMission: (json['xp_mission'] as num?)?.toInt() ?? 0,
        isVerified: json['is_verified'] == true,
      );
}

/// Serviço social do KLAY K: busca, notificações, coleções, histórico,
/// denúncia/bloqueio/silêncio, moderação de live, anti-spam, painel do criador
/// e conquistas. Tudo persiste no Supabase via RLS (sem mocks).
class SocialService {
  SocialService._();

  static final SocialService instance = SocialService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // Busca
  // ---------------------------------------------------------------------------

  /// Busca combinada: usuários, vídeos (posts), hashtags e lives.
  /// `scope` limita: 'all' | 'user' | 'post' | 'hashtag' | 'live'.
  Future<List<SearchResult>> search(String query, {String scope = 'all'}) async {
    if (query.trim().isEmpty) return const [];
    final q = query.trim().toLowerCase();
    final out = <SearchResult>[];

    if (scope == 'all' || scope == 'user') {
      try {
        final res = await _db
            .from('profiles')
            .select('id, username, display_name, avatar_url, is_verified')
            .or('username.ilike.%$q%,display_name.ilike.%$q%')
            .limit(20);
        for (final row in (res as List).whereType<Map>()) {
          final m = Map<String, dynamic>.from(row);
          out.add(SearchResult(
            type: 'user',
            id: m['id']?.toString() ?? '',
            title: m['display_name']?.toString() ??
                m['username']?.toString() ??
                'Usuário',
            subtitle: m['username']?.toString() ?? '',
            avatarUrl: m['avatar_url']?.toString(),
            isVerified: m['is_verified'] == true,
          ));
        }
      } catch (_) {}
    }

    if (scope == 'all' || scope == 'post') {
      try {
        final isHashtagQuery = q.startsWith('#');
        final hq = q.replaceAll('#', '').trim();
        if (isHashtagQuery && hq.isNotEmpty) {
          final res = await _db
              .from('posts')
              .select('id, description, video_url, cover_url')
              .contains('hashtags', [hq])
              .limit(20);
          for (final row in (res as List).whereType<Map>()) {
            final m = Map<String, dynamic>.from(row);
            out.add(SearchResult(
              type: 'post',
              id: m['id']?.toString() ?? '',
              title: m['description']?.toString() ?? 'Vídeo',
              subtitle: 'Vídeo',
              avatarUrl: m['cover_url']?.toString(),
            ));
          }
        } else {
          final res = await _db
              .from('posts')
              .select('id, description, video_url, cover_url')
              .ilike('description', '%$q%')
              .limit(20);
          for (final row in (res as List).whereType<Map>()) {
            final m = Map<String, dynamic>.from(row);
            out.add(SearchResult(
              type: 'post',
              id: m['id']?.toString() ?? '',
              title: m['description']?.toString() ?? 'Vídeo',
              subtitle: 'Vídeo',
              avatarUrl: m['cover_url']?.toString(),
            ));
          }
        }
      } catch (_) {}
    }

    if (scope == 'all' || scope == 'hashtag') {
      // Hashtags: extrai de posts via um termos ilike simples.
      // Ignora o '#': a coluna posts.hashtags guarda as tags sem o prefixo.
      final hq = q.replaceAll('#', '').trim();
      try {
        final res = await _db
            .from('posts')
            .select('hashtags')
            .limit(300);
        final seen = <String>{};
        for (final row in (res as List).whereType<Map>()) {
          final tags = row['hashtags'];
          if (tags is List) {
            for (final tag in tags.whereType<String>()) {
              final lower = tag.toLowerCase();
              if (lower.contains(hq) && seen.add(lower)) {
                out.add(SearchResult(
                  type: 'hashtag',
                  id: lower,
                  title: '#$lower',
                  subtitle: 'Hashtag',
                ));
              }
            }
          }
        }
      } catch (_) {}
    }

    if (scope == 'all' || scope == 'live') {
      try {
        final res = await _db
            .from('lives')
            .select('id, title, streamer_id, status')
            .or('title.ilike.%$q%,description.ilike.%$q%')
            .eq('status', 'live')
            .limit(10);
        for (final row in (res as List).whereType<Map>()) {
          final m = Map<String, dynamic>.from(row);
          out.add(SearchResult(
            type: 'live',
            id: m['id']?.toString() ?? '',
            title: m['title']?.toString() ?? 'Live',
            subtitle: 'Ao vivo',
          ));
        }
      } catch (_) {}
    }

    return out;
  }

  // ---------------------------------------------------------------------------
  // Histórico de buscas + tendências (backend real)
  // ---------------------------------------------------------------------------

  /// Persiste o termo no histórico do usuário (upsert + touched_at).
  Future<void> recordSearch(String query, {String resultType = 'all'}) async {
    if (query.trim().isEmpty) return;
    try {
      await _db.rpc('record_search', params: {
        'p_query': query.trim(),
        'p_type': resultType,
      });
    } catch (_) {}
  }

  /// Retorna os termos mais recentes pesquisados pelo usuário.
  Future<List<String>> fetchSearchHistory({int limit = 12}) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('search_history')
          .select('query')
          .eq('user_id', user.id)
          .order('touched_at', ascending: false)
          .limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => r['query']?.toString() ?? '')
          .where((q) => q.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Limpa o histórico de buscas do usuário.
  Future<void> clearSearchHistory() async {
    try {
      await _db.rpc('clear_search_history');
    } catch (_) {}
  }

  /// Hashtags mais usadas nos posts (contagem real).
  Future<List<HashtagTrend>> trendingHashtags({int limit = 20}) async {
    try {
      final res = await _db.rpc('trending_hashtags', params: {'p_limit': limit});
      final list = res as List;
      return list
          .whereType<Map>()
          .map((r) => HashtagTrend(
                tag: r['tag']?.toString() ?? '',
                count: (r['cnt'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Coleções / favoritos
  // ---------------------------------------------------------------------------

  Future<List<CollectionItem>> fetchCollections() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('collections')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (res as List)
        .whereType<Map>()
        .map((r) => CollectionItem.fromJson(
              Map<String, dynamic>.from(
                r.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ))
        .toList();
  }

  Future<CollectionItem> createCollection(
    String name, {
    String description = '',
    bool isPublic = false,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('collections')
        .insert({
          'user_id': user.id,
          'name': name,
          'description': description,
          'is_public': isPublic,
        })
        .select()
        .single();
    return CollectionItem.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> deleteCollection(String id) async {
    await _db.from('collections').delete().eq('id', id);
  }

  Future<void> addPostToCollection(String collectionId, String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('collection_posts').insert({
        'collection_id': collectionId,
        'post_id': postId,
        'user_id': user.id,
      }).then((_) {});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  /// Retorna os posts dentro de uma coleção do usuário (detalhe da coleção).
  Future<List<Map<String, dynamic>>> fetchCollectionPosts(
    String collectionId,
  ) async {
    final ids = await _collectionPostIds(collectionId);
    if (ids.isEmpty) return const [];
    final res = await _db
        .from('posts')
        .select('*, profiles:user_id(display_name, username, avatar_url)')
        .inFilter('id', ids);
    return (res as List)
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  Future<List<String>> _collectionPostIds(String collectionId) async {
    try {
      final res = await _db
          .from('collection_posts')
          .select('post_id')
          .eq('collection_id', collectionId);
      return (res as List)
          .whereType<Map>()
          .map((r) => r['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Histórico
  // ---------------------------------------------------------------------------

  Future<void> recordHistory({
    String? postId,
    String? liveId,
    String refType = 'post',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      // upsert com a mesma chave (user_id, post_id, live_id, ref_type)
      await _db.from('user_history').upsert({
        'user_id': user.id,
        'post_id': postId,
        'live_id': liveId,
        'ref_type': refType,
        'watched_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id, post_id, live_id, ref_type');
      await _bumpStat('total_views');
    } catch (_) {}
  }

  Future<List<FeedPost>> fetchHistory() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('user_history')
        .select('post_id')
        .eq('user_id', user.id)
        .eq('ref_type', 'post')
        .order('watched_at', ascending: false)
        .limit(50);
    final postIds = (res as List)
        .whereType<Map>()
        .map((r) => r['post_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (postIds.isEmpty) return const [];
    final posts = await _db
        .from('posts')
        .select('*, profiles:user_id(display_name, username, avatar_url)')
        .inFilter('id', postIds);
    return (posts as List)
        .whereType<Map>()
        .map((row) => FeedPost.fromJson(
              Map<String, dynamic>.from(
                row.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ))
        .toList()
      ..sort((a, b) => postIds.indexOf(a.id).compareTo(postIds.indexOf(b.id)));
  }

  Future<void> clearHistory() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db.from('user_history').delete().eq('user_id', user.id);
  }

  // ---------------------------------------------------------------------------
  // Denúncia / bloqueio / silêncio
  // ---------------------------------------------------------------------------

  Future<void> reportItem({
    required String targetId,
    required String targetType,
    required String reason,
    String details = '',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db.from('reports').insert({
      'reporter_id': user.id,
      'target_id': targetId,
      'target_type': targetType,
      'reason': reason,
      'details': details,
    });
  }

  Future<bool> isMuted(String userId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('muted_users')
        .select('muted_id')
        .eq('muter_id', user.id)
        .eq('muted_id', userId)
        .maybeSingle();
    return res != null;
  }

  Future<void> muteUser(String userId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('muted_users').insert({
        'muter_id': user.id,
        'muted_id': userId,
      }).then((_) {});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> unmuteUser(String userId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('muted_users')
        .delete()
        .eq('muter_id', user.id)
        .eq('muted_id', userId);
  }

  // ---------------------------------------------------------------------------
  // Moderação de LIVE
  // ---------------------------------------------------------------------------

  Future<bool> isLiveModerator(String liveId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('live_moderators')
          .select('moderator_id')
          .eq('live_id', liveId)
          .eq('moderator_id', user.id)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> addLiveModerator(String liveId, String moderatorId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db.from('live_moderators').insert({
      'live_id': liveId,
      'moderator_id': moderatorId,
      'added_by': user.id,
    });
  }

  Future<void> removeLiveModerator(String liveId, String moderatorId) async {
    await _db
        .from('live_moderators')
        .delete()
        .eq('live_id', liveId)
        .eq('moderator_id', moderatorId);
  }

  /// Ação de moderação (excluir mensagem de chat/comentário).
  Future<void> logModerationAction({
    String? liveId,
    String? postId,
    String? commentId,
    required String action,
    String reason = '',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('moderation_actions').insert({
        'live_id': liveId,
        'post_id': postId,
        'comment_id': commentId,
        'actor_id': user.id,
        'action': action,
        'reason': reason,
      }).then((_) {});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Anti-spam
  // ---------------------------------------------------------------------------

  /// Carrega regras anti-spam ativas para aplicar filtro local.
  Future<List<String>> loadSpamRules({String scope = 'all'}) async {
    try {
      var query = _db
          .from('anti_spam_rules')
          .select('pattern')
          .eq('active', true);
      if (scope != 'all') query = query.eq('scope', scope);
      final res = await query;
      return (res as List)
          .whereType<Map>()
          .map((r) => (r['pattern']?.toString() ?? '').toLowerCase())
          .where((p) => p.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Verifica se uma mensagem viola as regras anti-spam.
  bool isSpam(String message, List<String> rules) {
    final lower = message.toLowerCase();
    return rules.any((r) => lower.contains(r));
  }

  // ---------------------------------------------------------------------------
  // Moderação de LIVE persistida (ban/silêncio) + painel administrativo
  // ---------------------------------------------------------------------------

  bool _isLiveUuid(String id) {
    final s = id.replaceAll('-', '');
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(s);
  }

  Future<void> liveModBan(String liveId, String userId, {String reason = ''}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('live_mod_ban', params: {
        'p_live_id': liveId,
        'p_user_id': userId,
        'p_reason': reason,
      });
    } catch (_) {}
  }

  Future<void> liveModUnban(String liveId, String userId) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('live_mod_unban', params: {
        'p_live_id': liveId,
        'p_user_id': userId,
      });
    } catch (_) {}
  }

  Future<void> liveModMute(
    String liveId,
    String userId, {
    int minutes = 10,
    String reason = '',
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('live_mod_mute', params: {
        'p_live_id': liveId,
        'p_user_id': userId,
        'p_minutes': minutes,
        'p_reason': reason,
      });
    } catch (_) {}
  }

  Future<void> liveModUnmute(String liveId, String userId) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('live_mod_unmute', params: {
        'p_live_id': liveId,
        'p_user_id': userId,
      });
    } catch (_) {}
  }

  /// Usuários banidos atualmente de uma live (todos os participantes veem).
  Future<Set<String>> fetchLiveBannedIds(String liveId) async {
    try {
      if (!_isLiveUuid(liveId)) return {};
      final res = await _db
          .from('live_bans')
          .select('user_id')
          .eq('live_id', liveId);
      return (res as List)
          .whereType<Map>()
          .map((r) => r['user_id']?.toString() ?? '')
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Usuários silenciados (não expirados) numa live.
  Future<Set<String>> fetchLiveMutedIds(String liveId) async {
    try {
      if (!_isLiveUuid(liveId)) return {};
      final res = await _db
          .from('live_mutes')
          .select('user_id')
          .eq('live_id', liveId)
          .or('until.is.null,until.gte.now');
      return (res as List)
          .whereType<Map>()
          .map((r) => r['user_id']?.toString() ?? '')
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// O usuário atual é administrador do KLAY K?
  Future<bool> isAdmin() async {
    try {
      final me = SupabaseService.instance.client.auth.currentUser?.id;
      if (me == null) return false;
      final res = await _db
          .from('profiles')
          .select('is_admin')
          .eq('id', me)
          .maybeSingle();
      return res?['is_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Denúncias (painel administrativo; falha se não for admin).
  Future<List<Map<String, dynamic>>> modListReports({String? status}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .rpc('mod_list_reports', params: {'p_status': status});
      return List<Map<String, dynamic>>.from(
        (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> modUpdateReport(
    String reportId,
    String status, {
    String note = '',
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('mod_update_report', params: {
        'p_report_id': reportId,
        'p_status': status,
        'p_note': note,
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> modListSpamRules() async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('mod_list_spam_rules', params: {});
      return List<Map<String, dynamic>>.from(
        (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> modAddSpamRule(
    String pattern, {
    String ruleType = 'block',
    String scope = 'all',
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('mod_add_spam_rule', params: {
        'p_pattern': pattern,
        'p_rule_type': ruleType,
        'p_scope': scope,
      });
    } catch (_) {}
  }

  Future<void> modRemoveSpamRule(String ruleId) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.rpc('mod_remove_spam_rule', params: {'p_rule_id': ruleId});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Painel do criador (estatísticas)
  // ---------------------------------------------------------------------------

  Future<CreatorStats> fetchCreatorStats({bool recompute = true}) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    if (recompute) {
      await _recomputeStats(user.id);
    }
    try {
      final res = await _db
          .from('user_stats')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (res != null) {
        return CreatorStats.fromJson(Map<String, dynamic>.from(res as Map));
      }
    } catch (_) {}
    return const CreatorStats();
  }

  Future<void> _recomputeStats(String userId) async {
    try {
      final followers = await _db
          .from('follows')
          .select('id')
          .eq('following_id', userId);
      final following = await _db
          .from('follows')
          .select('id')
          .eq('follower_id', userId);
      final posts = await _db.from('posts').select('likes_count, comments_count').eq('user_id', userId);
      final views = await _db
          .from('user_history')
          .select('id')
          .eq('ref_type', 'post');

      var totalLikes = 0, totalComments = 0;
      for (final row in (posts as List).whereType<Map>()) {
        totalLikes += (row['likes_count'] as num?)?.toInt() ?? 0;
        totalComments += (row['comments_count'] as num?)?.toInt() ?? 0;
      }

      final row = {
        'user_id': userId,
        'followers_count': (followers as List).length,
        'following_count': (following as List).length,
        'posts_count': (posts as List).length,
        'total_likes': totalLikes,
        'total_comments': totalComments,
        'total_views': (views as List).length,
        'total_live_views': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _db.from('user_stats').upsert(row, onConflict: 'user_id');
    } catch (_) {}
  }

  Future<void> _bumpStat(String field) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _db
          .from('user_stats')
          .select(field)
          .eq('user_id', user.id)
          .maybeSingle();
      final cur = res == null ? 0 : (res[field] as num?)?.toInt() ?? 0;
      await _db.from('user_stats').upsert({
        'user_id': user.id,
        field: cur + 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {
      await _recomputeStats(user.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Conquistas e níveis
  // ---------------------------------------------------------------------------

  Future<List<Achievement>> fetchAchievements() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final unlockedRes = await _db
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', user.id);
      final unlocked = (unlockedRes as List)
          .whereType<Map>()
          .map((r) => r['achievement_id']?.toString() ?? '')
          .toSet();
      final res = await _db.from('achievements').select().order('xp', ascending: true);
      return (res as List)
          .whereType<Map>()
          .map((row) => Achievement.fromJson(
                Map<String, dynamic>.from(
                  row.map((k, v) => MapEntry(k.toString(), v)),
                ),
                unlocked: unlocked.contains(row['id']?.toString()),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

/// Concede uma conquista quando a condição é atendida (idempotente).
  Future<void> unlockAchievement(String achievementId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('user_achievements').insert({
        'user_id': user.id,
        'achievement_id': achievementId,
      }).then((_) {});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Níveis / XP / Missões (calculados e validados no backend)
  // ---------------------------------------------------------------------------

  /// Progresso completo (nível, XP total, barra até próximo nível e missões
  /// do período atual) via RPC `my_progress` (security definer).
  Future<LevelProgress> fetchMyProgress() async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('my_progress', params: {});
      return LevelProgress.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return LevelProgress.empty();
    }
  }

  /// Ranking de níveis (mais XP total primeiro) via RPC `level_ranking`.
  Future<List<LevelRankEntry>> fetchLevelRanking({int limit = 20}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('level_ranking', params: {'p_limit': limit});
      return (res as List)
          .whereType<Map>()
          .map((r) => LevelRankEntry.fromJson(
                Map<String, dynamic>.from(
                  r.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Ranking de missões (XP de missões primeiro) via RPC `mission_ranking`.
  Future<List<MissionRankEntry>> fetchMissionRanking({int limit = 20}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('mission_ranking', params: {'p_limit': limit});
      return (res as List)
          .whereType<Map>()
          .map((r) => MissionRankEntry.fromJson(
                Map<String, dynamic>.from(
                  r.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Criadores em ascensão (maior momentum nos últimos 7 dias) via RPC
  /// `rising_creators`, com o perfil do criador embutido.
  Future<List<RisingCreator>> fetchRisingCreators({int limit = 20}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('rising_creators', params: {'p_limit': limit});
      final rows = res as List? ?? const [];
      final creatorIds = rows.whereType<Map>()
          .map((r) => r['creator_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      Map<String, Map<String, dynamic>> profiles = const {};
      if (creatorIds.isNotEmpty) {
        final pRes = await _db
            .from('profiles')
            .select('id, display_name, username, avatar_url, is_verified')
            .inFilter('id', creatorIds);
        profiles = {
          for (final p in (pRes as List? ?? const []).whereType<Map>())
            (p['id']?.toString() ?? ''): Map<String, dynamic>.from(
              p.map((k, v) => MapEntry(k.toString(), v)),
            ),
        };
      }
      return rows.whereType<Map>().map((r) {
        final id = r['creator_id']?.toString() ?? '';
        final enriched = Map<String, dynamic>.from(
          r.map((k, v) => MapEntry(k.toString(), v)),
        );
        enriched['profiles'] = profiles[id] ?? const {};
        return RisingCreator.fromJson(enriched);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Nível calculado a partir do XP total das conquistas do usuário.
  Future<int> fetchLevel() async {
    try {
      final unlocked = await _db
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', _db.auth.currentUser?.id ?? '');
      final ids = (unlocked as List)
          .whereType<Map>()
          .map((r) => r['achievement_id']?.toString() ?? '')
          .toList();
      if (ids.isEmpty) return 1;
      final res = await _db.from('achievements').select('xp').inFilter('id', ids);
      var xp = 0;
      for (final row in (res as List).whereType<Map>()) {
        xp += (row['xp'] as num?)?.toInt() ?? 0;
      }
      // 100 XP por nível
      return (xp ~/ 100) + 1;
    } catch (_) {
      return 1;
    }
  }
}
