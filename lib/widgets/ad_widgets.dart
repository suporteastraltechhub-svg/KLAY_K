import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../services/link_guard_service.dart';
import 'ad_report_sheet.dart';

/// ============================================================================
/// KLAY K — Componentes reutilizáveis do Sistema Oficial de Anúncios.
///
/// Identidade preto/grafite/roxo neon com detalhes DOURADOS reservados
/// exclusivamente a elementos oficiais/verificados (selo). O selo é sempre
/// renderizado pelo app quando o backend informa APPROVED + verificado —
/// nunca vindo de imagem enviada pelo anunciante.
/// ============================================================================

const Color kAdPurple = Color(0xFF8B5CF6);
const Color kAdGold = Color(0xFFD4AF37);
const Color kAdSurface = Color(0xFF17141F);
const Color kAdBorder = Color(0xFF2A2540);

/// Último toque em CTA, por anúncio, para ignorar cliques duplicados rápidos
/// (anti double-tap local). Chaveado por creative_id para não bloquear toques
/// legítimos em anúncios diferentes (§49/§50).
final Map<String, DateTime> _lastAdCtaTapByCreative = {};

/// Abre o destino de um anúncio com validação de segurança (reglas §10/§11).
///
/// - Só conta o clique após ação real do usuário (security definer valida);
/// - Só abre destinos autorizados (http/https explícito com host);
/// - Rejeita `javascript:`, `intent:`, esquemas desconhecidos e URLs inválidas;
/// - Nunca abre navegador automaticamente (sempre ação explícita do usuário);
/// - Ignora toques repetidos rápidos no MESMO anúncio (anti double-tap).
Future<void> openAdCta(BuildContext context, AdCreative ad) async {
  if (!ad.hasValidCta) return;

  final now = DateTime.now();
  final lastTap = _lastAdCtaTapByCreative[ad.id];
  if (lastTap != null &&
      now.difference(lastTap) < const Duration(milliseconds: 600)) {
    return;
  }
  _lastAdCtaTapByCreative[ad.id] = now;

  final url = ad.ctaUrl.trim();

  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    uri = null;
  }
  final scheme = uri?.scheme.toLowerCase() ?? '';
  final isSafe =
      (scheme == 'http' || scheme == 'https') &&
      (uri?.host.isNotEmpty ?? false);

  if (!isSafe) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adInvalidLinkSnack)));
    }
    return;
  }

  // Só conta o clique se o backend aceitar (security definer filtra APPROVED).
  AdsService.instance.trackEvent(ad.id, 'click');

  // Proteção de links: confirma que o usuário está saindo do KLAY K e mostra
  // o domínio antes de abrir o destino externo.
  final l10n = AppLocalizations.of(context)!;
  final opened = await LinkGuard.instance.openExternal(context, url);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.adOpenFailedSnack)));
  }
}

