import 'package:flutter/material.dart';

import '../theme/klayk_theme.dart';

/// ============================================================================
/// KLAY K — Design System
///
/// Componentes reutilizáveis que dão a identidade visual premium do KLAY K:
/// fundo profundo escuro + roxo neon com glow equilibrado. Tudo aqui usa as
/// cores do [KlaykColors] já existente — nunca duplica a paleta.
/// ============================================================================

/// Acessor: cores do tema (fallback seguro para paleta dark).
KlaykColors kc(BuildContext context) => kcolors(context);

/// Raio padrão de cards / superfícies.
const double kRadiusCard = 18;
const double kRadiusChip = 999;

/// ---------------------------------------------------------------------------
/// DESIGN TOKENS — espaçamento, raio, sombra e tipografia centralizados.
/// (Nada de valores mágicos espalhados pelo projeto.)
/// ---------------------------------------------------------------------------

/// Espaçamento consistente (escala 4pt).
class KlaykSpacing {
  KlaykSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Raios das superfícies.
class KlaykRadius {
  KlaykRadius._();
  static const double card = kRadiusCard;
  static const double chip = kRadiusChip;
  static const double field = 14;
  static const double sheet = 22;
  static const double pill = 999;
}

/// Sombras padrão do KLAY K (glow roxo + sombra escura de profundidade).
class KlaykShadows {
  KlaykShadows._();

  /// Glow roxo para elementos de destaque (botão CRIAR, badges).
  static List<BoxShadow> glow(BuildContext context,
          {double blur = 18, double opacity = 0.35}) =>
      kGlow(context, blur: blur, opacity: opacity);

  /// Profundidade discreta para cards.
  static const List<BoxShadow> elevation = [
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];
}

/// Estilos de texto reutilizáveis (hierarquia visual limpa).
class KlaykTypography {
  KlaykTypography._();

  static const TextStyle hero = TextStyle(
    color: Colors.white,
    fontSize: 26,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
  );

  static const TextStyle title = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle subtitle = TextStyle(
    color: Colors.white54,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle body = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    color: Colors.white38,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle button = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );
}

/// ---------------------------------------------------------------------------
/// GLOW ROXO
/// ---------------------------------------------------------------------------

/// Sombra "glow" roxa para dar destaque sem poluir a tela.
List<BoxShadow> kGlow(BuildContext context, {double blur = 18, double opacity = 0.35}) {
  final color = kc(context).primary;
  return [
    BoxShadow(color: color.withValues(alpha: opacity), blurRadius: blur, offset: const Offset(0, 3)),
  ];
}

/// ---------------------------------------------------------------------------
/// BOTÕES
/// ---------------------------------------------------------------------------

/// Botão primário roxo com glow e cantos arredondados.
class KlayKButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final double height;

  const KlayKButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final button = FilledButton.icon(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        minimumSize: Size(expanded ? double.infinity : 0, height),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusCard),
          side: BorderSide(color: colors.primarySoft.withValues(alpha: 0.4)),
        ),
      ).copyWith(
        shadowColor: WidgetStatePropertyAll(colors.glow),
        elevation: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return 2;
          return 8;
        }),
      ),
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : (icon != null ? Icon(icon, size: 20) : null),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Botão secundário — superfície escura com borda roxa discreta.
class KlayKSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  const KlayKSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: colors.bgElevated,
        side: BorderSide(color: colors.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: Size(expanded ? double.infinity : 0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
      ),
      icon: icon != null ? Icon(icon, size: 20, color: colors.primarySoft) : null,
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Botão de ícone circular (usado em barras superiores e ações).
class KlayKIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final bool glow;
  final Widget? badge;

  const KlayKIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 38,
    this.color,
    this.glow = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface.withValues(alpha: 0.72),
            border: Border.all(color: colors.border.withValues(alpha: 0.6)),
            boxShadow: glow ? kGlow(context, blur: 12, opacity: 0.3) : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  icon,
                  color: color ?? Colors.white,
                  size: size * 0.5,
                ),
              ),
              if (badge != null)
                Positioned(right: -2, top: -2, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// CARD
/// ---------------------------------------------------------------------------

/// Card moderno do KLAY K: fundo elevado escuro, borda discreta e glow sutil.
class KlayKCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  const KlayKCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = kRadiusCard,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.border.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: box,
    );
  }
}

