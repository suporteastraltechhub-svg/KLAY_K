import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Coleções/favoritos do KLAY K. Agrupa vídeos salvos em listas nomeadas,
/// persistidas no Supabase (`collections` + `collection_posts`).
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  bool _loading = true;
  List<CollectionItem> _collections = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final collections = await SocialService.instance.fetchCollections();
      if (!mounted) return;
      setState(() {
        _collections = collections;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCollection() async {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(l10n.collectionsNew),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.collectionsNameHint,
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            child: Text(l10n.createAction),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await SocialService.instance.createCollection(name);
      _load();
    } catch (e) {
      _snack(l10n.collectionsCreateError(e.toString()));
    }
  }

  Future<void> _openCollection(CollectionItem c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CollectionDetailScreen(collection: c)),
    );
    _load();
  }

  Future<void> _delete(CollectionItem c) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(l10n.collectionsDeleteTitle(c.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Color(0xFFFF4D6A)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SocialService.instance.deleteCollection(c.id);
      _load();
    } catch (e) {
      _snack(l10n.collectionsDeleteError(e.toString()));
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.collectionsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCollection,
        backgroundColor: _kAccent,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(l10n.collectionsNew),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _collections.isEmpty
          ? Center(
              child: Text(
                l10n.collectionsEmpty,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _collections.length,
              itemBuilder: (context, i) {
                final c = _collections[i];
                return Card(
                  color: const Color(0xFF1B1A26),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF2A2740),
                      backgroundImage:
                          c.coverUrl != null && c.coverUrl!.isNotEmpty
                          ? NetworkImage(c.coverUrl!)
                          : null,
                      child: c.coverUrl == null || c.coverUrl!.isEmpty
                          ? const Icon(
                              Icons.video_library_outlined,
                              color: Colors.white54,
                            )
                          : null,
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      c.isPublic
                          ? l10n.collectionsPublic
                          : l10n.collectionsPrivate,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _delete(c),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFFFF4D6A),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ],
                    ),
                    onTap: () => _openCollection(c),
                  ),
                );
              },
            ),
    );
  }
}

class _CollectionDetailScreen extends StatefulWidget {
  final CollectionItem collection;
  const _CollectionDetailScreen({required this.collection});

  @override
  State<_CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<_CollectionDetailScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final posts = await SocialService.instance.fetchCollectionPosts(
        widget.collection.id,
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
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
          widget.collection.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _posts.isEmpty
          ? Center(
              child: Text(
                l10n.collectionsDetailEmpty,
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.75,
              ),
              itemCount: _posts.length,
              itemBuilder: (context, i) {
                final p = _posts[i];
                final url = p['video_url']?.toString() ?? '';
                final desc = p['description']?.toString() ?? '';
                return Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (url.isNotEmpty)
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.movie, color: Colors.white24),
                        )
                      else
                        const Icon(Icons.movie, color: Colors.white24),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Text(
                          desc.isEmpty ? l10n.collectionsVideoLabel : desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
