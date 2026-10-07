import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing/marketing_engine.dart';
import '../../services/marketing_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import 'marketing_components.dart';

/// Detalhe de uma campanha gerada pelo Agente KLAY K.
///
/// Edição manual + ações administrativas: Salvar, Aprovar (revisão CEO,
/// nunca publica automaticamente), novas variações, Copiar, Exportar,
/// Duplicar, Arquivar/Reativar e Excluir.
class MarketingCampaignScreen extends StatefulWidget {
  final MarketingCampaign campaign;

  const MarketingCampaignScreen({super.key, required this.campaign});

  @override
  State<MarketingCampaignScreen> createState() =>
      _MarketingCampaignScreenState();
}

class _MarketingCampaignScreenState extends State<MarketingCampaignScreen> {
  late MarketingCampaign _campaign;
  late bool _editing;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _ctaCtrl;

  final List<bool> _checked = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _campaign = widget.campaign;
    _editing = widget.campaign.localOnly;
    _nameCtrl = TextEditingController(text: _campaign.name);
    _titleCtrl = TextEditingController(text: _campaign.title);
    _descCtrl = TextEditingController(text: _campaign.description);
    _ctaCtrl = TextEditingController(text: _campaign.cta);
    for (final item in _campaign.checklist) {
      _checked.add(item.checked);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  MarketingCampaign get _draft => _campaign.copyWith(
    name: _nameCtrl.text.trim(),
    title: _titleCtrl.text.trim(),
    description: _descCtrl.text.trim(),
    cta: _ctaCtrl.text.trim(),
    checklist: List.generate(
      _checked.length,
      (i) => _campaign.checklist[i].copyWith(checked: _checked[i]),
    ),
  );

  MarketingCampaign get _live {
    final draft = _draft;
    return _campaign.copyWith(
      name: draft.name,
      title: draft.title,
      description: draft.description,
      cta: draft.cta,
      checklist: draft.checklist,
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save({String status = 'draft'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final id = await MarketingService.instance.saveCampaign(
        _draft,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _campaign = _draft.copyWith(id: id, status: status, localOnly: false);
        if (status == 'approved') {
          _campaign = _campaign.copyWith(approvedAt: DateTime.now());
        }
        _editing = false;
        _busy = false;
      });
      _snack(
        status == 'approved'
            ? l10n.marketingApprovedSaveMsg
            : l10n.marketingCampaignSaved,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(marketingSaveErrorMessage(l10n, e));
    }
  }

  Future<void> _approve() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(l10n.marketingApproveDialogTitle),
        content: Text(l10n.marketingApproveDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.marketingApprove,
              style: const TextStyle(color: Color(0xFF34D399)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_campaign.id == null || _campaign.localOnly) {
      await _save(status: 'approved');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await MarketingService.instance.setStatus(
        _campaign.id!,
        'approved',
      );
      if (!mounted) return;
      setState(() {
        if (changed) {
          _campaign = _campaign.copyWith(
            status: 'approved',
            approvedAt: DateTime.now(),
          );
        }
        _busy = false;
      });
      _snack(
        changed
            ? l10n.marketingApprovedManualMsg
            : l10n.marketingStatusUnchanged,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.marketingApproveFail(marketingSaveErrorMessage(l10n, e)));
    }
  }

  void _regenerateVariations() {
    final l10n = AppLocalizations.of(context)!;
    final variants = MarketingEngine.generateVariations(
      objectiveId: _campaign.objectiveId,
      product: _live.title,
      toneId: _campaign.toneId,
      keywords: _campaign.keywords,
    );
    setState(() {
      _campaign = _campaign.copyWith(variations: variants);
      if (variants.isNotEmpty) {
        _titleCtrl.text = variants.first.title;
        _descCtrl.text = variants.first.description;
        _ctaCtrl.text = variants.first.cta;
      }
    });
    _snack(l10n.marketingVariationsRegenerated);
  }

  void _copy() {
    final l10n = AppLocalizations.of(context)!;
    copyToClipboard(context, _live.summary, l10n.marketingCampaignNoun);
  }

  void _export() {
    Share.share(_live.summary, subject: _live.name);
  }

  void _duplicate() {
    final l10n = AppLocalizations.of(context)!;
    final copy = _live.copyWith(
      id: null,
      name: '${_live.name}${l10n.marketingCopySuffix}',
      status: 'draft',
      approvedAt: null,
      localOnly: true,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketingCampaignScreen(campaign: copy),
      ),
    );
    _snack(l10n.marketingCopyCreated);
  }

  Future<void> _archive() async {
    final l10n = AppLocalizations.of(context)!;
    final target = _campaign.isArchived ? 'draft' : 'archived';
    if (_campaign.id == null || _campaign.localOnly) {
      setState(() {
        _campaign = _live.copyWith(status: target);
      });
      _snack(
        target == 'archived'
            ? l10n.marketingArchivedLocal
            : l10n.marketingReactivatedLocal,
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await MarketingService.instance.setStatus(
        _campaign.id!,
        target,
      );
      if (!mounted) return;
      setState(() {
        if (changed) {
          _campaign = _campaign.copyWith(status: target);
        }
        _busy = false;
      });
      _snack(
        changed
            ? (target == 'archived'
                  ? l10n.marketingArchived
                  : l10n.marketingReactivated)
            : l10n.marketingStatusUnchanged,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.marketingArchiveFail(marketingSaveErrorMessage(l10n, e)));
    }
  }

  Future<void> _delete() async {
    if (_campaign.isApproved) return;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(l10n.marketingDeleteDialogTitle),
        content: Text(l10n.marketingDeleteDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Color(0xFFE4183C)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_campaign.id != null && !_campaign.localOnly) {
      try {
        await MarketingService.instance.delete(_campaign.id!);
      } catch (e) {
        if (!mounted) return;
        _snack(l10n.marketingDeleteFail(marketingSaveErrorMessage(l10n, e)));
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final c = _live;
    return Scaffold(
      backgroundColor: colors.bgElevated,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        title: MarketingBrandHeader(title: l10n.marketingCampaignTitle),
      ),
      body: SafeArea(
        child: _busy
            ? KlaykLoader(label: l10n.marketingProcessing)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _hero(c, l10n),
                  const SizedBox(height: 18),
                  _actions(c, l10n),
                  const SizedBox(height: 18),
                  _meta(c, l10n),
                  const SizedBox(height: 18),
                  _contentSection(c, l10n),
                  if (c.variations.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    MarketingSectionHeader(
                      title: l10n.marketingVariationsTitle,
                      icon: Icons.copy_all_outlined,
                    ),
                    MarketingVariationList(variations: c.variations),
                  ],
                  if (c.script != null) ...[
                    const SizedBox(height: 22),
                    MarketingSectionHeader(
                      title: l10n.marketingScriptTitle,
                      icon: Icons.theaters_outlined,
                    ),
                    _scriptCard(c.script!, l10n),
                  ],
                  const SizedBox(height: 22),
                  MarketingSectionHeader(
                    title: l10n.marketingChecklistTitle,
                    icon: Icons.checklist_rounded,
                  ),
                  _checklistCard(),
                ],
              ),
      ),
    );
  }

  Widget _hero(MarketingCampaign c, AppLocalizations l10n) {
    final colors = kcolors(context);
    return KlayKCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MarketingStatusChip(status: c.status, localOnly: c.localOnly),
              const Spacer(),
              Text(
                '${formatMarketingDate(c.createdAt)}'
                '${c.approvedAt != null ? ' · ${l10n.marketingApprovedOn(formatMarketingDate(c.approvedAt!))}' : ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editing)
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
              decoration: _fieldDeco(colors, l10n.marketingCampaignNameHint),
            )
          else
            Text(
              c.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              KlayKChip(
                label: '${c.objective.emoji} ${c.objective.label}',
                selected: true,
              ),
              KlayKChip(label: '${c.format.emoji} ${c.format.label}'),
              KlayKChip(label: '${c.tone.emoji} ${c.tone.label}'),
              for (final k in c.keywords) KlayKChip(label: '#$k'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.groups_outlined, color: colors.primarySoft, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.audience.isEmpty
                      ? l10n.marketingAudienceNotSet
                      : c.audience,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(MarketingCampaign c, AppLocalizations l10n) {
    final colors = kcolors(context);
    final buttons = <Widget>[
      MarketingActionButton(
        icon: Icons.save_outlined,
        label: _editing ? l10n.save : l10n.edit,
        color: colors.primary,
        onTap: () {
          if (_editing) {
            _save();
          } else {
            setState(() => _editing = true);
          }
        },
      ),
      MarketingActionButton(
        icon: Icons.check_rounded,
        label: c.isApproved
            ? l10n.marketingStatusApproved
            : l10n.marketingApproveCampaign,
        color: colors.success,
        onTap: c.isApproved ? null : _approve,
      ),
      MarketingActionButton(
        icon: Icons.casino_outlined,
        label: l10n.marketingNewVariations,
        onTap: _regenerateVariations,
      ),
      MarketingActionButton(
        icon: Icons.copy_all_rounded,
        label: l10n.marketingCopyCampaign,
        onTap: _copy,
      ),
      MarketingActionButton(
        icon: Icons.upload_rounded,
        label: l10n.marketingExport,
        onTap: _export,
      ),
      MarketingActionButton(
        icon: Icons.content_copy_rounded,
        label: l10n.marketingDuplicate,
        onTap: _duplicate,
      ),
      MarketingActionButton(
        icon: c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
        label: c.isArchived ? l10n.marketingReactivate : l10n.marketingArchive,
        onTap: _archive,
      ),
      if (!c.isApproved)
        MarketingActionButton(
          icon: Icons.delete_outline_rounded,
          label: l10n.delete,
          color: colors.danger,
          onTap: _delete,
        ),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Widget _meta(MarketingCampaign c, AppLocalizations l10n) {
    return KlayKCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.marketingTargetAudience,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.audience,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.marketingAgentMotivation,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.marketingAgentMotivationText,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentSection(MarketingCampaign c, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarketingSectionHeader(
          title: l10n.marketingContentSection,
          icon: Icons.article_outlined,
        ),
        KlayKCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editing) ...[
                TextField(
                  controller: _titleCtrl,
                  maxLength: 200,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco(
                    kcolors(context),
                    l10n.marketingTitleLabel,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  maxLines: 5,
                  maxLength: 2000,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco(
                    kcolors(context),
                    l10n.marketingDescriptionLabel,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctaCtrl,
                  maxLength: 40,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco(
                    kcolors(context),
                    l10n.marketingCtaLabel,
                  ),
                ),
              ] else ...[
                _label(l10n.marketingTitleLabel),
                Text(
                  c.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _label(l10n.marketingDescriptionLabel),
                Text(
                  c.description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _label(l10n.marketingCtaLabel),
                Text(
                  c.cta,
                  style: TextStyle(
                    color: kcolors(context).primarySoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _scriptCard(MarketingScript script, AppLocalizations l10n) {
    return KlayKCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${script.category} · ~${script.estimatedSeconds} s',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.marketingCopyScript,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: kcolors(context).primarySoft,
                ),
                onPressed: () => copyToClipboard(
                  context,
                  script.fullText,
                  l10n.marketingScriptNoun,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in script.sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.step.toUpperCase(),
                    style: TextStyle(
                      color: kcolors(context).primarySoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.text,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _checklistCard() {
    final colors = kcolors(context);
    return KlayKCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          for (var i = 0; i < _checked.length; i++)
            CheckboxListTile(
              value: _checked[i],
              dense: true,
              activeColor: colors.primary,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                _campaign.checklist[i].label,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              onChanged: (v) => setState(() => _checked[i] = v ?? false),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(KlaykColors colors, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF17141F),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        borderSide: BorderSide(color: colors.primary),
      ),
    );
  }
}
