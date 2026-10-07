import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../models/store_models.dart';
import '../services/content_service.dart';
import '../services/store_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Gestão do meu anúncio na Loja: cadastro, edição, ativar/pausar e excluir
/// produtos. Tudo persistido em `store_products` com RLS do vendedor.
class StoreManageScreen extends StatefulWidget {
  const StoreManageScreen({super.key});

  @override
  State<StoreManageScreen> createState() => _StoreManageScreenState();
}

class _StoreManageScreenState extends State<StoreManageScreen> {
  List<StoreProduct> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await StoreService.instance.fetchMyProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([StoreProduct? p]) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _ProductFormScreen(product: p)));
    _load();
  }

  Future<void> _toggle(StoreProduct p) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await StoreService.instance.toggleProductActive(p.id, !p.isActive);
      _load();
    } catch (e) {
      _snack(l10n.storeErrorGeneric(e));
    }
  }

  Future<void> _delete(StoreProduct p) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(
          l10n.deleteProductTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.deleteProductBody(p.title),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.back,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StoreService.instance.deleteProduct(p.id);
      _load();
    } catch (e) {
      _snack(l10n.storeErrorGeneric(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.myAdsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(l10n.newProductButton),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _products.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    color: Colors.white24,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${l10n.storeNoProductsTitle}\n${l10n.storeNoProductsBody}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: _kAccent,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: _products.length,
                itemBuilder: (context, i) => _productRow(l10n, _products[i]),
              ),
            ),
    );
  }

  Widget _productRow(AppLocalizations l10n, StoreProduct p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: p.imageUrl.isNotEmpty
                  ? Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : Container(
                      color: const Color(0xFF26223A),
                      child: const Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.white24,
                        ),
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
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!p.isActive)
                      Text(
                        '  ${l10n.storeProductPaused}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatPrice(p.price)} • ${l10n.storeInStock(p.stock)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            color: const Color(0xFF17151F),
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _openForm(p);
                case 'toggle':
                  _toggle(p);
                case 'delete':
                  _delete(p);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  l10n.edit,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Text(
                  p.isActive ? l10n.pauseTooltip : l10n.enableTooltip,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  l10n.delete,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductFormScreen extends StatefulWidget {
  final StoreProduct? product;

  const _ProductFormScreen({this.product});

  @override
  State<_ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<_ProductFormScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  List<StoreCategory> _categories = [];
  String? _categoryId;
  String? _imageUrl;
  bool _loading = true;
  bool _saving = false;

  StoreProduct? get _p => widget.product;

  @override
  void initState() {
    super.initState();
    _categoriesLoad();
  }

  Future<void> _categoriesLoad() async {
    try {
      final cats = await StoreService.instance.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        final p = widget.product;
        _titleCtrl.text = p?.title ?? '';
        _descCtrl.text = p?.description ?? '';
        _priceCtrl.text = p == null ? '' : p.price.toStringAsFixed(2);
        _stockCtrl.text = p == null ? '' : '${p.stock}';
        _categoryId = p?.categoryId;
        _imageUrl = p?.imageUrl;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const Center(child: CircularProgressIndicator(color: _kAccent)),
      );
      final url = await ContentService.instance.uploadCover(File(picked.path));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack(l10n.storeImageUploadError(e));
    }
  }

  double _parsePrice() {
    var raw = _priceCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (raw.isEmpty) raw = '0';
    return double.tryParse(raw) ?? 0;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack(l10n.storeTitleRequired);
      return;
    }
    final price = _parsePrice();
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      final p = widget.product;
      if (p == null) {
        await StoreService.instance.createProduct(
          title: title,
          description: _descCtrl.text.trim(),
          price: price,
          categoryId: _categoryId,
          imageUrl: _imageUrl ?? '',
          stock: stock,
        );
      } else {
        await StoreService.instance.updateProduct(
          id: p.id,
          title: title,
          description: _descCtrl.text.trim(),
          price: price,
          categoryId: _categoryId,
          imageUrl: _imageUrl ?? '',
          stock: stock,
          isActive: p.isActive,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(l10n.storeSaveError(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          _p == null ? l10n.productFormTitleNew : l10n.productFormTitleEdit,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 180,
                        height: 180,
                        child: _imageUrl != null
                            ? Image.network(
                                _imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _imagePlaceholder(),
                              )
                            : _imagePlaceholder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    l10n.storePickPhotoHint,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                _field(_titleCtrl, l10n.storeProductTitleHint),
                const SizedBox(height: 10),
                _field(_descCtrl, l10n.descriptionLabel, maxLines: 3),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _priceCtrl,
                        l10n.storePriceHint,
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        prefix: const Text(
                          'R\$ ',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _stockCtrl,
                        l10n.stockLabel,
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _categoryDropdown(l10n),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _saving ? l10n.savingLabel : l10n.saveProductButton,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFF26223A),
      alignment: Alignment.center,
      child: const Icon(
        Icons.add_a_photo_outlined,
        color: Colors.white38,
        size: 40,
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboard,
    Widget? prefix,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: keyboard == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefix: prefix,
        filled: true,
        fillColor: const Color(0xFF1B1A26),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _categoryDropdown(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
      initialValue: _categoryId,
      dropdownColor: const Color(0xFF17151F),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: l10n.categoryLabel,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1B1A26),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(
            l10n.noCategoryLabel,
            style: TextStyle(
              color: _categoryId == null || _categoryId!.isEmpty
                  ? Colors.white
                  : Colors.white54,
            ),
          ),
        ),
        ..._categories.map(
          (c) => DropdownMenuItem<String>(
            value: c.id,
            child: Text(
              '${c.icon} ${c.name}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
      onChanged: (v) =>
          setState(() => _categoryId = (v == null || v.isEmpty) ? null : v),
    );
  }
}