/// ---------------------------------------------------------------------------
/// Badge "ANÚNCIO" — em todo anúncio exibido (identificação transparente).
/// ---------------------------------------------------------------------------
class AdBadge extends StatelessWidget {
  const AdBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Badge único para identificar publicidade em qualquer contexto; nunca
    // depende só de cor ("não depender apenas de cor para indicar anúncio").
    return Semantics(
      label: l10n.adBadge,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kAdSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A3355)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_rounded, color: kAdPurple, size: 13),
            const SizedBox(width: 5),
            Text(
              l10n.adBadge.toUpperCase(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Selo oficial "KLAY K · OFICIAL · ANÚNCIO VERIFICADO".
/// Usa o PNG oficial `assets/images/klay_k_oficial_anuncio_verificado.png`
/// (1310×1200, RGBA com transparência, declarado via `assets: - assets/`).
/// Só aparece quando o backend informa anúncio verificado (APPROVED + is_verified).
/// Nunca vindo de imagem enviada pelo anunciante. Se o asset falhar, cai no
/// fallback em ícone/texto equivalente.
/// ---------------------------------------------------------------------------
class VerifiedAdSeal extends StatelessWidget {
  const VerifiedAdSeal({super.key, this.compact = false});

  /// [compact] = badge reduzido; senão, badge completo com faixa OFICIAL.
  final bool compact;

  static const String _sealAsset =
      'assets/images/klay_k_oficial_anuncio_verificado.png';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.adVerifiedSemantics,
      image: true,
      child: Image.asset(
        _sealAsset,
        width: compact ? 26 : 52,
        height: compact ? 24 : 48,
        fit: BoxFit.contain,
        // Decodifica em tamanho pequeno (performance §67/§41): nítido até
        // ~3x density sem carregar o PNG de 1.9 MB em memória cheia.
        cacheWidth: 160,
        errorBuilder: (_, _, _) => compact
            ? _sealFallbackCompact(context)
            : _sealFallbackFull(context),
      ),
    );
  }

  /// Fallback discreto se o PNG oficial não puder ser exibido.
  Widget _sealFallbackCompact(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kAdSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAdGold, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, color: kAdGold, size: 12),
          const SizedBox(width: 4),
          Text(
            l10n.adVerifiedSealFallback,
            style: const TextStyle(
              color: kAdGold,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sealFallbackFull(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _sealShell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, color: kAdGold, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'KLAY K',
                style: TextStyle(
                  color: kAdGold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                l10n.adVerifiedSealText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sealShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2E14), Color(0xFF1E1608)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAdGold, width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55D4AF37),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Chip de status de campanha/anúncio.
class AdStatusChip extends StatelessWidget {
  final AdStatus status;
  const AdStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (status) {
      AdStatus.approved => (l10n.adStatusApproved, Colors.greenAccent),
      AdStatus.pendingReview => (
        l10n.statusInProgress,
        const Color(0xFFF59E0B),
      ),
      AdStatus.rejected => (l10n.adStatusRejected, Colors.redAccent),
      AdStatus.paused => (l10n.adStatusPaused, Colors.orangeAccent),
      AdStatus.expired => (l10n.adStatusExpired, Colors.blueGrey),
      AdStatus.blocked => (l10n.adStatusBlocked, Colors.redAccent),
      _ => (l10n.adStatusDraft, Colors.white54),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String adStatusLabel(AppLocalizations l10n, AdStatus s) {
  switch (s) {
    case AdStatus.approved:
      return l10n.adStatusLabelApproved;
    case AdStatus.pendingReview:
      return l10n.statusInProgress;
    case AdStatus.rejected:
      return l10n.adStatusLabelRejected;
    case AdStatus.paused:
      return l10n.adStatusLabelPaused;
    case AdStatus.expired:
      return l10n.adStatusLabelExpired;
    case AdStatus.blocked:
      return l10n.adStatusLabelBlocked;
    default:
      return l10n.adStatusDraft;
  }
}

/// Avatar do anunciante (logo ou inicial).
class AdAvatar extends StatelessWidget {
  final AdCreative ad;
  final double size;
  const AdAvatar({super.key, required this.ad, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = ad.advertiserName.isNotEmpty
        ? ad.advertiserName
        : l10n.advertiser;
    return Semantics(
      label: l10n.adSemanticsAdvertiserLogo(name),
      image: true,
      child: ad.advertiserLogo.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.3),
              child: Image.network(
                ad.advertiserLogo,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Fallback seguro de logo: avatar genérico da empresa (§36).
                errorBuilder: (_, __, ___) => _fallback(name, size),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _fallback(name, size),
              ),
            )
          : _fallback(name, size),
    );
  }

  /// Avatar genérico do anunciante (inicial do nome) quando o logo falha.
  Widget _fallback(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Card de anúncio exibido no feed/descoberta. Sempre com AdBadge e, se o
/// backend marcou como verificado (APPROVED + verified), o selo KLAY K.
class AdCard extends StatelessWidget {
  final AdCreative ad;

  /// Chamado após o usuário ocultar o anúncio (remoção imediata da lista).
  final VoidCallback? onHidden;

  /// [preview] marca visual realista mas claramente "PRÉ-VISUALIZAÇÃO":
  /// usado antes da aprovação (ex.: revisão do anunciante/admin). Nunca deve
  /// parecer publicidade publicada (§55/§56): CTA não dispara ação.
  final bool preview;

  const AdCard({
    super.key,
    required this.ad,
    this.onHidden,
    this.preview = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final advertiser = ad.advertiserName.isNotEmpty
        ? ad.advertiserName
        : l10n.advertiser;
    return Semantics(
      container: true,
      label: ad.title.isEmpty
          ? l10n.adSemanticsAd(advertiser)
          : '${l10n.adSemanticsAd(advertiser)} · ${ad.title}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(
          opacity: value,
          // Entrada suave e discreta (fade-in leve, sem movimento excessivo).
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        ),
        child: _content(context, l10n, advertiser),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    String advertiser,
  ) {
    return KlayKCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AdBadge(),
                  ),
                ),
                if (preview) ...[
                  const _AdPreviewBanner(),
                  const SizedBox(width: 6),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: AdOverflowMenu(ad: ad, onHidden: onHidden),
                ),
              ],
            ),
          ),
          _media(ad),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (ad.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    ad.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (ad.advertiserName.isNotEmpty)
                  Row(
                    children: [
                      AdAvatar(ad: ad),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ad.advertiserName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        l10n.advertiser,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                if (ad.verified) ...[
                  const SizedBox(height: 8),
                  const VerifiedAdSeal(),
                ],
                if (ad.hasValidCta) ...[
                  const SizedBox(height: 12),
                  _AdCtaButton(ad: ad, enabled: !preview),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _media(AdCreative ad) {
    return Container(
      height: 170,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2350), Color(0xFF141020)],
        ),
      ),
      child: ad.mediaUrl.isEmpty
          ? const Center(
              child: Icon(Icons.campaign_rounded, color: kAdPurple, size: 40),
            )
          : Image.network(
              ad.mediaUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.campaign_rounded, color: kAdPurple, size: 40),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kAdPurple,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Botão CTA de anúncio com microinteração leve (escala no toque) e alvo de
/// toque adequado (48dp). Desabilitado em [enabled] == false (pré-visualização):
/// nunca dispara ação antes que o anúncio exista de verdade (§52/§81).
class _AdCtaButton extends StatefulWidget {
  final AdCreative ad;
  final bool enabled;
  const _AdCtaButton({required this.ad, this.enabled = true});

  @override
  State<_AdCtaButton> createState() => _AdCtaButtonState();
}

class _AdCtaButtonState extends State<_AdCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: widget.enabled
                ? () => openAdCta(context, widget.ad)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: kAdPurple,
              disabledBackgroundColor: kAdPurple.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(widget.ad.ctaLabel),
          ),
        ),
      ),
    );
  }
}

