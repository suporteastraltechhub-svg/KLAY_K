import 'dart:async';

import 'package:flutter/material.dart';

import '../models/klayk_live_models.dart';
import '../services/content_service.dart';
import '../services/live_kit_service.dart';
import '../services/supabase_service.dart';
import '../widgets/content_actions.dart';
import '../widgets/verified_badge.dart';
import 'live_room_screen.dart';
import 'profile/user_profile_screen.dart';
import 'start_live_screen.dart';

/// Área principal "🎮 LIVE GAMES / JOGOS AO VIVO" do KLAY K.
///
/// Mostra lives de jogo em tempo real, categorias de gameplay, ranking,
/// criadores e um botão proeminente para INICIAR uma Live de Jogo (com
/// captura de tela). Tudo conectado ao backend real (tabela `lives`).
class LiveGamesScreen extends StatefulWidget {
  const LiveGamesScreen({super.key});

  @override
  State<LiveGamesScreen> createState() => _LiveGamesScreenState();
}

/// Categoria de gameplay (a mesma usada na filtragem de lives de jogo).
class GameCategory {
  final String name;
  final String emoji;
  const GameCategory(this.name, this.emoji);
}

const List<GameCategory> kGameCategories = [
  GameCategory('Ação', '⚔️'),
  GameCategory('Corrida', '🏎️'),
  GameCategory('Futebol', '⚽'),
  GameCategory('FPS', '🔫'),
  GameCategory('Battle Royale', '🪂'),
  GameCategory('RPG', '🐉'),
  GameCategory('Casual', '🎲'),
  GameCategory('Mobile', '📱'),
  GameCategory('Outros', '🎮'),
];

class _LiveGamesScreenState extends State<LiveGamesScreen> {
  final SupabaseService _db = SupabaseService.instance;

  List<RealLive> _lives = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  String _activeCategory = 'Todos';
  static const String _all = 'Todos';

