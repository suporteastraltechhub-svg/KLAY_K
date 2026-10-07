import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/user_profile.dart';
import '../services/audio_room_service.dart';
import '../services/community_service.dart';
import '../services/content_service.dart';
import '../services/event_service.dart';
import '../services/gift_service.dart';
import '../services/moment_service.dart';
import '../services/profile_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import '../l10n/app_localizations.dart';
import 'audio_rooms_screen.dart';
import 'communities/communities_screen.dart';
import 'events_screen.dart';
import 'friends_screen.dart';
import 'moments_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// "Meu KLAY K": hub da MINHA atividade dentro do app. Agrega dados REAIS do
/// usuário logado (perfil, nível/XP, rede de amigos, comunidades, eventos,
/// salas de voz, carteira) e abre as telas de cada território num toque.
class MeuKlayKScreen extends StatefulWidget {
  const MeuKlayKScreen({super.key});

  @override
  State<MeuKlayKScreen> createState() => _MeuKlayKScreenState();
}

class _MeuKlayKScreenState extends State<MeuKlayKScreen> {
  bool _loading = true;
  bool _failed = false;

  UserProfile? _profile;
  LevelProgress? _level;

  int _following = 0;
  int _friends = 0;
  int _communities = 0;
  int _events = 0;
  int _audioRooms = 0;
  int _posts = 0;
  int _moments = 0;

  Map<String, dynamic> _wallet = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      if (!SupabaseService.instance.isConfigured) {
        throw Exception('Supabase não configurado');
      }
      await SupabaseService.instance.ensureAuthenticated();

      final profile = await ProfileService.instance.fetchMyProfile();
      final myId = profile?.id ?? ProfileService.instance.myId ?? '';
      final level = await SocialService.instance.fetchMyProgress();
      final friendCounts = await ProfileService.instance.fetchFriendCounts();
      final communities = await CommunityService.instance.fetchMyCommunities();
      final events = await EventService.instance.fetchMyEvents();
      final audioRooms = await AudioRoomService.instance.fetchMyAudioRooms();
      final moments = await MomentService.instance.fetchMyMoments();
      final posts = myId.isEmpty
          ? <dynamic>[]
          : await ContentService.instance.fetchPostsByUser(myId);
      Map<String, dynamic> wallet = const {};
      try {
        wallet = await GiftService.instance.fetchWalletCurrencies();
      } catch (_) {
        wallet = const {};
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _level = level;
        _following = friendCounts['following'] ?? 0;
        _friends = friendCounts['friends'] ?? 0;
        _communities = communities.length;
        _events = events.length;
        _audioRooms = audioRooms.length;
        _moments = moments.length;
        _posts = posts.length;
        _wallet = wallet;
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

  void _open(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.myKlayK,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 7)
          : _failed
          ? KlaykEmptyState(
              icon: Icons.cloud_off_outlined,
              title: l10n.errorLoading,
              message: l10n.loadDataFail,
              actionLabel: l10n.retry,
              actionIcon: Icons.refresh_rounded,
              onAction: _load,
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: _kAccent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  if (_level != null) _buildLevelCard(_level!),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    l10n.sectionMyActivity,
                    icon: Icons.auto_awesome_rounded,
                  ),
                  const SizedBox(height: 4),
                  _buildActivityGrid(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    l10n.sectionMyWallet,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 4),
                  _buildWalletCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final p = _profile;
    final name = p?.name ?? kAppIdentity.displayName;
    final handle = p?.handle ?? kAppIdentity.username;
    final avatar = (p?.avatarUrl?.isNotEmpty == true)
        ? p!.avatarUrl
        : (kAppIdentity.avatarUrl?.isNotEmpty == true
              ? kAppIdentity.avatarUrl
              : null);
    final verified = p?.hasVerifiedBadge == true;
    return Row(
      children: [
        ClipOval(
          child: avatar == null
              ? Container(
                  width: 72,
                  height: 72,
                  color: const Color(0xFF2A2350),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : Image.network(
                  avatar,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    color: const Color(0xFF2A2350),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty
                          ? name.characters.first.toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      color: _kAccent,
                      size: 18,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                handle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.presenceSummary,
                style: const TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLevelCard(LevelProgress level) {
    final l10n = AppLocalizations.of(context)!;
    final next = level.xpNextLevel;
    return KlayKCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFA78BFA), Color(0xFF6D28D9)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${level.level}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.levelLine(level.level, level.levelTitle),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      next == null
                          ? l10n.xpTotalLine(level.xpTotal)
                          : l10n.xpToNextLine(level.xpTotal, level.xpToNext),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: level.levelFraction,
              minHeight: 8,
              backgroundColor: const Color(0xFF2A2540),
              valueColor: const AlwaysStoppedAnimation(_kAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _statCard(
          '$_following',
          l10n.following,
          Icons.person_add_alt_1_outlined,
          onTap: () => _open(const FriendsScreen()),
        ),
        const SizedBox(width: 8),
        _statCard(
          '$_friends',
          l10n.friends,
          Icons.group_outlined,
          onTap: () => _open(const FriendsScreen()),
        ),
        const SizedBox(width: 8),
        _statCard(
          '$_communities',
          l10n.communities,
          Icons.groups_outlined,
          onTap: () => _open(const CommunitiesScreen()),
        ),
        const SizedBox(width: 8),
        _statCard('$_posts', l10n.videos, Icons.movie_outlined),
      ],
    );
  }

  Widget _statCard(
    String value,
    String label,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: KlayKCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: _kAccent, size: 20),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: _kAccent, size: 18),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityGrid() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _activityTile(
                Icons.waves_rounded,
                l10n.voiceRooms,
                '$_audioRooms',
                subtitle: l10n.voiceRoomsMine,
                onTap: () => _open(const AudioRoomsScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _activityTile(
                Icons.auto_awesome_rounded,
                l10n.moments,
                '$_moments',
                subtitle: l10n.momentsActive,
                onTap: () => _open(const MomentsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _activityTile(
                Icons.event_rounded,
                l10n.events,
                '$_events',
                subtitle: l10n.eventsConfirmed,
                onTap: () => _open(const EventsScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _activityTile(
                Icons.groups_rounded,
                l10n.communities,
                '$_communities',
                subtitle: l10n.communitiesJoined,
                onTap: () => _open(const CommunitiesScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _activityTile(
                Icons.group_add_rounded,
                l10n.friendships,
                '$_friends',
                subtitle: l10n.friendshipNetwork,
                onTap: () => _open(const FriendsScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activityTile(
    IconData icon,
    String title,
    String count, {
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: KlayKCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF2A2350),
                border: Border.all(color: const Color(0xFF2A2540)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard() {
    final l10n = AppLocalizations.of(context)!;
    final entries = <(String, IconData, String)>[
      ('credits', Icons.stars_rounded, l10n.credits),
      ('diamonds', Icons.diamond_rounded, l10n.diamonds),
      ('rubies', Icons.toll_rounded, l10n.rubies),
    ];
    final hasAny = entries.any((e) {
      final v = _wallet[e.$1];
      return v is num && v > 0;
    });
    return KlayKCard(
      padding: const EdgeInsets.all(16),
      child: hasAny
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (key, icon, label) in entries)
                  Column(
                    children: [
                      Icon(icon, color: _kAccent, size: 24),
                      const SizedBox(height: 6),
                      Text(
                        _fmt(_wallet[key]),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          : Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF8B5CF6),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.walletEmpty,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }

  String _fmt(Object? v) {
    if (v is num) {
      return v.truncate() == v ? v.toInt().toString() : v.toString();
    }
    return v?.toString() ?? '0';
  }
}
