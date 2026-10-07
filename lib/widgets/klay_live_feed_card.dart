import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/klayk_live_models.dart';
import '../widgets/klayk_ux.dart';
import '../widgets/verified_badge.dart';

const Color _kPurple = Color(0xFF8B5CF6);
const Color _kPurpleSoft = Color(0xFF9B5CFF);
const Color _kLiveRed = Color(0xFFFF2E4D);

/// Card profissional de uma LIVE real no feed/grid do KLAY K.
///
/// Hierarquia: [preview da transmissão] em destaque (capa real com fallback
/// KLAY K, badge 🔴 AO VIVO e contador REAL de espectadores) e, abaixo,
/// as informações do criador (avatar, nome, @username, título, categoria) e o
/// botão "Entrar na Live". Nenhum dado é inventado: tudo vem de [RealLive].
///
/// O card NÃO conecta ao LiveKit — apenas navega para a sala real via [onTap]
/// (performance §19/20). Leve: usa `cacheWidth` da densidade e animações de
/// um único disparo (sem tickers eternos em listas).
class KlayLiveFeedCard extends StatelessWidget {
  final RealLive live;
  final VoidCallback onTap;

  /// Widget opcional exibido à direita do nome do criador (ex.: menu de
  /// editar/encerrar para o DONO da live — jamais para o público).
  final Widget? headerTrailing;

  const KlayLiveFeedCard({
    super.key,
    required this.live,
    required this.onTap,
    this.headerTrailing,
  });

  bool get _isGame =>
      live.category.toLowerCase().contains('jogo') ||
      (live.gameName != null && live.gameName!.isNotEmpty);

  /// Ícone de apresentação derivado da categoria Real — nunca um valor fixo.
  String get _categoryIcon {
    final c = (live.gameName?.isNotEmpty == true)
        ? live.gameName!
        : live.category;
    final lower = c.toLowerCase();
    if (lower.contains('jogo') ||
        lower.contains('roblox') ||
        lower.contains('game') ||
        lower.contains('minecraft')) {
      return '🎮';
    }
    if (lower.contains('música') ||
        lower.contains('musica') ||
        lower.contains('music')) {
      return '🎤';
    }
    if (lower.contains('filme') ||
        lower.contains('cinema') ||
        lower.contains('movie')) {
      return '🎬';
    }
    if (lower.contains('conversa') ||
        lower.contains('batepapo') ||
        lower.contains('chat') ||
        lower.contains('amigos')) {
      return '💬';
    }
    if (lower.contains('esporte') ||
        lower.contains('futebol') ||
        lower.contains('sport')) {
      return '⚽';
    }
    return '📺';
  }

  /// Categoria de exibição usando dados reais (jogo > categoria > fallback
  /// neutro localizado). Nunca um texto fixo.
  String _displayCategory(AppLocalizations l10n) {
    final game = live.gameName;
    if (_isGame && game != null && game.isNotEmpty) {
      return '$_categoryIcon $game';
    }
    if (live.category.isNotEmpty) return '$_categoryIcon ${live.category}';
    return '$_categoryIcon ${l10n.liveTransmissionFallback}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name =
        live.streamerDisplayName ??
        live.streamerUsername ??
        l10n.liveTransmissionFallback;

    return Semantics(
      container: true,
      button: true,
      label: '${l10n.liveBadge}. ${live.title}. Por $name. ${l10n.enterLive}',
      child: KlayKPressableScale(
        onTap: onTap,
        scaleDown: 0.97,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(opacity: t, child: child),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF251A45), Color(0xFF12101E)],
              ),
              border: Border.all(color: _kPurple.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: _kPurple.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildPreview(context, l10n)),
                _buildInfoBlock(l10n, name),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Área de destaque: capa real (com fallback elegante) + badge + viewers.
  Widget _buildPreview(BuildContext context, AppLocalizations l10n) {
    final hasCover = live.coverUrl != null && live.coverUrl!.isNotEmpty;
    return ClipRRect(
      // Preserva apenas a borda superior do card (parte de baixo é info).
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildCoverLayer(context, hasCover, constraints.maxWidth),
              // Leve scrim para manter badges legíveis sobre qualquer capa.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x66000000),
                      Colors.transparent,
                      Color(0x40000000),
                    ],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
              const Positioned(top: 8, left: 8, child: _LivePill()),
              if (live.viewerCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _ViewersPill(count: live.viewerCount),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCoverLayer(BuildContext context, bool hasCover, double width) {
    final fallback = _PreviewFallback(title: live.title);
    if (!hasCover) return fallback;
    return Image.network(
      live.coverUrl!,
      fit: BoxFit.cover,
      cacheWidth: imageDecodeWidth(context, width),
      filterQuality: FilterQuality.low,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  /// Bloco de informações: avatar + nome/@username, título, categoria e o
  /// botão real "Entrar na Live". Tudo com ellipsis — nunca transborda.
  Widget _buildInfoBlock(AppLocalizations l10n, String name) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF15121F),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCreatorRow(l10n, name),
          const SizedBox(height: 6),
          Text(
            live.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          _buildCategoryChip(l10n),
          const SizedBox(height: 8),
          _buildEnterButton(l10n),
        ],
      ),
    );
  }

  Widget _buildCreatorRow(AppLocalizations l10n, String name) {
    final hasUsername =
        live.streamerUsername != null && live.streamerUsername!.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: _kPurple.withValues(alpha: 0.3),
          backgroundImage:
              live.streamerAvatar != null && live.streamerAvatar!.isNotEmpty
              ? NetworkImage(live.streamerAvatar!)
              : null,
          child: const Icon(Icons.person, color: Colors.white70, size: 15),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (live.streamerVerified) ...[
                    const SizedBox(width: 4),
                    const VerifiedBadge(size: 12),
                  ],
                ],
              ),
              if (hasUsername)
                Text(
                  '@${live.streamerUsername}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
            ],
          ),
        ),
        if (headerTrailing != null) headerTrailing!,
      ],
    );
  }

  Widget _buildCategoryChip(AppLocalizations l10n) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _kPurple.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _kPurple.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        _displayCategory(l10n),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildEnterButton(AppLocalizations l10n) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPurpleSoft, _kPurple],
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 4),
          Text(
            l10n.enterLive,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder de preview sem capa/imagem (nunca um retângulo vazio):
/// gradiente KLAY K + ícone com anel de luz + título real da live.
class _PreviewFallback extends StatelessWidget {
  final String title;

  const _PreviewFallback({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1B54), Color(0xFF0D0B14)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kPurple.withValues(alpha: 0.55),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kPurple.withValues(alpha: 0.35),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: const Icon(
                Icons.sensors_rounded,
                color: Colors.white70,
                size: 26,
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill vermelha "AO VIVO" com pulso leve de anel (um único disparo por
/// build — nenhum ticker eterno em listas).
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kLiveRed,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(color: _kLiveRed.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOut,
            builder: (_, t, __) => Container(
              width: 7 + 2 * (1 - t),
              height: 7 + 2 * (1 - t),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.75 * (1 - t)),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: SizedBox(width: 4, height: 4),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context)!.liveBadge,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill com o número REAL de espectadores (nunca fixo).
class _ViewersPill extends StatelessWidget {
  final int count;

  const _ViewersPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.remove_red_eye_rounded,
            color: Colors.white70,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
