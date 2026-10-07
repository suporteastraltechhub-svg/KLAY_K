import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/gift_models.dart';
import '../services/gift_service.dart';
import '../widgets/gift_animations.dart';

/// Tela de catálogo de presentes. Carrega sob demanda (paginação + lazy
/// loading) a partir do backend real. Busca, filtros por categoria/raridade e
/// abas dinâmicas (Recomendados/Populares/Tendências/Novos/Favoritos).
///
/// Se chamado com [liveId]/[receiverId], habilita o envio seguro.
class GiftCatalogScreen extends StatefulWidget {
  final String? liveId;
  final String? receiverId;
  final String title;

  const GiftCatalogScreen({
    super.key,
    this.liveId,
    this.receiverId,
    this.title = '',
  });

  @override
  State<GiftCatalogScreen> createState() => GiftCatalogScreenState();
}

class GiftCatalogScreenState extends State<GiftCatalogScreen> {
  final _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  GiftService get _gift => GiftService.instance;

  List<GiftCategory> _categories = [];
  List<GiftRarity> _rarities = [];
  String? _categoryId;
  String? _rarityId;

  int _tab =
      0; // 0 recomendados, 1 populares, 2 tendências, 3 novos, 4 favoritos
  final List<Gift> _items = [];
  Set<String> _favs = {};
  int? _wallet;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const _pageSize = 40;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await _gift.fetchCategories();
      final rars = await _gift.fetchRarities();
      int wallet = 0;
      try {
        wallet = await _gift.fetchWallet();
      } catch (_) {}
      List<String> favIds = const [];
      try {
        favIds = await _gift.fetchFavoriteIds();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _rarities = rars;
        _wallet = wallet;
        _favs = favIds.toSet();
        _loading = false;
      });
      await _reload(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<Gift>> _loadPage(int page) async {
    switch (_tab) {
      case 1:
        return _gift.fetchPopular(limit: _pageSize);
      case 2:
        return _gift.fetchTrending(limit: _pageSize);
      case 3:
        return _gift.fetchNewest(limit: _pageSize);
      case 4:
        return _gift.fetchFavoriteGifts();
      default:
        return _gift.fetchGifts(
          categoryId: _categoryId,
          rarityId: _rarityId,
          query: _query,
          page: page,
          pageSize: _pageSize,
        );
    }
  }

  Future<void> _reload({bool reset = true}) async {
    if (reset) {
      setState(() {
        _items.clear();
        _page = 0;
        _hasMore = true;
        _loading = true;
      });
    }
    try {
      if (_tab == 4) {
        final favGifts = await _gift.fetchFavoriteGifts();
        if (!mounted) return;
        setState(() {
          _items
            ..clear()
            ..addAll(favGifts);
          _hasMore = false;
          _loading = false;
        });
        return;
      }
      final newItems = await _loadPage(_page);
      if (!mounted) return;
      setState(() {
        _items.addAll(newItems);
        _hasMore = newItems.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _tab == 4) return;
    setState(() => _loadingMore = true);
    _page += 1;
    try {
      final newItems = await _loadPage(_page);
      if (!mounted) return;
      setState(() {
        _items.addAll(newItems);
        _hasMore = newItems.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _selectTab(int t) {
    if (_tab == t) return;
    setState(() => _tab = t);
    _reload(reset: true);
  }

  void _onCategory(String? id) {
    setState(() => _categoryId = id);
    _reload(reset: true);
  }

  void _onRarity(String? id) {
    setState(() => _rarityId = id);
    _reload(reset: true);
  }

  void _onSearch(String q) {
    _query = q.trim();
    _reload(reset: true);
  }

  Future<void> _toggleFav(Gift g) async {
    try {
      await _gift.toggleFavorite(g.id);
      final ids = await _gift.fetchFavoriteIds();
      if (!mounted) return;
      setState(() => _favs = ids.toSet());
      if (_tab == 4) {
        await _reload(reset: true);
      }
    } catch (_) {}
  }

  Future<void> _openGift(Gift g) async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _GiftDetailSheet(
        gift: g,
        wallet: _wallet,
        canSend: widget.liveId != null,
        onFavorite: () async {
          await _gift.toggleFavorite(g.id);
          final ids = await _gift.fetchFavoriteIds();
          if (ctx.mounted) {
            // estado atualizado via hero após retornar
          }
          if (mounted) setState(() => _favs = ids.toSet());
        },
      ),
    );
    if (amount == null || !mounted) return;
    await _send(g, amount);
  }

  Future<void> _send(Gift g, int amount) async {
    try {
      if (widget.liveId == null) {
        final l10n = AppLocalizations.of(context);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n!.sendGiftsOnlyInLive)));
        return;
      }
      final result = await _gift.sendGift(
        gift: g,
        amount: amount,
        liveId: widget.liveId,
        receiverId: widget.receiverId,
      );
      if (!mounted) return;
      setState(() => _wallet = result.balance);
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF14141B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C26),
        title: Text(
          widget.title.isEmpty ? l10n.giftsTitle : widget.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_wallet != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: CreditsPill(credits: _wallet!)),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCategoryRow(),
          _buildRarityRow(),
          _buildTabs(),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onSubmitted: _onSearch,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: l10n.searchGiftsHint,
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear, color: Colors.white54),
            onPressed: () {
              _searchCtrl.clear();
              _onSearch('');
            },
          ),
          filled: true,
          fillColor: const Color(0xFF23232E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildCategoryRow() {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(l10n.giftAllFilter, null, _categoryId == null),
          for (final c in _categories)
            _chip('${c.emoji} ${c.name}', c.id, _categoryId == c.id),
        ],
      ),
    );
  }

  Widget _chip(String label, String? id, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        selected: selected,
        backgroundColor: const Color(0xFF23232E),
        selectedColor: const Color(0xFF7C4DFF),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        onSelected: (_) => _onCategory(id),
      ),
    );
  }

  Widget _buildRarityRow() {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _rarityChip(l10n.giftAllFilter, null, _rarityId == null),
          for (final r in _rarities)
            _rarityChip('${r.emoji} ${r.name}', r.id, _rarityId == r.id),
        ],
      ),
    );
  }

  Widget _rarityChip(String label, String? id, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        selected: selected,
        backgroundColor: const Color(0xFF2A2A35),
        selectedColor: const Color(0xFFB388FF),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        onSelected: (_) => _onRarity(id),
      ),
    );
  }

  Widget _buildTabs() {
    final l10n = AppLocalizations.of(context)!;
    final tabs = [
      l10n.giftRecommended,
      l10n.giftPopular,
      l10n.giftTrending,
      l10n.giftNew,
      l10n.giftFavorites,
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  tabs[i],
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                selected: _tab == i,
                backgroundColor: const Color(0xFF1C1C26),
                selectedColor: const Color(0xFF00E5FF),
                onSelected: (_) => _selectTab(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final l10n = AppLocalizations.of(context)!;
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.giftCatalogLoadFail(_error!),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          l10n.noGiftsFound,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final g = _items[index];
        return _GiftCard(
          gift: g,
          isFav: _favs.contains(g.id),
          onTap: () => _openGift(g),
          onFav: () => _toggleFav(g),
        );
      },
    );
  }
}

