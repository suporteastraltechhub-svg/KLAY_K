import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/store_models.dart';
import '../../services/store_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/klay_live_widgets.dart';

/// Formulário de anúncio: ＋ Vender.
///
/// Publica pelo RPC `store_publish_product`, que valida título, preço, estoque
/// e categoria NO SERVIDOR. A validação daqui é só para dar retorno rápido;
/// quem decide é o banco.
class StoreSellScreen extends StatefulWidget {
  const StoreSellScreen({super.key, this.produto});

  /// Quando informado, o formulário vira EDIÇÃO do próprio anúncio.
  final StoreProduct? produto;

  @override
  State<StoreSellScreen> createState() => _StoreSellScreenState();
}

class _StoreSellScreenState extends State<StoreSellScreen> {
  final _form = GlobalKey<FormState>();
  StoreService get _svc => StoreService.instance;

  late final TextEditingController _titulo;
  late final TextEditingController _descricao;
  late final TextEditingController _preco;
  late final TextEditingController _estoque;
  late final TextEditingController _cidade;
  late final TextEditingController _uf;

  List<StoreCategory> _categorias = const [];
  String? _categoriaId;
  String _condicao = 'novo';
  String _status = 'publicado';
  final Set<String> _entrega = {'entrega'};
  final List<String> _fotos = [];
  bool _enviando = false;
  String? _erro;

