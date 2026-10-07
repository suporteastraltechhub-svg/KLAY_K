import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/store_models.dart';
import '../services/store_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import '../design/klayk_design.dart';
import 'store_cart_screen.dart';
import 'store_manage_screen.dart';
import 'store_orders_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Marketplace do KLAY K: catálogo em grid por categoria, busca, carrinho e
/// acesso aos meus anúncios e pedidos.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final _searchDebounce = KlaykDebouncer(const Duration(milliseconds: 350));
  List<StoreCategory> _categories = [];
  List<StoreProduct> _products = [];
  String? _selectedCategory;
  bool _loading = true;
  int _cartCount = 0;
  int _searchTick = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final categories = await StoreService.instance.fetchCategories();
      final products = await _queryProducts();
      final count = await StoreService.instance.cartCount();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _products = products;
        _cartCount = count;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<StoreProduct>> _queryProducts() {
    return StoreService.instance.fetchProducts(
      categoryId: _selectedCategory,
      query: _searchTick == 0 ? null : _searchCtrl.text,
    );
  }

  Future<void> _refresh() => _load();

  Future<void> _openCart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StoreCartScreen()));
    _refresh();
  }

  Future<void> _openOrders() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StoreOrdersScreen()));
  }

  Future<void> _openManage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StoreManageScreen()));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.store,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          KlayKIconButton(onTap: _openManage, icon: Icons.storefront_outlined),
          KlayKIconButton(
            onTap: _openOrders,
            icon: Icons.receipt_long_outlined,
          ),
          _cartBadge(),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 5)
          : RefreshIndicator(
              onRefresh: _refresh,
              color: _kAccent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _searchField(l10n),
                  const SizedBox(height: 12),
                  _categoryChips(l10n),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.productsLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        l10n.storeProductCount(_products.length),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!SupabaseService.instance.isConfigured)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          l10n.storeConfigureSupabase,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else if (_products.isEmpty)
                    KlaykEmptyState(
                      icon: Icons.shopping_bag_outlined,
                      title: l10n.noProductsFound,
                      message: l10n.noProductsFoundBody,
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                      itemCount: _products.length,
                      itemBuilder: (context, i) =>
                          _productCard(l10n, _products[i]),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _cartBadge() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: KlayKIconButton(
        onTap: _openCart,
        icon: Icons.shopping_cart_outlined,
        badge: _cartCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: const BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                child: Text(
                  '$_cartCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _searchField(AppLocalizations l10n) {
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white),
      onSubmitted: (_) {
        _searchTick++;
        _refresh();
      },
      onChanged: (_) {
        _searchDebounce.run(() {
          if (!mounted) return;
          _searchTick++;
          _refresh();
        });
      },
      decoration: InputDecoration(
        hintText: l10n.storeSearchHint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        suffixIcon: TextButton(
          onPressed: _searchCtrl.text.trim().isEmpty
              ? null
              : () {
                  _searchCtrl.clear();
                  _searchTick++;
                  _refresh();
                },
          child: Text(l10n.clear),
        ),
        filled: true,
        fillColor: const Color(0xFF17141F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2540)),
        ),
      ),
    );
  }

  Widget _categoryChips(AppLocalizations l10n) {
    const all = StoreCategory(id: '', name: '', icon: '🛍️', slug: 'todas');
    final items = [all, ..._categories];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final selected =
              (c.id.isEmpty && _selectedCategory == null) ||
              (_selectedCategory == c.id && c.id.isNotEmpty);
          return KlayKChip(
            label: '${c.icon} ${c.id.isEmpty ? l10n.allCategory : c.name}',
            selected: selected,
            onTap: () {
              setState(() {
                _selectedCategory = c.id.isEmpty ? null : c.id;
              });
              _refresh();
            },
          );
        },
      ),
    );
  }

  Widget _productCard(AppLocalizations l10n, StoreProduct p) {
    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProductDetail(l10n, p),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF17141F),
            border: Border.all(color: const Color(0xFF2A2540)),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (p.imageUrl.isNotEmpty)
                      Image.network(
                        p.imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: imageDecodeWidth(context, 140),
                        errorBuilder: (_, _, _) => _imageFallback(p),
                      )
                    else
                      _imageFallback(p),
                    if (p.outOfStock)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Text(
                          l10n.outOfStockChip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatPrice(p.price),
                          style: const TextStyle(
                            color: _kAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    if (p.stock > 0 && p.stock < 5) ...[
                      const SizedBox(height: 2),
                      Text(
                        l10n.lowStockCount(p.stock),
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageFallback(StoreProduct p) {
    return Container(
      color: const Color(0xFF211D33),
      alignment: Alignment.center,
      child: Text(
        p.title.isEmpty ? '🛍️' : p.title.substring(0, 1).toUpperCase(),
        style: const TextStyle(color: Colors.white24, fontSize: 34),
      ),
    );
  }

  Future<void> _showProductDetail(AppLocalizations l10n, StoreProduct p) async {
    var qty = 1;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (p.imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    p.imageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                p.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatPrice(p.price),
                style: const TextStyle(
                  color: _kAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  p.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    l10n.quantityLabel,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: qty > 1 ? () => setModal(() => qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$qty',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    onPressed: p.stock > qty
                        ? () => setModal(() => qty++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: p.outOfStock
                      ? null
                      : () async {
                          try {
                            Navigator.of(ctx).pop();
                            await StoreService.instance.addToCart(
                              p.id,
                              quantity: qty,
                            );
                            _refresh();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.addedToCart)),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.addToCartError(e))),
                              );
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    p.outOfStock ? l10n.outOfStockLabel : l10n.addToCartButton,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
