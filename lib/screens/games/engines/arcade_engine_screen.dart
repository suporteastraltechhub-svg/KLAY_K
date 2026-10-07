import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE ARCADE — desvie dos obstáculos.
///
/// Toque na metade esquerda/direita da arena para mover o jogador. Cada
/// obstáculo desviado vale 1 ponto (limitado a `max_score`). Duração e
/// velocidade vêm de `rules.engine_config` (`duration_seconds`, `speed`).
/// Mesma tela para Acrobata, Goleiro, Trilha na Floresta etc.
class ArcadeEngineScreen extends StatefulWidget {
  const ArcadeEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<ArcadeEngineScreen> createState() => _ArcadeEngineScreenState();
}

class _ArcadeEngineScreenState extends State<ArcadeEngineScreen> {
  late final int _duration = cfgInt(
    widget.game,
    'duration_seconds',
    widget.game.durationSeconds,
  );
  late final double _speed = cfgDouble(widget.game, 'speed', 1.0);

  final Random _random = Random();
  final List<_Obstacle> _obstacles = [];

  Timer? _tick;
  Timer? _spawn;
  int _remaining = 0;
  double _px = 0.5;
  double _targetX = 0.5;
  int _dodged = 0;
  bool _running = false;
  bool _finished = false;
  GameSubmitResult? _result;
  bool _submitting = false;
  Size _arena = Size.zero;

  static const double _playerSize = 46;
  static const double _obstacleSize = 40;

  int get _score => _dodged.clamp(0, widget.game.maxScore);

  @override
  void dispose() {
    _tick?.cancel();
    _spawn?.cancel();
    super.dispose();
  }

  void _start(Size arena) {
    _arena = arena;
    setState(() {
      _running = true;
      _finished = false;
      _remaining = _duration;
      _dodged = 0;
      _obstacles.clear();
      _result = null;
      _submitting = false;
      _px = 0.5;
      _targetX = 0.5;
    });
    _tick?.cancel();
    _spawn?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) => _step());
    _spawn = Timer.periodic(Duration(milliseconds: (860 / _speed).round()), (
      _,
    ) {
      if (!mounted || !_running) return;
      setState(() {
        _obstacles.add(
          _Obstacle(x: _random.nextDouble() * 0.8 + 0.1, y: -_obstacleSize),
        );
      });
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        _finish();
        return;
      }
      setState(() => _remaining--);
    });
  }

  Timer? _timer;

  void _step() {
    if (!mounted || !_running || _arena.height == 0) return;
    final fallStep = _arena.height / (140 ~/ _speed.clamp(0.4, 2.4));
    var collided = false;
    setState(() {
      _px += (_targetX - _px) * 0.14;
      final playerX = _px * _arena.width;
      final gone = <_Obstacle>[];
      for (final o in _obstacles) {
        o.y += fallStep;
        final ox = o.x * _arena.width;
        final verticalGap = (o.y - (_arena.height - _playerSize - 60)).abs();
        final horizontalGap = (ox - playerX).abs();
        if (verticalGap < (_playerSize + _obstacleSize) / 1.6 &&
            horizontalGap < _playerSize) {
          collided = true;
          gone.add(o);
          break;
        }
        if (o.y > _arena.height + _obstacleSize) {
          gone.add(o);
          if (_dodged < widget.game.maxScore) _dodged++;
        }
      }
      _obstacles.removeWhere((o) => gone.contains(o));
      if (collided) _running = false;
      if (!_running) {
        _tick?.cancel();
        _spawn?.cancel();
        _timer?.cancel();
      }
    });
    if (collided) _finish();
  }

  void _turn(double fraction) {
    if (!_running) return;
    setState(() => _targetX = fraction.clamp(0.05, 0.95));
  }

  Future<void> _finish() async {
    if (_submitting) return;
    setState(() {
      _running = false;
      _finished = true;
      _submitting = true;
    });
    _tick?.cancel();
    _spawn?.cancel();
    _timer?.cancel();
    final result = await submitMatch(
      widget.game,
      score: _score,
      elapsedSeconds: _duration - _remaining,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = result;
    });
  }

  void _restart() {
    _start(_arena);
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final tint = engineColor(widget.game);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(widget.game.name)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _stat(colors, tint, '⏱', '$_remaining s')),
                  const SizedBox(width: 12),
                  Expanded(child: _stat(colors, tint, '🛡️', '$_score')),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final arena = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return GestureDetector(
                      onTapDown: (d) => _turn(d.localPosition.dx / arena.width),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              tint.withValues(alpha: 0.12),
                              colors.surface,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: tint.withValues(alpha: 0.35),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _finished
                            ? EngineResultPanel(
                                emoji: widget.game.emoji,
                                score: _score,
                                maxScore: widget.game.maxScore,
                                result: _result,
                                title: l10n.engineDodged(_score),
                                accentColor: tint,
                                onReplay: _restart,
                                onClose: () => Navigator.of(context).pop(),
                              )
                            : Stack(
                                children: [
                                  Positioned.fill(
                                    child: _running
                                        ? const SizedBox.shrink()
                                        : Center(
                                            child: Text(
                                              _finished
                                                  ? ''
                                                  : '${widget.game.emoji}\n'
                                                        '${l10n.engineArcadeIntro(_duration)}',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 22,
                                                height: 1.4,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                  ),
                                  Positioned.fill(
                                    child: _running
                                        ? _obstacleLayer(colors)
                                        : const SizedBox.shrink(),
                                  ),
                                  if (_running)
                                    Positioned(
                                      left:
                                          _px * _arena.width - _playerSize / 2,
                                      bottom: 24,
                                      width: _playerSize,
                                      height: _playerSize,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              tint.withValues(alpha: 0.9),
                                              tint,
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: tint.withValues(
                                                alpha: 0.45,
                                              ),
                                              blurRadius: 16,
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            widget.game.emoji,
                                            style: const TextStyle(
                                              fontSize: 22,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!_running && !_finished)
                                    Positioned.fill(
                                      child: Center(
                                        child: FilledButton.icon(
                                          onPressed: () => _start(arena),
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                          ),
                                          label: Text(
                                            l10n.engineStart,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: tint,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 28,
                                              vertical: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _obstacleLayer(KlaykColors colors) {
    return Stack(
      children: [
        for (final o in _obstacles)
          Positioned(
            left: o.x * _arena.width - _obstacleSize / 2,
            top: o.y,
            width: _obstacleSize,
            height: _obstacleSize,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.danger.withValues(alpha: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: colors.danger.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stat(KlaykColors colors, Color tint, String emoji, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _Obstacle {
  double x;
  double y;

  _Obstacle({required this.x, required this.y});
}
