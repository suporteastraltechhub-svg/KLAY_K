import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_models.dart';
import 'supabase_service.dart';

/// Serviço de Comunidades do KLAY K: explorar, criar, entrar/sair, posts,
/// comentários, denúncia e moderação. Tudo persiste no Supabase via RLS.
class CommunityService {
  CommunityService._();

  static final CommunityService instance = CommunityService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // Comunidades (catálogo)
  // ---------------------------------------------------------------------------

  /// Comunidades públicas, ordenadas por mais membros. Opcional: busca/categoria.
  Future<List<Community>> fetchCommunities({
    String? query,
    String? category,
    int limit = 40,
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      var req = _db.from('communities').select('*').eq('is_public', true);
      if (category != null && category.isNotEmpty) {
        req = req.eq('category', category);
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        req = req.or('name.ilike.%$q%,description.ilike.%$q%');
      }
      final res = req.order('member_count', ascending: false).limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => Community.fromJson(
                Map<String, dynamic>.from(
                  r.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Categorias com contagem real de comunidades em cada uma.
  Future<List<CommunityCategory>> fetchCategories() async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('community_categories', params: {});
      return (res as List)
          .whereType<Map>()
          .map((r) => CommunityCategory(
                name: r['category']?.toString() ?? '',
                count: (r['cnt'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Comunidades das quais o usuário atual participa (com a role).
  Future<List<Community>> fetchMyCommunities() async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('community_members')
          .select('community_id')
          .eq('user_id', user.id);
      final ids = (res as List)
          .whereType<Map>()
          .map((r) => r['community_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return const [];
      final communities = await _db
          .from('communities')
          .select('*')
          .inFilter('id', ids)
          .order('member_count', ascending: false);
      return (communities as List)
          .whereType<Map>()
          .map((r) => Community.fromJson(
                Map<String, dynamic>.from(
                  r.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Community?> fetchCommunity(String id) async {
    try {
      final res = await _db
          .from('communities')
          .select('*')
          .eq('id', id)
          .maybeSingle();
      if (res == null) return null;
      return Community.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null;
    }
  }

  /// Cria uma comunidade; o trigger do banco torna o criador admin.
  Future<Community> createCommunity({
    required String name,
    required String slug,
    String description = '',
    String icon = '',
    String category = '',
    String coverUrl = '',
    String rules = '',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('communities')
        .insert({
          'name': name,
          'slug': slug,
          'description': description,
          'icon': icon,
          'category': category,
          'cover_url': coverUrl.isEmpty ? null : coverUrl,
          'rules': rules,
          'created_by': user.id,
        })
        .select()
        .single();
    return Community.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> updateCommunity(
    String id, {
    String? name,
    String? description,
    String? icon,
    String? category,
    String? rules,
  }) async {
    await _db.from('communities').update({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (category != null) 'category': category,
      if (rules != null) 'rules': rules,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteCommunity(String id) async {
    await _db.from('communities').delete().eq('id', id);
  }

  // ---------------------------------------------------------------------------
  // Membros / entrar / sair
  // ---------------------------------------------------------------------------

  /// Papel do usuário atual numa comunidade (admin/moderator/member) ou null.
  Future<CommunityMembership?> myMembership(String communityId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('community_members')
          .select()
          .eq('community_id', communityId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (res == null) return null;
      return CommunityMembership.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> joinCommunity(String communityId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('community_members').insert({
        'community_id': communityId,
        'user_id': user.id,
        'role': 'member',
      }).then((_) {});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> leaveCommunity(String communityId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', user.id);
  }

  /// Lista de membros de uma comunidade (até `limit`, com perfil).
  Future<List<Map<String, dynamic>>> fetchMembers(
    String communityId, {
    int limit = 50,
  }) async {
    try {
      final res = await _db
          .from('community_members')
          .select('user_id, role, joined_at, profiles:user_id(display_name, username, avatar_url)')
          .eq('community_id', communityId)
          .order('joined_at', ascending: true)
          .limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(
                r.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Promove/rebaixa um membro (owner faz moderação). Só permitido p/ admin.
  Future<void> setRole(String communityId, String userId, String role) async {
    await _db
        .from('community_members')
        .update({'role': role})
        .eq('community_id', communityId)
        .eq('user_id', userId);
  }

  Future<void> removeMember(String communityId, String userId) async {
    await _db
        .from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', userId);
  }

  // ---------------------------------------------------------------------------
  // Posts
  // ---------------------------------------------------------------------------

  Future<List<CommunityPost>> fetchPosts(String communityId, {int limit = 50}) async {
    try {
      final res = await _db
          .from('community_posts')
          .select('*, profiles:user_id(display_name, username, avatar_url, is_verified)')
          .eq('community_id', communityId)
          .eq('status', 'published')
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => CommunityPost.fromJson(
                Map<String, dynamic>.from(
                  r.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<CommunityPost> createPost(
    String communityId, {
    required String content,
    String mediaUrl = '',
    String mediaType = '',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('community_posts')
        .insert({
          'community_id': communityId,
          'user_id': user.id,
          'content': content,
          'media_url': mediaUrl.isEmpty ? null : mediaUrl,
          'media_type': mediaType,
        })
        .select('*, profiles:user_id(display_name, username, avatar_url, is_verified)')
        .single();
    return CommunityPost.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> deletePost(String postId) async {
    await _db.from('community_posts').delete().eq('id', postId);
  }

  /// Moderador esconde um post (deixa de aparecer no feed).
  Future<void> hidePost(String postId) async {
    await _db
        .from('community_posts')
        .update({'status': 'hidden'})
        .eq('id', postId);
  }

  Future<void> pinPost(String postId, bool pinned) async {
    await _db
        .from('community_posts')
        .update({'pinned': pinned})
        .eq('id', postId);
  }

  // ---------------------------------------------------------------------------
  // Curtidas / comentários
  // ---------------------------------------------------------------------------

  Future<bool> isPostLiked(String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('community_post_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleLike(String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      final existing = await _db
          .from('community_post_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) {
        await _db.from('community_post_likes').delete().eq('id', existing['id']);
        await _adjustPostCount(postId, 'likes', -1);
        return false;
      }
      await _db.from('community_post_likes').insert({
        'post_id': postId,
        'user_id': user.id,
      }).then((_) {});
      await _adjustPostCount(postId, 'likes', 1);
      return true;
    } on PostgrestException {
      return false;
    }
  }

  Future<List<CommunityComment>> fetchComments(String postId, {int limit = 100}) async {
    try {
      final res = await _db
          .from('community_post_comments')
          .select('*, profiles:user_id(display_name, username, avatar_url)')
          .eq('post_id', postId)
          .order('created_at', ascending: true)
          .limit(limit);
      return (res as List)
          .whereType<Map>()
          .map((r) => CommunityComment.fromJson(
                Map<String, dynamic>.from(
                  r.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<CommunityComment> addComment(String postId, String content) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('community_post_comments')
        .insert({'post_id': postId, 'user_id': user.id, 'content': content})
        .select('*, profiles:user_id(display_name, username, avatar_url)')
        .single();
    await _adjustPostCount(postId, 'comments', 1);
    return CommunityComment.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> deleteComment(String commentId) async {
    await _db.from('community_post_comments').delete().eq('id', commentId);
  }

  Future<void> _adjustPostCount(String postId, String field, int delta) async {
    try {
      final res = await _db
          .from('community_posts')
          .select(field)
          .eq('id', postId)
          .maybeSingle();
      final cur = res == null ? 0 : ((res[field] as num?)?.toInt() ?? 0);
      final next = (cur + delta) < 0 ? 0 : (cur + delta);
      await _db.from('community_posts').update({field: next}).eq('id', postId);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Denúncia
  // ---------------------------------------------------------------------------

  Future<void> reportPost({
    required String communityId,
    required String postId,
    required String reason,
    String details = '',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db.from('community_reports').insert({
      'community_id': communityId,
      'post_id': postId,
      'reporter_id': user.id,
      'reason': reason,
      'details': details,
    });
  }
}