import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing/marketing_engine.dart';
import '../../services/marketing_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import 'marketing_components.dart';

/// Testes A/B da Central.
///
/// Crie variações A e B de uma campanha e salve-as. NÃO existe infraestrutura
/// de métricas A/B no KLAY K: o painel sempre informa que nenhum vencedor é
/// declarado sem dados reais.
class MarketingAbScreen extends StatefulWidget {
  const MarketingAbScreen({super.key});

  @override
  State<MarketingAbScreen> createState() => _MarketingAbScreenState();
}

class _MarketingAbScreenState extends State<MarketingAbScreen> {
  final _productCtrl = TextEditingController();
  late bool _configured;
  String _objectiveId = 'divulgacao';
  MarketingCampaign? _test;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _configured = SupabaseService.instance.isConfigured;
  }

  @override
  void dispose() {
    _productCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final objective = MarketingObjective.byId(_objectiveId);
    final product = MarketingEngine.productFallback(_productCtrl.text);
    final variants = MarketingEngine.generateVariations(
      objectiveId: _objectiveId,
      product: product,
      count: 2,
    );
    final main = variants.isNotEmpty ? variants.first : null;
    setState(() {
      _test = MarketingCampaign(
        name: '${objective.emoji} Teste A/B — $product',
        objectiveId: _objectiveId,
        audience: MarketingEngine.suggestAudience(_objectiveId, product),
        formatId: 'video_curto',
        toneId: 'amigavel',
        keywords: const [],
        title: main?.title ?? '',
        description: main?.description ?? '',
        cta: main?.cta ?? 'Saiba mais',
        checklist: MarketingEngine.checklistDefault,
        variations: variants,
        createdAt: DateTime.now(),
        status: 'draft',
        localOnly: true,
      );
    });
  }

  Future<void> _save() async {
    final test = _test;
    if (test == null || _saving) return;
    setState(() => _saving = true);
    try {
      final id = await MarketingService.instance.saveCampaign(test);
      if (!mounted) return;
      setState(() {
        _test = test.copyWith(id: id, localOnly: false);
        _saving = false;
      });
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.marketingAbSaved)));
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
        title: MarketingBrandHeader(title: l10n.marketingAbTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            KlayKCard(
              child: Row(
                children: [
                  Icon(
                    Icons.science_outlined,
                    color: colors.primarySoft,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.marketingAbIntro,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            MarketingSectionHeader(
              title: l10n.marketingAbTestSection,
              icon: Icons.edit_outlined,
            ),
            TextField(
              controller: _productCtrl,
              decoration: _decoration(l10n.marketingAbProductHint),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
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
              icon: const Icon(Icons.science_outlined, size: 20),
              label: Text(
                l10n.marketingGenerateAb,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            if (_test != null) ...[
              const SizedBox(height: 24),
              MarketingSectionHeader(
                title: l10n.marketingVariationsTitle,
                icon: Icons.compare_arrows_outlined,
              ),
              MarketingVariationList(variations: _test!.variations),
              const SizedBox(height: 18),
              if (_configured)
                _saving
                    ? KlaykLoader(label: l10n.marketingSavingTest)
                    : FilledButton.icon(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.save_outlined, size: 20),
                        label: Text(
                          l10n.marketingSaveAb,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.marketingAbBackendMsg,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 18),
              KlayKCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.marketingAbMetrics,
                      style: TextStyle(
                        color: colors.primarySoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.marketingAbMetricsText,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
