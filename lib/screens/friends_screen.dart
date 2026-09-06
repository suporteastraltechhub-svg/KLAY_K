import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';
import '../widgets/verified_badge.dart';
import 'profile/user_profile_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Amizades do KLAY K: hub social com amigos em comum, convites e sugestões
/// reais derivados do grafo de `follows` (sem dados inventados).
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<UserProfile> _friends = const [];
  List<UserProfile> _suggestions = const [];
  Map<String, int> _counts = const {};
  bool _loading = true;
  bool _failed = false;
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
        _failed = false;
      });
    }
    try {
      final results = await Future.wait<Object>([
        ProfileService.instance.fetchMutualFriends(),
        ProfileService.instance.fetchFriendSuggestions(),
        ProfileService.instance.fetchFriendCounts(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = (results[0] as List).cast<UserProfile>();
        _suggestions = (results[1] as List).cast<UserProfile>();
        _counts = (results[2] as Map).cast<String, int>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _toggle(UserProfile user) async {
    if (_busy) return;
    setState(() => _busy = true);
    final next = await ProfileService.instance.toggleFollow(user.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _applyFollowState(user.id, next);
    });
  }

  void _applyFollowState(String id, bool following) {
    UserProfile sync(UserProfile u) =>
        u.id == id ? u.copyWith(isFollowing: following) : u;
    _friends = _friends.map(sync).toList();
    _suggestions = _suggestions.map(sync).toList();
  }

  void _open(UserProfile user) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: user.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: const Text('Amizades', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 8, withAvatar: true)
          : _failed
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _kAccent,
                  child: _content(),
                ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.white38, size: 40),
            const SizedBox(height: 14),
            const Text(
              'Erro ao carregar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Não conseguimos carregar suas amizades. Tentar novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.4),
            ),
            const SizedBox(height: 18),
            KlayKButton(
              label: 'Tentar novamente',
              icon: Icons.refresh_rounded,
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final hasFriends = _friends.isNotEmpty;
    final hasSuggestions = _suggestions.isNotEmpty;
    final invitees = _counts['invitees'] ?? 0;
    final hasInvites = invitees > 0;

    if (!hasFriends && !hasSuggestions && !hasInvites) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(24),
        child: KlaykEmptyState(
          icon: Icons.people_outline,
          title: 'Vamos fazer amizades?',
          message:
              'Segue criadores e comece a interagir. Sugestões e amigos em comum aparecem aqui.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _countRow(),
        const SizedBox(height: 18),
        if (hasFriends) ...[
          _sectionHeader('Amigos', count: _friends.length, icon: Icons.favorite_rounded),
          _userList(_friends),
          const SizedBox(height: 18),
        ],
        if (hasInvites) ...[
          _sectionHeader('Convites para seguir', count: invitees, icon: Icons.person_add_alt_1_rounded),
          _inviteeHint(),
          const SizedBox(height: 6),
        ],
        if (hasSuggestions) ...[
          _sectionHeader('Sugestões para você', count: _suggestions.length, icon: Icons.wb_sunny_outlined),
          _userList(_suggestions),
        ],
      ],
    );
  }

  Widget _countRow() {
    final colors = kcolors(context);
    final c = _counts;
    return Row(
      children: [
        _countCell(colors, Icons.person_outline_rounded, c['following'] ?? 0, 'Seguindo'),
        _vDivider(),
        _countCell(colors, Icons.people_outline_rounded, c['followers'] ?? 0, 'Seguidores'),
        _vDivider(),
        _countCell(colors, Icons.favorite_rounded, c['friends'] ?? 0, 'Amigos'),
      ],
    );
  }

  Widget _countCell(KlaykColors colors, IconData icon, int value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: _kAccent, size: 20),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(width: 1, height: 44, color: const Color(0xFF2A2540));

  Widget _sectionHeader(String title, {int? count, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: _kAccent, size: 18),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              count != null ? '$title  ·  $count' : title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inviteeHint() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Text(
        'Pessoas que te seguem e você ainda não segue de volta.',
        style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
      ),
    );
  }

  Widget _userList(List<UserProfile> users) {
    return Column(
      children: users.map((u) => _row(u)).toList(),
    );
  }

  Widget _row(UserProfile user) {
    final me = ProfileService.instance.myId;
    final showButton = user.id.isNotEmpty && user.id != me && !user.isSelf;
    return ListTile(
      contentPadding: EdgeInsets.zero,
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
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (user.isVerified) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(size: 15),
          ],
        ],
      ),
      subtitle: Text(
        user.handle.isEmpty ? '@usuario' : user.handle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: showButton
          ? OutlinedButton(
              onPressed: () => _toggle(user),
              style: OutlinedButton.styleFrom(
                backgroundColor: user.isFollowing ? null : _kAccent,
                foregroundColor: Colors.white,
                side: BorderSide(color: user.isFollowing ? const Color(0xFF3A3550) : _kAccent),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                user.isFollowing ? 'Seguindo' : 'Seguir',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }
}