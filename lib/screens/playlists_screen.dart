import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/playlist_models.dart';
import '../services/playlist_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import 'playlist_detail_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Playlists do KLAY K: descoberta de playlists públicas criadas pelos
/// criadores, busca e criação. Toque abre os vídeos da playlist.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<KlayKPlaylist> _all = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      if (!SupabaseService.instance.isConfigured) {
        throw Exception('Supabase não configurado');
      }
      final playlists = await PlaylistService.instance.fetchPublic(
        query: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _all = playlists;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _openCreate() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreatePlaylistDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _creating = true);
    try {
      final created = await PlaylistService.instance.create(name: name);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PlaylistDetailScreen(playlist: created, ownsIt: created.isMine),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : l10n.playlistsCreateFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
    _load();
  }

  void _openPlaylist(KlayKPlaylist p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlist: p, ownsIt: p.isMine),
      ),
    );
  }

  void _clearSearch() {
    _searchCtrl.clear();
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
          l10n.playlistsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _load(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: l10n.playlistsSearchHint,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _searchCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38),
                        onPressed: _clearSearch,
                      ),
                filled: true,
                fillColor: const Color(0xFF17141F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2540)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2540)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kAccent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading ? const KlaykListSkeleton(rows: 6) : _buildBody(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        onPressed: _creating ? null : _openCreate,
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: Text(_creating ? l10n.playlistsCreating : l10n.playlistsNew),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: l10n.playlistsLoadFailTitle,
        message: l10n.playlistsLoadFailMsg,
        actionLabel: l10n.retry,
        actionIcon: Icons.refresh_rounded,
        onAction: _load,
      );
    }
    if (_all.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.video_library_outlined,
        title: l10n.playlistsEmptyTitle,
        message: l10n.playlistsEmptyMsg,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _all.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _playlistCard(context, _all[i]),
      ),
    );
  }

  Widget _playlistCard(BuildContext context, KlayKPlaylist p) {
    final l10n = AppLocalizations.of(context)!;
    final colors = kc(context);
    return GestureDetector(
      onTap: () => _openPlaylist(p),
      child: KlayKCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: p.coverUrl.isEmpty
                  ? Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2A2350), Color(0xFF161026)],
                        ),
                        border: Border.all(color: const Color(0xFF2A2540)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.video_library_rounded,
                        color: _kAccent,
                        size: 26,
                      ),
                    )
                  : Image.network(
                      p.coverUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFF2A2350),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.video_library_rounded,
                          color: Color(0xFF8B5CF6),
                          size: 26,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (p.isMine) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.person_pin_rounded,
                          color: Colors.white38,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.playlistsVideoCount(p.postCount),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        color: colors.primarySoft,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          p.creatorName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.play_circle_outline_rounded,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: const Color(0xFF17141F),
      title: Text(
        l10n.playlistsNew,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            maxLength: 60,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.playlistsNameHint,
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            maxLength: 140,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.playlistsDescHint,
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.cancel,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
          ),
          onPressed: _submit,
          child: Text(l10n.createAction),
        ),
      ],
    );
  }
}
