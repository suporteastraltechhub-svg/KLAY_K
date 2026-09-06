import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/playlist_models.dart';
import 'supabase_service.dart';

/// Camada de acesso às Playlists (território Playlists) do KLAY K.
///
/// Centraliza descoberta pública, criação/edição, adição de vídeos e os meus
/// playlists (RPC `my_playlist_ids`). Nada é persistido sem backend real.
class PlaylistService {
  PlaylistService._();

  static final PlaylistService instance = PlaylistService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  bool get _configured => SupabaseService.instance.isConfigured;

  String? get _myId => SupabaseService.instance.currentUser?.id;

  /// Playlists públicas com o perfil do criador embutido, opcionalmente com
  /// busca pelo nome/descrição.
  Future<List<KlayKPlaylist>> fetchPublic({
    String? query,
    int limit = 40,
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      var req = _db
          .from('playlists')
          .select('*, profiles:creator_id(display_name, username, avatar_url, is_verified)')
          .eq('is_public', true);
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        req = req.or('name.ilike.%$q%,description.ilike.%$q%');
      }
      final res = await req.order('created_at', ascending: false).limit(limit);
      return _toPlaylists(res);
    } catch (_) {
      return const [];
    }
  }

  /// Playlists públicas do usuário logado (para o hub "Meu KLAY K").
  Future<List<KlayKPlaylist>> fetchMyPlaylists({int limit = 20}) async {
    final uid = _myId;
    if (!_configured || uid == null || uid.isEmpty) return const [];
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final idsRes = await _db.rpc('my_playlist_ids', params: {});
      final ids = (idsRes as List? ?? const [])
          .whereType<Map>()
          .map((r) => r['playlist_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return const [];
      final res = await _db
          .from('playlists')
          .select('*, profiles:creator_id(display_name, username, avatar_url, is_verified)')
          .inFilter('id', ids)
          .order('created_at', ascending: false)
          .limit(limit);
      return _toPlaylists(res);
    } catch (_) {
      return const [];
    }
  }

  /// Cria uma playlist (sempre como creator_id = usuário logado).
  Future<KlayKPlaylist> create({
    required String name,
    String description = '',
    String coverUrl = '',
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Dê um nome à sua playlist.');
    }
    final res = await _db.from('playlists').insert({
      'creator_id': user.id,
      'name': trimmed,
      'description': description.trim(),
      if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
      'is_public': true,
    }).select('id').single();
    return KlayKPlaylist(
      id: res['id']?.toString() ?? '',
      creatorId: user.id,
      name: trimmed,
      description: description.trim(),
      coverUrl: coverUrl,
      isPublic: true,
      createdAt: DateTime.now(),
      isMine: true,
    );
  }

  /// Adiciona um vídeo do próprio criador à playlist (RLS exige ser o dono).
  Future<void> addPost(String playlistId, String postId) async {
    await SupabaseService.instance.ensureAuthenticated();
    await _db.from('playlist_posts').insert({
      'playlist_id': playlistId,
      'post_id': postId,
    });
  }

  /// Remove um vídeo da playlist.
  Future<void> removePost(String playlistId, String postId) async {
    await SupabaseService.instance.ensureAuthenticated();
    await _db
        .from('playlist_posts')
        .delete()
        .eq('playlist_id', playlistId)
        .eq('post_id', postId);
  }

  /// Exclui uma playlist (somente o dono; RLS protege).
  Future<void> delete(String playlistId) async {
    await SupabaseService.instance.ensureAuthenticated();
    await _db.from('playlists').delete().eq('id', playlistId);
  }

  List<KlayKPlaylist> _toPlaylists(Object? res) {
    final myId = _myId ?? '';
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((r) => KlayKPlaylist.fromJson(
              Map<String, dynamic>.from(r.map((k, v) => MapEntry(k.toString(), v))),
              myId: myId,
            ))
        .toList();
  }
}