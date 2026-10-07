import 'dart:math';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE MATEMÁTICA — contas rápidas.
///
/// Configuração via `rules.engine_config`: `rounds` (quantas contas),
/// `ops` (operadores permitidos: +, -, ×, ÷), `digits` (dígitos máximos),
/// `tint`. Uma conta por vez com 4 alternativas. Acerto = 1 ponto,
/// limitado a `max_score` no submit.
class MatematicaEngineScreen extends StatefulWidget {
  const MatematicaEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<MatematicaEngineScreen> createState() => _MatematicaEngineScreenState();
}

class _MatematicaEngineScreenState extends State<MatematicaEngineScreen> {
  late final int _rounds = cfgInt(widget.game, 'rounds', 8).clamp(3, 30);
  late final List<String> _opsResolved = _ops(widget.game.engineConfig['ops']);
  late final int _digits = cfgInt(
    widget.game,
    'digit',
    cfgInt(widget.game, 'digits', 2),
  ).clamp(1, 3);
  final Random _random = Random();

  int _index = 0;
  int _score = 0;
  bool _answered = false;
  int? _selected;
  _Problem? _problem;
  GameSubmitResult? _result;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _problem = _genProblem();
  }

  int get _maxScore => _rounds.clamp(1, widget.game.maxScore.clamp(1, 1 << 20));

  List<String> _ops(dynamic raw) {
    const defaults = ['+', '-'];
    if (raw is! List || raw.isEmpty) return defaults;
    final out = raw.whereType<String>().toList();
    return out.isEmpty ? defaults : out;
  }

  _Problem _genProblem() {
    int a, b;
    String op;
    final maxN = int.parse('9' * _digits);
    op = _opsResolved[_random.nextInt(_opsResolved.length)];
    a = _random.nextInt(maxN) + 1;
    // divisão: garante divisão exata
    if (op == '÷') {
      b = _random.nextInt(max(1, min(9, maxN))) + 1;
      a = b * (_random.nextInt(9) + 1);
    } else {
      b = _random.nextInt(maxN) + 1;
      if (op == '-' && b > a) (a, b) = (b, a);
    }
    final correct = complete(op, a, b);
    // 3 distratores distintos do resultado
    final options = <int>{correct};
    while (options.length < 4) {
      options.add(correct + (_random.nextInt(9) - 4).abs() + 1);
    }
    final list = options.toList()..shuffle(_random);
    return _Problem(text: '$a $op $b', answer: correct, options: list);
  }

  int complete(String op, int a, int b) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return a ~/ b;
      default:
        return a + b;
    }
  }

  void _answer(int i) {
    if (_answered || _submitting) return;
    setState(() {
      _answered = true;
      _selected = i;
      if (i == _problem!.options.indexOf(_problem!.answer)) _score++;
    });
  }

  Future<void> _next() async {
    if (_index < _rounds - 1) {
      setState(() {
        _index++;
        _answered = false;
        _selected = null;
        _problem = _genProblem();
      });
      return;
    }
    setState(() => _submitting = true);
    final result = await submitMatch(
      widget.game,
      score: _score,
      elapsedSeconds: _rounds * 10,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = result;
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _answered = false;
      _selected = null;
      _result = null;
      _problem = _genProblem();
    });
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
        child: _result != null
            ? EngineResultPanel(
                emoji: widget.game.emoji,
                score: _score,
                maxScore: _maxScore,
                result: _result,
                title: l10n.engineMathsCorrect(_score, _maxScore),
                accentColor: tint,
                onReplay: _restart,
                onClose: () => Navigator.of(context).pop(),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    EngineHeader(
                      title: '${widget.game.emoji} ${widget.game.name}',
                      leftLabel: l10n.engineMathCounter(_index + 1, _rounds),
                      rightLabel: l10n.engineHits(_score),
                      tint: tint,
                    ),
                    LinearProgressIndicator(
                      value: ((_index + 1) / _rounds).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: colors.surfaceAlt,
                      color: tint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tint.withValues(alpha: 0.2), colors.surface],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: tint.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _problem!.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: tint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _problem!.options.length,
                        itemBuilder: (context, i) {
                          final answer = _problem!.answer;
                          final opt = _problem!.options[i];
                          final isCorrect = _answered && opt == answer;
                          final isWrong =
                              _answered && i == _selected && opt != answer;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: isCorrect
                                  ? colors.success.withValues(alpha: 0.18)
                                  : isWrong
                                  ? colors.danger.withValues(alpha: 0.18)
                                  : colors.surface,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () => _answer(i),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isCorrect
                                          ? colors.success
                                          : isWrong
                                          ? colors.danger
                                          : colors.border,
                                    ),
                                  ),
                                  child: Text(
                                    '$opt',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _answered && !_submitting ? _next : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: tint,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: colors.surfaceAlt,
                          disabledForegroundColor: Colors.white38,
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
                                _index < _rounds - 1
                                    ? l10n.engineNextMath
                                    : l10n.engineViewResult,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Problem {
  final String text;
  final int answer;
  final List<int> options;

  const _Problem({
    required this.text,
    required this.answer,
    required this.options,
  });
}
