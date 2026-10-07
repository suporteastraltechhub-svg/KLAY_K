import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/klayk_ux.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const List<String> _kStatusFilters = [
  '',
  'DRAFT',
  'PENDING_REVIEW',
  'APPROVED',
  'REJECTED',
  'PAUSED',
  'BLOCKED',
];

/// Pantalla administrativa de Publicidade del KLAY K.
/// Acceso con profiles.is_admin (validado en backend). Moderação de anúncios,
/// denúncias y acciones (aprovar/rejeitar/pausar/bloquear).
class AdsAdminScreen extends StatefulWidget {
  /// Quando embutido em outro painel (ex.: Painel do Fundador), oculta o
  /// AppBar/Scaffold próprio e renderiza apenas TabBar + conteúdo.
  final bool showAppBar;
  const AdsAdminScreen({super.key, this.showAppBar = true});

  @override
  State<AdsAdminScreen> createState() => _AdsAdminScreenState();
}

class _AdsAdminScreenState extends State<AdsAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loading = true;
  String _filterStatus = '';

  List<AdminAdRow> _rows = [];
  List<AdReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AdsService.instance.adminList(status: _filterStatus),
        AdsService.instance.adminReports(),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<AdminAdRow>;
        _reports = results[1] as List<AdReport>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _action(
    String fn,
    String creativeId, {
    String reason = '',
  }) async {
    switch (fn) {
      case 'approve':
        await AdsService.instance.adminApprove(creativeId, reason: reason);
      case 'reject':
        await AdsService.instance.adminReject(creativeId, reason);
      case 'request_changes':
        await AdsService.instance.adminRequestChanges(creativeId, reason);
      case 'pause':
        await AdsService.instance.adminPause(creativeId);
      case 'block':
        await AdsService.instance.adminBlock(creativeId, reason);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = _loading
        ? const KlaykListSkeleton(rows: 6, withAvatar: false)
        : _tab.index == 0
        ? _adsTab(l10n)
        : _reportsTab(l10n);
    final tabs = [
      Tab(icon: const Icon(Icons.campaign_rounded), text: l10n.advertisements),
      Tab(
        icon: const Icon(Icons.report_gmailerrorred_outlined),
        text: l10n.adsTabReports,
      ),
    ];
    if (!widget.showAppBar) {
      return Column(
        children: [
          Material(
            color: const Color(0xFF0E0C16),
            child: TabBar(
              controller: _tab,
              indicatorColor: _kAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: tabs,
            ),
          ),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.adsAdminTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: tabs,
        ),
      ),
      body: content,
    );
  }

  Widget _adsTab(AppLocalizations l10n) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kStatusFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final s = _kStatusFilters[i];
                return KlayKChip(
                  label: s.isEmpty ? l10n.all : s.replaceAll('_', ' '),
                  selected: _filterStatus == s,
                  onTap: () => setState(() => _filterStatus = s),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? KlaykEmptyState(
                  icon: Icons.campaign_outlined,
                  title: l10n.adsNoAdsToModerate,
                  message: l10n.adsNoAdsToModerateBody,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _adminRow(l10n, _rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _reportsTab(AppLocalizations l10n) {
    if (_reports.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.report_gmailerrorred_outlined,
        title: l10n.adsNoReports,
        message: l10n.adsNoReportsBody,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _reports.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => KlayKCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _reports[i].category,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _reports[i].title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (_reports[i].description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _reports[i].description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              l10n.adsReportedBy(_reports[i].reporterUsername),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminRow(AppLocalizations l10n, AdminAdRow row) {
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row.businessName} · ${row.campaignName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              AdStatusChip(status: row.creativeStatus),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill('${row.impressions}', l10n.adsMetricViews),
              const SizedBox(width: 8),
              _pill('${row.clicks}', l10n.adsMetricClicks),
            ],
          ),
          if (row.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.adsReasonLabel(row.rejectionReason),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _actionBtn(l10n.adsActionPreview, Icons.visibility_outlined, () {
                _showPreview(l10n, row);
              }),
              if (row.creativeStatus != AdStatus.approved)
                _actionBtn(l10n.approveAction, Icons.check_circle, () async {
                  await _showReason(
                    l10n,
                    l10n.approveAction,
                    (r) => _action('approve', row.creativeId, reason: r),
                  );
                }),
              if (row.creativeStatus != AdStatus.blocked)
                _actionBtn(l10n.block, Icons.block, () async {
                  await _showReason(
                    l10n,
                    l10n.block,
                    (r) => _action('block', row.creativeId, reason: r),
                  );
                }),
              if (row.creativeStatus != AdStatus.rejected)
                _actionBtn(l10n.rejectAction, Icons.highlight_off, () async {
                  await _showReason(
                    l10n,
                    l10n.rejectAction,
                    (r) => _action('reject', row.creativeId, reason: r),
                  );
                }),
              if (row.creativeStatus != AdStatus.paused)
                _actionBtn(l10n.pauseTooltip, Icons.pause_circle, () async {
                  await _showReason(
                    l10n,
                    l10n.pauseTooltip,
                    (r) => _action('pause', row.creativeId, reason: r),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String val, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2350),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$val $label',
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        backgroundColor: const Color(0xFF2A2540),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Prévia visual do anúncio para moderação. Quando ainda não aprovado,
  /// exibe com o chip "PRÉ-VISUALIZAÇÃO" (nunca parece publicidade pública);
  /// quando aprovado, mostra a aparência real do anúncio publicado (§55/§56).
  void _showPreview(AppLocalizations l10n, AdminAdRow row) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3355),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.creativeStatus == AdStatus.approved
                          ? l10n.adsPreviewPublished
                          : l10n.adsPreviewPending,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  AdStatusChip(status: row.creativeStatus),
                ],
              ),
              const SizedBox(height: 14),
              AdCard(
                ad: AdCreative(
                  id: row.creativeId,
                  campaignId: row.campaignId,
                  campaignName: row.campaignName,
                  title: row.title,
                  description: row.description,
                  mediaUrl: row.media,
                  mediaType: 'image',
                  ctaLabel: row.cta,
                  ctaUrl: row.ctaUrl,
                  advertiserName: row.businessName,
                  advertiserCategory: row.category,
                ),
                preview: row.creativeStatus != AdStatus.approved,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReason(
    AppLocalizations l10n,
    String title,
    Future<void> Function(String reason) onOk,
  ) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF17141F),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.adsReasonHint,
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(title),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await onOk(ctrl.text.trim());
    }
  }
}
