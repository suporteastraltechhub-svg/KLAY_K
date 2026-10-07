import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing/marketing_engine.dart';
import '../../services/marketing_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/klayk_theme.dart';
import 'marketing_components.dart';

/// Criativos — briefing pronto para copiar (sem geração de imagens).
class MarketingBriefsScreen extends StatefulWidget {
  const MarketingBriefsScreen({super.key});

  @override
  State<MarketingBriefsScreen> createState() => _MarketingBriefsScreenState();
}

class _MarketingBriefsScreenState extends State<MarketingBriefsScreen> {
  final _productCtrl = TextEditingController();
  final _audienceCtrl = TextEditingController();
  late bool _configured;
  String _formatId = 'video_curto';
  MarketingBrief? _brief;
  bool _saving = false;
  List<Map<String, dynamic>> _saved = [];

  @override
  void initState() {
    super.initState();
    _configured = SupabaseService.instance.isConfigured;
    _loadSaved();
  }

  @override
  void dispose() {
    _productCtrl.dispose();
    _audienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    if (!_configured) return;
    try {
      final rows = await MarketingService.instance.listBriefs();
      if (mounted) setState(() => _saved = rows);
    } catch (_) {}
  }

  void _generate() {
    final brief = MarketingEngine.generateBrief(
      formatId: _formatId,
      product: _productCtrl.text,
      objectiveId: 'divulgacao',
      audience: _audienceCtrl.text,
    );
    setState(() => _brief = brief);
  }

  Future<void> _saveBrief() async {
    final brief = _brief;
    if (brief == null || _saving) return;
    setState(() => _saving = true);
    try {
      await MarketingService.instance.saveBrief(
        title: '${brief.format} · ${brief.product}',
        format: brief.format,
        product: brief.product,
        briefText: brief.fullText,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.marketingBriefSaved)));
      _loadSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(marketingSaveErrorMessage(l10n, e))),
        );
    }
  }

  Future<void> _deleteBrief(String id) async {
    try {
      await MarketingService.instance.deleteBrief(id);
      if (mounted) {
        setState(() => _saved.removeWhere((b) => b['id']?.toString() == id));
      }
    } catch (_) {}
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF17141F),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2540)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2540)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kcolors(context).primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bgElevated,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        title: MarketingBrandHeader(title: l10n.marketingCreativesTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MarketingSectionHeader(
              title: l10n.marketingBriefsFormatSection,
              icon: Icons.aspect_ratio_rounded,
            ),
            MarketingChipRow(
              options: MarketingFormat.values
                  .map((f) => (id: f.id, label: f.label, emoji: f.emoji))
                  .toList(),
              selectedId: _formatId,
              onChanged: (v) => setState(() => _formatId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _productCtrl,
              decoration: _decoration(l10n.marketingBriefsProductHint),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _audienceCtrl,
              decoration: _decoration(l10n.marketingAudienceHint),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _generate,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.palette_outlined, size: 20),
              label: Text(
                l10n.marketingGenerateBrief,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            if (_brief != null) _briefPreview(_brief!, l10n),
            const SizedBox(height: 24),
            MarketingSectionHeader(
              title: l10n.marketingSavedBriefsSection,
              icon: Icons.folder_outlined,
            ),
            if (_saved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.marketingNoBriefs,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              for (final b in _saved) _savedBriefCard(b, l10n),
            if (!_configured)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  l10n.marketingBackendOfflineBriefs,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _briefPreview(MarketingBrief brief, AppLocalizations l10n) {
    final colors = kcolors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        MarketingSectionHeader(
          title: l10n.marketingBriefPreviewTitle(brief.format),
          trailing: brief.objective,
          icon: Icons.description_outlined,
        ),
        KlayKCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(l10n.marketingProductLabel, brief.product),
              _line(l10n.marketingAudienceLabel, brief.audience),
              const SizedBox(height: 8),
              Text(
                l10n.marketingSpecsHeader,
                style: TextStyle(
                  color: colors.primarySoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              for (final s in brief.specs) _bullet(s),
              const SizedBox(height: 10),
              Text(
                l10n.marketingScenesHeader,
                style: TextStyle(
                  color: colors.primarySoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              for (final s in brief.scenes)
                _bullet('${s.step}: ${s.description}'),
              const SizedBox(height: 10),
              Text(
                l10n.marketingDoHeader,
                style: TextStyle(
                  color: colors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              for (final s in brief.doItems) _bullet(s),
              const SizedBox(height: 10),
              Text(
                l10n.marketingDontHeader,
                style: TextStyle(
                  color: colors.danger,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              for (final s in brief.dontItems) _bullet(s),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => copyToClipboard(
                        context,
                        brief.fullText,
                        l10n.marketingBriefNoun,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(
                          color: colors.primary.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(l10n.marketingCopyBrief),
                    ),
                  ),
                  if (_configured) ...[
                    const SizedBox(width: 8),
                    _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : OutlinedButton.icon(
                            onPressed: _saveBrief,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(
                                color: colors.border.withValues(alpha: 0.6),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: Text(l10n.save),
                          ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kcolors(context).primary.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedBriefCard(Map<String, dynamic> b, AppLocalizations l10n) {
    final colors = kcolors(context);
    final id = b['id']?.toString() ?? '';
    final title = b['title']?.toString() ?? '';
    final text = b['brief_text']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KlayKCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMarketingDate(
                      DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                          DateTime.now(),
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.marketingCopyBrief,
              icon: Icon(
                Icons.copy_rounded,
                size: 18,
                color: colors.primarySoft,
              ),
              onPressed: () =>
                  copyToClipboard(context, text, l10n.marketingBriefNoun),
            ),
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFE4183C),
              ),
              onPressed: () => _deleteBrief(id),
            ),
          ],
        ),
      ),
    );
  }
}
