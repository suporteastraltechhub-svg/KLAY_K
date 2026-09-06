import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/post_models.dart';
import '../../services/content_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/content_actions.dart';
import '../../widgets/verified_badge.dart';
import 'user_profile_screen.dart';

/// Player fullscreen autônomo para um único post (aberto a partir dos grids de
/// vídeo do perfil). Não depende do monólito do feed — resolve a URL assinada
/// e reproduz com play/pause, curtida de toque duplo e acesso ao perfil do
/// autor.
class VideoPreviewScreen extends StatefulWidget {
  final FeedPost post;

  const VideoPreviewScreen({super.key, required this.post});

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _error = false;
  bool _playing = false;
  bool _liked = false;
  bool _likeBusy = false;
  int _likes = 0;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likes = widget.post.likesCount;
    _init();
  }

  Future<void> _init() async {
    try {
      final url =
          await ContentService.instance.resolveVideoUrl(widget.post);
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _playing = true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _playing = false;
      } else {
        c.play();
        _playing = true;
      }
    });
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final next = !_liked;
    setState(() {
      _liked = next;
      _likes += next ? 1 : -1;
    });
    _likeBusy = true;
    try {
      if (next) {
        await ContentService.instance.likePost(widget.post.id);
      } else {
        await ContentService.instance.unlikePost(widget.post.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !next;
          _likes += next ? -1 : 1;
        });
      }
    } finally {
      _likeBusy = false;
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: widget.post.userId),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ações do dono (Editar / Apagar). A validação de posse é feita no backend
  // (RLS + RPCs security definer); aqui apenas gating de UI.
  // ---------------------------------------------------------------------------

  bool get _isOwner =>
      SupabaseService.instance.currentUser?.id == widget.post.userId;

  Future<void> _editPost() async {
    final res = await editPostDialog(
      context,
      description: widget.post.description,
      hashtags: widget.post.hashtags,
    );
    if (res == null || !mounted) return;
    final ok = await ContentService.instance.updatePost(
      postId: widget.post.id,
      description: res.description,
      hashtags: res.hashtags,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vídeo atualizado.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível atualizar agora. Tente de novo.')),
      );
    }
  }

  Future<void> _deletePost() async {
    final go = await confirmDeleteDialog(
      context,
      title: 'Apagar vídeo?',
      message:
          'O vídeo, a capa, curtidas e comentários serão removidos '
          'permanentemente. Essa ação não pode ser desfeita.',
    );
    if (!go || !mounted) return;
    try {
      await ContentService.instance.deletePost(
        widget.post.id,
        videoPath: widget.post.videoUrl,
        coverUrl: widget.post.coverUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível apagar o vídeo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.post.author;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _togglePlay,
        onDoubleTap: _toggleLike,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              Container(
                color: const Color(0xFF131118),
                child: widget.post.coverUrl != null &&
                        widget.post.coverUrl!.isNotEmpty
                    ? Image.network(
                        widget.post.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.play_circle_outline,
                          color: Colors.white24,
                          size: 64,
                        ),
                      )
                    : const Icon(
                        Icons.play_circle_outline,
                        color: Colors.white24,
                        size: 64,
                      ),
              ),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF8B5CF6),
                  strokeWidth: 2.5,
                ),
              ),
            if (_error)
              const Center(
                child: Text(
                  'Não foi possível carregar o vídeo',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_controller != null && !_playing)
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            // ---------- Gradiente inferior + informações ----------
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 48, 16, bottomPadding + 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _openProfile,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundImage:
                                (author != null &&
                                        author.avatarUrl != null &&
                                        author.avatarUrl!.isNotEmpty)
                                    ? NetworkImage(author.avatarUrl!)
                                    : null,
                            child: (author == null ||
                                    author.avatarUrl == null ||
                                    author.avatarUrl!.isEmpty)
                                ? const Icon(Icons.person,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    author?.name ?? 'Usuário',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (author?.isVerified ?? false) ...[
                                  const SizedBox(width: 4),
                                  const VerifiedBadge(size: 16),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.white60, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _openProfile,
                      child: Text(
                        widget.post.description.isEmpty
                            ? 'Vídeo de ${author?.name ?? 'KLAY K'}'
                            : widget.post.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ---------- Barra superior ----------
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: topPadding + 6,
                  left: 12,
                  right: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _likeChip(),
                        ContentOverflowMenu(
                          isOwner: _isOwner,
                          onEdit: _editPost,
                          onDelete: _deletePost,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _likeChip() {
    return GestureDetector(
      onTap: _toggleLike,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _liked ? const Color(0xFFFF4D6A) : Colors.white,
              size: 17,
            ),
            const SizedBox(width: 6),
            Text(
              '$_likes',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}