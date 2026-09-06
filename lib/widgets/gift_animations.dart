import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/gift_models.dart';
import '../services/experience_settings.dart';

/// Presets de animação reutilizáveis. Tudo é gerado proceduralmente com
/// CustomPainter + partículas — NENHUM arquivo de asset pesado dentro do APK.
/// Novos presentes reutilizam os mesmos presets (só mudam cores/glyph), e o
/// catálogo inteiro (50k+/100k+) não pesa nada no apk.
enum GiftAnimKind {
  sparkle,
  heartburst,
  starfall,
  diamondrain,
  fireflight,
  cosmicgate,
  dragoncelestial,
  royalthrone,
  supernova,
}

GiftAnimKind animKindFor(String key) {
  switch (key) {
    case 'heartburst':
      return GiftAnimKind.heartburst;
    case 'starfall':
      return GiftAnimKind.starfall;
    case 'diamondrain':
      return GiftAnimKind.diamondrain;
    case 'fireflight':
      return GiftAnimKind.fireflight;
    case 'cosmicgate':
      return GiftAnimKind.cosmicgate;
    case 'dragoncelestial':
      return GiftAnimKind.dragoncelestial;
    case 'royalthrone':
      return GiftAnimKind.royalthrone;
    case 'supernova':
      return GiftAnimKind.supernova;
    default:
      return GiftAnimKind.sparkle;
  }
}

Color _parseColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return fallback;
  return Color(value);
}

/// Anima um presente na tela (sobreposição full-screen), exibindo animação de
/// entrada, principal e saída conforme o preset, com identificação do remetente
/// e nome do presente (requisitos de entrada cinematográfica).
class GiftAnimationOverlay extends StatefulWidget {
  final Gift gift;
  final String senderName;
  final int amount;
  final VoidCallback onComplete;

  const GiftAnimationOverlay({
    super.key,
    required this.gift,
    this.senderName = '',
    this.amount = 1,
    required this.onComplete,
  });

  @override
  State<GiftAnimationOverlay> createState() => GiftAnimationOverlayState();
}