  bool get _edicao => widget.produto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.produto;
    _titulo = TextEditingController(text: p?.title ?? '');
    _descricao = TextEditingController(text: p?.description ?? '');
    _preco = TextEditingController(
      text: p == null ? '' : p.price.toStringAsFixed(2),
    );
    _estoque = TextEditingController(text: p == null ? '' : '${p.stock}');
    _cidade = TextEditingController(text: p?.city ?? '');
    _uf = TextEditingController(text: p?.state ?? '');
    _categoriaId = p?.categoryId;
    _condicao = p?.condition ?? 'novo';
    _status = p?.status ?? 'publicado';
    if (p != null) {
      _fotos.addAll(p.allPhotos);
      _entrega
        ..clear()
        ..addAll(p.deliveryOptions.isEmpty ? ['entrega'] : p.deliveryOptions);
    }
    _carregarCategorias();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descricao.dispose();
    _preco.dispose();
    _estoque.dispose();
    _cidade.dispose();
    _uf.dispose();
    super.dispose();
  }

  Future<void> _carregarCategorias() async {
    try {
      final c = await _svc.fetchCategories();
      if (!mounted) return;
      setState(() => _categorias = c);
    } catch (_) {
      // Sem categorias o formulário ainda funciona: o campo é opcional.
    }
  }

  /// "1.234,56" ou "1234.56" -> 1234.56
  double? _parsePreco(String t) {
    var s = t.trim().replaceAll(RegExp(r'[^\d,.]'), '');
    if (s.isEmpty) return null;
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  Future<void> _adicionarFotos() async {
    final restantes = StoreService.maxPhotos - _fotos.length;
    if (restantes <= 0) {
      _avisar('Máximo de ${StoreService.maxPhotos} fotos por anúncio.');
      return;
    }
    try {
      final picked = await ImagePicker().pickMultiImage(limit: restantes);
      if (picked.isEmpty) return;

      final userId = SupabaseService.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _avisar('Entre na sua conta para vender.');
        return;
      }

      for (final x in picked) {
        final bytes = await x.readAsBytes();
        if (bytes.length > StoreService.maxPhotoBytes) {
          _avisar('A imagem "${x.name}" passa de 5 MB. Escolha uma menor.');
          continue;
        }
        final url = await _svc.uploadProductPhoto(
          userId: userId,
          fileName: x.name,
          bytes: bytes,
        );
        if (!mounted) return;
        setState(() => _fotos.add(url));
      }
    } catch (e) {
      if (!mounted) return;
      _avisar(descreverErroLoja(e));
    }
  }

  void _avisar(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: kkBg),
    );
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;
    final preco = _parsePreco(_preco.text);
    if (preco == null) {
      _avisar('Informe um preço válido.');
      return;
    }
    final estoque = int.tryParse(_estoque.text.trim());
    if (estoque == null || estoque < 0) {
      _avisar('Informe uma quantidade válida.');
      return;
    }
    if (_fotos.isEmpty) {
      _avisar('Adicione pelo menos uma foto do produto.');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      if (_edicao) {
        await _svc.editProduct(
          id: widget.produto!.id,
          title: _titulo.text,
          description: _descricao.text,
          price: preco,
          stock: estoque,
          categoryId: _categoriaId,
          photos: _fotos,
          condition: _condicao,
          deliveryOptions: _entrega.toList(),
          city: _cidade.text.trim(),
          state: _uf.text.trim(),
        );
        if (_status != (widget.produto!.status)) {
          await _svc.setProductStatus(widget.produto!.id, _status);
        }
      } else {
        await _svc.publishProduct(
          title: _titulo.text,
          price: preco,
          stock: estoque,
          description: _descricao.text,
          categoryId: _categoriaId,
          photos: _fotos,
          condition: _condicao,
          deliveryOptions: _entrega.toList(),
          city: _cidade.text.trim(),
          state: _uf.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _avisar(_edicao ? 'Anúncio atualizado.' : 'Anúncio publicado!');
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = descreverErroLoja(e);
      });
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
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _edicao ? 'Editar anúncio' : 'Vender',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _fotoPicker(),
            const SizedBox(height: 20),
            _campo(_titulo, 'Nome do produto', validar: _vTitulo),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descricao,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Descrição (opcional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _campo(
                    _preco,
                    'Preço (R\$)',
                    teclado: const TextInputType.numberWithOptions(decimal: true),
                    validar: _vPreco,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campo(
                    _estoque,
                    'Quantidade',
                    teclado: TextInputType.number,
                    validar: _vEstoque,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _seccao('Categoria'),
            if (_categorias.isEmpty)
              const Text(
                'Nenhuma categoria disponível.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categorias
                    .map(
                      (c) => _chip(
                        c.name,
                        _categoriaId == c.id,
                        () => setState(
                          () => _categoriaId = _categoriaId == c.id ? null : c.id,
                        ),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 20),
            _seccao('Estado do produto'),
            Row(
              children: [
                _chip('Novo', _condicao == 'novo', () => setState(() => _condicao = 'novo')),
                const SizedBox(width: 8),
                _chip('Usado', _condicao == 'usado', () => setState(() => _condicao = 'usado')),
              ],
            ),
            const SizedBox(height: 20),
            _seccao('Entrega'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipToggle('Entrega combinada', 'entrega'),
                _chipToggle('Retirada', 'retirada'),
                _chipToggle('Envio', 'envio'),
              ],
            ),
            const SizedBox(height: 20),
            _seccao('Onde você entrega (opcional)'),
            Row(
              children: [
                Expanded(child: _campo(_cidade, 'Cidade')),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: _campo(_uf, 'UF'),
                ),
              ],
            ),
            if (_edicao) ...[
              const SizedBox(height: 20),
              _seccao('Status do anúncio'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('Publicado', _status == 'publicado', () => setState(() => _status = 'publicado')),
                  _chip('Pausado', _status == 'pausado', () => setState(() => _status = 'pausado')),
                  _chip('Vendido', _status == 'vendido', () => setState(() => _status = 'vendido')),
                ],
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _erro!,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _barra(),
    );
  }

  Widget _barra() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: _enviando ? null : _enviar,
          style: FilledButton.styleFrom(
            backgroundColor: kkAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _enviando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _edicao ? 'Salvar alterações' : 'Publicar anúncio',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
        ),
      ),
    ),
  );

  Widget _fotoPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _seccao('Fotos (até ${StoreService.maxPhotos})'),
      SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < _fotos.length; i++)
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _fotos[i],
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: kkSurface,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _fotos.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (_fotos.length < StoreService.maxPhotos)
              GestureDetector(
                onTap: _adicionarFotos,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: kkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, color: Colors.white70),
                      SizedBox(height: 4),
                      Text(
                        'Adicionar',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _seccao(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );

  Widget _campo(
    TextEditingController c,
    String rotulo, {
    TextInputType? teclado,
    String? Function(String?)? validar,
  }) => TextFormField(
    controller: c,
    keyboardType: teclado,
    style: const TextStyle(color: Colors.white),
    validator: validar,
    decoration: _dec(rotulo),
  );

  String? _vTitulo(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Dê um nome ao produto.' : null;

  String? _vPreco(String? v) {
    if (v == null || v.trim().isEmpty) return 'Informe o preço.';
    if (_parsePreco(v) == null) return 'Preço inválido.';
    return null;
  }

  String? _vEstoque(String? v) {
    if (v == null || v.trim().isEmpty) return 'Informe a quantidade.';
    final n = int.tryParse(v.trim());
    if (n == null || n < 0) return 'Quantidade inválida.';
    return null;
  }

  InputDecoration _dec(String h) => InputDecoration(
    hintText: h,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: kkSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _chip(String txt, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: sel ? kkAccent.withValues(alpha: 0.22) : kkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sel ? kkAccent : Colors.white12,
          width: sel ? 1.4 : 1,
        ),
      ),
      child: Text(
        txt,
        style: TextStyle(
          color: sel ? Colors.white : Colors.white70,
          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    ),
  );

  Widget _chipToggle(String txt, String chave) {
    final sel = _entrega.contains(chave);
    return _chip(txt, sel, () {
      setState(() {
        sel ? _entrega.remove(chave) : _entrega.add(chave);
      });
    });
  }
}

/// Mensagem de rede do Supabase para o usuário final.
String descreverErroLoja(Object e) {
  if (e is PostgrestException) return 'Não foi possível falar com a loja agora.';
  return 'Não foi possível concluir. Tente de novo.';
}