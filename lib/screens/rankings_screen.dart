import 'package:flutter/material.dart';

import '../services/social_service.dart';
import '../widgets/verified_badge.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Classificações (rankings) de NÍVEIS e MISSÕES, com selo de verificado.
class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<List<LevelRankEntry>> _levels;
  late Future<List<MissionRankEntry>> _missions;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _levels = SocialService.instance.fetchLevelRanking();
    _missions = SocialService.instance.fetchMissionRanking();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        centerTitle: true,
        title: const Text('Classificações',
            style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Níveis'),
            Tab(text: 'Missões'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _levelsBuilder(),
          _missionsBuilder(),
        ],
      ),
    );
  }

  Widget _levelsBuilder() {
    return FutureBuilder<List<LevelRankEntry>>(
      future: _levels,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
        }
        final list = snapshot.data ?? const <LevelRankEntry>[];
        if (list.isEmpty) {
          return const Center(
              child: Text('Sem dados de ranking.',
                  style: TextStyle(color: Colors.white54)));
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => _levelRow(list[i], list.length > 3),
        );
      },
    );
  }

  Widget _missionsBuilder() {
    return FutureBuilder<List<MissionRankEntry>>(
      future: _missions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
        }
        final list = snapshot.data ?? const <MissionRankEntry>[];
        if (list.isEmpty) {
          return const Center(
              child: Text('Sem dados de ranking.',
                  style: TextStyle(color: Colors.white54)));
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => _missionRow(list[i], list.length > 3),
        );
      },
    );
  }

  Widget _rankBadge(int rank) {
    const colors = <int, Color>{
      1: Color(0xFFFFD700),
      2: Color(0xFFC0C0C0),
      3: Color(0xFFCD7F32),
    };
    final color = colors[rank] ?? Colors.white38;
    if (rank <= 3) {
      return Text('$rank',
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.w900));
    }
    return Text('$rank',
        style: const TextStyle(color: Colors.white38, fontSize: 14));
  }

  Widget _name(String name, bool verified) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        if (verified) ...[
          const SizedBox(width: 4),
          const VerifiedBadge(size: 14),
        ],
      ],
    );
  }

  Widget _levelRow(LevelRankEntry e, bool showRank) {
    return ListTile(
      leading: showRank
          ? SizedBox(width: 24, child: Center(child: _rankBadge(e.rank)))
          : _rankBadge(e.rank),
      title: _name(e.name, e.isVerified),
      subtitle: Text('Nível ${e.level}',
          style: const TextStyle(color: _kAccent, fontSize: 12)),
      trailing: Text('${e.xpTotal} XP',
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }

  Widget _missionRow(MissionRankEntry e, bool showRank) {
    return ListTile(
      leading: showRank
          ? SizedBox(width: 24, child: Center(child: _rankBadge(e.rank)))
          : _rankBadge(e.rank),
      title: _name(e.name, e.isVerified),
      subtitle: Text('${e.missionsDone} missões',
          style: const TextStyle(color: _kAccent, fontSize: 12)),
      trailing: Text('${e.xpMission} XP',
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }
}