/// ---------------------------------------------------------------------------
/// CHIP / TAB
/// ---------------------------------------------------------------------------

/// Chip de filtro/categoria. Quando [selected], ganha preenchimento roxo + glow.
class KlayKChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const KlayKChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.9)
              : colors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(kRadiusChip),
          border: Border.all(
            color: selected
                ? colors.primarySoft.withValues(alpha: 0.6)
                : colors.border.withValues(alpha: 0.5),
          ),
          boxShadow: selected ? kGlow(context, blur: 14, opacity: 0.4) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: selected ? Colors.white : Colors.white70,
                size: 15,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// AVATAR
/// ---------------------------------------------------------------------------

/// Avatar do KLAY K: foto em círculo com borda roxa e badge "+"/check opcional.
class KlayKAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;
  final bool following;
  final VoidCallback? onTap;
  final Color? borderColor;

  /// Em contextos sem ação de seguir (ex.: footer de cards), oculta o badge.
  final bool showFollowBadge;

  const KlayKAvatar({
    super.key,
    required this.imageUrl,
    this.size = 48,
    this.following = false,
    this.onTap,
    this.borderColor,
    this.showFollowBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final border = borderColor ??
        (following ? colors.primary : colors.border);
    return Semantics(
      label: 'Perfil',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: border, width: 2),
                boxShadow: following
                    ? kGlow(context, blur: 12, opacity: 0.45)
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: ClipOval(
                child: imageUrl.isEmpty
                    ? Container(
                        color: colors.surfaceAlt,
                        child: Icon(
                          Icons.person,
                          color: Colors.white54,
                          size: size * 0.5,
                        ),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: colors.surfaceAlt,
                          child: Icon(
                            Icons.person,
                            color: Colors.white54,
                            size: size * 0.5,
                          ),
                        ),
                      ),
              ),
            ),
            if (!following && showFollowBadge)
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: Colors.black,
                    size: size * 0.28,
                    weight: 800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// BADGE
/// ---------------------------------------------------------------------------

/// Badge de contagem (notificações/mensagens não lidas).
class KlayKBadge extends StatelessWidget {
  final int count;
  final Color? color;

  const KlayKBadge({super.key, required this.count, this.color});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? kc(context).danger,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 1.4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
        ],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// SETOR / TÍTULO DE SEÇÃO
/// ---------------------------------------------------------------------------

/// Título de seção com icone opcional, subtítulo e ação "ver tudo".
class KlayKSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const KlayKSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          if (icon != null) ...[
            Icon(icon, color: colors.primary, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: KlaykTypography.title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: KlaykTypography.subtitle,
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            Padding(
              padding: const EdgeInsets.all(6),
              child: GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: colors.primarySoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// ESTADOS (loading / vazio / erro)
/// ---------------------------------------------------------------------------

class KlayKLoading extends StatelessWidget {
  const KlayKLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: kc(context).primary,
        ),
      ),
    );
  }
}

class KlayKEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subMessage;

  const KlayKEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.subMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.primary.withValues(alpha: 0.6), size: 44),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// SKELETON (loading suave)
/// ---------------------------------------------------------------------------

/// Placeholder de carregamento com pulso leve (um único controller, descartado
/// corretamente — sem vazar animações por item).
class KlayKSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final Color? color;

  const KlayKSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = kRadiusCard,
    this.color,
  });

  @override
  State<KlayKSkeleton> createState() => _KlayKSkeletonState();
}

class _KlayKSkeletonState extends State<KlayKSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? kc(context).surfaceAlt.withValues(alpha: 0.6);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// MICROINTERAÇÃO DE PRESS (toque)
/// ---------------------------------------------------------------------------

/// Envolve qualquer widget com feedback de escala ao toque. Leve (uma animação
/// por instância, sem cost da build).
class KlayKPressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const KlayKPressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.93,
  });

  @override
  State<KlayKPressableScale> createState() => _KlayKPressableScaleState();
}

class _KlayKPressableScaleState extends State<KlayKPressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onTap == null) return;
    _controller.forward();
  }

  void _release() {
    if (_controller.status == AnimationStatus.completed) {
      _controller.reverse();
    }
  }

  void _tap() {
    _controller.value = 0;
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: widget.scaleDown).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        ),
        child: widget.child,
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// APP BAR PREMIUM
/// ---------------------------------------------------------------------------

