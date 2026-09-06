import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_models.dart';
import 'app_config.dart';
import 'storage_upload.dart';
import 'supabase_service.dart';

/// Camada de acesso ao conteúdo real do KLAY K (feed, upload, curtidas,
/// comentários, salvos, seguidores, notificações e perfil). Não há mocks aqui:
/// todas as operações persistem no Supabase.
class ContentService {
  ContentService._();

  static final ContentService instance = ContentService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // Feed / posts
  // ---------------------------------------------------------------------------

  /// Busca os posts mais recentes do feed. Opcionalmente restringe ao autor
  /// `userId` (perfil do criador / "meus vídeos"). Se `onlyFollowing` for true,
  /// retorna apenas posts de pessoas que o usuário segue. `offset` permite
  /// paginação por rolamento (feed infinito).
  Future<List<FeedPost>> fetchFeed({
    String? userId,
    bool onlyFollowing = false,
    int limit = 50,
    int? offset,
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    final me = _db.auth.currentUser?.id;

    final base = _db.from('posts').select(
      '*, profiles:user_id(display_name, username, avatar_url, is_verified)',
    );
    final filtered = userId != null ? base.eq('user_id', userId) : base;
    final ordered = filtered.order('created_at', ascending: false);
    final rows = await (offset != null && offset > 0
        ? ordered.range(offset, offset + limit - 1)
        : ordered.limit(limit));
    final posts = <FeedPost>[];

    // Recolhe os ids para consultar likes/saves do usuário atual em lote.
    final ids = rows
        .whereType<Map>()
        .map((r) => r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    Set<String> likedIds = {};
    Set<String> savedIds = {};
    Set<String> followingIds = {};
    if (me != null && ids.isNotEmpty) {
      try {
        final likeRes = await _db
            .from('post_likes')
            .select('post_id')
            .eq('user_id', me)
            .inFilter('post_id', ids);
        likedIds = (likeRes as List)
            .whereType<Map>()
            .map((r) => r['post_id']?.toString() ?? '')
            .toSet();
      } catch (_) {}

      try {
        final savedRes = await _db
            .from('saved_posts')
            .select('post_id')
            .eq('user_id', me);
        savedIds = (savedRes as List)
            .whereType<Map>()
            .map((r) => r['post_id']?.toString() ?? '')
            .toSet();
      } catch (_) {}

      if (onlyFollowing) {
        try {
          final followRes = await _db
              .from('follows')
              .select('following_id')
              .eq('follower_id', me);
          followingIds = (followRes as List)
              .whereType<Map>()
              .map((r) => r['following_id']?.toString() ?? '')
              .toSet();
        } catch (_) {}
      }
    }

    for (final row in rows.whereType<Map>()) {
      final m = Map<String, dynamic>.from(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      final post = FeedPost.fromJson(
        m,
        liked: likedIds.contains(m['id']),
        saved: savedIds.contains(m['id']),
        following: followingIds.contains(m['user_id']),
      );
      posts.add(post);
    }

    if (onlyFollowing) {
      return posts.where((p) => followingIds.contains(p.userId)).toList();
    }
    return posts;
  }

  /// Busca os posts de um usuário (perfil do criador / meus vídeos).
  Future<List<FeedPost>> fetchPostsByUser(String userId) =>
      fetchFeed(userId: userId);

  /// Vídeos CURTIDOS pelo usuário atual (aba Curtidos do perfil). Consulta de
  /// dados reais de `post_likes` → `posts`; nunca inventa. Vazio se sem conta/
  /// sem curtidas/offline.
  Future<List<FeedPost>> fetchLikedPosts({int limit = 60}) =>
      _fetchPostsByRelation('post_likes', 'post_id', limit, liked: true);

  /// Vídeos SALVOS pelo usuário atual (aba Salvos do perfil). Consulta real de
  /// `saved_posts` → `posts`; nunca inventa. Vazio se sem conta/sem saves.
  Future<List<FeedPost>> fetchSavedPosts({int limit = 60}) =>
      _fetchPostsByRelation('saved_posts', 'post_id', limit, saved: true);

  /// Base comum das abas Curtidos/Salvos: pega os ids da tabela de relação,
  /// busca os posts em lote e marca o estado do usuário conforme a origem.
  Future<List<FeedPost>> _fetchPostsByRelation(
    String table,
    String idColumn,
    int limit, {
    bool liked = false,
    bool saved = false,
  }) async {
    if (!SupabaseService.instance.isConfigured) return const <FeedPost>[];
    await SupabaseService.instance.ensureAuthenticated();
    final me = _db.auth.currentUser?.id;
    if (me == null) return const <FeedPost>[];

    List<String> ids;
    try {
      final res = await _db
          .from(table)
          .select(idColumn)
          .eq('user_id', me)
          .order('created_at', ascending: false)
          .limit(limit);
      ids = (res as List)
          .whereType<Map>()
          .map((r) => r[idColumn]?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return const <FeedPost>[];
    }
    if (ids.isEmpty) return const <FeedPost>[];

    try {
      final rows = await _db
          .from('posts')
          .select('*, profiles:user_id(display_name, username, avatar_url, is_verified)')
          .inFilter('id', ids)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.whereType<Map>().map((row) {
        final m = Map<String, dynamic>.from(
          row.map((k, v) => MapEntry(k.toString(), v)),
        );
        return FeedPost.fromJson(m, liked: liked, saved: saved);
      }).toList();
    } catch (_) {
      return const <FeedPost>[];
    }
  }

  /// Conta quantos posts reais usam o áudio [audioName]. Retorna 0 quando
  /// não configurado/sem áudio — nunca inventa dados (substitui demo).
  Future<int> countPostsByAudio(String audioName) async {
    if (audioName.isEmpty) return 0;
    if (!SupabaseService.instance.isConfigured) return 0;
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db
          .from('posts')
          .select('id')
          .eq('audio_name', audioName)
          .limit(500);
      return (res as List?)?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Publicação
  // ---------------------------------------------------------------------------

  /// Faz upload de um arquivo de vídeo no bucket privado `videos` sob o
  /// caminho `{uid}/{arquivo}` (RLS garante que só o dono sobe). Retorna o
  /// caminho do objeto.
  ///
  /// Otimização de fluxo: o envio é feito por STREAM (corpo binário direto,
  /// sem multipart), então o vídeo NUNCA é copiado inteiro para a memória
  /// (`readAsBytesSync`) antes/durante o upload — o gargalo original que
  /// travava e levava minutos em vídeos longos. [onProgress] reporta o
  /// progresso real (0..1) e [isCancelled] aborta o envio imediatamente.
  /// [path] fixa o caminho do objeto (permite reaproveitar um upload já
  /// concluído — nunca reenviar o mesmo vídeo).
  Future<String> uploadVideo(
    File file, {
    String? mime,
    String? path,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final ext = _extensionOf(file.path);
    final objectPath =
        path ?? '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final db = SupabaseService.instance;
    final token = db.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sessão ausente para o upload do vídeo.');
    }
    await streamUploadFile(
      supabaseUrl: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseKey,
      accessToken: token,
      bucket: 'videos',
      objectPath: objectPath,
      file: file,
      contentType: mime ?? 'video/mp4',
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return objectPath;
  }

  /// Remove um objeto já enviado ao bucket `videos` (best-effort). Usado para
  /// limpar o objeto de um vídeo selecionado e nunca publicado (orphan).
  Future<void> removeVideoObject(String videoPath) async {
    if (videoPath.isEmpty) return;
    try {
      await _db.storage.from('videos').remove([videoPath]);
    } catch (_) {
      // Remoção é best-effort: um objeto órfão não quebra nenhum fluxo.
    }
  }

  /// Faz upload de uma capa/imagem no bucket público `covers`. Retorna a URL
  /// pública. `coverExtension` preserva a extensão real do arquivo (a extensão
  /// antiga fixa `.png` distorcia JPEGs/WEBPs); `mime` sobrepõe a derivação
  /// automática por extensão.
  Future<String> uploadCover(
    File file, {
    String? mime,
    String? coverExtension,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final ext = coverExtension != null && coverExtension.trim().isNotEmpty
        ? coverExtension.toLowerCase().replaceFirst(RegExp(r'^\.'), '')
        : 'png';
    final resolvedMime = mime ??
        (ext == 'jpg' || ext == 'jpeg'
            ? 'image/jpeg'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/png');
    final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('covers').upload(
          path,
          file,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: resolvedMime,
            upsert: false,
          ),
        );
    return _db.storage.from('covers').getPublicUrl(path);
  }

  /// Remove um objeto do bucket `covers` (best-effort). Aceita a URL pública
  /// ou o caminho do objeto. Usado para limpar capas órfãs quando a criação
  /// da live falha após o upload.
  Future<void> removeCoverObject(String coverUrlOrPath) async {
    final path = coverPathFromCoverUrl(coverUrlOrPath);
    if (path.isEmpty) return;
    try {
      await _db.storage.from('covers').remove([path]);
    } catch (_) {
      // Remoção é best-effort: um objeto órfão não quebra nenhum fluxo.
    }
  }

  /// Extrai o caminho do objeto a partir da URL pública (ou devolve o caminho
  /// quando já é um caminho `covers/...`).
  static String coverPathFromCoverUrl(String urlOrPath) {
    const marker = '/object/public/covers/';
    final idx = urlOrPath.indexOf(marker);
    if (idx >= 0) return urlOrPath.substring(idx + marker.length);
    if (urlOrPath.startsWith('covers/')) return urlOrPath;
    return '';
  }

  // ---------------------------------------------------------------------------
  // Editar / apagar conteúdo próprio (posts/vídeos e lives)
  // A segurança é validada no backend: os RPCs `security definer` (e as
  // policies RLS de UPDATE/DELETE por-dono) rejeitam qualquer tentativa de
  // editar/apagar conteúdo alheio, mesmo que o cliente não esconda os botões.
  // ---------------------------------------------------------------------------

  /// Edita o próprio vídeo (descrição, hashtags e capa) via RPC backend que
  /// valida posse. Retorna `false` se o backend ainda não tiver o RPC.
  Future<bool> updatePost({
    required String postId,
    required String description,
    List<String> hashtags = const [],
    String? coverUrl,
  }) async {
    try {
      final res = await _db.rpc('update_post', params: {
        'p_post_id': postId,
        'p_description': description,
        'p_hashtags': hashtags,
        'p_cover_url': coverUrl,
      });
      final data = res is Map ? Map<String, dynamic>.from(res) : const {};
      return data['ok'] == true;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' ||
          e.message.toString().contains('404') ||
          e.message.toString().contains('function')) {
        return false;
      }
      rethrow;
    }
  }

  /// Apaga o próprio vídeo: remove os arquivos de vídeo/capa do Storage
  /// (best-effort) e então remove a linha (RPC backend valida a posse; a
  /// cascata limpa curtidas/comentários/salvos).
  Future<void> deletePost(
    String postId, {
    String? videoPath,
    String? coverUrl,
  }) async {
    removeVideoObject(videoPath ?? '');
    removeCoverObject(coverUrl ?? '');
    await _db.rpc('delete_post', params: {'p_post_id': postId});
  }

  /// Edita a própria live (título, descrição, categoria, privacidade e capa)
  /// via RPC backend que valida posse. Retorna `false` se o RPC não existir.
  Future<bool> updateLive({
    required String liveId,
    required String title,
    String description = '',
    String category = '',
    String privacy = 'public',
    String? coverUrl,
  }) async {
    try {
      final res = await _db.rpc('update_live', params: {
        'p_live_id': liveId,
        'p_title': title,
        'p_description': description,
        'p_category': category,
        'p_privacy': privacy,
        'p_cover_url': coverUrl,
      });
      final data = res is Map ? Map<String, dynamic>.from(res) : const {};
      return data['ok'] == true;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' ||
          e.message.toString().contains('404') ||
          e.message.toString().contains('function')) {
        return false;
      }
      rethrow;
    }
  }

  /// Apaga a própria live: remove a capa do Storage (se houver, best-effort) e
  /// remove a linha (RPC backend valida a posse; a cascata limpa participantes/
  /// chat/presentes/eventos).
  Future<void> deleteLive(
    String liveId, {
    String? coverUrl,
  }) async {
    removeCoverObject(coverUrl ?? '');
    await _db.rpc('delete_live', params: {'p_live_id': liveId});
  }

  /// Cria um post de vídeo na tabela `public.posts`.
  Future<FeedPost> createPost({
    required String videoPath,
    String? coverUrl,
    String description = '',
    String? audioName,
    List<String> hashtags = const [],
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('posts')
        .insert({
          'user_id': user.id,
          'video_url': videoPath,
          if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
          'description': description,
          if (audioName != null && audioName.isNotEmpty) 'audio_name': audioName,
          'hashtags': hashtags,
        })
        .select()
        .single();
    return FeedPost.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Obtém a URL assinada (1h) de um vídeo privado via Edge Function
  /// `signed-url`. Necessário para reproduzir vídeos do feed.
  Future<String> signedVideoUrl(String path) async {
    final res = await SupabaseService.instance.invoke('signed-url', body: {
      'bucket': 'videos',
      'path': path,
    });
    final url = res['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Não foi possível gerar a URL assinada do vídeo.');
    }
    return url;
  }

  /// Se o vídeo for público (URL http/https) retorna direto; caso contrário
  /// resolve a URL assinada. Útil para `VideoPlayerController.networkUrl`.
  Future<String> resolveVideoUrl(FeedPost post) async {
    final url = post.videoUrl;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (url.contains('/storage/v1/object/public/')) return url;
      // Pode já ser uma URL assinada ou um link externo de demonstração.
      return url;
    }
    return signedVideoUrl(url);
  }

  // ---------------------------------------------------------------------------
  // Curtidas
  // ---------------------------------------------------------------------------

  Future<void> likePost(String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final owner = await _postOwner(postId);
    try {
      await _db.from('post_likes').insert({
        'post_id': postId,
        'user_id': user.id,
      }).then((_) {});
      if (owner != null && owner != user.id) {
        await notify(
          toUserId: owner,
          actorId: user.id,
          type: 'like',
          refId: postId,
          message: '',
        );
      }
    } on PostgrestException catch (e) {
      // 23505 = já curtiu; ignora.
      if (e.code != '23505') rethrow;
    }
  }

  Future<String?> _postOwner(String postId) async {
    try {
      final res = await _db.from('posts').select('user_id').eq('id', postId).maybeSingle();
      return res?['user_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> unlikePost(String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', user.id);
  }

  // ---------------------------------------------------------------------------
  // Comentários
  // ---------------------------------------------------------------------------

  Future<List<PostComment>> fetchComments(String postId) async {
    final res = await _db
        .from('comments')
        .select('*, profiles:user_id(display_name, username, avatar_url, is_verified)')
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(200);
    return res
        .whereType<Map>()
        .map((row) => PostComment.fromJson(
              Map<String, dynamic>.from(
                row.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ))
        .toList();
  }

  Future<PostComment> addComment(
    String postId,
    String text, {
    String? parentId,
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final owner = await _postOwner(postId);
    final res = await _db
        .from('comments')
        .insert({
          'post_id': postId,
          'user_id': user.id,
          if (parentId != null) 'parent_id': parentId,
          'text': text,
        })
        .select('*, profiles:user_id(display_name, username, avatar_url, is_verified)')
        .single();
    if (owner != null && owner != user.id) {
      await notify(
        toUserId: owner,
        actorId: user.id,
        type: 'comment',
        refId: postId,
        message: text,
      );
    }
    return PostComment.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> deleteComment(String commentId) async {
    await _db.from('comments').delete().eq('id', commentId);
  }

  /// Edita o próprio comentário via RPC `edit_comment` (backend valida posse).
  /// Retorna `false` se a migração/RPC ainda não estiver aplicada no backend.
  Future<bool> editComment(String commentId, String newText) async {
    try {
      final res = await SupabaseService.instance.client
          .rpc('edit_comment', params: {'p_comment_id': commentId, 'p_text': newText});
      final data = res is Map ? Map<String, dynamic>.from(res) : const {};
      return data['ok'] == true && data['id'] != null;
    } on PostgrestException catch (e) {
      final msg = e.message.toString();
      if (e.code == 'PGRST202' ||
          msg.contains('404') ||
          msg.contains('function')) {
        return false;
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Salvar posts
  // ---------------------------------------------------------------------------

  Future<void> savePost(String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('saved_posts').insert({
        'post_id': postId,
        'user_id': user.id,
      }).then((_) {});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> unsavePost(String postId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('saved_posts')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', user.id);
  }

  // ---------------------------------------------------------------------------
  // Seguidores
  // ---------------------------------------------------------------------------

  Future<void> followUser(String followingId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    try {
      await _db.from('follows').insert({
        'follower_id': user.id,
        'following_id': followingId,
      }).then((_) {});
      if (followingId != user.id) {
        await notify(
          toUserId: followingId,
          actorId: user.id,
          type: 'follow',
          message: '',
        );
      }
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> unfollowUser(String followingId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('follows')
        .delete()
        .eq('follower_id', user.id)
        .eq('following_id', followingId);
  }

  Future<bool> isFollowing(String userId) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final res = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', user.id)
        .eq('following_id', userId)
        .maybeSingle();
    return res != null;
  }

  // ---------------------------------------------------------------------------
  // Perfis
  // ---------------------------------------------------------------------------

  /// Carrega o perfil detalhado de um criador: dados de `profiles` + totais de
  /// seguidores/seguindo/curtidas/posts + estado de "sigo este usuário".
  Future<CreatorProfile> fetchCreatorProfile(String userId) async {
    final me = _db.auth.currentUser?.id;
    final profile = await SupabaseService.instance.profileFor(userId);

    final followersCount = await _countRows(
      () async =>
          await _db.from('follows').select('id').eq('following_id', userId).count(),
    );
    final followingCount = await _countRows(
      () async =>
          await _db.from('follows').select('id').eq('follower_id', userId).count(),
    );
    final likes = await _db
        .from('posts')
        .select('likes_count')
        .eq('user_id', userId);

    var totalLikes = 0;
    for (final row in (likes as List).whereType<Map>()) {
      totalLikes += (row['likes_count'] as num?)?.toInt() ?? 0;
    }

    var followsCreator = false;
    if (me != null && me != userId) {
      followsCreator = await isFollowing(userId);
    }

    final postsCount = await _countRows(
      () async => await _db.from('posts').select('id').eq('user_id', userId).count(),
    );

    return CreatorProfile(
      id: userId,
      username: profile?['username'] as String?,
      displayName: profile?['display_name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
      bio: profile?['bio'] as String?,
      followersCount: followersCount,
      followingCount: followingCount,
      totalLikes: totalLikes,
      postsCount: postsCount,
      isFollowing: followsCreator,
      isSelf: me == userId,
    );
  }

  /// Executa uma query de contagem e retorna 0 em caso de qualquer erro
  /// (nunca quebra o carregamento do perfil).
  Future<int> _countRows(
    Future<PostgrestResponse<List<Map<String, dynamic>>>> Function() fn,
  ) async {
    try {
      final res = await fn();
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  /// Quantidade de notificações não lidas do usuário atual.
  Future<int> unreadNotificationCount() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return 0;
    try {
      final res = await _db
          .from('notifications')
          .select('id')
          .eq('user_id', me)
          .eq('read', false)
          .count();
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Notificações
  // ---------------------------------------------------------------------------

  Future<List<AppNotification>> fetchNotifications() async {
    await SupabaseService.instance.ensureAuthenticated();
    final me = _db.auth.currentUser?.id;
    if (me == null) return [];
    final res = await _db
        .from('notifications')
        .select('*, actor:actor_id(display_name, username, avatar_url, is_verified)')
        .eq('user_id', me)
        .order('created_at', ascending: false)
        .limit(100);
    return res
        .whereType<Map>()
        .map((row) => AppNotification.fromJson(
              Map<String, dynamic>.from(
                row.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ))
        .toList();
  }

  Future<void> markNotificationsRead() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return;
    await _db
        .from('notifications')
        .update({'read': true})
        .eq('user_id', me)
        .eq('read', false);
  }

  /// Marca uma única notificação como lida (ao tocar nela).
  Future<void> markOneNotificationRead(String id) async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return;
    try {
      await _db
          .from('notifications')
          .update({'read': true})
          .eq('id', id)
          .eq('user_id', me);
    } catch (_) {}
  }

  /// Cria uma notificação para outro usuário (ex.: ao curtir/seguir/comentar).
  /// Insere apenas se o receptor informado existir; nunca explode em falha.
  Future<void> notify({
    required String toUserId,
    String? actorId,
    required String type,
    String? refId,
    String? message,
  }) async {
    if (toUserId.isEmpty) return;
    try {
      await _db.from('notifications').insert({
        'user_id': toUserId,
        'actor_id': actorId,
        'type': type,
        'ref_id': refId,
        'message': message ?? '',
      }).then((_) {});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'mp4';
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'mp4' : ext;
  }
}
