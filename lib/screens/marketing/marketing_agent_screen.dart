import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing/marketing_engine.dart';
import '../../theme/klayk_theme.dart';
import 'marketing_campaign_screen.dart';
import 'marketing_components.dart';

/// Agente KLAY K — descrição -> campanha pronta.
///
/// Motor 100% local (regras/templates): funciona offline, não usa APIs
/// externas e nunca publica nada automaticamente.
class MarketingAgentScreen extends StatefulWidget {
  const MarketingAgentScreen({super.key});

  @override
  State<MarketingAgentScreen> createState() => _MarketingAgentScreenState();
}

class _MarketingAgentScreenState extends State<MarketingAgentScreen> {
  final _productCtrl = TextEditingController();
  final _audienceCtrl = TextEditingController();
  final _keywordCtrl = TextEditingController();
  final List<TextEditingController> _disposeGroup = [];

  String _objectiveId = 'divulgacao';
  String _formatId = 'video_curto';
  String _toneId = 'amigavel';
  final List<String> _keywords = [];

  @override
  void initState() {
    super.initState();
    _disposeGroup
      ..add(_productCtrl)
      ..add(_audienceCtrl)
      ..add(_keywordCtrl);
  }

  @override
  void dispose() {
    for (final c in _disposeGroup) {
      c.dispose();
    }
    super.dispose();
  }

  void _addKeyword() {
    final cleaned = MarketingEngine.cleanKeywords([_keywordCtrl.text]);
    if (cleaned.isNotEmpty) {
      setState(() {
        _keywords.add(cleaned.first);
        _keywordCtrl.clear();
      });
    }
  }

  void _removeKeyword(String k) {
    setState(() => _keywords.remove(k));
  }

  void _generate() {
    FocusScope.of(context).unfocus();
    final campaign = MarketingEngine.generateCampaign(
      objectiveId: _objectiveId,
      product: _productCtrl.text,
      audience: _audienceCtrl.text,
      formatId: _formatId,
      toneId: _toneId,
      keywords: _keywords,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketingCampaignScreen(campaign: campaign),
      ),
    );
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
        title: MarketingBrandHeader(title: l10n.marketingAgentTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            KlayKCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.smart_toy_outlined,
                      color: Color(0xFFB794FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.marketingAgentGreeting,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingAgentProductSection,
              icon: Icons.work_outline_rounded,
            ),
            TextField(
              controller: _productCtrl,
              decoration: _decoration(l10n.marketingAgentProductHint),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _audienceCtrl,
              decoration: _decoration(l10n.marketingAudienceHint),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingObjectiveSection,
              icon: Icons.flag_outlined,
            ),
            MarketingChipRow(
              options: MarketingObjective.values
                  .map((o) => (id: o.id, label: o.label, emoji: o.emoji))
                  .toList(),
              selectedId: _objectiveId,
              onChanged: (v) => setState(() => _objectiveId = v),
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingFormatSection,
              icon: Icons.aspect_ratio_rounded,
            ),
            MarketingChipRow(
              options: MarketingFormat.values
                  .map((f) => (id: f.id, label: f.label, emoji: f.emoji))
                  .toList(),
              selectedId: _formatId,
              onChanged: (v) => setState(() => _formatId = v),
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingToneSection,
              icon: Icons.record_voice_over_rounded,
            ),
            MarketingChipRow(
              options: MarketingTone.values
                  .map((t) => (id: t.id, label: t.label, emoji: t.emoji))
                  .toList(),
              selectedId: _toneId,
              onChanged: (v) => setState(() => _toneId = v),
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingKeywordsSection,
              icon: Icons.tag_rounded,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordCtrl,
                    decoration: _decoration(l10n.marketingKeywordHint),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addKeyword(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addKeyword,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: l10n.marketingAddKeyword,
                ),
              ],
            ),
            if (_keywords.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _keywords
                    .map(
                      (k) => InputChip(
                        label: Text('#$k'),
                        backgroundColor: const Color(0xFF1E1A2B),
                        deleteIconColor: colors.primarySoft,
                        side: BorderSide(
                          color: colors.border.withValues(alpha: 0.6),
                        ),
                        labelStyle: const TextStyle(color: Colors.white70),
                        onDeleted: () => _removeKeyword(k),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _generate,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(
                l10n.marketingGenerateAgent,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_offer_outlined,
                  color: Colors.white24,
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.marketingLocalOfflineMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
