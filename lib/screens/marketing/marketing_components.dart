import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../design/klayk_design.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marketing_models.dart';
import '../../services/marketing_service.dart';
import '../../theme/klayk_theme.dart';

/// Componentes compartilhados da Central de Marketing.
/// Identidade KLAY K (preto/profundo + roxo neon), alinhados ao design system.

const Color _kGold = Color(0xFFD4AF37);

/// Título de seção consistente nas telas de marketing.
class MarketingSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final IconData? icon;

  const MarketingSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: colors.primary, size: 18),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// Chip de status de campanha (Rascunho / Aprovada / Arquivada / Local).
class MarketingStatusChip extends StatelessWidget {
  final String status;
  final bool localOnly;

  const MarketingStatusChip({
    super.key,
    required this.status,
    this.localOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final (text, color) = localOnly
        ? (l10n.marketingStatusLocal, colors.warning)
        : switch (status) {
            'approved' => (l10n.marketingStatusApproved, colors.success),
            'archived' => (l10n.marketingStatusArchived, Colors.white54),
            _ => (l10n.marketingStatusDraft, colors.primarySoft),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Linha de chips (formato/tom/categoria). Core sem quebra.
class MarketingChipRow extends StatelessWidget {
  final List<({String id, String label, String emoji})> options;
  final String selectedId;
  final ValueChanged<String> onChanged;

  const MarketingChipRow({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options
            .map(
              (o) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: KlayKChip(
                  label: '${o.emoji} ${o.label}',
                  selected: o.id == selectedId,
                  onTap: () => onChanged(o.id),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Tile de métrica (valor + rótulo).
class MarketingMetricTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color? color;

  const MarketingMetricTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return KlayKCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: color ?? colors.primary, size: 18),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Card de acesso do hub (ícone + título + subtítulo + seta).
class MarketingHubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;

  const MarketingHubCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final a = accent ?? colors.primary;
    return KlayKCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: a.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: a.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: a, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: a.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

/// Linha de ação da campanha (botão com ícone e rótulo).
class MarketingActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const MarketingActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final c = color ?? colors.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Copy para clipboard com feedback.
void copyToClipboard(BuildContext context, String text, String label) {
  final l10n = AppLocalizations.of(context)!;
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.marketingCopied(label))));
}

/// Chamada de marca do topo da Central (título + selo KLAY K Marketing).
class MarketingBrandHeader extends StatelessWidget {
  final String title;

  const MarketingBrandHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const Text(
          'KLAY K MARKETING',
          style: TextStyle(
            color: _kGold,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// Formata data curta pt-BR.
String formatMarketingDate(DateTime d) {
  String p(int x) => x.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year}';
}

/// Lista visual de variações (A–E) com copiar por variação.
class MarketingVariationList extends StatelessWidget {
  final List<MarketingVariation> variations;

  const MarketingVariationList({super.key, required this.variations});

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (var i = 0; i < variations.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          KlayKCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        variations[i].label,
                        style: TextStyle(
                          color: colors.primarySoft,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        variations[i].title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: l10n.marketingCopyVariation,
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: colors.primarySoft,
                      ),
                      onPressed: () => copyToClipboard(
                        context,
                        '[${variations[i].label}] ${variations[i].title}\n'
                        '${variations[i].description}\n'
                        '${l10n.marketingCtaPrefix(variations[i].cta)}',
                        l10n.marketingVariationNoun(variations[i].label),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  variations[i].description,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.marketingCtaPrefix(variations[i].cta),
                  style: TextStyle(
                    color: colors.primarySoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Traduz falhas de salvar/carregar da Central de Marketing em mensagens
/// claras, sem expor detalhes internos (URLs, tokens, SQL).
/// O antigo catch-all escondia a causa real sob "conexão": agora distinguimos
/// tempo esgotado, procedimento não encontrado, permissão e erro de backend.
String marketingSaveErrorMessage(AppLocalizations l10n, Object error) {
  if (error is MarketingAccessDeniedException) {
    return l10n.marketingErrAccessDenied;
  }
  if (error is TimeoutException) {
    return l10n.marketingErrTimeout;
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case 'PGRST202':
      case 'PGRST301':
        return l10n.marketingErrUnavailable;
      case '42501':
        return l10n.marketingErrPermission;
      case '53300':
        return l10n.marketingErrBusy;
      default:
        if (error.code != null && error.code!.startsWith('5')) {
          return l10n.marketingErrInternal(error.code!);
        }
        return l10n.marketingErrGeneric;
    }
  }
  return l10n.marketingErrGeneric;
}
