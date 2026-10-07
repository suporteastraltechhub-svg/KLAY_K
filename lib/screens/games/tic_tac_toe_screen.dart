import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/game_service.dart';
import '../../theme/klayk_theme.dart';

/// Jogo da Velha (3x3) x CPU. Pontuação: vitória = 10, empate = 2, derrota = 0
/// (max_score=10 no backend). Ao terminar, submete na sessão via RPC
/// `game_submit_score` — recompensa em cristais decidida no servidor.
class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  final _svc = GameService.instance;
  List<String> _board = List.filled(9, '');
  bool _playerTurn = true;
  bool _busy = false;
  bool _gameOver = false;
  bool _submitting = false;
  String? _result;
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
    if (_busy || _gameOver || _board[index] != '' || !_playerTurn) return;
    setState(() {
      _board[index] = 'X';
      _playerTurn = false;
      _startedMs = DateTime.now().millisecondsSinceEpoch;
      _checkAfterMove();
    });
  }

  void _checkAfterMove() {
    final winner = _checkWinner();
    if (winner != null || !_board.contains('')) {
      _finish(winner);
      return;
    }
    Timer(const Duration(milliseconds: 450), _cpuMove);
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
        _findWinningMove('X') ?? (_board[4] == '' ? 4 : _findCorner(empty));

    setState(() {
      _board[pick as int] = 'O';
      _playerTurn = true;
      _checkAfterMove();
    });
  }

  /// Retorna índice que completa linha com `mark` (=vence/bloqueia).
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
    // Sem cantos livres: busca primeira borda, depois qualquer.
    const edges = [1, 3, 5, 7];
    for (final e in edges) {
      if (empty.contains(e)) return e;
    }
    return empty.first;
  }

  Future<void> _finish(String? winner) async {
    final l10n = AppLocalizations.of(context)!;
    final elapsed =
        (DateTime.now().millisecondsSinceEpoch - _startedMs) ~/ 1000;
    final score = winner == 'X'
        ? 10
        : winner == 'O'
        ? 0
        : 2;
    setState(() {
      _gameOver = true;
      _submitting = true;
      _result = winner == 'X'
          ? l10n.gameYouWon
          : winner == 'O'
          ? l10n.gameKlkWon
          : l10n.gameDraw;
    });
    try {
      final sessionId = await _svc.startSession('velha');
      final r = await _svc.submitScore(
        sessionId: sessionId,
        score: score,
        durationSeconds: elapsed > 0 ? elapsed : 20,
      );
      if (mounted) {
        setState(() {
          _result = winner == 'X'
              ? '${l10n.gameYouWon}${r.improved ? '\n+${r.reward} 🔮 cristais!' : ''}'
              : winner == 'O'
              ? l10n.gameKlkWon
              : l10n.gameDraw;
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    setState(() {
      _board = List.filled(9, '');
      _playerTurn = true;
      _busy = false;
      _gameOver = false;
      _result = null;
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(l10n.gameVelhaTitle)),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              _result ?? (_gameOver ? '' : l10n.gameYouPlayX),
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB28DFF),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
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
                            color: value.isEmpty
                                ? const Color(0xFF1E1B2E)
                                : value == 'X'
                                ? const Color(0xFF8A2BE2)
                                : const Color(0xFFFF4D6A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2BE2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
