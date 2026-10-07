import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE REFLEXO — toque no alvo (reação).
///
/// Configuração via `rules.engine_config`: `duration_seconds`, `shrink_every`
/// (0 desliga o encolhimento), `tint`. Pontuação = toques no alvo, limitada a
/// `max_score` do backend (o servidor rejeita qualquer valor acima).
class ReflexEngineScreen extends StatefulWidget {
  const ReflexEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<ReflexEngineScreen> createState() => _ReflexEngineScreenState();
}

class _ReflexEngineScreenState extends State<ReflexEngineScreen> {
  late final int _duration = cfgInt(
    widget.game,
    'duration_seconds',
    widget.game.durationSeconds,
  );
  late final int _shrinkEvery = cfgInt(widget.game, 'shrink_every', 5);
  final Random _random = Random();

  Timer? _timer;
  int _remaining = 0;
  int _taps = 0;
  bool _running = false;
  bool _finished = false;
  Offset _target = const Offset(0, 0);
  double _size = 44;
  GameSubmitResult? _result;
  bool _submitting = false;

  int get _score => _taps.clamp(0, widget.game.maxScore);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _finished = false;
      _remaining = _duration;
      _taps = 0;
      _result = null;
      _submitting = false;
      _size = 44;
      _relocate();
    });
    _timer?.cancel();
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

  Future<void> _finish() async {
    setState(() {
      _running = false;
      _finished = true;
      _submitting = true;
    });
    final result = await submitMatch(
      widget.game,
      score: _score,
      elapsedSeconds: _duration,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = result;
    });
  }

  void _hit(BoxConstraints constraints) {
    if (!_running) return;
    setState(() {
      if (_taps < widget.game.maxScore) _taps++;
      _relocate(constraints);
    });
    if (_shrinkEvery > 0 && _taps % _shrinkEvery == 0) {
      setState(() {
        _size = max(30, _size - 3);
      });
    }
  }

  void _relocate([BoxConstraints? c]) {
    final size = c?.maxWidth ?? 320;
    final height = c?.maxHeight ?? 500;
    _target = Offset(
      _random.nextDouble() * max(0, size - 120) + 24,
      _random.nextDouble() * max(0, height - 120) + 24,
    );
  }

  void _restart() {
    _start();
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
                  _statCard(colors, '⏱', '$_remaining s', tint),
                  const SizedBox(width: 12),
                  _statCard(colors, '🎯', '$_score', tint),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_finished) {
                      return EngineResultPanel(
                        emoji: widget.game.emoji,
                        score: _score,
                        maxScore: widget.game.maxScore,
                        result: _result,
                        subtitle: l10n.gameTaps(_score),
                        accentColor: tint,
                        onReplay: _restart,
                        onClose: () => Navigator.of(context).pop(),
                      );
                    }
                    if (!_running) {
                      return Center(child: _idleView(colors, tint));
                    }
                    return Stack(
                      children: [
                        Positioned(
                          left: _target.dx,
                          top: _target.dy,
                          child: GestureDetector(
                            onTap: () => _hit(constraints),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: _size,
                              height: _size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tint,
                                boxShadow: [
                                  BoxShadow(
                                    color: tint.withValues(alpha: 0.4),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.bolt_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (!_running)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: tint,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _finished ? l10n.enginePlayAgain : l10n.engineStart,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                )
              else
                Text(
                  _shrinkEvery > 0
                      ? l10n.engineTapShrinkHint(_shrinkEvery)
                      : l10n.engineTapHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tint, fontSize: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(KlaykColors colors, String emoji, String value, Color tint) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idleView(KlaykColors colors, Color tint) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(widget.game.emoji, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text(
          l10n.engineTapIntro(_duration),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
