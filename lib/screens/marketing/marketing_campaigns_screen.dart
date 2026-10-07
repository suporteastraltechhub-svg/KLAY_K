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

/// Campanhas salvas da Central de Marketing.
class MarketingCampaignsScreen extends StatefulWidget {
  const MarketingCampaignsScreen({super.key});

  @override
  State<MarketingCampaignsScreen> createState() =>
      _MarketingCampaignsScreenState();
}

class _MarketingCampaignsScreenState extends State<MarketingCampaignsScreen> {
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
      setState(() {
        _loading = false;
        _failed = false;
      });
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openCreate() => Navigator.of(
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
        title: MarketingBrandHeader(title: l10n.marketingCampaignsTitle),
      ),
      body: SafeArea(child: _configured ? _body(l10n) : _unconfigured(l10n)),
      floatingActionButton: _configured
          ? FloatingActionButton.extended(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              onPressed: _openCreate,
              icon: const Icon(Icons.smart_toy_outlined),
              label: Text(l10n.marketingAgentShort),
            )
          : null,
    );
  }

  Widget _unconfigured(AppLocalizations l10n) {
    return KlaykEmptyState(
      icon: Icons.cloud_off_outlined,
      title: l10n.marketingBackendNotConfigured,
      message: l10n.marketingCampaignsBackendMsg,
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_failed) {
      return KlaykErrorState(
        message: l10n.marketingCampaignsLoadFail,
        onRetry: _load,
      );
    }
    if (_loading) {
      return const KlaykListSkeleton(rows: 5, withAvatar: false);
    }
    if (_rows.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.campaign_outlined,
        title: l10n.marketingNoCampaigns,
        message: l10n.marketingNoCampaignsMsg,
        actionLabel: l10n.marketingGenerateWithAgent,
        actionIcon: Icons.smart_toy_outlined,
        onAction: _openCreate,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kcolors(context).primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _campaignCard(_rows[i]),
      ),
    );
  }

  Widget _campaignCard(MarketingCampaign c) {
    final colors = kcolors(context);
    return KlayKCard(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarketingCampaignScreen(campaign: c),
          ),
        );
        _load();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MarketingStatusChip(status: c.status),
              const Spacer(),
              Text(
                formatMarketingDate(c.updatedAtOrCreated),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final v in c.variations) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    v.label,
                    style: TextStyle(
                      color: colors.primarySoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

extension on MarketingCampaign {
  DateTime get updatedAtOrCreated => createdAt;
}
