import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE TRIVIA — múltipla escolha.
///
/// Lê `rules.engine_config.questions` do backend: lista de
/// `[pergunta, opA, opB, opC, opD, indiceCorreto]`. Um jogo = uma configuração;
/// a mesma tela serve para qualquer número de quizzes (novos jogos = novos
/// dados, nunca telas novas). Pontuação = acertos (0..maxScore) validada via
/// `game_submit_score`.
class TriviaEngineScreen extends StatefulWidget {
  const TriviaEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<TriviaEngineScreen> createState() => _TriviaEngineScreenState();
}

class _TriviaEngineScreenState extends State<TriviaEngineScreen> {
  late final List<_TriviaQuestion> _questions;
  int _index = 0;
  int _score = 0;
  bool _answered = false;
  int? _selected;
  bool _submitting = false;
  String? _resultText;
  GameSubmitResult? _result;

  @override
  void initState() {
    super.initState();
    _questions = _parseQuestions(widget.game.engineConfig['questions']);
    _questions.shuffle();
  }

  List<_TriviaQuestion> _parseQuestions(dynamic raw) {
    const fallback = [
      [
        'Qual é a capital do Brasil?',
        'Rio',
        'Brasília',
        'São Paulo',
        'Salvador',
        1,
      ],
      ['Quantas cores tem o arco-íris?', '5', '6', '7', '8', 2],
      [
        'Quem pintou a "Monalisa"?',
        'Michelangelo',
        'Da Vinci',
        'Picasso',
        'Van Gogh',
        1,
      ],
      ['Qual é o maior planeta?', 'Terra', 'Marte', 'Júpiter', 'Saturno', 2],
      ['Quantos meses têm 1 ano?', '10', '11', '12', '13', 2],
      ['Que som faz o gato?', 'Au au', 'Miau', 'Muu', 'Piupiu', 1],
    ];
    if (raw is! List || raw.isEmpty) {
      return [for (final q in fallback) _TriviaQuestion.fromList(q)];
    }
    final out = <_TriviaQuestion>[];
    for (final item in raw) {
      if (item is List && item.length >= 6) {
        out.add(_TriviaQuestion.fromList(item));
      }
    }
    if (out.isEmpty) {
      for (final q in fallback) {
        out.add(_TriviaQuestion.fromList(q));
      }
    }
    return out;
  }

  int get _maxScore => _questions.length.clamp(1, widget.game.maxScore);

  void _answer(int i) {
    if (_answered || _submitting) return;
    setState(() {
      _answered = true;
      _selected = i;
      if (i == _questions[_index].correct) _score++;
    });
  }

  Future<void> _next() async {
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _answered = false;
        _selected = null;
      });
      return;
    }
    setState(() => _submitting = true);
    final result = await submitMatch(
      widget.game,
      score: _score,
      elapsedSeconds: _questions.length * 12,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _submitting = false;
      _result = result;
      _resultText = l10n.engineCorrect(_score, _questions.length);
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _answered = false;
      _selected = null;
      _resultText = null;
      _result = null;
      _questions.shuffle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final tint = engineColor(widget.game);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(widget.game.name),
        actions: [
          if (_resultText != null)
            IconButton(
              onPressed: _restart,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _resultText != null
          ? EngineResultPanel(
              emoji: widget.game.emoji,
              score: _score,
              maxScore: _maxScore,
              result: _result,
              title: _resultText,
              accentColor: tint,
              onReplay: _restart,
              onClose: () => Navigator.of(context).pop(),
            )
          : SafeArea(child: _questionView(colors, tint)),
    );
  }

  Widget _questionView(KlaykColors colors, Color tint) {
    final l10n = AppLocalizations.of(context)!;
    final q = _questions[_index];
    final progress = (_index / _questions.length).clamp(0.0, 1.0);
    return Column(
      children: [
        EngineHeader(
          title: '${widget.game.emoji} ${widget.game.name}',
          leftLabel: l10n.engineQuestionCounter(_index + 1, _questions.length),
          rightLabel: l10n.engineHits(_score),
          tint: tint,
        ),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: colors.surfaceAlt,
          color: tint,
          borderRadius: BorderRadius.circular(4),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  q.text,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: q.options.length,
                    itemBuilder: (context, i) {
                      final isCorrect = i == q.correct && _answered;
                      final isWrong =
                          _answered && i == _selected && i != q.correct;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: _answered && (isCorrect || isWrong)
                              ? (isCorrect
                                    ? colors.success.withValues(alpha: 0.18)
                                    : colors.danger.withValues(alpha: 0.18))
                              : colors.surface,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () => _answer(i),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _answered && (isCorrect || isWrong)
                                      ? (isCorrect
                                            ? colors.success
                                            : colors.danger)
                                      : colors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _answered
                                        ? (isCorrect
                                              ? Icons.check_circle_rounded
                                              : isWrong
                                              ? Icons.cancel_rounded
                                              : Icons.radio_button_unchecked)
                                        : Icons.radio_button_unchecked,
                                    size: 20,
                                    color: _answered && (isCorrect || isWrong)
                                        ? (isCorrect
                                              ? colors.success
                                              : colors.danger)
                                        : Colors.white38,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      q.options[i],
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
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
                          _index == _questions.length - 1
                              ? l10n.engineViewResult
                              : l10n.engineNextQuestion,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TriviaQuestion {
  final String text;
  final List<String> options;
  final int correct;

  const _TriviaQuestion({
    required this.text,
    required this.options,
    required this.correct,
  });

  factory _TriviaQuestion.fromList(List<dynamic> raw) {
    final answerIdx = (raw[5] as num?)?.toInt() ?? 0;
    return _TriviaQuestion(
      text: raw[0].toString(),
      options: [
        raw[1].toString(),
        raw[2].toString(),
        raw[3].toString(),
        raw[4].toString(),
      ],
      correct: answerIdx.clamp(0, 3),
    );
  }
}
