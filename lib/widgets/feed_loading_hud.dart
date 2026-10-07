import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/experience_settings.dart';

class FeedLoadingHud extends StatefulWidget {
  const FeedLoadingHud({super.key, required this.progress});

  final double progress;

  @override
  State<FeedLoadingHud> createState() => _FeedLoadingHudState();
}

class _FeedLoadingHudState extends State<FeedLoadingHud>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _purple = Color(0xFF8B5CF6);
  static const _violet = Color(0xFFC4B5FD);

  late final AnimationController _motion;
  bool _reduceAnimations = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    ExperienceSettings.instance.prefs.addListener(_onExperienceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionMode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncMotionMode();
    } else if (_motion.isAnimating) {
      _motion.stop();
    }
  }

  void _onExperienceChanged() {
    if (!mounted) return;
    setState(_syncMotionMode);
  }

  void _syncMotionMode() {
    final reduce =
        MediaQuery.maybeOf(context)?.disableAnimations == true ||
        ExperienceSettings.instance.reduceAnimations;
    _reduceAnimations = reduce;
    if (reduce) {
      _motion.stop();
      _motion.value = 0.18;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ExperienceSettings.instance.prefs.removeListener(_onExperienceChanged);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0).toDouble();
    final compact = MediaQuery.sizeOf(context).height < 620;
    final tickerEnabled = !_reduceAnimations && TickerMode.of(context);

    return TickerMode(
      enabled: tickerEnabled,
      child: ColoredBox(
        color: const Color(0xFF030308),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHud = math.min(
              constraints.maxWidth * (compact ? 0.70 : 0.76),
              constraints.maxHeight * (compact ? 0.42 : 0.48),
            );
            final hudSize = math.min(320.0, maxHud).toDouble();
            final progressWidth = math
                .min(250.0, constraints.maxWidth * 0.76)
                .toDouble();

            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(painter: _HudBackgroundPainter(_motion)),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      compact ? 12 : 22,
                      20,
                      compact ? 12 : 18,
                    ),
                    child: Column(
                      children: [
                        _buildIdentity(compact),
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RepaintBoundary(
                                  child: SizedBox.square(
                                    dimension: hudSize,
                                    child: CustomPaint(
                                      painter: _HudRadarPainter(
                                        _motion,
                                        progress,
                                        _reduceAnimations,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 12 : 22),
                                _buildStatus(progress, progressWidth, compact),
                              ],
                            ),
                          ),
                        ),
                        _buildFooter(compact),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIdentity(bool compact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'KLAY K',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 18 : 22,
            fontWeight: FontWeight.w900,
            letterSpacing: compact ? 4 : 5,
            shadows: const [Shadow(color: Color(0x668B5CF6), blurRadius: 14)],
          ),
        ),
        SizedBox(height: compact ? 4 : 7),
        Text(
          'KLAY K  |  클레이 케이',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          'FEITA NO BRASIL',
          style: TextStyle(
            color: _purple.withValues(alpha: 0.86),
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.3,
          ),
        ),
      ],
    );
  }

  Widget _buildStatus(double progress, double width, bool compact) {
    final percentage = (progress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CARREGANDO',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.2,
          ),
        ),
        SizedBox(height: compact ? 3 : 5),
        Text(
          'SEU FEED...',
          style: TextStyle(
            color: _violet.withValues(alpha: 0.88),
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          '$percentage%',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 19 : 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            shadows: const [Shadow(color: Color(0x558B5CF6), blurRadius: 12)],
          ),
        ),
        SizedBox(height: compact ? 8 : 11),
        SizedBox(
          width: width,
          height: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: _purple.withValues(alpha: 0.22),
                  width: 0.7,
                ),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: _reduceAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_purple, _violet],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withValues(alpha: 0.55),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(bool compact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ASTRAL TECH',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.6,
          ),
        ),
        SizedBox(height: compact ? 3 : 5),
        Text(
          'Todos os direitos reservados',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _HudBackgroundPainter extends CustomPainter {
  _HudBackgroundPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _purple = Color(0xFF8B5CF6);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width / 2, size.height * 0.46);
    final maxRadius = math.max(size.width, size.height);
    final glowRect = Rect.fromCircle(center: center, radius: maxRadius * 0.72);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _purple.withValues(alpha: 0.10),
            _purple.withValues(alpha: 0.025),
            Colors.transparent,
          ],
          stops: const [0, 0.42, 1],
        ).createShader(glowRect),
    );

    final grid = Paint()
      ..color = _purple.withValues(alpha: 0.035)
      ..strokeWidth = 0.7;
    for (var i = 1; i < 8; i++) {
      final y = size.height * i / 8;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final t = animation.value;
    for (var i = 0; i < 16; i++) {
      final phase = t * math.pi * 2 + i * 1.71;
      final x = size.width * (0.08 + ((i * 37) % 85) / 100);
      final y = size.height * (0.10 + ((i * 53) % 78) / 100);
      final alpha = 0.10 + (math.sin(phase) + 1) * 0.08;
      canvas.drawCircle(
        Offset(x, y),
        i % 3 == 0 ? 1.5 : 0.8,
        Paint()..color = _purple.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HudBackgroundPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _HudRadarPainter extends CustomPainter {
  _HudRadarPainter(this.animation, this.progress, this.reduceAnimations)
    : super(repaint: animation);

  final Animation<double> animation;
  final double progress;
  final bool reduceAnimations;

  static const _purple = Color(0xFF8B5CF6);
  static const _violet = Color(0xFFC4B5FD);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final t = reduceAnimations ? 0.18 : animation.value;
    final turn = t * math.pi * 2;

    void ring(double factor, Color color, double width) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color;
      canvas.drawCircle(center, radius * factor, paint);
    }

    void arc(
      double factor,
      double start,
      double sweep,
      Color color,
      double width,
    ) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * factor),
        start,
        sweep,
        false,
        paint,
      );
    }

    final pulse = (math.sin(turn * 2) + 1) * 0.5;
    ring(0.96, _purple.withValues(alpha: 0.13 + pulse * 0.08), 1.1);
    ring(0.82, _purple.withValues(alpha: 0.40), 1.0);
    ring(0.67, _violet.withValues(alpha: 0.32), 0.9);
    ring(0.50, _purple.withValues(alpha: 0.52), 1.1);
    ring(0.31, _violet.withValues(alpha: 0.28), 0.8);

    for (var i = 0; i < 36; i++) {
      final angle = turn * 0.18 + i * math.pi * 2 / 36;
      final major = i % 3 == 0;
      final outer = radius * 0.995;
      final inner = outer - (major ? radius * 0.075 : radius * 0.042);
      final alpha = major ? 0.56 : 0.25;
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * inner,
          center.dy + math.sin(angle) * inner,
        ),
        Offset(
          center.dx + math.cos(angle) * outer,
          center.dy + math.sin(angle) * outer,
        ),
        Paint()
          ..strokeWidth = major ? 1.1 : 0.65
          ..color = _violet.withValues(alpha: alpha),
      );
    }

    for (var i = 0; i < 10; i++) {
      final direction = i.isEven ? 1.0 : -0.72;
      final angle = turn * direction + i * math.pi * 2 / 10;
      final sweep = (0.12 + (i % 3) * 0.06) * math.pi;
      arc(
        0.74,
        angle,
        sweep,
        _violet.withValues(alpha: i.isEven ? 0.78 : 0.46),
        i.isEven ? 2.1 : 1.25,
      );
    }

    final scanAngle = -math.pi / 2 + turn;
    final scanRect = Rect.fromCircle(center: center, radius: radius * 0.88);
    final scanPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(scanRect, scanAngle, math.pi / 2.8, false)
      ..close();
    canvas.drawPath(
      scanPath,
      Paint()..color = _purple.withValues(alpha: 0.055),
    );
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(scanAngle) * radius * 0.88,
        center.dy + math.sin(scanAngle) * radius * 0.88,
      ),
      Paint()
        ..strokeWidth = 1.2
        ..color = _violet.withValues(alpha: 0.64),
    );

    for (var i = 0; i < 14; i++) {
      final angle = turn * (i.isEven ? 0.46 : -0.31) + i * 1.37;
      final distance = radius * (0.34 + ((i * 29) % 42) / 100);
      final point = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      final alpha = 0.24 + (math.sin(turn * 2.4 + i) + 1) * 0.22;
      canvas.drawCircle(
        point,
        i % 4 == 0 ? 1.8 : 1.0,
        Paint()..color = _violet.withValues(alpha: alpha),
      );
    }

    final crosshair = Paint()
      ..strokeWidth = 0.8
      ..color = _violet.withValues(alpha: 0.30);
    canvas.drawLine(
      Offset(center.dx - radius * 0.19, center.dy),
      Offset(center.dx + radius * 0.19, center.dy),
      crosshair,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.19),
      Offset(center.dx, center.dy + radius * 0.19),
      crosshair,
    );

    final flash = math.pow(math.max(0.0, math.sin(turn * 1.5)), 12).toDouble();
    if (flash > 0.02) {
      canvas.drawCircle(
        Offset(center.dx + radius * 0.58, center.dy - radius * 0.45),
        2.0 + flash * 2.0,
        Paint()..color = _violet.withValues(alpha: flash * 0.7),
      );
    }

    final progressArc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..color = _violet;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressArc,
    );

    canvas.drawCircle(
      center,
      3.0 + pulse * 1.4,
      Paint()..color = _violet.withValues(alpha: 0.82),
    );
  }

  @override
  bool shouldRepaint(covariant _HudRadarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.reduceAnimations != reduceAnimations ||
      oldDelegate.animation != animation;
}
