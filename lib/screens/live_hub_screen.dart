import 'dart:async';

import 'package:flutter/material.dart';

import '../models/klayk_live_models.dart';
import '../services/live_kit_service.dart';
import '../services/supabase_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/klay_live_feed_card.dart';
import 'live_room_screen.dart';
import 'start_live_screen.dart';

/// Tela "LIVE AO VIVO" — hub central de todas as lives ativas.
///
/// Mostra lives reais do Supabase (status='live'), com miniatura/capa,
/// nome do criador, título, categoria, quantidade de espectadores e
/// indicador 🔴 AO VIVO. Ao tocar na miniatura, o usuário entra na
/// transmissão (tela cheia ou modo normal).
class LiveHubScreen extends StatefulWidget {
  const LiveHubScreen({super.key});

  @override
  State<LiveHubScreen> createState() => _LiveHubScreenState();
}

class _LiveHubScreenState extends State<LiveHubScreen> {
  final SupabaseService _db = SupabaseService.instance;

  List<RealLive> _lives = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  String _filterCategory = 'Todos';

  static const _kFilterCategories = [
    'Todos',
    '🎮 Jogos',
    '📹 Vídeo',
    '🎙️ Áudio',
    '🎬 Conteúdo',
    '👥 Amigos',
    '🎟️ Eventos',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_db.isConfigured) {
      if (mounted) {
        setState(() {
          _loading = false;
          _lives = [];
          _error = null;
        });
      }
      return;
    }
    try {
      final lives = await _db.fetchActiveLives();
      if (!mounted) return;
      setState(() {
        _lives = lives;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar as lives';
      });
    }
  }

  List<RealLive> get _filteredLives {
    if (_filterCategory == 'Todos') return _lives;
    return _lives.where((l) => l.category == _filterCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0812),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0812),
        automaticallyImplyLeading: false,
        title: Text(
          l10n.liveHubTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _load,
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStartBanner(),
          _buildCategoryFilter(l10n),
          const SizedBox(height: 4),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildStartBanner() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: FilledButton.icon(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const StartLiveScreen()));
        },
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8B5CF6),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.sensors_rounded),
        label: Text(
          l10n.createLiveTitle,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(AppLocalizations l10n) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _kFilterCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _kFilterCategories[index];
          final selected = _filterCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _filterCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFF1C1C26),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF8B5CF6)
                      : const Color(0xFF2A2540),
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sensors_rounded,
                color: Colors.white38,
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    if (_filteredLives.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.live_tv_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.noLivesTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noLivesSubtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StartLiveScreen()),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              icon: const Icon(Icons.sensors_rounded),
              label: Text(l10n.createLiveTitle),
            ),
          ],
        ),
      );
    }
    return _buildLivesGrid();
  }

  Widget _buildLivesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: _filteredLives.length,
      itemBuilder: (context, index) {
        final live = _filteredLives[index];
        final isOwner =
            SupabaseService.instance.client.auth.currentUser?.id ==
            live.streamerId;
        return KlayLiveFeedCard(
          live: live,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LiveRoomScreen(
                  live: live,
                  role: isOwner ? LiveRole.streamer : LiveRole.viewer,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
