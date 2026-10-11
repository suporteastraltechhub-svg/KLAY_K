import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/post_models.dart';
import '../services/content_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';
import 'profile/video_preview_screen.dart';

/// Página de uma hashtag: vídeos relacionados, contador e ordenação.
///
/// É a destino de tocar numa hashtag na busca, no Descobrir e nos vídeos em
/// alta. Não existe tabela de hashtags no projeto (só a coluna `text[]` em
/// `posts`), então "seguir hashtag" não cabe na arquitetura atual e não foi
/// inventado aqui — para isso seria preciso o modelo de assinatura de hashtag.
class HashtagScreen extends StatefulWidget {
  const HashtagScreen({super.key, required this.tag});

  ///.Tag sem `#`. Pode chegar com ou sem, a limpeza é feita na service.
  final String tag;

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  static const int _pageSize = 24;

  final ScrollController _scroll = ScrollController();

  List<FeedPost> _posts = const <FeedPost>[];
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 400;
    if (nearEnd && _hasMore && !_loadingMore && !_loading) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
    });
    final svc = ContentService.instance;
    // Contador e lista em paralelo: uma espera a outra não.
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      svc.countPostsByHashtag(widget.tag),
      svc.fetchPostsByHashtag(widget.tag, limit: _pageSize),
    ]);
    if (!mounted) return;
    final posts = (results[1] as List<FeedPost>);
    setState(() {
      _total = (results[0] as int);
      _posts = posts;
      _offset = posts.length;
      _hasMore = posts.length < _total;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final more = await ContentService.instance.fetchPostsByHashtag(
      widget.tag,
      limit: _offset + _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _posts = more;
      _offset = more.length;
      _hasMore = more.length < _total;
      _loadingMore = false;
    });
  }

  String get _cleanTag {
    final t = widget.tag.trim().replaceAll('#', '').toLowerCase();
    return t.isEmpty ? 'klayk' : t;
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text('#$_cleanTag'), backgroundColor: colors.bg),
      body: RefreshIndicator(
        onRefresh: _load,
        color: colors.primary,
        child: _body(colors, l10n),
      ),
    );
  }

  Widget _body(KlaykColors colors, AppLocalizations? l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorState(colors);
    }
    if (_posts.isEmpty) {
      return _emptyState(colors, l10n);
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _posts.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _tile(_posts[i], colors);
      },
    );
  }

  Widget _tile(FeedPost post, KlaykColors colors) {
    final cover = post.coverUrl ?? '';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => VideoPreviewScreen(post: post)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: colors.surface,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (cover.isNotEmpty)
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  cacheWidth: imageDecodeWidth(context, 130),
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              Positioned(
                left: 4,
                bottom: 4,
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _compact(post.likesCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compact(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1)}M';
    }
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _errorState(KlaykColors colors) {
    return ListView(
      children: <Widget>[
        const SizedBox(height: 90),
        Icon(Icons.cloud_off_rounded, color: colors.primary, size: 44),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Não foi possível carregar agora',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(KlaykColors colors, AppLocalizations? l10n) {
    return ListView(
      children: <Widget>[
        const SizedBox(height: 90),
        Icon(Icons.tag_rounded, color: colors.primary, size: 46),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Nenhum vídeo com #$_cleanTag ainda',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Sigue para o primeiro',
            style: TextStyle(color: colors.primary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
