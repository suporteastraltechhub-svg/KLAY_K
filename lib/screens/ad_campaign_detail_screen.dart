import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../widgets/ad_widgets.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kGold = Color(0xFFD4AF37);

/// Detalhes de uma campanha (Central de Anúncios).
///
/// Exibe métricas reais do backend (impressões, cliques, CTR, orçamento),
/// status (campanha + criativo), datas e motivo de rejeição quando houver —
/// sem nenhum número fabricado. A cobrança ainda não é calculada pelo
/// servidor, então o app não exibe valor gasto nem saldo disponível.
class AdCampaignDetailScreen extends StatefulWidget {
  final AdCampaignRow row;

  /// Chamado quando uma ação muda o status, para a Central recarregar.
  final VoidCallback? onChanged;

  const AdCampaignDetailScreen({
    super.key,
    required this.row,
    this.onChanged,
  });

  @override
  State<AdCampaignDetailScreen> createState() =>
      _AdCampaignDetailScreenState();
}

class _AdCampaignDetailScreenState extends State<AdCampaignDetailScreen> {
  bool _busy = false;

  AdCampaignRow get row => widget.row;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _success(String message) {
    _toast(message);
    setState(() {});
    widget.onChanged?.call();
  }

  void _report(AdOpResult r, AppLocalizations l10n, String okMessage) {
    switch (r) {
      case AdOpResult.ok:
        _success(okMessage);
      case AdOpResult.unavailable:
        _toast(l10n.adBackendMissing);
      case AdOpResult.failed:
        _toast(l10n.adCreateSubmitFailed);
    }
  }

