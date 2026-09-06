import 'package:flutter/material.dart';

import '../services/social_service.dart';
import 'rankings_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Conquistas do KLAY K. Mostra o catálogo real (`public.achievements`) com o
/// estado de desbloqueio por usuário (`public.user_achievements`).
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  bool _loading = true;
  List<Achievement> _achievements = [];
  int _totalXp = 0;
  LevelProgress _progress = LevelProgress.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        SocialService.instance.fetchAchievements(),
        SocialService.instance.fetchMyProgress(),
      ]);
      final list = (results[0] as List).cast<Achievement>();
      final progress = (results[1] as LevelProgress);
      if (!mounted) return;
      setState(() {
        _achievements = list;
        _progress = progress;
        _totalXp =
            list.where((a) => a.unlocked).fold(0, (sum, a) => sum + a.xp);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRankings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RankingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _achievements.where((a) => a.unlocked).length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Conquistas',
            style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openRankings,
            icon: const Icon(Icons.leaderboard_rounded),
            tooltip: 'Classificações',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _levelCard(),
                const SizedBox(height: 12),
                if (_progress.missions.isNotEmpty) ...[
                  const Text(
                    'Missões',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  ..._progress.missions.map((m) => _missionTile(m)),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1A26),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          color: _kAccent, size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$unlocked de ${_achievements.length} desbloqueadas',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text('$_totalXp XP em conquistas',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: _achievements.isEmpty
                                    ? 0
                                    : unlocked / _achievements.length,
                                minHeight: 8,
                                backgroundColor: const Color(0xFF2A2740),
                                valueColor: const AlwaysStoppedAnimation(
                                    _kAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_achievements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Nenhuma conquista disponível',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: _achievements.length,
                    itemBuilder: (context, i) {
                      final a = _achievements[i];
                      return _achievementCard(a);
                    },
                  ),
              ],
            ),
    );
  }

  Widget _levelCard() {
    final p = _progress;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
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
              color: Colors.black.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$p.level',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nível ${p.level} • ${p.levelTitle}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  p.xpNextLevel == null
                      ? '${p.xpTotal} XP total'
                      : '${p.xpTotal} XP • ${p.xpToNext} XP para o próximo nível',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: p.levelFraction,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _missionTile(MissionProgress m) {
    final pct = m.target <= 0 ? 0.0 : (m.progress / m.target).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: m.completed
              ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
              : const Color(0xFF2A2740),
        ),
      ),
      child: Row(
        children: [
          Text(m.icon.isEmpty ? '🎯' : m.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.title,
                        style: TextStyle(
                          color: m.completed ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      m.frequency == 'daily' ? 'Hoje' : 'Semana',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: const Color(0xFF2A2740),
                    valueColor: AlwaysStoppedAnimation(
                        m.completed ? const Color(0xFF4CAF50) : _kAccent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  m.completed
                      ? 'Concluída (+${m.xpReward} XP)'
                      : '${m.progress}/${m.target} • +${m.xpReward} XP',
                  style: TextStyle(
                    color: m.completed
                        ? const Color(0xFF4CAF50)
                        : Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (m.completed)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle_rounded,
                  color: Color(0xFF4CAF50), size: 20),
            ),
        ],
      ),
    );
  }

  Widget _achievementCard(Achievement a) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: a.unlocked
              ? _kAccent.withValues(alpha: 0.6)
              : const Color(0xFF2A2740),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _iconWidget(a.icon, a.unlocked),
          const SizedBox(height: 8),
          Text(
            a.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: a.unlocked ? Colors.white : Colors.white38,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '+${a.xp} XP',
            style: TextStyle(
              color: a.unlocked ? _kAccent : Colors.white24,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconWidget(String icon, bool unlocked) {
    IconData data;
    switch (icon) {
      case 'first_video':
        data = Icons.videocam_rounded;
        break;
      case 'first_like':
        data = Icons.favorite_rounded;
        break;
      case 'first_follower':
        data = Icons.person_add_alt_1_rounded;
        break;
      case 'first_live':
        data = Icons.sensors_rounded;
        break;
      case 'first_comment':
        data = Icons.comment_rounded;
        break;
      case 'first_collection':
        data = Icons.folder_special_rounded;
        break;
      case 'verified_creator':
        data = Icons.verified_rounded;
        break;
      default:
        data = Icons.emoji_events_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: unlocked
            ? _kAccent.withValues(alpha: 0.2)
            : const Color(0xFF2A2740),
        shape: BoxShape.circle,
      ),
      child: Icon(
        data,
        color: unlocked ? _kAccent : Colors.white24,
        size: 28,
      ),
    );
  }
}
