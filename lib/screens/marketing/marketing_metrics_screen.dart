import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../services/marketing_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import 'marketing_ab_screen.dart';
import 'marketing_components.dart';

/// Métricas da Central — dados REAIS (nunca inventados).
///
/// Agrega `admin_ads_list` do sistema de anúncios. Sem impressões, mostramos
/// "Dados insuficientes para calcular." — não há conversões/A-B até existir
/// infraestrutura real que os produza.
class MarketingMetricsScreen extends StatefulWidget {
  const MarketingMetricsScreen({super.key});

  @override
  State<MarketingMetricsScreen> createState() => _MarketingMetricsScreenState();
}

class _MarketingMetricsScreenState extends State<MarketingMetricsScreen> {
  late bool _configured;
  bool _loading = true;
  bool _failed = false;
  MarketingSummary _summary = MarketingSummary.empty;

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
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final summary = await MarketingService.instance.adminMetrics();
      if (!mounted) return;
      setState(() {
        _summary = summary ?? MarketingSummary.empty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bgElevated,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        title: MarketingBrandHeader(title: l10n.marketingMetricsTitle),
      ),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (!_configured) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: l10n.marketingBackendNotConfigured,
        message: l10n.marketingMetricsBackendMsg,
      );
    }
    if (_failed) {
      return KlaykErrorState(
        message: l10n.marketingMetricsLoadFail,
        onRetry: _load,
      );
    }
    if (_loading) {
      return const KlaykListSkeleton(rows: 5, withAvatar: false);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kcolors(context).primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MarketingSectionHeader(
            title: l10n.marketingAdsPerformance,
            trailing: l10n.marketingReal,
            icon: Icons.query_stats_rounded,
          ),
          if (!_summary.hasData) const _InsufficientBanner(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MarketingMetricTile(
                  value: _summary.hasData ? '${_summary.impressions}' : '—',
                  label: l10n.marketingImpressions,
                  icon: Icons.visibility_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MarketingMetricTile(
                  value: _summary.hasData ? '${_summary.clicks}' : '—',
                  label: l10n.marketingClicks,
                  icon: Icons.touch_app_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MarketingMetricTile(
                  value: _summary.ctrText ?? '—',
                  label: l10n.marketingCtr,
                  icon: Icons.trending_up_rounded,
                  color: _summary.hasData
                      ? kcolors(context).success
                      : kcolors(context).primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          MarketingSectionHeader(
            title: l10n.marketingAdsStatus,
            icon: Icons.verified_outlined,
          ),
          Row(
            children: [
              Expanded(
                child: MarketingMetricTile(
                  value: '${_summary.approved}',
                  label: l10n.marketingApprovedMetric,
                  icon: Icons.check_circle_outline_rounded,
                  color: kcolors(context).success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MarketingMetricTile(
                  value: '${_summary.rejected}',
                  label: l10n.marketingRejectedMetric,
                  icon: Icons.cancel_outlined,
                  color: kcolors(context).danger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MarketingMetricTile(
                  value: '${_summary.paused}',
                  label: l10n.marketingPausedMetric,
                  icon: Icons.pause_circle_outline_rounded,
                  color: kcolors(context).warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MarketingMetricTile(
                  value: '${_summary.blocked}',
                  label: l10n.marketingBlockedMetric,
                  icon: Icons.block_rounded,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MarketingMetricTile(
                  value: '${_summary.advertisers}',
                  label: l10n.marketingAdvertisers,
                  icon: Icons.apartment_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MarketingMetricTile(
                  value: '—',
                  label: l10n.marketingConversions,
                  icon: Icons.timeline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          MarketingSectionHeader(
            title: l10n.marketingMissingData,
            icon: Icons.info_outline_rounded,
          ),
          KlayKCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _note(Icons.swap_horiz_rounded, l10n.marketingConversionsNote),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MarketingAbScreen(),
                    ),
                  ),
                  child: _note(
                    Icons.science_outlined,
                    l10n.marketingAbNote,
                    accent: kcolors(context).primarySoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text, {Color? accent}) {
    final colors = kcolors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent ?? colors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _InsufficientBanner extends StatelessWidget {
  const _InsufficientBanner();

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFF59E0B),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.marketingInsufficientBanner,
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
}
