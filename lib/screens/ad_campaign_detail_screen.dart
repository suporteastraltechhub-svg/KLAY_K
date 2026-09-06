import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/ad_models.dart';
import '../widgets/ad_widgets.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kGold = Color(0xFFD4AF37);

/// Detalhes de uma campanha (Central de Anúncios).
///
/// Exibe métricas reais do backend (impressões, cliques, CTR, investimento),
/// status (campanha + criativo), datas e motivo de rejeição quando houver —
/// sem nenhum número fabricado.
class AdCampaignDetailScreen extends StatelessWidget {
  final AdCampaignRow row;
  const AdCampaignDetailScreen({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          row.campaignName.isEmpty ? 'Detalhes da campanha' : row.campaignName,
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
              'Status da campanha: ${adStatusLabel(row.campaignStatus)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (row.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 14),
              _rejectionBanner(),
            ],
            const SizedBox(height: 20),
            _sectionHeader('Métricas'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    '${row.impressions}',
                    'Visualizações',
                    Icons.visibility_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricTile(
                    '${row.clicks}',
                    'Cliques',
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
            _sectionHeader('Investimento'),
            const SizedBox(height: 10),
            _investmentCard(),
            const SizedBox(height: 20),
            _sectionHeader('Linha do tempo'),
            const SizedBox(height: 10),
            _timelineCard(context),
            if (row.cta.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionHeader('Chamada para ação'),
              const SizedBox(height: 10),
              _ctaCard(context),
            ],
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
                child:
                    Icon(Icons.campaign_rounded, color: _kAccent, size: 48),
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

  Widget _rejectionBanner() {
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
          const Icon(Icons.gpp_bad_outlined,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Motivo: ${row.rejectionReason}',
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

  Widget _investmentCard() {
    final remaining = (row.budget - row.spent).clamp(0, row.budget);
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _kv('Investimento total', row.budget.toStringAsFixed(0)),
              ),
              Expanded(child: _kv('Gasto', '${row.spent}')),
              Expanded(
                child: _kv(
                  'Disponível',
                  remaining.toStringAsFixed(0),
                  valueColor: Colors.greenAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value,
      {Color? valueColor = Colors.white}) {
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

  Widget _timelineCard(BuildContext context) {
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _timelineRow(
            Icons.create_rounded,
            'Criada em',
            _fmtDate(row.createdAt),
          ),
          const SizedBox(height: 10),
          _timelineRow(
            Icons.verified_outlined,
            'Aprovada em',
            row.approvedAt != null ? _fmtDate(row.approvedAt!) : 'Ainda não',
            row.approvedAt != null ? Colors.greenAccent : null,
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(
      IconData icon, String label, String value, [Color? accent]) {
    return Row(
      children: [
        Icon(
          icon,
          color: accent ?? _kAccent,
          size: 18,
        ),
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

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}