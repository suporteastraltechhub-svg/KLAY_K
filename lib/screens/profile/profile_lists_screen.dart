import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/klayk_ux.dart';
import '../../widgets/profile_widgets.dart';
import '../../widgets/verified_badge.dart';
import 'user_profile_screen.dart';

/// Lista de seguidores ou seguidos de um usuário, com botões de seguir.
class ProfileListsScreen extends StatefulWidget {
  final String userId;
  final bool following; // true = "quem este usuário segue"

  const ProfileListsScreen({
    super.key,
    required this.userId,
    required this.following,
  });

  @override
  State<ProfileListsScreen> createState() => _ProfileListsScreenState();
}

class _ProfileListsScreenState extends State<ProfileListsScreen> {
  List<UserProfile>? _users;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _users = null;
      _error = false;
    });
    final list = widget.following
        ? await ProfileService.instance.fetchFollowing(widget.userId)
        : await ProfileService.instance.fetchFollowers(widget.userId);
    if (!mounted) return;
    setState(() {
      _users = list;
      _error = list.isEmpty && SupabaseService.instance.isConfigured;
    });
  }

  Future<void> _toggle(UserProfile user) async {
    final svc = ProfileService.instance;
    final next = await svc.toggleFollow(user.id);
    if (!mounted || next == user.isFollowing) return;
    setState(() {
      _users = [
        for (final u in _users!)
          if (u.id == user.id) u.copyWith(isFollowing: next) else u,
      ];
    });
  }

  void _open(UserProfile user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: user.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.following ? 'Seguindo' : 'Seguidores';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: switch (_users) {
        null => const KlaykListSkeleton(rows: 8, withAvatar: true),
        final users when users.isEmpty => _empty(),
        final users => RefreshIndicator(
            onRefresh: _load,
            color: kProfileAccent,
            backgroundColor: const Color(0xFF1B1A26),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, i) => _row(users[i]),
            ),
          ),
      },
    );
  }

  Widget _empty() {
    final msg = _error
        ? 'Não foi possível carregar a lista.'
        : widget.following
            ? 'Este usuário ainda não segue ninguém.'
            : 'Ainda não há seguidores por aqui.';
    return KlaykEmptyState(
      icon: Icons.people_outline,
      title: msg,
    );
  }

  Widget _row(UserProfile user) {
    final me = ProfileService.instance.myId;
    final showButton =
        user.id.isNotEmpty && user.id != me && !user.isSelf;
    return ListTile(
      onTap: () => _open(user),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFF2A2740),
        backgroundImage:
            (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                ? NetworkImage(user.avatarUrl!)
                : null,
        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
            ? const Icon(Icons.person, color: Colors.white54)
            : null,
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              user.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (user.isVerified) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(size: 15),
          ],
        ],
      ),
      subtitle: Text(
        user.handle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: showButton
          ? SizedBox(
              width: 96,
              child: OutlinedButton(
                onPressed: () => _toggle(user),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: user.isFollowing
                        ? const Color(0xFF3A3550)
                        : kProfileAccent,
                  ),
                  backgroundColor: user.isFollowing
                      ? null
                      : kProfileAccent.withValues(alpha: 0.1),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  user.isFollowing ? 'Seguindo' : 'Seguir',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}