/// Barra superior padrão do KLAY K: título em destaque e ações no fim.
class KlayKAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool centerTitle;

  const KlayKAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.centerTitle = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: centerTitle,
      leading: leading,
      actions: actions,
      title: Text(
        title,
        style: KlaykTypography.title.copyWith(fontSize: 18),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 0.5,
          color: kc(context).border.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// BADGE AO VIVO
/// ---------------------------------------------------------------------------

/// Pill vermelho "AO VIVO" reutilizável (feed, cards de live, topo da sala).
class KlayKLiveBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const KlayKLiveBadge({
    super.key,
    this.label = 'AO VIVO',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE4183C),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE4183C).withValues(alpha: 0.5),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Colors.white, size: 7),
          SizedBox(width: compact ? 3 : 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 8 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// CARD DE LIVE (conceito do Studio adaptado ao KLAY K)
/// ---------------------------------------------------------------------------

/// Card de transmissão: thumbnail real + badge AO VIVO + rodapé com gradiente,
/// avatar real do criador, título real e espectadores reais.
class KlayKLiveCard extends StatelessWidget {
  /// URL real da capa (fallback: gradiente roxo do KLAY K).
  final String? imageUrl;
  final String title;
  final String? creatorName;
  final String? avatarUrl;
  final int viewerCount;
  /// `false` para lives que já encerraram (sem badge).
  final bool live;
  final VoidCallback onTap;
  final double height;

  const KlayKLiveCard({
    super.key,
    required this.imageUrl,
    required this.title,
    this.creatorName,
    this.avatarUrl,
    this.viewerCount = 0,
    this.live = true,
    required this.onTap,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return KlayKPressableScale(
      onTap: onTap,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
          boxShadow: KlaykShadows.glow(context, blur: 14, opacity: 0.22),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const _LiveCardFallback(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _LiveCardFallback(),
              )
            else
              const _LiveCardFallback(),
            // Scrim inferior para legibilidade do rodapé.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
            ),
            if (live)
              const Positioned(
                top: 10,
                left: 10,
                child: KlayKLiveBadge(compact: true),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                child: Row(
                  children: [
                    if (avatarUrl != null && avatarUrl!.isNotEmpty)
                      KlayKAvatar(
                        imageUrl: avatarUrl!,
                        size: 30,
                        showFollowBadge: false,
                        borderColor: colors.primarySoft.withValues(alpha: 0.6),
                      ),
                    if (avatarUrl != null && avatarUrl!.isNotEmpty)
                      const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (creatorName != null && creatorName!.isNotEmpty)
                            Text(
                              creatorName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KlaykTypography.caption.copyWith(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.remove_red_eye_rounded,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        viewerCount > 0 ? '$viewerCount' : '--',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fundo de fallback: gradiente roxo profundo + ícone de transmissão.
class _LiveCardFallback extends StatelessWidget {
  const _LiveCardFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1B4D), Color(0xFF14142B)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.live_tv_rounded,
          color: kc(context).primary.withValues(alpha: 0.7),
          size: 40,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// CARD DE VÍDEO (grade)
/// ---------------------------------------------------------------------------

/// Tile de vídeo para grades (perfil, busca, descoberta): miniatura real,
/// gradiente, título e métricas reais ou vazias.
class KlayKVideoCard extends StatelessWidget {
  final String? thumbUrl;
  final String title;
  final String? views;
  final String? duration;
  final VoidCallback onTap;

  const KlayKVideoCard({
    super.key,
    required this.thumbUrl,
    required this.title,
    this.views,
    this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            color: colors.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbUrl != null && thumbUrl!.isNotEmpty)
                  Image.network(
                    thumbUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => centerIcon(colors),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : centerIcon(colors),
                  )
                else
                  centerIcon(colors),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ),
                if (duration != null && duration!.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        duration!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (views != null && views!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.play_arrow_rounded,
                                color: Colors.white70, size: 12),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                views!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget centerIcon(KlaykColors colors) => Center(
        child: Icon(
          Icons.play_circle_fill_rounded,
          color: colors.primary.withValues(alpha: 0.6),
          size: 34,
        ),
      );
}