class GiftAnimationOverlayState extends State<GiftAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final GiftAnimKind _kind;
  late final Color _color;
  late final Color _trail;
  late final bool _reduced;

  @override
  void initState() {
    super.initState();
    _reduced = ExperienceSettings.instance.reduceAnimations ||
        ExperienceSettings.instance.reduceEffects;
    _kind = animKindFor(widget.gift.animationKey);
    final fx = widget.gift.effects;
    _color = _parseColor(fx['color']?.toString(), const Color(0xFFFFD700));
    _trail =
        _parseColor(fx['trail']?.toString(), const Color(0xFFFFE082));
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(_kind),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      });
    _controller.forward();
  }

  Duration _durationFor(GiftAnimKind k) {
    if (_reduced) return const Duration(milliseconds: 700);
    switch (k) {
      case GiftAnimKind.cosmicgate:
      case GiftAnimKind.dragoncelestial:
      case GiftAnimKind.royalthrone:
        return const Duration(seconds: 5);
      case GiftAnimKind.supernova:
        return const Duration(seconds: 4);
      default:
        return const Duration(milliseconds: 2600);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (_reduced) {
      // Modo reduzido: reconhecimento estático e curto (sem partículas).
      return FadeTransition(
        opacity: anim,
        child: GestureDetector(
          onTap: () => _controller.forward(from: 1.0),
          behavior: HitTestBehavior.translucent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xE6161420),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: _color.withValues(alpha: 0.6), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${widget.gift.icon} ${widget.gift.name}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  if (widget.senderName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(widget.senderName,
                        style: TextStyle(
                            color: _color,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                  if (widget.amount > 1) ...[
                    const SizedBox(height: 2),
                    Text('x${widget.amount}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _controller.forward(from: 1.0),
              behavior: HitTestBehavior.translucent,
            ),
            // Partículas procedurais ao fundo.
            CustomPaint(
              painter: _ParticlePainter(
                kind: _kind,
                color: _color,
                trail: _trail,
                icon: widget.gift.icon,
                progress: anim.value,
              ),
            ),
            // Cabeçalho: nome do presente + remetente.
            if (_controller.value > 0.4)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: FadeTransition(
                      opacity: anim,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.gift.icon} ${widget.gift.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(
                                  blurRadius: 12,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                          if (widget.senderName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                widget.senderName,
                                style: TextStyle(
                                  color: _color,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (widget.amount > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'x${widget.amount}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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
  }
}

/// Pintor procedural das partículas e elemento principal do presente.
class _ParticlePainter extends CustomPainter {
  final GiftAnimKind kind;
  final Color color;
  final Color trail;
  final String icon;
  final double progress;

  _ParticlePainter({
    required this.kind,
    required this.color,
    required this.trail,
    required this.icon,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final center = Offset(size.width / 2, size.height / 2);

    switch (kind) {
      case GiftAnimKind.sparkle:
        _drawSparkle(canvas, center);
        break;
      case GiftAnimKind.heartburst:
        _drawBurst(canvas, center, '❤️');
        break;
      case GiftAnimKind.starfall:
        _drawRain(canvas, size, '⭐');
        break;
      case GiftAnimKind.diamondrain:
        _drawRain(canvas, size, '💎');
        break;
      case GiftAnimKind.fireflight:
        _drawFire(canvas, center);
        break;
      case GiftAnimKind.cosmicgate:
        _drawCosmicGate(canvas, center);
        break;
      case GiftAnimKind.royalthrone:
        _drawRoyal(canvas, center);
        break;
      case GiftAnimKind.supernova:
        _drawNova(canvas, center);
        break;
      case GiftAnimKind.dragoncelestial:
        _drawCelestialDragon(canvas, size, rnd);
        break;
    }

    // Elemento principal (glifo/ícone) central com leve flutuação.
    if (kind != GiftAnimKind.dragoncelestial) {
      _drawGlyph(canvas, center, icon, 46);
    }
  }

  void _drawGlyph(Canvas canvas, Offset center, String glyph, double size) {
    if (glyph.isEmpty) return;
    final bob = math.sin(progress * math.pi * 2) * 8;
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontSize: size, shadows: [
          Shadow(blurRadius: 24, color: color.withValues(alpha: 0.8)),
        ]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2 + bob));
  }

  void _drawSparkle(Canvas canvas, Offset center) {
    const n = 40;
    for (var i = 0; i < n; i++) {
      final t = ((progress * n) + i) % n / n;
      final angle = i * 2.39996;
      final radius = 30 + progress * (200 + (i % 7) * 20);
      final p = center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = trail.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(p, 2 + t * 6, paint);
    }
  }

  void _drawBurst(Canvas canvas, Offset center, String g) {
    final isHeart = g == '❤️';
    for (var i = 0; i < 26; i++) {
      final t = ((progress * 26) + i) % 26 / 26;
      final angle = i * 0.483;
      final spd = 60 + (i % 5) * 22;
      final radius = progress * (90 + spd);
      final p = center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius * 0.9);
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      _paintGlyphAt(canvas, p, isHeart ? '❤️' : '💖',
          (10 + (i % 4) * 4) * (0.6 + t), color.withValues(alpha: alpha));
    }
  }

  void _drawRain(Canvas canvas, Size size, String g) {
    const n = 30;
    for (var i = 0; i < n; i++) {
      final x = ((i * 137.0) % size.width);
      final fall = (((progress * 1.6) + i * 0.17) % 1.0);
      final y = -40 + fall * (size.height + 80);
      final alpha = (1.0 - fall * 0.6).clamp(0.0, 1.0);
      _paintGlyphAt(canvas, Offset(x, y), g, 18 + (i % 3) * 6,
          Colors.white.withValues(alpha: alpha));
    }
  }

  void _drawFire(Canvas canvas, Offset center) {
    for (var i = 0; i < 60; i++) {
      final t = ((progress * 60) + i) % 60 / 60;
      final angle = (i % 6) * 1.047 + (i % 2 == 0 ? progress * 0.4 : 0);
      final radius = 20 + t * (150 + (i % 4) * 30);
      final p = center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius * 0.7);
      final alpha = (1.0 - t) * 0.9;
      final c = i % 2 == 0 ? const Color(0xFFFF7043) : const Color(0xFFFFB300);
      final paint = Paint()
        ..color = c.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(p, 3 + t * 10, paint);
    }
  }

  void _drawCosmicGate(Canvas canvas, Offset center) {
    final r = 40 + progress * 220;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        r,
        [
          color.withValues(alpha: 0.5),
          color.withValues(alpha: 0.05),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(center, r, paint);
    for (var i = 0; i < 3; i++) {
      final rr = (40 + progress * 220) * (0.5 + i * 0.25);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = trail.withValues(alpha: 0.6 - i * 0.18);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(progress * (2 + i));
      canvas.drawOval(Rect.fromCenter(
          center: Offset.zero, width: rr, height: rr * 0.5), ring);
      canvas.restore();
    }
  }

  void _drawRoyal(Canvas canvas, Offset center) {
    // Arco ascendente + coroa.
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(0.0, 1.0))
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (var i = 0; i < 5; i++) {
      final base = center + Offset(-140 + i * 70, 120);
      final h = progress * (80 + (i % 3) * 20);
      canvas.drawLine(
          base, base - Offset(0, h), paint..color = trail.withValues(alpha: 0.7));
    }
    _drawGlyph(canvas, center - Offset(0, 40 * progress), '👑', 48);
  }

  void _drawNova(Canvas canvas, Offset center) {
    final r = progress * 260;
    final c1 = Paint()
      ..shader = ui.Gradient.radial(center, r, [
        Colors.white,
        color.withValues(alpha: 0.7),
        Colors.transparent,
      ]);
    canvas.drawCircle(center, r, c1);
    // Anéis.
    for (var i = 0; i < 4; i++) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: (1 - progress).clamp(0.0, 1.0));
      canvas.drawCircle(center, r * (0.4 + i * 0.22), ring);
    }
  }

  void _drawParticleTrail(Canvas canvas, Offset from, Offset to, int count) {
    final paint = Paint()
      ..color = trail.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (var i = 0; i < count; i++) {
      final t = i / count;
      final p = Offset.lerp(from, to, t)!;
      canvas.drawCircle(p, 2.5, paint);
    }
  }

  void _drawCelestialDragon(Canvas canvas, Size size, math.Random rnd) {
    final w = size.width;
    final h = size.height;

    // 1) Portal dourado de entrada (primeiro 15%).
    if (progress < 0.15) {
      final t = (progress / 0.15);
      final c = Offset(w / 2, h / 2);
      final r = 20 + t * 140;
      final p = Paint()
        ..shader = ui.Gradient.radial(c, r, [
          const Color(0xFFFFD700).withValues(alpha: 0.7),
          const Color(0xFFFFE082).withValues(alpha: 0.3),
          Colors.transparent,
        ]);
      canvas.drawCircle(c, r, p);
      return;
    }

    // 2-5) Dragão cruza a tela com rastro de partículas douradas.
    final cross = ((progress - 0.15) / 0.55).clamp(0.0, 1.0);
    final arc = math.sin(cross * math.pi);
    final x = w * (0.1 + 0.8 * cross);
    final y = h * (0.25 + 0.35 * (1 - arc)); // loop/volta
    final dragonPos = Offset(x, y);

    // Rastro de partículas.
    _drawParticleTrail(canvas, Offset(w, y), dragonPos, 24);

    // Brilho ao redor do dragão.
    final glow = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(dragonPos, 34, glow);

    // Glifo do dragão.
    _drawGlyph(canvas, dragonPos, '🐉', 64);

    // Espalha partículas flutuantes douradas pela tela.
    for (var i = 0; i < 40; i++) {
      final px = (rnd.nextDouble() * w);
      final py = (rnd.nextDouble() * h);
      final alpha = (1 - cross) * 0.8;
      final p = Paint()
        ..color = const Color(0xFFFFE082).withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(px, py), 1.5 + rnd.nextDouble() * 2, p);
    }

    // 6) Volta ao redor da transmissão + revelação do nome (próximo do fim).
    // O nome/remetente é exibido pelo widget cabeçalho quando progress > 0.4.
    if (cross > 0.92) {
      final sparkle = Paint()
        ..color = Colors.white.withValues(alpha: (1 - progress).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      for (var i = 0; i < 16; i++) {
        final a = i * 0.392;
        final r = 150 * (1 + (progress - 0.93) * 2);
        canvas.drawCircle(
          Offset(w / 2 + math.cos(a) * r, h / 2 + math.sin(a) * r),
          4,
          sparkle,
        );
      }
    }
  }

  void _paintGlyphAt(
      Canvas canvas, Offset at, String g, double size, Color color) {
    if (g.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: g, style: TextStyle(fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.progress != progress;
}

/// Painel/possível widget auxiliar para exibir o saldo de créditos.
class CreditsPill extends StatelessWidget {
  final int credits;
  const CreditsPill({super.key, required this.credits});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFD700), size: 16),
          const SizedBox(width: 4),
          Text(
            '$credits',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
