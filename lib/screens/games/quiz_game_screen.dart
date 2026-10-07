import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/game_service.dart';
import '../../theme/klayk_theme.dart';

/// Quiz KLAY K: 6 perguntas rápidas. Pontuação = acertos (0–6). Ao final,
/// abre sessão no backend e submete a pontuação (recompensa se melhorar o
/// recorde). Nunca há recompensa local — o servidor decide.
class QuizGameScreen extends StatefulWidget {
  const QuizGameScreen({super.key, this.gameOverride});

  final dynamic gameOverride;

  @override
  State<QuizGameScreen> createState() => _QuizGameScreenState();
}

class _QuizGameScreenState extends State<QuizGameScreen> {
  static const List<({String q, List<String> opts, int answer})> _questions = [
    (
      q: 'Qual é a capital do Brasil?',
      opts: ['Rio de Janeiro', 'Brasília', 'São Paulo', 'Salvador'],
      answer: 1,
    ),
    (
      q: 'Quantos estados tem o Brasil?',
      opts: ['25', '26', '27', '32'],
      answer: 2,
    ),
    (
      q: 'Quem pintou o "Monalisa"?',
      opts: ['Van Gogh', 'Picasso', 'Da Vinci', 'Michelangelo'],
      answer: 2,
    ),
    (
      q: 'Qual é o maior planeta do Sistema Solar?',
      opts: ['Terra', 'Júpiter', 'Saturno', 'Netuno'],
      answer: 1,
    ),
    (
      q: 'Qual animal é o símbolo da sabedoria?',
      opts: ['Leão', 'Gato', 'Coruja', 'Tigre'],
      answer: 2,
    ),
    (
      q: 'Quantos minutos tem 1h30?',
      opts: ['60', '80', '90', '120'],
      answer: 2,
    ),
  ];

  final _svc = GameService.instance;
  final _questionOrder = List.generate(_questions.length, (i) => i)
    ..shuffle(Random());
  int _index = 0;
  int _score = 0;
  bool _answered = false;
  int? _selected;
  bool _submitting = false;
  String? _resultMessage;

  int get _currentQ => _questionOrder[_index];

  void _answer(int i) {
    if (_answered || _submitting) return;
    setState(() {
      _answered = true;
      _selected = i;
      if (i == _questions[_currentQ].answer) _score++;
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
    // Partida terminou: submete ao backend.
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    try {
      final sessionId = await _svc.startSession('quiz');
      final result = await _svc.submitScore(
        sessionId: sessionId,
        score: _score,
        durationSeconds: _questions.length * 12,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _resultMessage =
            '${l10n.engineCorrect(_score, _questions.length)}\n'
            '${result.improved ? l10n.engineReward(result.reward) : l10n.engineRewardAlready}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _resultMessage =
            '${l10n.engineCorrect(_score, _questions.length)}\n'
            '${l10n.engineSyncFailed}';
      });
    }
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _answered = false;
      _selected = null;
      _resultMessage = null;
      _questionOrder
        ..clear()
        ..addAll(List.generate(_questions.length, (i) => i)..shuffle(Random()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(l10n.gameQuizTitle),
        actions: [
          if (_resultMessage != null)
            IconButton(
              onPressed: _restart,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _resultMessage != null
          ? _resultView(colors, l10n)
          : _questionView(colors, l10n),
    );
  }

  Widget _resultView(KlaykColors colors, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏁', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              _resultMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _restart,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: Text(l10n.enginePlayAgain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionView(KlaykColors colors, AppLocalizations l10n) {
    final q = _questions[_currentQ];
    final progress = (_index / _questions.length).clamp(0.0, 1.0);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text(
                  l10n.engineQuestionCounter(_index + 1, _questions.length),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  l10n.engineHits(_score),
                  style: const TextStyle(color: Color(0xFFB794FF)),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: colors.surfaceAlt,
            color: colors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    q.q,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: q.opts.length,
                      itemBuilder: (context, i) {
                        final isCorrect = i == q.answer && _answered;
                        final isWrong =
                            _answered && i == _selected && i != q.answer;
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
                                        q.opts[i],
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
                      backgroundColor: colors.primary,
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
      ),
    );
  }
}
