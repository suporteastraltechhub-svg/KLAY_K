import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Abertura cinematográfica do KLAY K (~4s), 100% nativa (animação Flutter,
/// sem vídeo). Sequência: partículas/brilho roxo → logo → ícones do universo →
/// frase institucional → rodapé.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const int _kTotalMs = 4000;

  late final AnimationController _controller;
  late final Animation<double> _bg;
  late final Animation<double> _logo;
  late final Animation<double> _chips;
  late final Animation<double> _tagline;
  late final Animation<double> _footer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kTotalMs),
    );

    _bg = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 1.0));
    _logo = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 0.5, curve: Curves.easeOutBack),
    );
    _chips = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.72, curve: Curves.easeOut),
    );
    _tagline = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.72, 0.88, curve: Curves.easeOut),
    );
    _footer = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.86, 1.0, curve: Curves.easeOut),
    );
    _controller.forward().whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedBuilder(
              animation: _bg,
              builder: (context, _) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _KlayParticlesPainter(progress: _bg.value),
                      ),
                    ),
                    Positioned.fill(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: FadeTransition(
                                      opacity: _logo,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: 0.6,
                                          end: 1.0,
                                        ).animate(_logo),
                                        child: _KlayLogo(l10n: l10n),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: FadeTransition(
                                    opacity: _chips,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.25),
                                        end: Offset.zero,
                                      ).animate(_chips),
                                      child: _KlayUniverseChips(
                                        labels: [
                                          l10n.splashChipVideos,
                                          l10n.splashChipLive,
                                          l10n.splashChipGames,
                                          l10n.splashChipConnections,
                                          l10n.splashChipGifts,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                  ),
                                  child: FadeTransition(
                                    opacity: _tagline,
                                    child: Column(
                                      children: [
                                        Text(
                                          l10n.splashTagline,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          l10n.splashTaglineSub,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xFFB7A3E8),
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                FadeTransition(
                                  opacity: _footer,
                                  child: Column(
                                    children: [
                                      Text(
                                        l10n.splashCopyright,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        l10n.splashBrandTagline,
                                        style: const TextStyle(
                                          color: Color(0xFF8B5CF6),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _KlayLogo extends StatelessWidget {
  final AppLocalizations l10n;

  const _KlayLogo({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                blurRadius: 40,
                spreadRadius: 6,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClipOval(
            child: Image.asset(
              'assets/images/klay_k_icon.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF2A2740),
                alignment: Alignment.center,
                child: const Text(
                  'k',
                  style: TextStyle(
                    fontSize: 46,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'KLAY K',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: [
              Shadow(color: Color(0xFFA78BFA), blurRadius: 24),
              Shadow(color: Color(0xFF8B5CF6), blurRadius: 60),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.splashLogoTagline,
          style: const TextStyle(
            color: Color(0xFFB7A3E8),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _KlayUniverseChips extends StatelessWidget {
  final List<String> labels;

  const _KlayUniverseChips({required this.labels});

  static const List<String> kEmojis = ['📹', '📺', '🎮', '💬', '🎁'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < labels.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C2E).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              '${kEmojis[i]} ${labels[i]}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Partículas roxas com brilho neon suave, derivadas apenas do `progress`
/// (sem loop infinito — acompanha os ~4s da abertura).
class _KlayParticlesPainter extends CustomPainter {
  final double progress;

  const _KlayParticlesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.5);

    const count = 26;
    for (var i = 0; i < count; i++) {
      final seed = i * 1.618;
      final px = ((seed * 37.0) % 1.0) * size.width;
      final py = ((seed * 23.0) % 1.0) * size.height;
      final driftX = math.sin(progress * 2 * math.pi + i * 0.9) * 14;
      final driftY = ((seed * 0.5) % 1.0) * 60 * (progress);
      final x = (px + driftX) % size.width;
      final y = (py + driftY) % size.height;
      final r = 1.5 + (seed * 4) % 3;
      final opacity = 0.25 + ((seed * 0.7) % 0.5);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = const Color(0xFFC4B5FD).withValues(alpha: opacity),
      );
      if (i % 4 == 0) {
        canvas.drawCircle(Offset(x, y), r * 2.4, glow);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KlayParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
