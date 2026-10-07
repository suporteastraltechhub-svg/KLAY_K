import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/klayk_theme.dart';
import '../services/supabase_service.dart';

/// ============================================================================
/// KLAY K — Componentes de experiência premium
/// Loading (skeleton), estado vazio, erro com retry e loader nativo leve.
/// ============================================================================

/// Skeleton com brilho suave (pulso de opacidade — barato em GPU/CPU).
class KlaykSkeleton extends StatefulWidget {
  const KlaykSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 10,
    this.color,
  });

  final double? width;
  final double height;
  final double radius;
  final Color? color;

  @override
  State<KlaykSkeleton> createState() => _KlaykSkeletonState();
}

class _KlaykSkeletonState extends State<KlaykSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _a = Tween<double>(
      begin: 0.45,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return FadeTransition(
      opacity: _a,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color ?? colors.surfaceAlt,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Esqueleto de lista para telas (linhas simuladas + avatars).
class KlaykListSkeleton extends StatelessWidget {
  const KlaykListSkeleton({super.key, this.rows = 6, this.withAvatar = true});

  final int rows;
  final bool withAvatar;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            if (withAvatar) ...[
              const KlaykSkeleton(width: 42, height: 42, radius: 21),
              const SizedBox(width: 12),
            ],
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KlaykSkeleton(width: 150),
                  SizedBox(height: 7),
                  KlaykSkeleton(width: double.infinity, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loader premium para encartes (substitui CircularProgressIndicator puro).
class KlaykLoader extends StatelessWidget {
  const KlaykLoader({super.key, this.label, this.padding});

  final String? label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Center(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                backgroundColor: colors.primary.withValues(alpha: 0.15),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 14),
              Text(
                label!,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado vazio elegante: ícone em painel gradiente + título + ação útil.
class KlaykEmptyState extends StatelessWidget {
  const KlaykEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.padding,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Center(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2350), Color(0xFF161026)],
                ),
                border: Border.all(color: colors.border),
              ),
              child: Icon(icon, color: colors.primarySoft, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: colors.primary),
                icon: Icon(actionIcon ?? Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de erro: mensagem clara + botão "Tentar novamente".
class KlaykErrorState extends StatelessWidget {
  const KlaykErrorState({
    super.key,
    required this.onRetry,
    this.title = '',
    this.message = '',
    this.padding,
  });

  final VoidCallback onRetry;
  final String title;
  final String message;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = kcolors(context);
    final resolvedTitle = title.isNotEmpty ? title : l10n.errorStateTitle;
    final resolvedMessage = message.isNotEmpty
        ? message
        : l10n.errorStateMessage;
    return Center(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.danger.withValues(alpha: 0.1),
                border: Border.all(color: colors.danger.withValues(alpha: 0.5)),
              ),
              child: Icon(
                Icons.wifi_tethering_off_rounded,
                color: colors.danger,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              resolvedTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              resolvedMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primarySoft,
                side: BorderSide(color: colors.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão de navegação premium com transição suave (usado em lugar de
/// `Navigator.push` para transições consistentes).
class KlaykNav {
  KlaykNav._();

  static Future<T?> push<T>(
    BuildContext context,
    Widget screen, {
    bool fullscreenDialog = false,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (_) => screen,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }
}

/// Painel "cartão" padronizado do KLAY K.
class KlaykCard extends StatelessWidget {
  const KlaykCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.gradient,
    this.onTap,
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final decoration = BoxDecoration(
      gradient:
          gradient ??
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.surfaceAlt, colors.surface],
          ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor ?? colors.border),
      boxShadow: [
        BoxShadow(
          color: colors.primary.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
    final content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: content,
    );
  }
}

/// Título de seção premium.
class KlaykSectionTitle extends StatelessWidget {
  const KlaykSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: KlaykColors.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Cabeçalho de tela premium (gradiente + brilho discreto).
class KlaykScreenBackground extends StatelessWidget {
  const KlaykScreenBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.7, -0.9),
          radius: 1.1,
          colors: [
            const Color(0xFF8B5CF6).withValues(alpha: 0.14),
            const Color(0xFF08070D).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.6],
        ),
      ),
      child: child,
    );
  }
}

/// Anima um número ao mudar (`AnimatedSwitcher` leve) para contadores premium.
class KlaykAnimatedNumber extends StatelessWidget {
  const KlaykAnimatedNumber(this.value, {super.key, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: Text('$value', key: ValueKey(value), style: style),
    );
  }
}

/// Helper para debounce simples (busca em tempo de digitação).
class KlaykDebouncer {
  KlaykDebouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() => _timer?.cancel();
}

/// Gera um `cacheWidth` com base na densidade para economizar memória ao
/// decodificar imagens de rede com `Image.network`.
int imageDecodeWidth(BuildContext context, double displayWidth) {
  final dpr = MediaQuery.of(context).devicePixelRatio.ceil().clamp(1, 3);
  return (displayWidth * dpr).round().clamp(48, 1024);
}

/// Shortcut: se o aplicativo está rodando contra o backend real (evita
/// chamadas em modo demo).
bool liveBackendEnabled() => SupabaseService.instance.isConfigured;
