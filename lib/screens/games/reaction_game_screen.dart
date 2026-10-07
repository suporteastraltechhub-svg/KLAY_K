import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/game_service.dart';
import '../../theme/klayk_theme.dart';

/// Toque Rápido: toque o alvo o máximo de vezes em 15 segundos.
/// Pontuação = número de toques (até `max_score=40`). Ao final o score é
/// submetido via RPC `game_submit_score` — recompensa decidida no servidor.
class ReactionGameScreen extends StatefulWidget {
  const ReactionGameScreen({super.key});

  @override
  State<ReactionGameScreen> createState() => _ReactionGameScreenState();
}

class _ReactionGameScreenState extends State<ReactionGameScreen> {
  static const int _duration = 15;
  final _svc = GameService.instance;

  Timer? _timer;
  int _remaining = _duration;
  int _score = 0;
  bool _running = false;
  bool _finished = false;
  Offset _target = const Offset(0, 0);
  double _size = 44;
  final Random _random = Random();
  String? _resultText;
  bool _submitting = false;

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
      _score = 0;
      _resultText = null;
      _submitting = false;
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

  void _finish() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _running = false;
      _finished = true;
      _submitting = true;
    });
    try {
      final sessionId = await _svc.startSession('toque');
      final r = await _svc.submitScore(
        sessionId: sessionId,
        score: _score,
        durationSeconds: _duration,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _resultText =
            l10n.gameTaps(_score) +
            (r.improved ? '\n${l10n.engineReward(r.reward)}' : '');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _resultText = '${l10n.gameTaps(_score)}\n${l10n.gameNotSynced}';
      });
    }
  }

  void _hitTarget(BoxConstraints constraints) {
    if (!_running) return;
    setState(() {
      _score++;
      _relocate(constraints);
    });
    if (_score % 5 == 0) {
      setState(() {
        _size = max(34, _size - 3);
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

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(l10n.gameTapTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  _statCard(colors, '⏱', '$_remaining s'),
                  const SizedBox(width: 12),
                  _statCard(colors, '🎯', l10n.gameTaps(_score)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (!_running) {
                      return Center(child: _idleView(colors));
                    }
                    return Stack(
                      children: [
                        Positioned(
                          left: _target.dx,
                          top: _target.dy,
                          child: GestureDetector(
                            onTap: () => _hitTarget(constraints),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: _size,
                              height: _size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.danger,
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.danger.withValues(alpha: 0.4),
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
                      backgroundColor: colors.primary,
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
                  l10n.gameTapTargetHint,
                  style: const TextStyle(
                    color: Color(0xFFB28DFF),
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(KlaykColors colors, String emoji, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
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

  Widget _idleView(KlaykColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        const Text('⚡', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text(
          l10n.gameTapIntro15,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Colors.white70,
          ),
        ),
        if (_resultText != null) ...[
          const SizedBox(height: 20),
          Text(
            _resultText!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }
}