/// Chip "PRÉ-VISUALIZAÇÃO · PENDENTE DE REVISÃO" para deixar claro que o
/// anúncio ainda não está publicado (§55/§56).
class _AdPreviewBanner extends StatelessWidget {
  const _AdPreviewBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.adPreviewBannerSemantics,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2350),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF8B5CF6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.preview_rounded, color: kAdPurple, size: 13),
            const SizedBox(width: 5),
            Text(
              l10n.adPreviewBanner.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card compacto de campanha (Central de Anúncios).
class AdCampaignCard extends StatelessWidget {
  final AdCampaignRow row;
  final VoidCallback? onTap;

  /// Callback opcional de "duplicar campanha". Só aparece quando informado.
  final VoidCallback? onDuplicate;

  const AdCampaignCard({
    super.key,
    required this.row,
    this.onTap,
    this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: KlayKCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.campaignName.isEmpty ? row.title : row.campaignName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                AdStatusChip(status: row.creativeStatus),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              row.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric('${row.impressions}', l10n.adsMetricViews),
                _metric('${row.clicks}', l10n.adsMetricClicks),
                _metric('${row.ctr.toStringAsFixed(1)}%', 'CTR'),
                _metric(
                  row.budget.toStringAsFixed(0),
                  l10n.adsMetricInvestment,
                ),
              ],
            ),
            if (row.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                l10n.adsReasonLabel(row.rejectionReason),
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            if (onDuplicate != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onDuplicate,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8B5CF6),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(
                    l10n.adDuplicateAction,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Column(
      children: [
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
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

/// Cart de perfil do anunciante ("Sobre este anunciante").
class AdvertiserCard extends StatelessWidget {
  final AdCreative ad;
  const AdvertiserCard({super.key, required this.ad});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdAvatar(ad: ad, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.advertiserName.isEmpty
                          ? l10n.advertiser
                          : ad.advertiserName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (ad.advertiserCategory.isNotEmpty)
                      Text(
                        ad.advertiserCategory,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (ad.verified) const VerifiedAdSeal(compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.adAdvertiserCardBody,
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
}

/// Menu "Por que estou vendo este anúncio?" + Ocultar + Denunciar.
class AdOverflowMenu extends StatelessWidget {
  final AdCreative ad;

  /// Chamado depois que o usuário oculta o anúncio (remoção imediata do
  /// local que exibiu, ex.: slot do feed), sem depender de recarregamento.
  final VoidCallback? onHidden;

  const AdOverflowMenu({super.key, required this.ad, this.onHidden});

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) =>
          _AdAboutSheet(ad: ad, sheetFrom: context, onHidden: onHidden),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      onPressed: () => _open(context),
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      tooltip: l10n.adWhyThisAd,
    );
  }
}

/// Bottom sheet "Por que estou vendo este anúncio?" com ações.
class _AdAboutSheet extends StatelessWidget {
  final AdCreative ad;
  final BuildContext sheetFrom;
  final VoidCallback? onHidden;
  const _AdAboutSheet({
    required this.ad,
    required this.sheetFrom,
    this.onHidden,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
            Text(
              l10n.adWhyThisAd,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.adAboutBody,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (ad.verified) ...[
                  const VerifiedAdSeal(compact: true),
                  const SizedBox(width: 8),
                ],
                const AdBadge(),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _hide(sheetFrom);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF3A3355)),
                ),
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text(l10n.adHideAd),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openReport(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Color(0x55FF5252)),
                ),
                icon: const Icon(Icons.report_gmailerrorred_outlined),
                label: Text(l10n.adReportAd),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _hide(BuildContext context) async {
    await AdsService.instance.hideCreative(ad.id);
    onHidden?.call();
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.adHiddenSnack)));
  }

  void _openReport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => AdReportSheet(creativeId: ad.id),
    );
  }
}