  /// Diálogo de confirmação para ação destrutiva ou que encerra a campanha.
  Future<void> _confirmThen(
    String title,
    String body,
    String confirmLabel,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17141F),
        title: Text(title),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await action();
  }

  Future<void> _setStatus(String action) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final r = await AdsService.instance.setCampaignStatus(
      row.campaignId,
      action,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    final okMessage = switch (action) {
      'pause' => l10n.adActionPause,
      'resume' => l10n.adActionResume,
      _ => l10n.adActionEnd,
    };
    _report(r, l10n, okMessage);
  }

  Future<void> _pause() async {
    final l10n = AppLocalizations.of(context)!;
    await _confirmThen(
      l10n.adConfirmPauseTitle,
      l10n.adConfirmPauseBody,
      l10n.adActionPause,
      () => _setStatus('pause'),
    );
  }

  Future<void> _end() async {
    final l10n = AppLocalizations.of(context)!;
    await _confirmThen(
      l10n.adConfirmEndTitle,
      l10n.adConfirmEndBody,
      l10n.adActionEnd,
      () => _setStatus('end'),
    );
  }

  Future<void> _runDeleteDraft() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final r = await AdsService.instance.deleteDraft(row.creativeId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == AdOpResult.ok) {
      _toast(l10n.adDraftDeleted);
      Navigator.of(context).pop();
      widget.onChanged?.call();
      return;
    }
    _report(r, l10n, l10n.adDraftDeleted);
  }

  Future<void> _deleteDraft() async {
    final l10n = AppLocalizations.of(context)!;
    await _confirmThen(
      l10n.deleteDraftTitle,
      l10n.adConfirmDeleteBody,
      l10n.delete,
      _runDeleteDraft,
    );
  }

  Future<void> _resubmit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final r = await AdsService.instance.resubmitCreative(row.creativeId);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(r, l10n, l10n.adCreateSubmit);
  }

  Future<void> _duplicate() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final r = await AdsService.instance.duplicateCampaignFast(row);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(r, l10n, l10n.adDuplicatedToast);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          row.campaignName.isEmpty
              ? l10n.campaignDetailTitle
              : row.campaignName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _media(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AdStatusChip(status: row.creativeStatus),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.campaignStatusLabel(adStatusLabel(l10n, row.campaignStatus)),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (row.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 14),
              _rejectionBanner(l10n),
            ],
            const SizedBox(height: 20),
            _sectionHeader(l10n.metricsLabel),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    '${row.impressions}',
                    l10n.adsMetricViews,
                    Icons.visibility_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricTile(
                    '${row.clicks}',
                    l10n.adsMetricClicks,
                    Icons.touch_app_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricTile(
                    '${row.ctr.toStringAsFixed(1)}%',
                    'CTR',
                    Icons.trending_up_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionHeader(l10n.adsBudgetLabel),
            const SizedBox(height: 10),
            _budgetCard(l10n),
            const SizedBox(height: 20),
            _sectionHeader(l10n.timelineLabel),
            const SizedBox(height: 10),
            _timelineCard(context, l10n),
            if (row.cta.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionHeader(l10n.ctaSectionLabel),
              const SizedBox(height: 10),
              _ctaCard(context),
            ],
            const SizedBox(height: 20),
            _sectionHeader(l10n.adActionsTitle),
            const SizedBox(height: 10),
            _actionsCard(l10n),
          ],
        ),
      ),
    );
  }

  /// Ações disponíveis conforme o status do criativo. Cada ação destrutiva
  /// ou que encerra a campanha pede confirmação antes.
  Widget _actionsCard(AppLocalizations l10n) {
    final s = row.creativeStatus;
    final actions = <Widget>[];

    if (s == AdStatus.approved) {
      actions.add(_action(icon: Icons.pause_rounded, label: l10n.adActionPause, onTap: _pause));
    }
    if (s == AdStatus.paused) {
      actions.add(_action(icon: Icons.play_arrow_rounded, label: l10n.adActionResume, onTap: () => _setStatus('resume')));
    }
    if (s == AdStatus.rejected) {
      actions.add(_action(icon: Icons.refresh_rounded, label: l10n.adFixAndResend, onTap: _resubmit));
    }

    final isDraft = s == AdStatus.draft;
    final isLive =
        s == AdStatus.approved ||
        s == AdStatus.paused ||
        s == AdStatus.pendingReview;

    if (isLive) {
      actions.add(_action(icon: Icons.stop_circle_outlined, label: l10n.adActionEnd, onTap: _end, danger: true));
    }
    actions.add(_action(icon: Icons.copy_rounded, label: l10n.adDuplicateAction, onTap: _duplicate));
    if (isDraft) {
      actions.add(_action(icon: Icons.delete_outline_rounded, label: l10n.deleteDraftTitle, onTap: _deleteDraft, danger: true));
    }

    if (_busy) {
      return const KlayKCard(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
            ),
        ),
      );
    }

    return KlayKCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (final a in actions) a,
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFFF4D6A) : _kAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _media() {
    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2350), Color(0xFF14101A)],
        ),
      ),
      child: row.media.isEmpty
          ? const Center(
              child: Icon(Icons.campaign_rounded, color: _kAccent, size: 48),
            )
          : Image.network(
              row.media,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.campaign_rounded, color: _kAccent, size: 48),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(color: _kAccent),
                  ),
                );
              },
            ),
    );
  }

  Widget _rejectionBanner(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gpp_bad_outlined, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.adsReasonLabel(row.rejectionReason),
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
    );
  }

  Widget _metricTile(String value, String label, IconData icon) {
    return KlayKCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: _kAccent, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// Orçamento e medições reais.
  ///
  /// O backend ainda não calcula cobrança: `spent` em `ads_my_list()` é a
  /// contagem de cliques, não dinheiro. Por isso nada aqui é subtraído do
  /// orçamento — exibir "gasto" e "disponível" em moeda mostraria cliques
  /// como se fossem reais. A cobrança real depende de CPM/CPC no servidor.
  Widget _budgetCard(AppLocalizations l10n) {
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _kv(
                  l10n.adsBudgetLabel,
                  row.budget.toStringAsFixed(0),
                ),
              ),
              Expanded(
                child: _kv(l10n.adsMetricClicks, '${row.clicks}'),
              ),
            ],
          ),
          if (row.dailyBudget != null ||
              row.spendCap != null ||
              row.placements.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (row.dailyBudget != null)
                  Expanded(
                    child: _kv(
                      l10n.adFieldDailyBudget,
                      row.dailyBudget!.toStringAsFixed(0),
                    ),
                  ),
                if (row.spendCap != null)
                  Expanded(
                    child: _kv(
                      l10n.adFieldSpendCap,
                      row.spendCap!.toStringAsFixed(0),
                    ),
                  ),
              ],
            ),
            if (row.placements.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in row.placements)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _kAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        _placementLabel(l10n, p),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Colors.white38,
                size: 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.adsNoBillingNote,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {Color? valueColor = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _timelineCard(BuildContext context, AppLocalizations l10n) {
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _timelineRow(
            Icons.create_rounded,
            l10n.timelineCreated,
            _fmtDate(row.createdAt),
          ),
          const SizedBox(height: 10),
          _timelineRow(
            Icons.verified_outlined,
            l10n.timelineApproved,
            row.approvedAt != null
                ? _fmtDate(row.approvedAt!)
                : l10n.timelineNotYet,
            row.approvedAt != null ? Colors.greenAccent : null,
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(
    IconData icon,
    String label,
    String value, [
    Color? accent,
  ]) {
    return Row(
      children: [
        Icon(icon, color: accent ?? _kAccent, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _ctaCard(BuildContext context) {
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.touch_app_outlined, color: _kGold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.cta,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (row.ctaUrl.isNotEmpty)
                  Text(
                    row.ctaUrl,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _placementLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'for_you' => l10n.adPlacementForYou,
      'between_videos' => l10n.adPlacementBetweenVideos,
      'highlights' => l10n.adPlacementHighlights,
      _ => l10n.adPlacementDiscovery,
    };
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
