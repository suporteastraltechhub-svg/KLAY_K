import 'package:flutter/material.dart';

import '../../models/post_models.dart';
import '../../models/user_profile.dart';
import '../../services/account_service.dart';
import '../../services/content_service.dart';
import '../../services/profile_service.dart';
import '../../services/social_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/klayk_ux.dart';
import '../../widgets/profile_widgets.dart';
import 'edit_profile_screen.dart';
import 'profile_lists_screen.dart';
import 'video_preview_screen.dart';

/// Tela de perfil de usuário — funciona tanto para o próprio usuário (mostra
/// "Editar perfil") quanto para visualizar qualquer outro usuário (botão de
/// seguir, denunciar e bloquear).
class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfile? _profile;
  List<FeedPost> _videos = const [];
  bool _loading = true;
  bool _error = false;
  bool _followBusy = false;
  bool _blocked = false;

  static const List<Color> _gridColors = [
    Color(0xFF8A2BE2),
    Color(0xFFFF4D6A),
    Color(0xFF1E1B2E),
  ];

  bool get _real => SupabaseService.instance.isConfigured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_real) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final profile =
          await ProfileService.instance.fetchProfile(widget.userId);
      final posts = await ContentService.instance
          .fetchFeed(userId: widget.userId, limit: 9);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _videos = posts;
        _loading = false;
      });
      _loadBlockState();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _loadBlockState() async {
    final ids = await AccountService.instance.fetchBlockedIds();
    if (mounted) setState(() => _blocked = ids.contains(widget.userId));
  }

  Future<void> _toggleFollow() async {
    setState(() => _followBusy = true);
    final next = await ProfileService.instance.toggleFollow(widget.userId);
    if (!mounted) return;
    setState(() {
      _followBusy = false;
      final p = _profile;
      if (p != null) {
        final delta = next ? 1 : -1;
        _profile = p.copyWith(
          isFollowing: next,
          followersCount: (p.followersCount + delta).clamp(0, 1 << 31),
        );
      }
    });
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EditProfileScreen(profile: _profile ?? _emptySelfProfile()),
      ),
    );
    if (changed == true) _load();
  }

  UserProfile _emptySelfProfile() => UserProfile(id: widget.userId);

  Future<void> _openFollowers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileListsScreen(
          userId: widget.userId,
          following: false,
        ),
      ),
    );
  }

  Future<void> _openFollowing() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileListsScreen(
          userId: widget.userId,
          following: true,
        ),
      ),
    );
  }

  void _share() {
    final p = _profile;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Perfil de ${p?.handle ?? '@usuario'} pronto para compartilhar!',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _moreMenu() async {
    final p = _profile;
    if (p == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined,
                  color: Colors.white70),
              title: const Text('Denunciar',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading: Icon(
                _blocked
                    ? Icons.person_remove_alt_1_outlined
                    : Icons.block_outlined,
                color: Colors.white70,
              ),
              title: Text(
                _blocked ? 'Desbloquear' : 'Bloquear',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'report') _report(p);
    if (action == 'block') _block(p);
  }

  Future<void> _report(UserProfile p) async {
    final reason = await _pickReason();
    if (reason == null || !mounted) return;
    try {
      await SocialService.instance.reportItem(
        targetId: p.id,
        targetType: 'user',
        reason: reason,
      );
      _snack('Denúncia enviada. Obrigado por ajudar o KLAY K!');
    } catch (e) {
      _snack('Erro ao enviar denúncia: $e');
    }
  }

  Future<String?> _pickReason() async {
    const reasons = [
      'Conteúdo inadequado ou ofensivo',
      'Assédio ou bullying',
      'Spam ou conta falsa',
      'Outro',
    ];
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Denunciar perfil',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (final r in reasons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined,
                    color: Colors.white38),
                title: Text(r, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    return reason;
  }

  Future<void> _block(UserProfile p) async {
    final me = ProfileService.instance.myId;
    if (me == null || me == p.id) return;
    try {
      if (_blocked) {
        await AccountService.instance.unblockUser(p.id);
      } else {
        await AccountService.instance.blockUser(p.id);
      }
      if (mounted) setState(() => _blocked = !_blocked);
      _snack(_blocked ? 'Usuário bloqueado.' : 'Usuário desbloqueado.');
    } catch (e) {
      _snack('Não foi possível atualizar o bloqueio: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          p?.handle ?? 'Perfil',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (p != null && !p.isSelf)
            IconButton(
              onPressed: _moreMenu,
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Mais opções',
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(p),
    );
  }

  Widget _buildBody(UserProfile? p) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kProfileAccent),
      );
    }
    if (_error || p == null) {
      return KlaykErrorState(
        message: 'Não foi possível carregar este perfil.',
        onRetry: _load,
      );
    }

    final isSelf = p.isSelf ||
        (ProfileService.instance.myId != null &&
            ProfileService.instance.myId == p.id);

    return RefreshIndicator(
      onRefresh: _load,
      color: kProfileAccent,
      backgroundColor: const Color(0xFF1B1A26),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          ProfileHeader(
            profile: p,
            actions: [
              ProfileActionButton(
                isSelf: isSelf,
                isFollowing: p.isFollowing,
                busy: _followBusy,
                onPressed: isSelf ? _openEdit : _toggleFollow,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _share,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3A3550)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.share_outlined, size: 17),
                  label: const Text('Compartilhar'),
                ),
              ),
            ],
            onNameTap: null,
          ),
          const SizedBox(height: 6),
          ProfileStats(
            profile: p,
            onFollowersTap: isSelf ? null : _openFollowers,
            onFollowingTap: isSelf ? null : _openFollowing,
          ),
          const SizedBox(height: 20),
          _sectionTitle('Vídeos'),
          const SizedBox(height: 12),
          if (_videos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nenhum vídeo publicado por aqui ainda.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _videos.length,
              itemBuilder: (context, i) => _videoTile(_videos[i], i),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _videoTile(FeedPost post, int index) {
    return GestureDetector(
      onTap: () async {
        final deleted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => VideoPreviewScreen(post: post)),
        );
        if (deleted == true && mounted) _load();
      },
      child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _gridColors[index % _gridColors.length],
        borderRadius: BorderRadius.circular(10),
      ),
      child: post.coverUrl != null && post.coverUrl!.isNotEmpty
          ? Image.network(
              post.coverUrl!,
              fit: BoxFit.cover,
              cacheWidth: imageDecodeWidth(context, 110),
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  '${post.likesCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : Center(
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white.withValues(alpha: 0.85),
                size: 34,
              ),
            ),
      ),
    );
  }
}