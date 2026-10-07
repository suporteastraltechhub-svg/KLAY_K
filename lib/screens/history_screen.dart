import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/post_models.dart';
import '../services/social_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';
import 'profile/video_preview_screen.dart';

/// Histórico de visualização do usuário (reusa `user_history` — repositório
/// real já persistido por feed/lives). Ordenado do mais recente para o mais
/// antigo, com opção de limpar tudo.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _loading = true;
  bool _clearing = false;
  List<FeedPost> _posts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await SocialService.instance.fetchHistory();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(l10n.historyClearTitle),
        content: Text(l10n.historyClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.historyClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || _clearing) return;
    setState(() => _clearing = true);
    try {
      await SocialService.instance.clearHistory();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _posts = const [];
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.historyClearedSnack)));
  }

  void _openPost(FeedPost post) {
    KlaykNav.push(context, VideoPreviewScreen(post: post));
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (_posts.isNotEmpty)
            IconButton(
              onPressed: _clearing ? null : _clear,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: KlaykLoader())
          : _posts.isEmpty
          ? KlaykEmptyState(
              icon: Icons.history_rounded,
              title: l10n.historyEmptyTitle,
              message: l10n.historyEmptyMsg,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _historyTile(_posts[i]),
            ),
    );
  }

  Widget _historyTile(FeedPost post) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return KlaykCard(
      padding: const EdgeInsets.all(10),
      onTap: () => _openPost(post),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 84,
              child: post.coverUrl != null && post.coverUrl!.isNotEmpty
                  ? Image.network(
                      post.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colors.surfaceAlt,
                        child: const Icon(Icons.movie_rounded),
                      ),
                    )
                  : Container(
                      color: colors.surfaceAlt,
                      child: const Icon(Icons.movie_rounded),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.description.isNotEmpty
                      ? post.description
                      : l10n.historyVideo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      post.author?.displayName ?? l10n.historyParticipant,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}
