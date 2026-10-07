import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import 'marketing_agent_screen.dart';
import 'marketing_campaign_screen.dart';
import 'marketing_components.dart';

/// Calendário: campanhas agrupadas por data (criação/aprovação).
///
/// A publicação é sempre manual — o calendário reflete datas reais de
/// criação/aprovação, nunca agendamentos automáticos.
class MarketingCalendarScreen extends StatefulWidget {
  const MarketingCalendarScreen({super.key});

  @override
  State<MarketingCalendarScreen> createState() =>
      _MarketingCalendarScreenState();
}

class _MarketingCalendarScreenState extends State<MarketingCalendarScreen> {
  late bool _configured;
  bool _loading = true;
  bool _failed = false;
  List<MarketingCampaign> _rows = [];

  @override
  void initState() {
    super.initState();
    _configured = SupabaseService.instance.isConfigured;
    _load();
  }

  Future<void> _load() async {
    if (!_configured) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await MarketingService.instance.listCampaigns();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  void _create() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingAgentScreen()));

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bgElevated,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        title: MarketingBrandHeader(title: l10n.marketingCalendarTitle),
      ),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (!_configured) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: l10n.marketingBackendNotConfigured,
        message: l10n.marketingCalendarBackendMsg,
      );
    }
    if (_failed) {
      return KlaykErrorState(
        message: l10n.marketingCalendarLoadFail,
        onRetry: _load,
      );
    }
    if (_loading) {
      return const KlaykListSkeleton(rows: 6, withAvatar: false);
    }
    if (_rows.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.calendar_month_outlined,
        title: l10n.marketingCalendarEmpty,
        message: l10n.marketingCalendarEmptyMsg,
        actionLabel: l10n.marketingGenerateCampaign,
        actionIcon: Icons.smart_toy_outlined,
        onAction: _create,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kcolors(context).primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.marketingCalendarManualMsg,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          ..._grouped(),
        ],
      ),
    );
  }

  List<Widget> _grouped() {
    final byDate = <String, List<MarketingCampaign>>{};
    for (final c in _rows) {
      final date = c.approvedAt ?? c.createdAt;
      final key = '${date.year}-${date.month}-${date.day}';
      byDate.putIfAbsent(key, () => []).add(c);
    }
    final sortedKeys = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    final children = <Widget>[];
    for (final key in sortedKeys) {
      final date = DateTime.parse(key);
      final items = byDate[key]!;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                color: kcolors(context).primary,
                size: 15,
              ),
              const SizedBox(width: 8),
              Text(
                formatMarketingDate(date),
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kcolors(context).surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
      children.addAll(
        items.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _campaignCard(c),
          ),
        ),
      );
    }
    return children;
  }

  Widget _campaignCard(MarketingCampaign c) {
    return KlayKCard(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarketingCampaignScreen(campaign: c),
          ),
        );
        _load();
      },
      child: Row(
        children: [
          Icon(
            Icons.campaign_outlined,
            color: kcolors(context).primarySoft,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${c.objective.label} · ${c.format.label}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          MarketingStatusChip(status: c.status),
        ],
      ),
    );
  }
}