class _GiftCard extends StatelessWidget {
  final Gift gift;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onFav;

  const _GiftCard({
    required this.gift,
    required this.isFav,
    required this.onTap,
    required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C26),
          borderRadius: BorderRadius.circular(14),
          border: gift.isExclusive
              ? Border.all(color: const Color(0xFF00E5FF), width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Text(gift.icon, style: const TextStyle(fontSize: 38)),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: GestureDetector(
                      onTap: onFav,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav
                              ? const Color(0xFFFF5252)
                              : Colors.white38,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                gift.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.creditsCount(gift.credits),
              style: TextStyle(
                color: gift.rarityColor != null
                    ? _hex(gift.rarityColor!)
                    : const Color(0xFFFFD700),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _hex(String h) {
  var s = h.replaceFirst('#', '');
  if (s.length == 6) s = 'FF$s';
  final v = int.tryParse(s, radix: 16);
  return v == null ? const Color(0xFFFFD700) : Color(v);
}

class _GiftDetailSheet extends StatelessWidget {
  final Gift gift;
  final int? wallet;
  final bool canSend;
  final VoidCallback onFavorite;

  const _GiftDetailSheet({
    required this.gift,
    required this.wallet,
    required this.canSend,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final afford = wallet != null && wallet! >= gift.credits;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${gift.icon} ${gift.name}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            if (gift.rarityName != null)
              Text(
                gift.rarityName!,
                style: TextStyle(
                  color: gift.rarityColor != null
                      ? _hex(gift.rarityColor!)
                      : const Color(0xFFFFD700),
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                gift.description.isEmpty
                    ? l10n.virtualGiftFromCatalog
                    : gift.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  l10n.creditsCount(gift.credits),
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (wallet != null)
                  Text(
                    l10n.balanceOf(wallet!),
                    style: TextStyle(
                      color: afford ? Colors.white70 : const Color(0xFFFF5252),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (!canSend)
              Text(
                l10n.enterLiveToSend,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            if (canSend) ...[
              Text(
                l10n.quantityLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [1, 5, 10, 66, 99].map((n) {
                  final cost = n * gift.credits;
                  final ok = wallet == null || wallet! >= cost;
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ok
                          ? const Color(0xFF7C4DFF)
                          : const Color(0xFF3A3A45),
                      disabledBackgroundColor: const Color(0xFF3A3A45),
                    ),
                    onPressed: ok ? () => Navigator.of(context).pop(n) : null,
                    child: Text('x$n'),
                  );
                }).toList(),
              ),
            ],
            TextButton(
              onPressed: onFavorite,
              child: Text(
                l10n.favoriteToggle,
                style: const TextStyle(color: Color(0xFFFF5252)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
