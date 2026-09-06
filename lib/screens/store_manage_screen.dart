import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ProductFormScreen(product: p)),
    );
    _load();
  }

  Future<void> _toggle(StoreProduct p) async {
    try {
      await StoreService.instance.toggleProductActive(p.id, !p.isActive);
      _load();
    } catch (e) {
      _snack('Erro: $e');
    }
  }

  Future<void> _delete(StoreProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: const Text('Excluir produto?',
            style: TextStyle(color: Colors.white)),
        content: Text('"${p.title}" será removido da Loja.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StoreService.instance.deleteProduct(p.id);
      _load();
    } catch (e) {
      _snack('Erro: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: const Text('Meus anúncios',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _products.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_outlined,
                          color: Colors.white24, size: 52),
                      SizedBox(height: 12),
                      Text(
                        'Você ainda não tem produtos\nCadastre o primeiro e comece a vender no KLAY K',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
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
                    itemBuilder: (context, i) => _productRow(_products[i]),
                  ),
                ),
    );
  }

  Widget _productRow(StoreProduct p) {
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
                          child: Icon(Icons.image_outlined,
                              color: Colors.white24)),
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
                            fontSize: 14),
                      ),
                    ),
                    if (!p.isActive)
                      const Text('  (pausado)',
                          style: TextStyle(
                              color: Colors.orange, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatPrice(p.price)} • ${p.stock} em estoque',
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
              const PopupMenuItem(
                  value: 'edit',
                  child: Text('Editar', style: TextStyle(color: Colors.white))),
              PopupMenuItem(
                  value: 'toggle',
                  child: Text(p.isActive ? 'Pausar' : 'Ativar',
                      style: const TextStyle(color: Colors.white))),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Excluir', style: TextStyle(color: Colors.redAccent))),
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
        builder: (_) => const Center(
            child: CircularProgressIndicator(color: _kAccent)),
      );
      final url = await ContentService.instance.uploadCover(File(picked.path));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack('Erro ao enviar imagem: $e');
    }
  }

  double _parsePrice() {
    var raw = _priceCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (raw.isEmpty) raw = '0';
    return double.tryParse(raw) ?? 0;
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Informe o título');
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
      _snack('Erro ao salvar: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
            _p == null ? 'Novo produto' : 'Editar produto',
            style: const TextStyle(fontWeight: FontWeight.w800)),
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
                const Center(
                  child: Text('Toque para escolher a foto',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
                const SizedBox(height: 16),
                _field(_titleCtrl, 'Título do produto'),
                const SizedBox(height: 10),
                _field(_descCtrl, 'Descrição', maxLines: 3),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _priceCtrl,
                        'Preço (R\$)',
                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                        prefix: const Text('R\$ ',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _stockCtrl,
                        'Estoque',
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _categoryDropdown(),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_saving ? 'Salvando…' : 'Salvar produto'),
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
      child: const Icon(Icons.add_a_photo_outlined,
          color: Colors.white38, size: 40),
    );
  }

  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboard, Widget? prefix}) {
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

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _categoryId,
      dropdownColor: const Color(0xFF17151F),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Categoria',
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
          child: Text('Sem categoria',
              style: TextStyle(
                  color: _categoryId == null || _categoryId!.isEmpty
                      ? Colors.white
                      : Colors.white54)),
        ),
        ..._categories.map(
          (c) => DropdownMenuItem<String>(
            value: c.id,
            child: Text('${c.icon} ${c.name}',
                style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _categoryId = (v == null || v.isEmpty) ? null : v),
    );
  }
}