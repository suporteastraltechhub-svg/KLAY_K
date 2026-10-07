import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/marketing_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import '../ad_create_screen.dart';
import 'marketing_ab_screen.dart';
import 'marketing_agent_screen.dart';
import 'marketing_briefs_screen.dart';
import 'marketing_calendar_screen.dart';
import 'marketing_campaigns_screen.dart';
import 'marketing_components.dart';
import 'marketing_metrics_screen.dart';

/// Central de Marketing — hub administrativo sobre o sistema de anúncios.
///
/// Acesso restrito a administradores: a UI espelha `marketing_is_admin()` do
/// backend e cada ação re-valida no servidor (RPCs `security definer`).
class MarketingHubScreen extends StatefulWidget {
  const MarketingHubScreen({super.key});

  @override
  State<MarketingHubScreen> createState() => _MarketingHubScreenState();
}

class _MarketingHubScreenState extends State<MarketingHubScreen> {
  late bool _configured;
  bool _loading = true;
  bool _isAdmin = false;

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
        _isAdmin = false;
      });
      return;
    }
    setState(() => _loading = true);
    final admin = await MarketingService.instance.isAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bgElevated,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        title: MarketingBrandHeader(title: l10n.marketingHubTitle),
      ),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) {
      return KlaykLoader(label: l10n.marketingChecking);
    }
    if (_configured && !_isAdmin) {
      return KlaykEmptyState(
        icon: Icons.lock_rounded,
        title: l10n.marketingRestrictedTitle,
        message: l10n.marketingRestrictedMsg,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kcolors(context).primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_configured)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kcolors(context).warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: kcolors(context).warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.marketingLocalModeMsg,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          MarketingSectionHeader(
            title: l10n.marketingToolsTitle,
            icon: Icons.widgets_outlined,
          ),
          MarketingHubCard(
            icon: Icons.smart_toy_outlined,
            title: l10n.marketingAgentTitle,
            subtitle: l10n.marketingAgentSubtitle,
            onTap: _openAgent,
          ),
          const SizedBox(height: 10),
          MarketingHubCard(
            icon: Icons.campaign_outlined,
            title: l10n.marketingCampaignsTitle,
            subtitle: l10n.marketingCampaignsSubtitle,
            onTap: _openCampaigns,
          ),
          const SizedBox(height: 10),
          MarketingHubCard(
            icon: Icons.edit_note_rounded,
            title: l10n.marketingAdCreatorTitle,
            subtitle: l10n.marketingAdCreatorSubtitle,
            onTap: _openAdCreator,
          ),
          const SizedBox(height: 10),
          MarketingHubCard(
            icon: Icons.palette_outlined,
            title: l10n.marketingCreativesTitle,
            subtitle: l10n.marketingCreativesSubtitle,
            onTap: _openBriefs,
          ),
          const SizedBox(height: 18),
          MarketingSectionHeader(
            title: l10n.marketingTrackingTitle,
            icon: Icons.insights_outlined,
          ),
          MarketingHubCard(
            icon: Icons.query_stats_rounded,
            title: l10n.marketingMetricsTitle,
            subtitle: l10n.marketingMetricsSubtitle,
            onTap: _openMetrics,
          ),
          const SizedBox(height: 10),
          MarketingHubCard(
            icon: Icons.science_outlined,
            title: l10n.marketingAbTitle,
            subtitle: l10n.marketingAbSubtitle,
            onTap: _openAb,
          ),
          const SizedBox(height: 10),
          MarketingHubCard(
            icon: Icons.calendar_month_outlined,
            title: l10n.marketingCalendarTitle,
            subtitle: l10n.marketingCalendarSubtitle,
            onTap: _openCalendar,
          ),
        ],
      ),
    );
  }

  void _openAgent() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingAgentScreen()));

  void _openCampaigns() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingCampaignsScreen()));

  void _openAdCreator() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const AdCreateScreen()));

  void _openBriefs() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingBriefsScreen()));

  void _openMetrics() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingMetricsScreen()));

  void _openAb() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingAbScreen()));

  void _openCalendar() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MarketingCalendarScreen()));
}
