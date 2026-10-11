import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE ESTRATÉGIA — 3 em linha contra a CPU.
///
/// Mesma mecânica do Jogo da Velha, mas 100% config-driven: vitória = pontos
/// de `max_score`, empate = 1. Tela ÚNICA para 'velha', 'estrela' e qualquer
/// futuro jogo 3 em linha (extensão = 1 linha no catálogo). Submissão via
/// `submitMatch` (backend decide a recompensa).
class EstrategiaEngineScreen extends StatefulWidget {
  const EstrategiaEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<EstrategiaEngineScreen> createState() => _EstrategiaEngineScreenState();
}

class _EstrategiaEngineScreenState extends State<EstrategiaEngineScreen> {
  /// Timer do movimento da CPU — cancelado em [dispose] para não
  /// disparar setState depois de a tela sair.
  Timer? _cpuTimer;
  List<String> _board = List.filled(9, '');
  bool _playerTurn = true;
  bool _gameOver = false;
  bool _submitting = false;
  String? _resultText;
  GameSubmitResult? _result;
  bool _won = false;
  int _startedMs = 0;

  static const List<List<int>> _lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  int get _winScore => widget.game.maxScore.clamp(1, 1 << 20);

  String? _checkWinner() {
    for (final line in _lines) {
      if (_board[line[0]] != '' &&
          _board[line[0]] == _board[line[1]] &&
          _board[line[1]] == _board[line[2]]) {
        return _board[line[0]];
      }
    }
    return null;
  }

  void _play(int index) {
    if (_gameOver || _board[index] != '' || !_playerTurn) return;
    setState(() {
      _board[index] = 'X';
      _playerTurn = false;
      if (_startedMs == 0) _startedMs = DateTime.now().millisecondsSinceEpoch;
      _checkAfterMove();
    });
  }

  void _checkAfterMove() {
    final winner = _checkWinner();
    if (winner != null || !_board.contains('')) {
      _finish(winner);
      return;
    }
    _cpuTimer?.cancel();
    _cpuTimer = Timer(const Duration(milliseconds: 420), _cpuMove);
  }

  @override
  void dispose() {
    _cpuTimer?.cancel();
    super.dispose();
  }

  void _cpuMove() {
    if (!mounted || _gameOver) return;
    final empty = <int>[
      for (int i = 0; i < 9; i++)
        if (_board[i] == '') i,
    ];
    if (empty.isEmpty) return;
    int? pick = _findWinningMove('O');
    pick ??=
        _findWinningMove('X') ?? ((_board[4] == '' ? 4 : _findCorner(empty)));
    setState(() {
      _board[pick as int] = 'O';
      _playerTurn = true;
      _checkAfterMove();
    });
  }

  int? _findWinningMove(String mark) {
    for (final line in _lines) {
      final cells = [for (final c in line) _board[c]];
      if (cells.where((c) => c == mark).length == 2 && cells.contains('')) {
        final idx = line[cells.indexOf('')];
        if (_board[idx] == '') return idx;
      }
    }
    return null;
  }

  int _findCorner(List<int> empty) {
    const corners = [0, 2, 6, 8];
    for (final c in corners) {
      if (empty.contains(c)) return c;
    }
    const edges = [1, 3, 5, 7];
    for (final e in edges) {
      if (empty.contains(e)) return e;
    }
    return empty.first;
  }

  Future<void> _finish(String? winner) async {
    final elapsed =
        ((DateTime.now().millisecondsSinceEpoch - _startedMs) ~/ 1000).clamp(
          1,
          1 << 20,
        );
    final playerWon = winner == 'X';
    final draw = winner == null;
    final score = playerWon ? _winScore : (draw ? 1 : 0);
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _gameOver = true;
      _submitting = true;
      _won = playerWon;
      _resultText = playerWon
          ? l10n.gameYouWon
          : (draw ? l10n.gameDraw : l10n.gameKlkWon);
    });
    final result = await submitMatch(
      widget.game,
      score: score,
      elapsedSeconds: elapsed,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = result;
    });
  }

  void _reset() {
    setState(() {
      _board = List.filled(9, '');
      _playerTurn = true;
      _gameOver = false;
      _submitting = false;
      _resultText = null;
      _result = null;
      _won = false;
      _startedMs = 0;
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
        child: Column(
          children: [
            EngineHeader(
              title: '${widget.game.emoji} ${widget.game.name}',
              leftLabel: l10n.gameYouPlayX,
              rightLabel: _resultText ?? l10n.gameCpuO,
              tint: tint,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _gameOver && _resultText != null
                  ? EngineResultPanel(
                      emoji: _won ? '🏆' : (winnerIsCpu() ? '🤖' : '🤝'),
                      score: _won ? _winScore : 0,
                      maxScore: _winScore,
                      result: _result,
                      title: _resultText,
                      accentColor: tint,
                      onReplay: _reset,
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                          itemCount: 9,
                          itemBuilder: (context, index) {
                            final value = _board[index];
                            return GestureDetector(
                              onTap: () => _play(index),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: value.isEmpty
                                      ? LinearGradient(
                                          colors: [
                                            colors.surface,
                                            colors.surfaceAlt,
                                          ],
                                        )
                                      : LinearGradient(
                                          colors: value == 'X'
                                              ? [
                                                  tint.withValues(alpha: 0.9),
                                                  tint,
                                                ]
                                              : [
                                                  const Color(0xFFE4183C),
                                                  const Color(0xFFB3243C),
                                                ],
                                        ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: value.isNotEmpty
                                      ? [
                                          BoxShadow(
                                            color:
                                                (value == 'X'
                                                        ? tint
                                                        : const Color(
                                                            0xFFE4183C,
                                                          ))
                                                    .withValues(alpha: 0.35),
                                            blurRadius: 12,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: value.isEmpty
                                    ? null
                                    : Text(
                                        value,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 38,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton.icon(
                onPressed: _submitting ? null : _reset,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(l10n.gameRestart),
                style: FilledButton.styleFrom(
                  backgroundColor: tint,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool winnerIsCpu() {
    final w = _checkWinner();
    return w == 'O';
  }
}
