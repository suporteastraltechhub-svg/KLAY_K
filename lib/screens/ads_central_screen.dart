import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/klayk_ux.dart';
import 'ad_campaign_detail_screen.dart';
import 'ad_create_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

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
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdCreateScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Central de Anúncios',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text('KLAY K Ads',
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                )),
          ],
        ),
      ),
      body: SafeArea(
        child: _configured ? _body() : _unconfigured(),
      ),
      floatingActionButton: _configured
          ? FloatingActionButton.extended(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('+ Criar anúncio'),
            )
          : null,
    );
  }

  Widget _unconfigured() {
    return const KlaykEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Backend não configurado',
      message:
          'Conecte o Supabase para usar a Central de Anúncios do KLAY K.',
    );
  }

  Widget _body() {
    if (_loadFailed) {
      return KlaykErrorState(
        message: 'Não conseguimos carregar seus anúncios.',
        onRetry: _load,
      );
    }
    if (_loading) {
      return const KlaykListSkeleton(rows: 6, withAvatar: false);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _metricsGrid(),
          const SizedBox(height: 20),
          _sectionHeader('Campanhas',
              trailing: '${_rows.length}'),
          const SizedBox(height: 10),
          if (_rows.isEmpty)
            const KlaykEmptyState(
              icon: Icons.campaign_outlined,
              title: 'Nenhuma campanha ainda',
              message:
                  'Toque em "+ Criar anúncio" para começar sua primeira campanha no KLAY K.',
            )
          else
            ..._groupedSections(),
        ],
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
  List<Widget> _groupedSections() {
    final active = _rows.where((r) => r.creativeStatus == AdStatus.approved);
    final pending =
        _rows.where((r) => r.creativeStatus == AdStatus.pendingReview);
    final closed = _rows.where((r) => [
          AdStatus.expired,
          AdStatus.rejected,
          AdStatus.blocked,
        ].contains(r.creativeStatus));
    final others = _rows.where((r) =>
        r.creativeStatus != AdStatus.approved &&
        r.creativeStatus != AdStatus.pendingReview &&
        r.creativeStatus != AdStatus.expired &&
        r.creativeStatus != AdStatus.rejected &&
        r.creativeStatus != AdStatus.blocked);

    final children = <Widget>[];
    void addGroup(String title, Iterable<AdCampaignRow> group, IconData icon) {
      final rows = group.toList();
      if (rows.isEmpty) return;
      children.add(Padding(
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
      ));
      children.addAll(rows.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AdCampaignCard(
              row: r,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdCampaignDetailScreen(row: r),
                ),
              ),
            ),
          )));
    }

    addGroup('Ativas', active, Icons.play_circle_outline_rounded);
    addGroup('Em análise', pending, Icons.hourglass_top_rounded);
    addGroup('Encerradas', closed, Icons.history_rounded);
    addGroup('Outras', others, Icons.more_horiz_rounded);
    return children;
  }

  Widget _metricsGrid() {
    final ctr = _metrics.impressions == 0
        ? 0.0
        : (_metrics.clicks / _metrics.impressions * 100);
    return Row(
      children: [
        Expanded(
          child: _metricTile(
            '${_metrics.impressions}',
            'Visualizações',
            Icons.visibility_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            '${_metrics.clicks}',
            'Cliques',
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
            'Investimento',
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