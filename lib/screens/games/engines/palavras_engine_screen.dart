import 'dart:math';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE PALAVRAS — desembaralhe ou descubra pela dica.
///
/// Configuração via `rules.engine_config`:
///  * `mode`: 'unscramble' (embaralha a palavra) ou 'definition' (dá uma dica);
///  * `rounds`: quantas rodadas;
///  * `words`: para 'unscramble', lista de strings; para 'definition', lista de
///    `[dica, palavraCorreta, distrator1, distrator2, ...]`.
///
/// Acerto = 1 ponto, limitado a `max_score` no submit.
class PalavrasEngineScreen extends StatefulWidget {
  const PalavrasEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<PalavrasEngineScreen> createState() => _PalavrasEngineScreenState();
}

class _PalavrasEngineScreenState extends State<PalavrasEngineScreen> {
  late final String _mode =
      (widget.game.engineConfig['mode'] as String?) ?? 'unscramble';
  late final int _rounds = cfgInt(widget.game, 'rounds', 8).clamp(3, 20);
  late final List<_WordEntry> _entries = _parseWords();
  final Random _random = Random();

  int _index = 0;
  int _score = 0;
  bool _answered = false;
  int? _selected;
  String _hint = '';
  List<String> _options = const [];
  GameSubmitResult? _result;
  bool _submitting = false;

  int get _maxScore => _rounds.clamp(1, widget.game.maxScore.clamp(1, 1 << 20));

  List<_WordEntry> _parseWords() {
    final raw = widget.game.engineConfig['words'];
    if (raw is! List || raw.isEmpty) {
      return [
        for (final w in const ['JOGO', 'LIVE', 'KLAY', 'MÚSICA'])
          _WordEntry(word: w),
      ];
    }
    final out = <_WordEntry>[];
    if (_mode == 'definition') {
      for (final item in raw) {
        if (item is List && item.isNotEmpty) {
          final opts = item
              .sublist(1)
              .whereType<String>()
              .map((e) => e.toUpperCase())
              .toList();
          out.add(
            _WordEntry(
              word: opts.isNotEmpty
                  ? opts.first
                  : item[1].toString().toUpperCase(),
              definition: item[0].toString(),
              distractors: opts.skip(1).toList(),
            ),
          );
        }
      }
    } else {
      for (final item in raw) {
        if (item is String) out.add(_WordEntry(word: item.toUpperCase()));
      }
    }
    if (out.isEmpty) {
      out.add(const _WordEntry(word: 'KLAY'));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _prepareRound();
  }

  void _prepareRound() {
    final entry = _entries[_index % _entries.length];
    final distractors = <String>{
      for (final e in _entries)
        if (e.word != entry.word) e.word,
    }.take(3).toList();
    final options = <String>{entry.word, ...distractors}.toList();
    while (options.length < 4 && _entries.length > 1) {
      options.add(options[_random.nextInt(options.length)]);
    }
    options.shuffle(_random);
    _hint = _mode == 'definition'
        ? entry.definition ?? entry.word
        : _scramble(entry.word);
    _options = options;
    _answered = false;
    _selected = null;
  }

  String _scramble(String word) {
    final letters = word.split('')..shuffle(_random);
    return letters.join('');
  }

  bool get _currentIsDefinition => _mode == 'definition';

  void _answer(int i) {
    if (_answered || _submitting) return;
    final target = _entries[_index % _entries.length].word;
    setState(() {
      _answered = true;
      _selected = i;
      if (_options[i] == target) _score++;
    });
  }

  Future<void> _next() async {
    if (_index < _rounds - 1) {
      setState(() {
        _index++;
        _prepareRound();
      });
      return;
    }
    setState(() => _submitting = true);
    final result = await submitMatch(
      widget.game,
      score: _score,
      elapsedSeconds: _rounds * 12,
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
      _submitting = false;
      _result = null;
    });
    _prepareRound();
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
                title: l10n.engineWordsCorrect(_score, _maxScore),
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
                      leftLabel: l10n.engineRoundCounter(_index + 1, _rounds),
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
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 120),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            tint.withValues(alpha: 0.18),
                            colors.surface,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: tint.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!_currentIsDefinition)
                            Text(
                              l10n.gameScrambled,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white54,
                                letterSpacing: 1.2,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            // hint embaralhada em mono espaçado ou dica
                            _currentIsDefinition
                                ? _hint
                                : _hint.split('').join(' '),
                            textAlign: TextAlign.center,
                            style: _currentIsDefinition
                                ? const TextStyle(fontSize: 20, height: 1.4)
                                : TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: tint,
                                    letterSpacing: 3,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _options.length,
                        itemBuilder: (context, i) {
                          final target =
                              _entries[_index % _entries.length].word;
                          final opt = _options[i];
                          final isCorrect = _answered && opt == target;
                          final isWrong =
                              _answered && i == _selected && opt != target;
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
                                    vertical: 15,
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
                                    opt,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
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
                                    ? l10n.engineNextRound
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

class _WordEntry {
  final String word;
  final String? definition;
  final List<String> distractors;

  const _WordEntry({
    required this.word,
    this.definition,
    this.distractors = const [],
  });
}