  @override
  void initState() {
    super.initState();
    _load();
    // Atualiza periodicamente o "ao vivo".
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_db.isConfigured) {
      try {
        final lives = await _db.fetchActiveLives();
        if (!mounted) return;
        setState(() {
          _lives = lives;
          _loading = false;
          _error = null;
        });
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar as lives de jogo.';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _lives = [];
    });
  }

  List<RealLive> get _gameLives =>
      _lives.where((l) => l.category.toLowerCase() == 'jogos').toList();

  List<RealLive> get _filtered {
    if (_activeCategory == _all) return _gameLives;
    // Filtra pela categoria informada no nome do jogo (heurística de busca).
    final query = _activeCategory.toLowerCase();
    return _gameLives
        .where((l) =>
            (l.gameName?.toLowerCase().contains(query) ?? false) ||
            l.title.toLowerCase().contains(query))
        .toList();
  }

  List<RealLive> get _popular {
    final sorted = [..._gameLives]..sort((a, b) => b.viewerCount.compareTo(a.viewerCount));
    return sorted.take(8).toList();
  }

  /// Ação principal: inicia uma nova Live de Jogo (captura de tela).
  Future<void> _startGameLive() async {
    if (!_db.isConfigured) {
      _snack('Configure o Supabase para iniciar uma live real.');
      return;
    }
    // O StartLiveScreen já configura categoria Jogos; aqui forçamos a categoria
    // de jogo e o fluxo de captura de tela no LiveRoomScreen.
    final started = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const StartLiveScreen(forceGame: true),
      ),
    );
    if (started == true && mounted) _load();
  }

  Future<void> _editLive(RealLive live) async {
    final res = await editLiveDialog(
      context,
      title: live.title,
      description: live.description,
      category: live.category,
      privacy: live.privacy,
    );
    if (res == null || !mounted) return;
    final ok = await ContentService.instance.updateLive(
      liveId: live.id,
      title: res.title,
      description: res.description,
      category: res.category,
      privacy: res.privacy,
      coverUrl: live.coverUrl,
    );
    if (!mounted) return;
    if (ok) {
      _load();
      _snack('Live atualizada.');
    } else {
      _snack('Não foi possível atualizar agora. Tente de novo.');
    }
  }

  Future<void> _deleteLive(RealLive live) async {
    final go = await confirmDeleteDialog(
      context,
      title: 'Apagar live?',
      message: 'A live e seu histórico (chat, presentes e eventos) serão '
          'removidos permanentemente. Essa ação não pode ser desfeita.',
    );
    if (!go || !mounted) return;
    try {
      await ContentService.instance.deleteLive(live.id, coverUrl: live.coverUrl);
      if (!mounted) return;
      _load();
    } catch (_) {
      if (!mounted) return;
      _snack('Não foi possível apagar a live.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0812),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0812),
        automaticallyImplyLeading: false,
        title: const Text(
          '🎮 LIVE GAMES · Jogos ao Vivo',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildStartBanner(),
          _buildCategoryChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildStartBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: FilledButton.icon(
        onPressed: _startGameLive,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE11D48),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.sensors_rounded),
        label: const Text(
          '🔴 INICIAR LIVE DE JOGO',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final cats = [_all, ...kGameCategories.map((c) => c.name)];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final name = cats[index];
          final emoji = index == 0
              ? ''
              : kGameCategories[index - 1].emoji;
          final selected = _activeCategory == name;
          return GestureDetector(
            onTap: () => setState(() => _activeCategory = name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFF1C1C26),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Text(
                  '$emoji $name'.trim(),
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_gameLives.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.sports_esports_rounded,
              color: Colors.white24, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma live de jogo no momento',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seja o primeiro a transmitir seu gameplay agora mesmo!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startGameLive,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            icon: const Icon(Icons.sensors_rounded),
            label: const Text('Iniciar Live de Jogo',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sectionHeader('🔴 Ao Vivo Agora'),
        _buildLivesList(_filtered),
        if (_filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nenhuma live nesta categoria agora.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38),
            ),
          ),
        _sectionHeader('🔥 Populares'),
        _buildPopularList(),
        _sectionHeader('🏆 Ranking de Criadores'),
        _buildRanking(),
        _sectionHeader('👤 Criadores de Jogos'),
        _buildCreators(),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildLivesList(List<RealLive> lives) {
    if (lives.isEmpty) {
      return const SizedBox.shrink();
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: lives.length,
      itemBuilder: (context, i) {
        final live = lives[i];
        return _GameLiveCard(
          live: live,
          onEditLive: () => _editLive(live),
          onDeleteLive: () => _deleteLive(live),
        );
      },
    );
  }

  Widget _buildPopularList() {
    if (_popular.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _popular.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final live = _popular[i];
          return SizedBox(
            width: 230,
            child: _GameLiveCard(
              live: live,
              horizontal: true,
              onEditLive: () => _editLive(live),
              onDeleteLive: () => _deleteLive(live),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRanking() {
    if (_popular.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < _popular.length && i < 5; i++)
            _RankingRow(
              rank: i + 1,
              live: _popular[i],
            ),
        ],
      ),
    );
  }

  Widget _buildCreators() {
    // Criadores únicos entre as lives de jogo (por streamer).
    final seen = <String>{};
    final creators = <RealLive>[];
    for (final l in _gameLives) {
      if (seen.add(l.streamerId)) creators.add(l);
      if (creators.length >= 6) break;
    }
    if (creators.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: creators.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final c = creators[i];
          return _CreatorCard(live: c);
        },
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _GameLiveCard extends StatelessWidget {
  final RealLive live;
  final bool horizontal;
  final VoidCallback? onEditLive;
  final VoidCallback? onDeleteLive;
  const _GameLiveCard({
    required this.live,
    this.horizontal = false,
    this.onEditLive,
    this.onDeleteLive,
  });

  bool get _isOwner =>
      SupabaseService.instance.client.auth.currentUser?.id == live.streamerId;

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveRoomScreen(
              live: live,
              role:
                  _isOwner ? LiveRole.streamer : LiveRole.viewer,
              isGameLive: true,
            ),
          ),
        );
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1B4D), Color(0xFF14142B)],
          ),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (live.coverUrl != null && live.coverUrl!.isNotEmpty)
              Image.network(
                live.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Positioned(top: 8, left: 8, child: _liveBadge()),
            if (_isOwner || onEditLive != null || onDeleteLive != null)
              Positioned(
                top: 4,
                right: 2,
                child: ContentOverflowMenu(
                  isOwner: _isOwner,
                  onEdit: onEditLive ?? () {},
                  onDelete: onDeleteLive ?? () {},
                ),
              ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 8,
                        backgroundColor: Colors.white24,
                        backgroundImage: live.streamerAvatar != null &&
                                live.streamerAvatar!.isNotEmpty
                            ? NetworkImage(live.streamerAvatar!)
                            : null,
                        child: live.streamerAvatar == null ||
                                live.streamerAvatar!.isEmpty
                            ? const Icon(Icons.person, size: 10, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                live.streamerDisplayName ?? 'Criador',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            if (live.streamerVerified) ...[
                              const SizedBox(width: 3),
                              const VerifiedBadge(size: 11),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (live.gameName != null && live.gameName!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const Text('🎮',
                        style: TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (horizontal) return Row(children: [Expanded(child: card)]);
    return card;
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            'AO VIVO · ${live.viewerCount}',
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final int rank;
  final RealLive live;
  const _RankingRow({required this.rank, required this.live});

  bool get _isOwner =>
      SupabaseService.instance.client.auth.currentUser?.id == live.streamerId;

  @override
  Widget build(BuildContext context) {
    final medals = <String>['🥇', '🥈', '🥉'];
    return ListTile(
      leading: Text(
        rank <= 3 ? medals[rank - 1] : '$rank°',
        style: const TextStyle(
            fontSize: 18, color: Colors.white, fontWeight: FontWeight.w900),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              live.streamerDisplayName ?? 'Criador',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          if (live.streamerVerified) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(size: 14),
          ],
        ],
      ),
      subtitle: Text(
        '${live.viewerCount} espectadores',
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LiveRoomScreen(
            live: live,
            role: _isOwner ? LiveRole.streamer : LiveRole.viewer,
            isGameLive: true,
          ),
        ));
      },
    );
  }
}

class _CreatorCard extends StatelessWidget {
  final RealLive live;
  const _CreatorCard({required this.live});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => UserProfileScreen(userId: live.streamerId),
        ));
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
            backgroundImage:
                live.streamerAvatar != null && live.streamerAvatar!.isNotEmpty
                    ? NetworkImage(live.streamerAvatar!)
                    : null,
            child: live.streamerAvatar == null || live.streamerAvatar!.isEmpty
                ? const Icon(Icons.person, color: Colors.white, size: 28)
                : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 88,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    live.streamerDisplayName ?? 'Criador',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                if (live.streamerVerified) ...[
                  const SizedBox(width: 3),
                  const VerifiedBadge(size: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 56),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }
}
