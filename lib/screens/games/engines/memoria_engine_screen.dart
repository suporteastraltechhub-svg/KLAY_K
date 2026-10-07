import 'dart:math';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// ENGINE MEMÓRIA — encontre os pares.
///
/// Configuração via `rules.engine_config`: `emojis` (pares de cartas),
/// `columns` (colunas do tabuleiro). As cartas são embaralhadas a cada partida.
/// Pontuação limitada a `max_score` (par = 1 ponto).
class MemoriaEngineScreen extends StatefulWidget {
  const MemoriaEngineScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<MemoriaEngineScreen> createState() => _MemoriaEngineScreenState();
}

class _MemoriaEngineScreenState extends State<MemoriaEngineScreen> {
  late List<String> _deck;
  late final List<String> _emojis;
  final Random _random = Random();

  int _flips = 0;
  int _pairs = 0;
  final List<int> _reveal = [];
  bool _locked = false;
  bool _won = false;
  GameSubmitResult? _result;

  List<bool> _matchedBase = [];

  @override
  void initState() {
    super.initState();
    final config = widget.game.engineConfig;
    final raw = config['emojis'] ?? config['pairs'];
    _emojis =
        (raw is List
              ? raw.map((e) => e.toString()).toList()
              : const ['🔥', '🦊', '🍕', '🌍', '💎', '🎵'])
          ..take(6).toList();
    _deck = _buildDeck();
  }

  int get _columns => cfgInt(widget.game, 'columns', 4).clamp(2, 6);

  List<String> _buildDeck() {
    final pool = <String>[..._emojis, ..._emojis]..shuffle(_random);
    _matchedBase = List<bool>.filled(pool.length, false);
    return pool;
  }

  int get _maxScore => _emojis.length;
  int get _score => _pairs.clamp(0, widget.game.maxScore);

  void _flip(int index) {
    if (_locked || _matchedBase[index] || _won) return;
    if (_reveal.contains(index)) return;
    if (_reveal.length >= 2) return;
    setState(() {
      _flips++;
      _reveal.add(index);
      if (_reveal.length < 2) return;
      _locked = true;
    });
    final matches = _deck[_reveal[0]] == _deck[_reveal[1]];
    Future.delayed(Duration(milliseconds: matches ? 220 : 650), () {
      if (!mounted) return;
      setState(() {
        if (matches) {
          _matchedBase[_reveal[0]] = true;
          _matchedBase[_reveal[1]] = true;
          _pairs++;
        }
        _reveal.clear();
        _locked = false;
      });
      if (matches && _pairs >= _maxScore) {
        setState(() => _won = true);
        _submit();
      }
    });
  }

  Future<void> _submit() async {
    final result = await submitMatch(
      widget.game,
      score: _score,
      elapsedSeconds: max(1, _flips ~/ 2),
    );
    if (!mounted) return;
    setState(() => _result = result);
  }

  void _restart() {
    setState(() {
      _flips = 0;
      _pairs = 0;
      _reveal.clear();
      _locked = false;
      _won = false;
      _result = null;
      _deck = _buildDeck();
    });
  }

  Widget _card(int index) {
    final colors = kcolors(context);
    final tint = engineColor(widget.game);
    final revealed = _reveal.contains(index);
    final done = _matchedBase[index];
    final show = done || revealed;
    return GestureDetector(
      onTap: () => _flip(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          gradient: show
              ? LinearGradient(colors: [tint.withValues(alpha: 0.9), tint])
              : const LinearGradient(
                  colors: [Color(0xFF262033), Color(0xFF1A1626)],
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (done ? colors.success : (revealed ? tint : colors.border))
                .withValues(alpha: 0.9),
            width: 1.2,
          ),
        ),
        child: Center(
          child: show
              ? Text(
                  _deck[index],
                  style: TextStyle(fontSize: _deck[index].length > 1 ? 18 : 26),
                )
              : const Icon(
                  Icons.help_outline_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
        ),
      ),
    );
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
              EngineHeader(
                title: '${widget.game.emoji} ${widget.game.name}',
                leftLabel: l10n.gamePairs(_score, _maxScore),
                rightLabel: _flips > 0
                    ? l10n.gameTries(_flips ~/ 2)
                    : l10n.gameTapACard,
                tint: tint,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _won
                    ? EngineResultPanel(
                        emoji: widget.game.emoji,
                        score: _score,
                        maxScore: _maxScore,
                        result: _result,
                        title: l10n.gameMemoriaCongrats(_score, _maxScore),
                        subtitle: l10n.gameTries(_flips ~/ 2),
                        accentColor: tint,
                        onReplay: _restart,
                        onClose: () => Navigator.of(context).pop(),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = _columns;
                          const gap = 8.0;
                          final size =
                              (constraints.maxWidth - gap * (columns - 1)) /
                              columns;
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Center(
                              child: SizedBox(
                                width: constraints.maxWidth,
                                child: Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (var i = 0; i < _deck.length; i++)
                                      SizedBox(
                                        width: size,
                                        height: size,
                                        child: _card(i),
                                      ),
                                  ],
                                ),
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
}
