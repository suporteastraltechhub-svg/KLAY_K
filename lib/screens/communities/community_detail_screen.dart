import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../models/community_models.dart';
import '../../services/community_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/klayk_ux.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Detalhe de uma comunidade: cabeçalho (entrar/sair), feed de posts,
/// curtidas, comentários, denúncia e moderação (post/hide/delete/pin).
class CommunityDetailScreen extends StatefulWidget {
  final Community community;

  const CommunityDetailScreen({super.key, required this.community});

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  late Community _community;
  CommunityMembership? _membership;
  List<CommunityPost> _posts = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _community = widget.community;
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
      final membership = await CommunityService.instance
          .myMembership(_community.id);
      final fetched = await CommunityService.instance
          .fetchCommunity(_community.id);
      final posts = await CommunityService.instance
          .fetchPosts(_community.id);
      if (!mounted) return;
      setState(() {
        _membership = membership;
        if (fetched != null) _community = fetched;
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _membership = null;
        _posts = [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  bool get _isAdmin => _membership?.isAdmin ?? false;
  bool get _isMod => _membership?.isModerator ?? false;
  bool get _isMember => _membership != null;

  Future<void> _toggleJoin() async {
    if (_isMember) {
      await CommunityService.instance.leaveCommunity(_community.id);
    } else {
      await CommunityService.instance.joinCommunity(_community.id);
    }
    await _load();
  }

  Future<void> _createPost() async {
    final controller = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Novo post',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Compartilhe algo com a comunidade…',
                hintStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF1B1A26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: KlayKButton(
                label: 'Publicar',
                expanded: true,
                onPressed: () async {
                  if (controller.text.trim().isEmpty) return;
                  await CommunityService.instance.createPost(
                    _community.id,
                    content: controller.text.trim(),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _openMembers() async {
    final members = await CommunityService.instance
        .fetchMembers(_community.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Membros',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: members.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  color: Colors.white10,
                ),
                itemBuilder: (context, i) {
                  final m = members[i];
                  final profile = m['profiles'];
                  final name = profile is Map
                      ? (profile['display_name']?.toString() ??
                          profile['username']?.toString() ??
                          'Membro')
                      : 'Membro';
                  final user = profile is Map
                      ? profile['username']?.toString() ?? ''
                      : '';
                  final role = m['role']?.toString() ?? 'member';
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2540),
                      child: Icon(Icons.person, color: Colors.white54),
                    ),
                    title: Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    subtitle: user.isNotEmpty
                        ? Text('@$user',
                            style:
                                const TextStyle(color: Colors.white38))
                        : null,
                    trailing: role != 'member'
                        ? Chip(
                            label: Text(
                              role == 'admin' ? 'Admin' : 'Moderador',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                            backgroundColor: _kAccent.withValues(alpha: 0.2),
                            side: BorderSide.none,
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postActions(CommunityPost post) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: _kAccent),
              title: const Text('Denunciar',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(ctx).pop('report'),
            ),
            if (_isMod) ...[
              const Divider(height: 1, color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined,
                    color: Colors.white54),
                title: const Text('Ocultar post',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(ctx).pop('hide'),
              ),
              ListTile(
                leading: Icon(
                  post.pinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin,
                  color: Colors.white54,
                ),
                title: Text(post.pinned ? 'Desafixar' : 'Fixar',
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(ctx).pop('pin'),
              ),
            ],
            if (_isMod || post.userId == SupabaseService.instance.currentUser?.id) ...[
              const Divider(height: 1, color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFFF4D6A)),
                title: const Text('Excluir',
                    style: TextStyle(color: Color(0xFFFF4D6A))),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'report':
        await _reportPost(post);
      case 'hide':
        await CommunityService.instance.hidePost(post.id);
        await _load();
      case 'pin':
        await CommunityService.instance
            .pinPost(post.id, !post.pinned);
        await _load();
      case 'delete':
        await CommunityService.instance.deletePost(post.id);
        await _load();
    }
  }

  Future<void> _reportPost(CommunityPost post) async {
    final reasons = [
      'Spam',
      'Discurso de ódio',
      'Conteúdo violento',
      'Assédio',
      'Outro',
    ];
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Denunciar post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...reasons.map((r) => ListTile(
                  title: Text(r, style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.of(ctx).pop(r),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    await CommunityService.instance.reportPost(
      communityId: _community.id,
      postId: post.id,
      reason: reason,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denúncia enviada. Obrigado!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  KlayKIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (_isMember && _isMod)
                    KlayKIconButton(
                      icon: Icons.group_rounded,
                      onTap: _openMembers,
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const KlaykListSkeleton(rows: 5);
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Erro ao carregar',
        message: 'Não conseguimos carregar a comunidade. Tentar novamente.',
        actionLabel: 'Tentar novamente',
        actionIcon: Icons.refresh_rounded,
        onAction: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _header(),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text(
                'Publicações',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '${_posts.length}',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_posts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'Ainda não há publicações.\nSeja a primeira voz aqui!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.4),
                ),
              ),
            )
          else
            ..._posts.map((p) => _postCard(p)),
        ],
      ),
    );
  }

  Widget _header() {
    final communityColors = _communityColors();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1C1630),
            Color(0xFF100B1D),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: communityColors.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: communityColors.withValues(alpha: 0.18),
                  border: Border.all(
                      color: communityColors.withValues(alpha: 0.45)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _community.icon.isNotEmpty
                      ? _community.icon
                      : _community.categoryIcon,
                  style: const TextStyle(fontSize: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _community.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_community.memberCount} membros · '
                      '${_community.postCount} posts',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_community.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _community.description,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _isMember
                    ? KlayKSecondaryButton(
                        label: _isAdmin
                            ? 'Admin'
                            : (_isMod ? 'Moderador' : 'Entrar'),
                        icon: _isAdmin
                            ? Icons.shield_outlined
                            : Icons.group_add_outlined,
                        expanded: true,
                        onPressed: _isMod ? null : _toggleJoin,
                      )
                    : KlayKButton(
                        label: 'Participar',
                        icon: Icons.group_add_rounded,
                        expanded: true,
                        onPressed: _toggleJoin,
                      ),
              ),
              const SizedBox(width: 10),
              KlayKSecondaryButton(
                label: 'Postar',
                icon: Icons.edit_rounded,
                onPressed: _isMember ? _createPost : _toggleJoin,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _communityColors() => _kAccent;

  Widget _postCard(CommunityPost post) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF17141F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2540)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF2A2540),
                backgroundImage: post.authorAvatar != null
                    ? NetworkImage(post.authorAvatar!)
                    : null,
                child: post.authorAvatar == null
                    ? const Icon(Icons.person,
                        color: Colors.white54, size: 20)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.authorDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (post.authorVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              color: _kAccent, size: 15),
                        ],
                      ],
                    ),
                    Text(
                      _timeAgo(post.createdAt),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (post.pinned)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.push_pin_rounded,
                      color: Colors.white24, size: 18),
                ),
              InkWell(
                onTap: () => _postActions(post),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.more_horiz_rounded,
                      color: Colors.white38),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            post.content,
            style: const TextStyle(color: Colors.white, height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _likeButton(post),
              const SizedBox(width: 16),
              _iconWithCount(
                Icons.mode_comment_outlined,
                post.commentsCount,
                onTap: () => _openComments(post),
              ),
              const Spacer(),
              Text(
                '#${_community.slug}',
                style: TextStyle(
                    color: _kAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _likeButton(CommunityPost post) {
    return FutureBuilder<bool>(
      future: CommunityService.instance.isPostLiked(post.id),
      builder: (context, snap) {
        final liked = snap.data ?? false;
        return _iconWithCount(
          liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          post.likesCount,
          color: liked ? const Color(0xFFFF4D6A) : Colors.white70,
          onTap: () async {
            await CommunityService.instance.toggleLike(post.id);
            await _load();
          },
        );
      },
    );
  }

  Widget _iconWithCount(
    IconData icon,
    int count, {
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white70, size: 20),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: color ?? Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openComments(CommunityPost post) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      isScrollControlled: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CommentsSheet(post: post),
    );
    if (added == true) await _load();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${diff.inDays ~/ 7}sem';
  }
}

/// Folha de comentários de um post.
class _CommentsSheet extends StatefulWidget {
  final CommunityPost post;
  const _CommentsSheet({required this.post});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late Future<List<CommunityComment>> _comments;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _comments = CommunityService.instance.fetchComments(widget.post.id);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() {
      _comments = CommunityService.instance
          .fetchComments(widget.post.id);
    });
    await CommunityService.instance.addComment(widget.post.id, text);
    if (mounted) {
      setState(() {
        _comments = CommunityService.instance
            .fetchComments(widget.post.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Comentários',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<CommunityComment>>(
                future: _comments,
                builder: (context, snap) {
                  final comments = snap.data ?? const [];
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: _kAccent, strokeWidth: 2.5),
                    );
                  }
                  if (comments.isEmpty) {
                    return const Center(
                      child: Text(
                        'Sem comentários ainda.\nSeja o primeiro!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white38, height: 1.4),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: comments.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, i) {
                      final c = comments[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(0xFF2A2540),
                              child: Icon(Icons.person,
                                  color: Colors.white54, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          c.authorDisplay,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _relative(c.createdAt),
                                        style: const TextStyle(
                                            color: Colors.white24,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    c.content,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Escreva um comentário…',
                          hintStyle:
                              const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF1B1A26),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    KlayKIconButton(
                      icon: Icons.send_rounded,
                      glow: true,
                      onTap: _send,
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

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}