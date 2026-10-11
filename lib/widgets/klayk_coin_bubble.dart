import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Anel neon roxo girando devagar ao redor da moeda, com brilhos passando.
///
/// Tudo aqui é `CustomPaint`: um gradiente varrido rotacionado em vez de
/// imagem, e os brilhos são pontos desenhados no mesmo canvas. Sem shader,
/// sem asset extra, sem `BackdropFilter` — barato o suficiente para o POCO C75.
///
/// Um único [AnimationController] de giro (6s, linear, repeat) dirige o giro, o
/// halo e a estrela; um segundo (2,4s) dirige apenas os brilhos. Ambos são
/// criados e destruídos junto com o widget, e a versão estática congela tudo
/// quando a bolinha não deve piscar (aba em segundo plano).
class KlaykCoinBubble extends StatelessWidget {
  const KlaykCoinBubble({
    super.key,
    required this.size,
    required this.coinAsset,
    this.paused = false,
  });

  final double size;
  final String coinAsset;

  /// Quando verdadeiro as animações ficam congeladas.
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final coin = Image.asset(
      coinAsset,
      fit: BoxFit.contain,
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => Icon(
        Icons.monetization_on_rounded,
        color: const Color(0xFFFFD700),
        size: size * 0.62,
      ),
    );

    if (paused) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CustomPaint(
              size: Size.square(size),
              painter: const _NeonRingPainter(spin: 0.08, glow: 0.55),
            ),
            coin,
          ],
        ),
      );
    }

    return _AnimatedNeonRing(size: size, coin: coin);
  }
}

class _AnimatedNeonRing extends StatefulWidget {
  const _AnimatedNeonRing({required this.size, required this.coin});

  final double size;
  final Widget coin;

  @override
  State<_AnimatedNeonRing> createState() => _AnimatedNeonRingState();
}

class _AnimatedNeonRingState extends State<_AnimatedNeonRing>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _spark;

  @override
  void initState() {
    super.initState();
    // Giro contínuo e lento: 6s por volta, linear (sem ease, o custo fica
    // constante em vez de redesenhar mais barato no meio da volta).
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    // Brilhos mais rápidos que o giro, para parecerem "passando" pelo anel.
    _spark = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    _spark.dispose();
    super.dispose();
  }

  /// Três brilhos, cada um com seu deslocamento ao longo do anel.
  static List<double> _sparkPositions(double t) {
    return <double>[t % 1.0, (t + 0.37) % 1.0, (t + 0.71) % 1.0];
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_spin, _spark]),
        builder: (context, child) {
          final t = _spin.value;
          // Pulso do halo: 0,35 → 0,75 → 0,35 ao longo do giro. Discreto e
          // nunca chega a zero, então não pisca.
          final glow = 0.55 + 0.20 * math.sin(t * 2 * math.pi);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: Size.square(size),
                painter: _NeonRingPainter(
                  spin: t,
                  glow: glow,
                  sparks: _sparkPositions(_spark.value),
                ),
              ),
              child!,
            ],
          );
        },
        child: widget.coin,
      ),
    );
  }
}

/// Halo + anel rotativo + brilhos + estrela pulsante, num único paint.
class _NeonRingPainter extends CustomPainter {
  const _NeonRingPainter({
    required this.spin,
    required this.glow,
    this.sparks = const <double>[],
  });

  /// 0..1 = uma volta completa.
  final double spin;

  /// Intensidade do halo (0..1).
  final double glow;

  /// Posições 0..1 dos brilhos ao longo do anel.
  final List<double> sparks;

  static const Color _purple = Color(0xFFA855F7);
  static const Color _purpleDeep = Color(0xFF6D28D9);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Anel na borda interna; o centro fica livre para a moeda.
    final radius = (size.shortestSide / 2) - 3.0;
    if (radius <= 0) return;

    _paintGlow(canvas, center, radius);
    _paintRing(canvas, center, radius);
    _paintSparks(canvas, center, radius);
    _paintStar(canvas, center, radius);
  }

  /// Halo roxo suave atrás do anel. Radial simples, sem shader customizado.
  void _paintGlow(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          _purple.withValues(alpha: 0.34 * glow),
          _purpleDeep.withValues(alpha: 0.0),
        ],
        stops: const <double>[0.55, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  /// Anel neon varrido girando: SweepGradient rotacionado por [spin].
  void _paintRing(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(spin * 2 * math.pi),
        colors: <Color>[
          _purpleDeep.withValues(alpha: 0.15),
          _purple,
          const Color(0xFFE9D5FF),
          _purple,
          _purpleDeep.withValues(alpha: 0.15),
        ],
        stops: const <double>[0.0, 0.22, 0.5, 0.78, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  /// Pequenos brilhos percorrendo o anel.
  void _paintSparks(Canvas canvas, Offset center, double radius) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in sparks) {
      final angle = (p - spin) * 2 * math.pi;
      final pos = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      // Cresce e some no meio do percurso: nunca pisca, apenas desliza.
      final fade = math.sin(p * math.pi).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: 0.85 * fade);
      canvas.drawCircle(pos, 1.6 + 0.9 * fade, paint);
    }
  }

  /// Estrela roxa pulsando devagar no topo do anel.
  void _paintStar(Canvas canvas, Offset center, double radius) {
    final pulse = 0.5 + 0.5 * math.sin(spin * 2 * math.pi);
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      2.6 + 1.1 * pulse,
      Paint()..color = _purple.withValues(alpha: 0.55 + 0.35 * pulse),
    );
  }

  @override
  bool shouldRepaint(covariant _NeonRingPainter old) {
    return old.spin != spin || old.glow != glow || old.sparks != sparks;
  }
}