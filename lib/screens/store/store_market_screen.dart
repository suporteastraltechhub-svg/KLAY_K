import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/store_models.dart';
import '../../services/store_service.dart';
import '../../widgets/klay_live_widgets.dart';
import 'store_product_screen.dart';
import 'store_sell_screen.dart';

/// Marketplace da aba Loja.
///
/// Catálogo real de produtos físicos entre usuários — separado da loja
/// oficial de itens digitais (`shop_screen.dart`), que não aparece aqui.
///
/// Tudo que aparece vem do banco via `StoreService`: se a tabela estiver
/// vazia, a tela mostra estado vazio de verdade. Nenhum produto de exemplo é
/// inventado.
class StoreMarketScreen extends StatefulWidget {
  const StoreMarketScreen({super.key, required this.topPadding});

  final double topPadding;

  @override
  State<StoreMarketScreen> createState() => _StoreMarketScreenState();
}

class _StoreMarketScreenState extends State<StoreMarketScreen> {
  StoreService get _svc => StoreService.instance;

  final _busca = TextEditingController();
  Timer? _debounce;

  List<StoreProduct> _produtos = const [];
  List<StoreCategory> _categorias = const [];
  bool _carregando = true;
  String? _erro;
  String? _categoriaId;
  String _ordem = 'recentes';
  int _aba = 0; // 0 catálogo, 1 minha loja

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarCategorias();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregarCategorias() async {
    try {
      final c = await _svc.fetchCategories();
      if (!mounted) return;
      setState(() => _categorias = c);
    } catch (_) {/* opcional */}
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final p = await _svc.browseMarketplace(
        categoryId: _categoriaId,
        search: _busca.text,
        sort: _ordem,
      );
      if (!mounted) return;
      setState(() {
        _produtos = p;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar os anúncios.';
      });
    }
  }

  void _buscar(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _carregar);
  }

  Future<void> _abrirProduto(StoreProduct p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoreProductScreen(productId: p.id)),
    );
    if (mounted) _carregar();
  }

  Future<void> _vender() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoreSellScreen()),
    );
    if (ok == true && mounted) {
      setState(() => _aba = 1);
      _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: widget.topPadding),
        _topo(),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator(color: kkAccent))
              : _erro != null
              ? _erroView()
              : IndexedStack(index: _aba, children: [_catalogo(), _minhaLoja()]),
        ),
      ],
    );
  }


  Widget _topo() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                l10n.store,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              _botaoVender(),
            ],
          ),
          const SizedBox(height: 12),
          _buscaField(),
          const SizedBox(height: 10),
          _abas(),
        ],
      ),
    );
  }

  /// Botão ＋ VENDER — destacado, com gradiente roxo do KLAY K.
  Widget _botaoVender() {
    return GestureDetector(
      onTap: _vender,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFFC084F0)],
          ),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
              blurRadius: 14,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: Colors.white),
            SizedBox(width: 5),
            Text(
              'Vender',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buscaField() => Container(
    height: 44,
    decoration: BoxDecoration(
      color: kkSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      children: [
        const SizedBox(width: 12),
        const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _busca,
            onChanged: _buscar,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Buscar produtos',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (_busca.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: Colors.white54,
            onPressed: () {
              _busca.clear();
              _carregar();
              setState(() {});
            },
          ),
      ],
    ),
  );

  Widget _abas() => Row(
    children: [
      _chip('Catálogo', _aba == 0, () => setState(() => _aba = 0)),
      const SizedBox(width: 8),
      _chip('Minha loja', _aba == 1, () => setState(() => _aba = 1)),
    ],
  );

  Widget _catalogo() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      if (_categorias.isNotEmpty) _filtros(),
      if (_produtos.isEmpty)
        _vazio(
          Icons.storefront_rounded,
          _carregando ? 'Carregando…' : 'Nenhum anúncio por aqui ainda.',
          _carregando ? '' : 'Seja o primeiro a vender no KLAY K.',
        )
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: _produtos.length,
          itemBuilder: (_, i) => _card(_produtos[i]),
        ),
    ],
  );

  Widget _filtros() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip('Tudo', _categoriaId == null, () {
              setState(() => _categoriaId = null);
              _carregar();
            }),
            const SizedBox(width: 8),
            for (final c in _categorias) ...[
              _chip(c.name, _categoriaId == c.id, () {
                setState(() => _categoriaId = c.id);
                _carregar();
              }),
              const SizedBox(width: 8),
            ],
            _chip(_rotuloOrdem(), true, () {
              setState(() => _ordem = _proximaOrdem());
              _carregar();
            }),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
  );

  String _rotuloOrdem() => switch (_ordem) {
    'populares' => 'Populares',
    'menor_preco' => 'Menor preço',
    'maior_preco' => 'Maior preço',
    _ => 'Recentes',
  };

  String _proximaOrdem() => switch (_ordem) {
    'recentes' => 'populares',
    'populares' => 'menor_preco',
    'menor_preco' => 'maior_preco',
    _ => 'recentes',
  };

  Widget _card(StoreProduct p) => GestureDetector(
    onTap: () => _abrirProduto(p),
    child: Container(
      decoration: BoxDecoration(
        color: kkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                p.imageUrl.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFF1F1F1F),
                        child: Icon(Icons.image_outlined, color: Colors.white24),
                      )
                    : Image.network(
                        p.imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 500,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFF1F1F1F),
                          child: Icon(Icons.broken_image_outlined, color: Colors.white24),
                        ),
                      ),
                if (p.status == 'vendido')
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _selo('VENDIDO', Colors.white24, Colors.white70),
                  )
                else if (!p.isNew)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _selo('USADO', Colors.black54, Colors.white70),
                  ),
                if (p.outOfStock)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: const Center(
                        child: Text(
                          'ESGOTADO',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'R\$ ${p.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: kkAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _vendedorCurto(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String _vendedorCurto(StoreProduct p) =>
      p.sellerId.isEmpty ? 'KLAY K' : 'Vendedor ${p.sellerId.substring(0, 8)}';

  Widget _selo(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(
      t,
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: fg),
    ),
  );

  Widget _minhaLoja() => FutureBuilder<List<StoreProduct>>(
    future: _svc.myProducts(),
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: kkAccent));
      }
      if (snap.hasError) {
        return _erroView();
      }
      final lista = snap.data ?? const [];
      if (lista.isEmpty) {
        return _vazio(
          Icons.sell_outlined,
          'Você ainda não tem anúncios.',
          'Toque em ＋ Vender para criar o primeiro.',
          acao: _vender,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: lista.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _linhaMeu(lista[i]),
      );
    },
  );

  Widget _linhaMeu(StoreProduct p) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: kkSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 54,
                height: 54,
                child: p.imageUrl.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFF1F1F1F),
                        child: Icon(Icons.image_outlined, size: 18),
                      )
                    : Image.network(
                        p.imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFF1F1F1F),
                          child: Icon(Icons.broken_image_outlined, size: 18),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'R\$ ${p.price.toStringAsFixed(2)} · ${p.stock} em estoque',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  _statusChip(p.status),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: kkSurface,
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
              onSelected: (v) => _acao(v, p),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'editar', child: Text('Editar')),
                PopupMenuItem(
                  value: p.status == 'publicado' ? 'pausar' : 'publicar',
                  child: Text(p.status == 'publicado' ? 'Pausar' : 'Republicar'),
                ),
                const PopupMenuItem(value: 'vendido', child: Text('Marcar vendido')),
                const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _miniAcao(
                Icons.remove_rounded,
                p.stock <= 0,
                () => _mudarEstoque(p, p.stock - 1),
              ),
            ),
            Expanded(
              child: Container(
                alignment: Alignment.center,
                child: Text(
                  '${p.stock}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Expanded(
              child: _miniAcao(Icons.add_rounded, false, () => _mudarEstoque(p, p.stock + 1)),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _acao(String acao, StoreProduct p) async {
    try {
      switch (acao) {
        case 'editar':
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => StoreSellScreen(produto: p)),
          );
          if (ok == true) setState(() {});
        case 'pausar':
          await _svc.setProductStatus(p.id, 'pausado');
          setState(() {});
        case 'publicar':
          await _svc.setProductStatus(p.id, 'publicado');
          setState(() {});
        case 'vendido':
          await _svc.setProductStatus(p.id, 'vendido');
          setState(() {});
        case 'excluir':
          final ok = await _confirmar('Excluir anúncio?', p.title);
          if (ok) {
            await _svc.deleteProduct(p.id);
            setState(() {});
          }
      }
    } on StoreException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _mudarEstoque(StoreProduct p, int n) async {
    try {
      await _svc.updateStock(p.id, n);
      setState(() {});
    } on StoreException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<bool> _confirmar(String titulo, String sub) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kkSurface,
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        content: Text(sub, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    return r == true;
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), backgroundColor: kkBg),
  );

  Widget _miniAcao(IconData ic, bool desativado, VoidCallback onTap) => InkWell(
    onTap: desativado ? null : onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        ic,
        size: 17,
        color: desativado ? Colors.white12 : Colors.white70,
      ),
    ),
  );

  Widget _statusChip(String s) {
    final (cor, rot) = switch (s) {
      'publicado' => (const Color(0xFF22C55E), 'Publicado'),
      'vendido' => (const Color(0xFFEF4444), 'Vendido'),
      _ => (Colors.white54, 'Pausado'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        rot,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cor),
      ),
    );
  }

  Widget _erroView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 42),
          const SizedBox(height: 12),
          Text(
            _erro ?? 'Erro ao carregar.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
        ],
      ),
    ),
  );

  Widget _vazio(IconData ic, String titulo, String sub, {VoidCallback? acao}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, color: Colors.white24, size: 48),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (acao != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: acao,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Vender'),
              style: FilledButton.styleFrom(backgroundColor: kkAccent),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _chip(String txt, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: sel ? kkAccent.withValues(alpha: 0.2) : kkSurface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: sel ? kkAccent : Colors.white12),
      ),
      child: Text(
        txt,
        style: TextStyle(
          color: sel ? Colors.white : Colors.white60,
          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    ),
  );
}