import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/klayk_ux.dart';
import 'ad_campaign_detail_screen.dart';
import 'ad_create_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Filtros da lista "Meus anúncios". A ordem de [values] deve acompanhar
/// [_AdsCentralScreenState._filterLabels].
enum _AdFilter { all, draft, review, active, paused, ended, rejected }

/// Central de Anúncios do KLAY K — painel do anunciante.
///
/// Mostra métricas reais (do backend), campanhas e o botão "+ Criar anúncio".
/// Nenhum número é inventado: tudo vem das RPCs `security definer`.
class AdsCentralScreen extends StatefulWidget {
  const AdsCentralScreen({super.key});

  @override
  State<AdsCentralScreen> createState() => _AdsCentralScreenState();
}

class _AdsCentralScreenState extends State<AdsCentralScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _loadFailed = false;
  bool _configured = false;
  AdMetrics _metrics = const AdMetrics();
  List<AdCampaignRow> _rows = [];
  _AdFilter _filter = _AdFilter.all;

  /// Rótulos dos filtros, na ordem de [_AdFilter.values].
  List<String> _filterLabels(AppLocalizations l10n) => [
    l10n.adsFilterAll,
    l10n.adsFilterDraft,
    l10n.adsFilterReview,
    l10n.adsFilterActive,
    l10n.adsFilterPaused,
    l10n.adsFilterEnded,
    l10n.adsFilterRejected,
  ];

  /// Aplica o filtro escolhido sobre os dados reais de `ads_my_list()`.
  List<AdCampaignRow> get _filteredRows => switch (_filter) {
    _AdFilter.all => _rows,
    _AdFilter.draft => _rows
        .where((r) => r.creativeStatus == AdStatus.draft)
        .toList(),
    _AdFilter.review => _rows
        .where((r) => r.creativeStatus == AdStatus.pendingReview)
        .toList(),
    _AdFilter.active => _rows
        .where((r) => r.creativeStatus == AdStatus.approved)
        .toList(),
    _AdFilter.paused => _rows
        .where((r) => r.creativeStatus == AdStatus.paused)
        .toList(),
    _AdFilter.ended => _rows
        .where((r) => r.creativeStatus == AdStatus.expired)
        .toList(),
    _AdFilter.rejected => _rows
        .where((r) => r.creativeStatus == AdStatus.rejected)
        .toList(),
  };

  @override
  void initState() {
    super.initState();
    _configured = SupabaseService.instance.isConfigured;
    _load();
  }

  Future<void> _load() async {
    if (!_configured) {
      setState(() {
        _loading = false;
        _loadFailed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait([
        AdsService.instance.myCampaigns(),
        AdsService.instance.myMetrics(),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<AdCampaignRow>;
        _metrics = results[1] as AdMetrics;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AdCreateScreen()));
    if (created == true) _load();
  }

  /// Duplica a campanha como rascunho. A original não é alterada.
  Future<void> _duplicate(AdCampaignRow row) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final r = await AdsService.instance.duplicateCampaignFast(row);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          switch (r) {
            AdOpResult.ok => l10n.adDuplicatedToast,
            AdOpResult.unavailable => l10n.adBackendMissing,
            AdOpResult.failed => l10n.adDuplicateFailed,
          },
        ),
      ),
    );
    if (r == AdOpResult.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.adsCentralTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Text(
              'KLAY K Ads',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(child: _configured ? _body(l10n) : _unconfigured(l10n)),
      floatingActionButton: _configured
          ? FloatingActionButton.extended(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.adsCreateButton),
            )
          : null,
    );
  }

  Widget _unconfigured(AppLocalizations l10n) {
    return KlaykEmptyState(
      icon: Icons.cloud_off_outlined,
      title: l10n.adsBackendNotConfigured,
      message: l10n.adsBackendNotConfiguredBody,
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loadFailed) {
      return KlaykErrorState(message: l10n.adsLoadError, onRetry: _load);
    }
    if (_loading) {
      return const KlaykListSkeleton(rows: 6, withAvatar: false);
    }
    final filtered = _filteredRows;
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _metricsGrid(l10n),
          const SizedBox(height: 20),
          _sectionHeader(
            l10n.adsCampaignsLabel,
            trailing: '${filtered.length}',
          ),
          const SizedBox(height: 10),
          _filterChips(l10n),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            KlaykEmptyState(
              icon: Icons.campaign_outlined,
              title: l10n.adsNoCampaigns,
              message: l10n.adsNoCampaignsBody,
            )
          else
            ..._groupedSections(l10n, filtered),
        ],
      ),
    );
  }

  /// Chips de status. Só aparecem os que têm de fato campanhas.
  Widget _filterChips(AppLocalizations l10n) {
    final labels = _filterLabels(l10n);
    final counts = <_AdFilter, int>{
      for (final f in _AdFilter.values)
        f: switch (f) {
          _AdFilter.all => _rows.length,
          _AdFilter.draft => _rows
              .where((r) => r.creativeStatus == AdStatus.draft)
              .length,
          _AdFilter.review => _rows
              .where((r) => r.creativeStatus == AdStatus.pendingReview)
              .length,
          _AdFilter.active => _rows
              .where((r) => r.creativeStatus == AdStatus.approved)
              .length,
          _AdFilter.paused => _rows
              .where((r) => r.creativeStatus == AdStatus.paused)
              .length,
          _AdFilter.ended => _rows
              .where((r) => r.creativeStatus == AdStatus.expired)
              .length,
          _AdFilter.rejected => _rows
              .where((r) => r.creativeStatus == AdStatus.rejected)
              .length,
        },
    };
    final visible = _AdFilter.values
        .where((f) => f == _AdFilter.all || (counts[f] ?? 0) > 0)
        .toList();
    if (visible.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = visible[i];
          return KlayKChip(
            label: '${labels[f.index]} ${counts[f]}',
            selected: _filter == f,
            onTap: () => setState(() => _filter = f),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        if (trailing != null)
          Text(trailing, style: const TextStyle(color: Colors.white54)),
      ],
    );
  }

  /// Campanhas agrupadas por bloco (ativas, em análise, encerradas, outras)
  /// para leitura mais clara da Central de Anúncios.
  List<Widget> _groupedSections(
    AppLocalizations l10n,
    List<AdCampaignRow> rows,
  ) {
    final active = rows.where((r) => r.creativeStatus == AdStatus.approved);
    final pending = rows.where(
      (r) => r.creativeStatus == AdStatus.pendingReview,
    );
    final closed = rows.where(
      (r) => [
        AdStatus.expired,
        AdStatus.rejected,
        AdStatus.blocked,
      ].contains(r.creativeStatus),
    );
    final others = rows.where(
      (r) =>
          r.creativeStatus != AdStatus.approved &&
          r.creativeStatus != AdStatus.pendingReview &&
          r.creativeStatus != AdStatus.expired &&
          r.creativeStatus != AdStatus.rejected &&
          r.creativeStatus != AdStatus.blocked,
    );

    final children = <Widget>[];
    void addGroup(String title, Iterable<AdCampaignRow> group, IconData icon) {
      final rows = group.toList();
      if (rows.isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Row(
            children: [
              Icon(icon, color: _kAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
      children.addAll(
        rows.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AdCampaignCard(
              row: r,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AdCampaignDetailScreen(row: r, onChanged: _load),
                ),
              ),
              onDuplicate: () => _duplicate(r),
            ),
          ),
        ),
      );
    }

    addGroup(l10n.adsGroupActive, active, Icons.play_circle_outline_rounded);
    addGroup(l10n.statusInProgress, pending, Icons.hourglass_top_rounded);
    addGroup(l10n.adsGroupClosed, closed, Icons.history_rounded);
    addGroup(l10n.adsGroupOthers, others, Icons.more_horiz_rounded);
    return children;
  }

  Widget _metricsGrid(AppLocalizations l10n) {
    final ctr = _metrics.impressions == 0
        ? 0.0
        : (_metrics.clicks / _metrics.impressions * 100);
    return Row(
      children: [
        Expanded(
          child: _metricTile(
            '${_metrics.impressions}',
            l10n.adsMetricViews,
            Icons.visibility_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            '${_metrics.clicks}',
            l10n.adsMetricClicks,
            Icons.touch_app_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            '${ctr.toStringAsFixed(1)}%',
            'CTR',
            Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            _metrics.budget.toStringAsFixed(0),
            l10n.adsMetricInvestment,
            Icons.payments_outlined,
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String value, String label, IconData icon) {
    final colors = kcolors(context);
    return KlayKCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: colors.primary, size: 18),
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
}
