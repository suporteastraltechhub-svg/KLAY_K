import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../services/community_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

const List<String> _kCategories = [
  'Games',
  'Música',
  'Tecnologia',
  'Esportes',
  'Humor',
  'Entretenimento',
  'Animes',
  'Educação',
];

const Map<String, String> _kCategoryIcons = {
  'Games': '🎮',
  'Música': '🎵',
  'Tecnologia': '💻',
  'Esportes': '⚽',
  'Humor': '😂',
  'Entretenimento': '🎬',
  'Animes': '🌸',
  'Educação': '📚',
};

/// Criação de uma nova comunidade no KLAY K.
class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();
  String _category = _kCategories.first;
  String _icon = _kCategoryIcons.values.first;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _rulesCtrl.dispose();
    super.dispose();
  }

  String _slug(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty
        ? 'comunidade-${DateTime.now().millisecondsSinceEpoch}'
        : s;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.communityCreateEmpty)));
      return;
    }
    setState(() => _saving = true);
    try {
      await CommunityService.instance.createCommunity(
        name: name,
        slug: _slug(name),
        description: _descCtrl.text.trim(),
        icon: _icon,
        category: _category,
        rules: _rulesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.communityCreateError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.communityCreateTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 4),
          _label(l10n.communityCreateName),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            maxLength: 40,
            decoration: _fieldStyle(l10n.communityCreateNameHint),
          ),
          const SizedBox(height: 8),
          _label(l10n.communityCreateCategory),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kCategories.map((c) {
              return KlayKChip(
                label: '${_kCategoryIcons[c] ?? ''} $c',
                selected: _category == c,
                onTap: () => setState(() {
                  _category = c;
                  _icon = _kCategoryIcons[c] ?? '👥';
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _label(l10n.communityCreateDesc),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            maxLength: 300,
            decoration: _fieldStyle(l10n.communityCreateDescHint),
          ),
          const SizedBox(height: 8),
          _label(l10n.communityCreateRules),
          const SizedBox(height: 6),
          TextField(
            controller: _rulesCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            maxLength: 500,
            decoration: _fieldStyle(l10n.communityCreateRulesHint),
          ),
          const SizedBox(height: 24),
          KlayKButton(
            label: l10n.communityCreateButton,
            icon: Icons.group_add_rounded,
            expanded: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
  );

  InputDecoration _fieldStyle(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: const Color(0xFF17141F),
    counterStyle: const TextStyle(color: Colors.white24),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF2A2540)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kAccent),
    ),
  );
}
