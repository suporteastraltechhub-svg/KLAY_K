import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing/marketing_engine.dart';
import '../../theme/klayk_theme.dart';
import 'marketing_agent_screen.dart';
import 'marketing_components.dart';

/// Criador de roteiros KLAY K.
///
/// Estrutura padrão: GANCHO → PROBLEMA → APRESENTAÇÃO → DIFERENCIAL → CTA.
/// Geração 100% local — funciona offline.
class MarketingScriptsScreen extends StatefulWidget {
  const MarketingScriptsScreen({super.key});

  @override
  State<MarketingScriptsScreen> createState() => _MarketingScriptsScreenState();
}

class _MarketingScriptsScreenState extends State<MarketingScriptsScreen> {
  final _productCtrl = TextEditingController();
  String _category = 'divulgacao';
  String _formatId = 'video_curto';
  String _toneId = 'amigavel';
  MarketingScript? _script;

  @override
  void dispose() {
    _productCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final script = MarketingEngine.generateScript(
      category: _category,
      product: _productCtrl.text,
      formatId: _formatId,
      toneId: _toneId,
    );
    setState(() => _script = script);
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
        title: MarketingBrandHeader(title: l10n.marketingScriptsTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MarketingSectionHeader(
              title: l10n.marketingScriptsThemeSection,
              icon: Icons.category_outlined,
            ),
            MarketingChipRow(
              options: MarketingEngine.scriptCategories
                  .map((c) => (id: c.id, label: c.label, emoji: '🎬'))
                  .toList(),
              selectedId: _category,
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _productCtrl,
              decoration: _decoration(l10n.marketingScriptsProductHint),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingScriptsFormatSection,
              icon: Icons.tune_rounded,
            ),
            MarketingChipRow(
              options: MarketingFormat.values
                  .map((f) => (id: f.id, label: f.label, emoji: f.emoji))
                  .toList(),
              selectedId: _formatId,
              onChanged: (v) => setState(() => _formatId = v),
            ),
            const SizedBox(height: 10),
            MarketingChipRow(
              options: MarketingTone.values
                  .map((t) => (id: t.id, label: t.label, emoji: t.emoji))
                  .toList(),
              selectedId: _toneId,
              onChanged: (v) => setState(() => _toneId = v),
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
              icon: const Icon(Icons.theaters_outlined, size: 20),
              label: Text(
                l10n.marketingGenerateScript,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            if (_script != null) _scriptPreview(_script!, l10n),
          ],
        ),
      ),
    );
  }

  Widget _scriptPreview(MarketingScript script, AppLocalizations l10n) {
    final colors = kcolors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        MarketingSectionHeader(
          title: l10n.marketingScriptPreviewTitle(
            script.category,
            script.estimatedSeconds,
          ),
          trailing: l10n.marketingScriptBlocks(script.sections.length),
          icon: Icons.playlist_play_rounded,
        ),
        KlayKCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in script.sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.step.toUpperCase(),
                        style: TextStyle(
                          color: colors.primarySoft,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.text,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => copyToClipboard(
                        context,
                        script.fullText,
                        l10n.marketingScriptNoun,
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
                      label: Text(l10n.marketingCopyScript),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MarketingAgentScreen(),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: colors.border.withValues(alpha: 0.6),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: Text(l10n.marketingCreateCampaign),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
