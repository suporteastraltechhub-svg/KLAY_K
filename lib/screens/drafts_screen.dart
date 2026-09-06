import 'package:flutter/material.dart';

import '../services/drafts_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';

/// Rascunhos do usuário: vídeos salvos para publicar depois. São privados
/// (bucket `drafts` + tabela `drafts` com RLS de dono) e nunca aparecem no
/// feed/perfil. Publicar envia a mídia para os buckets públicos e cria o post.
class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key, this.store});

  /// Armazenamento de rascunhos. Quando nulo, usa [DraftsService.instance]
  /// (Supabase real). Os testes injetam um fake determinístico.
  final DraftStore? store;

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  late final DraftStore _svc = widget.store ?? DraftsService.instance;
  List<Draft> _drafts = [];
  bool _loading = true;
  String? _publishingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final drafts = await _svc.list();
    if (!mounted) return;
    setState(() {
      _drafts = drafts;
      _loading = false;
    });
  }

  Future<void> _publish(Draft d) async {
    if (_publishingId != null) return;
    setState(() => _publishingId = d.id);
    try {
      final post = await _svc.publish(d.id);
      if (!mounted) return;
      if (post != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vídeo publicado com sucesso!')),
        );
        await _load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível publicar o rascunho.')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishingId = null);
    }
  }

  Future<void> _remove(Draft d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: const Text('Excluir rascunho?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _svc.remove(d.id);
    await _load();
  }

  /// Edita a legenda/hashtags do rascunho (publicação usa o que estiver aqui).
  Future<void> _edit(Draft d) async {
    final desc = TextEditingController(text: d.description);
    final tags = TextEditingController(
      text: d.hashtags.map((h) => '#$h').join(' '),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: const Text('Editar rascunho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: desc,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              cursorColor: const Color(0xFF8A2BE2),
              decoration: InputDecoration(
                labelText: 'Descrição',
                labelStyle: const TextStyle(color: Colors.white38),
                hintText: 'O que está acontecendo?',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1E1B2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tags,
              style: const TextStyle(color: Colors.white),
              cursorColor: const Color(0xFF8A2BE2),
              decoration: InputDecoration(
                labelText: 'Hashtags',
                labelStyle: const TextStyle(color: Colors.white38),
                hintText: '#klayk #amigo',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1E1B2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final parsed = <String>[
      for (final t in tags.text.split(RegExp(r'\s+')))
        if (t.startsWith('#')) t.substring(1),
    ];
    await _svc.update(
      d,
      description: desc.text.trim(),
      hashtags: parsed,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kcolors(context).bg,
      appBar: AppBar(title: const Text('Rascunhos')),
      body: _loading
          ? const Center(child: KlaykLoader())
          : _drafts.isEmpty
              ? const KlaykEmptyState(
                  icon: Icons.note_alt_rounded,
                  title: 'Nenhum rascunho',
                  message: 'Rascunhos privados ainda não criados. '
                      'Guardamos vídeos incompletos para você publicar depois.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _drafts.length,
                    itemBuilder: (context, i) => _draftTile(_drafts[i]),
                  ),
                ),
    );
  }

  Widget _draftTile(Draft d) {
    final colors = kcolors(context);
    final publishing = _publishingId == d.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KlaykCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 78,
                child: Container(
                  color: colors.surfaceAlt,
                  child: const Icon(Icons.movie_rounded, color: Colors.white38),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.description.trim().isNotEmpty
                        ? d.description
                        : 'Rascunho sem legenda',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Editado em ${_formatDate(d.updatedAt)}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: publishing ? null : () => _edit(d),
              icon: const Icon(Icons.edit_outlined, color: Colors.white38),
              tooltip: 'Editar',
            ),
            IconButton(
              onPressed: publishing ? null : () => _remove(d),
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white38),
              tooltip: 'Excluir',
            ),
            FilledButton.icon(
              onPressed: publishing ? null : () => _publish(d),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
              icon: publishing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_rounded, size: 16),
              label: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}