import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/playlist_models.dart';
import '../services/playlist_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';

/// Detalhe de uma playlist: lista os vídeos dela (reais) e, se for do dono,
/// permite adicionar vídeos próprios e remover itens.
class PlaylistDetailScreen extends StatefulWidget {
  final KlayKPlaylist playlist;
  final bool ownsIt;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.ownsIt,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final List<_PostRow> _posts = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      if (!SupabaseService.instance.isConfigured) {
        throw Exception('Supabase não configurado');
      }
      await SupabaseService.instance.ensureAuthenticated();

      // Postagens da playlist (reais, via playlist_posts + posts).
      final ppRes = await SupabaseService.instance.client
          .from('playlist_posts')
          .select('id, post_id, position, posts(cover_url, description, created_at)')
          .eq('playlist_id', widget.playlist.id)
          .order('position', ascending: true);
      final rows = ppRes as List? ?? const [];
      final posts = rows.whereType<Map>().map((r) {
        final p = r['posts'];
        final postMap = p is Map
            ? Map<String, dynamic>.from(p.map((k, v) => MapEntry(k.toString(), v)))
            : const <String, dynamic>{};
        return _PostRow(
          playlistPostId: r['id']?.toString() ?? '',
          postId: r['post_id']?.toString() ?? '',
          position: (r['position'] as num?)?.toInt() ?? 0,
          cover: postMap['cover_url']?.toString() ?? '',
          title: postMap['description']?.toString() ?? '',
          createdAt: DateTime.tryParse(postMap['created_at']?.toString() ?? ''),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _remove(_PostRow post) async {
    if (_busy) return;
    setState(() => _busy = true);
    await PlaylistService.instance.removePost(
      widget.playlist.id,
      post.postId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          widget.playlist.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 5)
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Erro ao carregar',
        message: 'Não conseguimos carregar esta playlist. Tentar novamente.',
        actionLabel: 'Tentar novamente',
        actionIcon: Icons.refresh_rounded,
        onAction: _load,
      );
    }
    return Column(
      children: [
        _header(),
        const Divider(color: Color(0xFF2A2540), height: 1),
        const SizedBox(height: 8),
        Expanded(
          child: _posts.isEmpty
              ? KlaykEmptyState(
                  icon: Icons.playlist_play_rounded,
                  title: 'Playlist vazia',
                  message: widget.ownsIt
                      ? 'Você ainda não adicionou vídeos. Os vídeos que você publicar podem ser organizados aqui.'
                      : 'Este criador ainda não adicionou vídeos a esta playlist.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _postCard(_posts[i]),
                ),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.playlist.coverUrl.isEmpty
                ? Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2A2350), Color(0xFF161026)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.video_library_rounded, color: Color(0xFF8B5CF6), size: 30),
                  )
                : Image.network(
                    widget.playlist.coverUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: const Color(0xFF2A2350),
                      child: const Icon(Icons.video_library_rounded, color: Color(0xFF8B5CF6), size: 30),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlist.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_posts.length} ${_posts.length == 1 ? 'vídeo' : 'vídeos'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  'por ${widget.playlist.creatorName}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _postCard(_PostRow post) {
    return KlayKCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: post.cover.isEmpty
                ? Container(
                    width: 64,
                    height: 48,
                    color: const Color(0xFF2A2350),
                    alignment: Alignment.center,
                    child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF8B5CF6), size: 22),
                  )
                : Image.network(
                    post.cover,
                    width: 64,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 64,
                      height: 48,
                      color: const Color(0xFF2A2350),
                      child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF8B5CF6), size: 22),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title.isEmpty ? 'Vídeo sem descrição' : post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vídeo #${post.position + 1}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          if (widget.ownsIt)
            IconButton(
              tooltip: 'Remover da playlist',
              onPressed: _busy ? null : () => _remove(post),
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white38, size: 20),
            ),
        ],
      ),
    );
  }
}

class _PostRow {
  final String playlistPostId;
  final String postId;
  final String cover;
  final String title;
  final int position;
  final DateTime? createdAt;

  const _PostRow({
    required this.playlistPostId,
    required this.postId,
    this.cover = '',
    this.title = '',
    this.position = 0,
    this.createdAt,
  });
}