import 'package:flutter/material.dart';

import '../models/store_models.dart';
import '../services/store_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Carrinho da Loja: quantidade, total e dados de entrega para finalizar a
/// compra (RPC `checkout_cart` valida estoque no backend).
class StoreCartScreen extends StatefulWidget {
  const StoreCartScreen({super.key});

  @override
  State<StoreCartScreen> createState() => _StoreCartScreenState();
}

class _StoreCartScreenState extends State<StoreCartScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  List<CartItem> _items = [];
  bool _loading = true;
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await StoreService.instance.fetchCart();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total =>
      _items.fold<double>(0, (sum, it) => sum + it.subtotal);

  Future<void> _checkout() async {
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    if (name.isEmpty || address.isEmpty) {
      _snack('Informe o nome e o endereço de entrega');
      return;
    }
    setState(() => _checkingOut = true);
    try {
      final count = await StoreService.instance.checkout(
        shippingName: name,
        shippingPhone: _phoneCtrl.text.trim(),
        shippingAddress: address,
      );
      if (!mounted) return;
      setState(() => _checkingOut = false);
      if (count > 0) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF17151F),
            icon: const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 44),
            title: const Text('Pedido realizado!',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            content: Text(
              count == 1
                  ? 'Seu pedido foi gerado. O vendedor foi notificado e o status acompanhado na aba Pedidos.'
                  : '$count pedidos gerados (um por vendedor). O status é acompanhado na aba Pedidos.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: _kAccent),
                child: const Text('Ok'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop(); // fecha o carrinho
      }
    } catch (e) {
      if (mounted) setState(() => _checkingOut = false);
      _snack('Erro no checkout: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: const Text('Carrinho',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          color: Colors.white24, size: 52),
                      SizedBox(height: 12),
                      Text('Seu carrinho está vazio',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ..._items.map((it) => _itemCard(it)),
                    const SizedBox(height: 16),
                    const Text('Dados de entrega',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    const SizedBox(height: 8),
                    _field(_nameCtrl, 'Nome de quem recebe'),
                    const SizedBox(height: 8),
                    _field(_phoneCtrl, 'Telefone (opcional)',
                        keyboard: TextInputType.phone),
                    const SizedBox(height: 8),
                    _field(_addressCtrl, 'Endereço completo',
                        maxLines: 2),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1A26),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Text('Total',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text(
                            formatPrice(_total),
                            style: const TextStyle(
                                color: _kAccent,
                                fontSize: 20,
                                fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _checkingOut ? null : _checkout,
                      icon: _checkingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text(_checkingOut
                          ? 'Finalizando…'
                          : 'Finalizar compra (${_items.length} item(ns))'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint,
      {TextInputType? keyboard, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1B1A26),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _itemCard(CartItem it) {
    final p = it.product;
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
              width: 64,
              height: 64,
              child: p != null && p.imageUrl.isNotEmpty
                  ? Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _thumbFallback(p.title),
                    )
                  : _thumbFallback(p?.title ?? '?'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p?.title ?? 'Produto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  formatPrice(it.subtotal),
                  style: const TextStyle(
                      color: _kAccent, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _qtyButton(Icons.remove, () async {
                      await StoreService.instance
                          .updateCartQuantity(it.id, it.quantity - 1);
                      _load();
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${it.quantity}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    _qtyButton(Icons.add, () async {
                      final max = p?.stock ?? 99;
                      if (max <= it.quantity) return;
                      await StoreService.instance
                          .updateCartQuantity(it.id, it.quantity + 1);
                      _load();
                    }),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: () async {
                        await StoreService.instance.removeFromCart(it.id);
                        _load();
                      },
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white38, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2740),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _thumbFallback(String title) {
    return Container(
      color: const Color(0xFF26223A),
      alignment: Alignment.center,
      child: Text(
        title.isEmpty ? '🛍️' : title.substring(0, 1).toUpperCase(),
        style: const TextStyle(color: Colors.white24, fontSize: 22),
      ),
    );
  }
}