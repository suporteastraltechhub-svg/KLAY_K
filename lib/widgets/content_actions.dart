import 'package:flutter/material.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _danger = Color(0xFFFF4D6A);
const Color _panel = Color(0xFF1C1C26);

/// Widgets reutilizáveis de ações de conteúdo do criador (menu ⋮, diálogos de
/// edição e exclusão). Reforçam a regra de negócio: somente o dono do conteúdo
/// vê/usa Editar e Apagar; a validação real acontece no backend (RLS + RPCs
/// security definer), nunca apenas escondendo os botões.

/// Botão de ⋮ que só aparece para o dono do conteúdo e oferece Editar/Apagar.
/// Para não-donos retorna um widget vazio (sem menu exposto).
class ContentOverflowMenu extends StatelessWidget {
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Color iconColor;

  const ContentOverflowMenu({
    super.key,
    required this.isOwner,
    required this.onEdit,
    required this.onDelete,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOwner) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      color: _panel,
      icon: Icon(Icons.more_vert_rounded, color: iconColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.edit_rounded, color: Colors.white, size: 22),
              SizedBox(width: 12),
              Text('Editar',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: _danger, size: 22),
              SizedBox(width: 12),
              Text('Apagar',
                  style: TextStyle(
                      color: _danger, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Diálogo de confirmação de exclusão. Retorna `true` se o usuário confirmar.
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Apagar',
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      icon: const Icon(Icons.warning_amber_rounded, color: _danger, size: 34),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(message,
          style: const TextStyle(color: Colors.white70, height: 1.35)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel,
              style: const TextStyle(color: _danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return go == true;
}

/// Resultado da edição de um vídeo.
class PostEditResult {
  final String description;
  final List<String> hashtags;
  const PostEditResult({required this.description, required this.hashtags});
}

/// Diálogo de edição de vídeo (descrição + hashtags).
Future<PostEditResult?> editPostDialog(
  BuildContext context, {
  required String description,
  List<String> hashtags = const [],
}) async {
  final descCtrl = TextEditingController(text: description);
  final tagsCtrl = TextEditingController(text: hashtags.join(' '));
  final result = await showDialog<PostEditResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      title: const Text('Editar vídeo', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: descCtrl,
            maxLines: 4,
            maxLength: 2200,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Descrição',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: _accent)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tagsCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Hashtags (separadas por espaço)',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: _accent)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          onPressed: () {
            final tags = tagsCtrl.text
                .split(RegExp(r'\s+'))
                .where((t) => t.trim().isNotEmpty)
                .map((t) => t.trim())
                .toList();
            Navigator.of(ctx).pop(PostEditResult(
              description: descCtrl.text.trim(),
              hashtags: tags,
            ));
          },
          style: FilledButton.styleFrom(backgroundColor: _accent),
          child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result;
}

/// Resultado da edição de uma live.
class LiveEditResult {
  final String title;
  final String description;
  final String category;
  final String privacy;
  const LiveEditResult({
    required this.title,
    required this.description,
    required this.category,
    required this.privacy,
  });
}

/// Diálogo de edição de live (título + descrição + categoria + privacidade).
Future<LiveEditResult?> editLiveDialog(
  BuildContext context, {
  required String title,
  String description = '',
  String category = '',
  String privacy = 'public',
}) async {
  final titleCtrl = TextEditingController(text: title);
  final descCtrl = TextEditingController(text: description);
  final catCtrl = TextEditingController(text: category);
  var selPrivacy = privacy;
  final result = await showDialog<LiveEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: _panel,
        title:
            const Text('Editar live', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                maxLength: 200,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Título',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder:
                      OutlineInputBorder(borderSide: BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder:
                      OutlineInputBorder(borderSide: BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: catCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder:
                      OutlineInputBorder(borderSide: BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Privacidade',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600)),
              ),
              DropdownButtonFormField<String>(
                initialValue: selPrivacy,
                dropdownColor: _panel,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder:
                      OutlineInputBorder(borderSide: BorderSide(color: _accent)),
                ),
                items: const [
                  DropdownMenuItem(value: 'public', child: Text('Pública')),
                  DropdownMenuItem(value: 'followers', child: Text('Seguidores')),
                  DropdownMenuItem(value: 'private', child: Text('Privada')),
                ],
                onChanged: (v) =>
                    setState(() => selPrivacy = v ?? 'public'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(LiveEditResult(
                title: titleCtrl.text.trim(),
                description: descCtrl.text.trim(),
                category: catCtrl.text.trim(),
                privacy: selPrivacy,
              ));
            },
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Salvar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
  return result;
}
