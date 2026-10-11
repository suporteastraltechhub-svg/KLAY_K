import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/klay_live_widgets.dart';
import '../../models/store_models.dart';
import '../../services/store_service.dart';

/// Detalhe de um anúncio do marketplace.
///
/// Lê preço, estoque e vendedor do que veio do BANCO. A tela não recalcula
/// preço nem decide disponibilidade: quem manda nisso é o `checkout_cart`,
/// que trava o produto e confere o estoque antes de fechar o pedido.
class StoreProductScreen extends StatefulWidget {
  const StoreProductScreen({super.key, required this.productId});

  final String productId;

  @override
  State<StoreProductScreen> createState() => _StoreProductScreenState();
}

class _StoreProductScreenState extends State<StoreProductScreen> {
  StoreService get _svc => StoreService.instance;

  StoreProduct? _produto;
  bool _carregando = true;
  bool _favorito = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final p = await _svc.fetchProduct(widget.productId);
      final fav = await _svc.isFavorite(widget.productId);
      if (!mounted) return;
      setState(() {
        _produto = p;
        _favorito = fav;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível abrir este anúncio.';
      });
    }
  }

  Future<void> _alternarFavorito() async {
    final novo = await _svc.toggleFavorite(widget.productId);
    if (!mounted) return;
    setState(() => _favorito = novo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(novo ? 'Adicionado aos favoritos' : 'Removido dos favoritos'),
        backgroundColor: kkBg,
      ),
    );
  }

  Future<void> _compartilhar() async {
    final p = _produto;
    if (p == null) return;
    await Share.share(
      '${p.title} — R\$ ${p.price.toStringAsFixed(2)} no KLAY K\n'
      'https://klayk.app/produto/${p.id}',
      subject: p.title,
    );
  }

  Future<void> _comprar() async {
    final p = _produto;
    if (p == null) return;
    try {
      await _svc.addToCart(p.id, quantity: 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicionado ao carrinho'),
          backgroundColor: kkBg,
        ),
      );
    } on StoreException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: kkBg),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kkBg,
      appBar: AppBar(
        backgroundColor: kkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Produto',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: Icon(_favorito ? Icons.favorite_rounded : Icons.favorite_border_rounded),
            color: kkAccent,
            tooltip: 'Favoritar',
            onPressed: _carregando ? null : _alternarFavorito,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Compartilhar',
            onPressed: _carregando ? null : _compartilhar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: kkAccent))
          : _erro != null
          ? _erroView()
          : _detalhe(),
      bottomNavigationBar: _produto == null || !_produto!.isListed
          ? null
          : _barraCompra(),
    );
  }

  Widget _erroView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 44),
          const SizedBox(height: 12),
          Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _carregar,
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    ),
  );

  Widget _detalhe() {
    final p = _produto!;
    final fotos = p.allPhotos;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (fotos.isNotEmpty)
          _Galeria(fotos: fotos)
        else
          Container(
            height: 220,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kkSurface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.image_not_supported_rounded, size: 40),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'R\$ ${p.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: kkAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Tag(
                    text: p.isNew ? 'Novo' : 'Usado',
                    fg: kkAccent,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _vendedor(p),
              const SizedBox(height: 16),
              _linhaInfo(
                Icons.inventory_2_outlined,
                p.outOfStock
                    ? 'Sem estoque no momento'
                    : '${p.stock} disponível(is)',
                p.outOfStock ? const Color(0xFFEF4444) : null,
              ),
              _linhaInfo(
                Icons.local_shipping_outlined,
                _entregaTexto(p),
              ),
              if (p.soldCount > 0)
                _linhaInfo(Icons.trending_up_rounded, '${p.soldCount} vendido(s)'),
              const SizedBox(height: 18),
              if (p.description.trim().isNotEmpty) ...[
                const Text(
                  'Descrição',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  p.description,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (!p.isListed)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kkSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kkAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'Este anúncio não está disponível para compra agora.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _entregaTexto(StoreProduct p) {
    final partes = <String>[
      if (p.deliveryOptions.contains('entrega')) 'Entrega combinada',
      if (p.deliveryOptions.contains('retirada')) 'Retirada',
      if (p.deliveryOptions.contains('envio')) 'Envio',
    ];
    final base = partes.isEmpty ? 'Combinar com o vendedor' : partes.join(' · ');
    final local = [p.city, p.state].where((e) => e != null && e.isNotEmpty).join('/');
    return local.isEmpty ? base : '$base · $local';
  }

  Widget _vendedor(StoreProduct p) => Row(
    children: [
      const CircleAvatar(
        radius: 16,
        backgroundColor: kkAccent,
        child: Icon(Icons.person_rounded, size: 18, color: Colors.white),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'Vendedor ${p.sellerId.isEmpty ? 'do KLAY K' : p.sellerId.substring(0, 8)}',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    ],
  );

  Widget _linhaInfo(IconData ic, String txt, [Color? cor]) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(ic, size: 19, color: cor ?? Colors.white54),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            txt,
            style: TextStyle(color: cor ?? Colors.white70),
          ),
        ),
      ],
    ),
  );

  Widget _barraCompra() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: kkBg,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          onPressed: _comprar,
          icon: const Icon(Icons.shopping_bag_rounded),
          label: const Text(
            'Comprar',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: kkAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Galeria extends StatefulWidget {
  const _Galeria({required this.fotos});
  final List<String> fotos;

  @override
  State<_Galeria> createState() => _GaleriaState();
}

class _GaleriaState extends State<_Galeria> {
  final _ctrl = PageController();
  int _i = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.fotos.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => Image.network(
              widget.fotos[i],
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, __, ___) => Container(
                color: kkSurface,
                child: const Icon(Icons.broken_image_rounded, size: 40),
              ),
            ),
          ),
        ),
        if (widget.fotos.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.fotos.length, (i) {
              final ativo = i == _i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: ativo ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: ativo ? kkAccent : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.fg});
  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: fg.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: fg.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: fg,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Erro de rede do Supabase mostrado ao usuário final.
String descreverErroLoja(Object e) {
  if (e is PostgrestException) return 'Não foi possível falar com a loja agora.';
  return 'Não foi possível concluir. Tente de novo.';
}