import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Painel do criador do KLAY K. Mostra estatísticas reais do usuário
/// (`public.user_stats`), recomputadas a partir dos dados atuais.
class CreatorDashboardScreen extends StatefulWidget {
  const CreatorDashboardScreen({super.key});

  @override
  State<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends State<CreatorDashboardScreen> {
  bool _loading = true;
  CreatorStats _stats = const CreatorStats();
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await SocialService.instance.fetchCreatorStats();
      int level = 1;
      try {
        level = await SocialService.instance.fetchLevel();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _level = level;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.creatorDashboardTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.creatorDashboardRefresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _levelCard(),
                const SizedBox(height: 16),
                _sectionHeader(l10n.creatorDashboardSectionTotal),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    _statCard(
                      _fmt(l10n, _stats.totalViews),
                      l10n.creatorDashboardViews,
                      Icons.visibility_rounded,
                    ),
                    _statCard(
                      _fmt(l10n, _stats.totalLikes),
                      l10n.creatorDashboardLikes,
                      Icons.favorite_rounded,
                    ),
                    _statCard(
                      _fmt(l10n, _stats.totalComments),
                      l10n.creatorDashboardComments,
                      Icons.comment_rounded,
                    ),
                    _statCard(
                      _fmt(l10n, _stats.totalLiveViews),
                      l10n.creatorDashboardLiveViews,
                      Icons.sensors_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionHeader(l10n.creatorDashboardSectionAudience),
                Row(
                  children: [
                    Expanded(
                      child: _audienceCard(
                        _fmt(l10n, _stats.followersCount),
                        l10n.creatorDashboardFollowers,
                        Icons.people_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _audienceCard(
                        _fmt(l10n, _stats.followingCount),
                        l10n.creatorDashboardFollowing,
                        Icons.person_add_alt_1_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionHeader(l10n.creatorDashboardSectionContent),
                _audienceCard(
                  _fmt(l10n, _stats.postsCount),
                  l10n.creatorDashboardPosts,
                  Icons.video_library_rounded,
                ),
              ],
            ),
    );
  }

  Widget _levelCard() {
    final l10n = AppLocalizations.of(context)!;
    // Nível derivado de XP de conquistas (ver social_service.fetchLevel).
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8A2BE2), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$_level',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.creatorDashboardLevelTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.creatorDashboardLevelBody,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kAccent, size: 28),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audienceCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kAccent, size: 26),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: _kAccent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );

  static String _fmt(AppLocalizations l10n, int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}'
          '${l10n.creatorDashboardFmtMillion}';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}'
          '${l10n.creatorDashboardFmtThousand}';
    }
    return '$n';
  }
}
