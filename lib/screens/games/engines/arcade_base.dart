import 'dart:async';
import 'dart:math' as math;
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';
import 'engine_common.dart';

/// Arquitetura compartilhada dos minijogos arcade do KLAY K.
///
/// Todos os jogos aqui são **recreativos**: pontuação, XP e recompensas
/// virtuais internas. Não existe aposta, depósito, saque, compra de jogada,
/// PIX ou qualquer conversão para dinheiro — o único valor tocado é a pontuação
/// do jogo, e o XP é o mesmo sistema de níveis já usado pelo resto do app.
///
/// O que a base resolve para todos:
///  * cronômetro de partida + estado de carregamento e de fim de partida;
///  * botão JOGAR/RESTART e encerra properly todos os timers e controllers;
///  * envio da pontuação pelo MESMO caminho das engines antigas
///    ([submitMatch] → `game_submit_score`), que é quem credita XP/recompensa
///    no backend. Nenhum sistema de recompensa duplicado.
abstract class ArcadeGameBase extends StatefulWidget {
  const ArcadeGameBase({super.key, required this.game});

  final GameInfo game;

  @override
  State<ArcadeGameBase> createState();
}

/// Estado base com as peças que todo minijogo precisa.
abstract class ArcadeGameStateBase extends State<ArcadeGameBase> {
  /// Pontuação da partida atual (sempre virtual).
  int score = 0;

  /// Pontos de XP/virtual acumulados na partida (exibidos, nunca "comprados").
  int xpEarned = 0;

  bool loading = true;
  bool running = false;
  bool finished = false;
  GameSubmitResult? result;
  DateTime? _startedAt;
  Timer? _ticker;
  Duration elapsed = Duration.zero;

  int get maxScore => widget.game.maxScore;

  /// Emoji mostrado no painel de resultado.

  /// Título padrão do painel de resultado.

  @override
  void initState() {
    super.initState();
    // "Carregando" curto: só o tempo de um frame para o predicado inicial e
    // a configuração virem do GameInfo. Nada de rede aqui.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => loading = false);
      buildRound();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  /// Monta/prepara a próxima rodada. Chamado ao abrir a tela e a cada restart.
  void buildRound();

  /// Começa o cronômetro da rodada.
  void startRound() {
    _ticker?.cancel();
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = _startedAt;
      if (s == null) return;
      setState(() => elapsed = DateTime.now().difference(s));
      onTick();
    });
    if (!running) setState(() => running = true);
    onRoundStart();
  }

  /// Gancho por segundo durante a partida.
  void onTick() {}

  /// Gancho no início da rodada (depois de `running = true`).
  void onRoundStart() {}

  /// Encerra a rodada e envia a pontuação pelo sistema existente.
  Future<void> endRound() async {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted || finished) return;
    setState(() => finished = true);
    final r = await submitMatch(
      widget.game,
      score: score,
      elapsedSeconds: max(1, elapsed.inSeconds),
    );
    if (!mounted) return;
    setState(() => result = r);
  }

  /// Reinicia do zero.
  void restart() {
    setState(() {
      score = 0;
      xpEarned = 0;
      finished = false;
      running = false;
      result = null;
      elapsed = Duration.zero;
    });
    buildRound();
  }

  /// Soma pontos respeitando o teto do jogo.
  void addScore(int points) {
    if (finished) return;
    final next = (score + points).clamp(0, maxScore);
    if (next != score) setState(() => score = next);
  }

  /// Texto do lado esquerdo do cabeçalho (resumo da partida).
  String get headerLeft => 'Pontos $score / $maxScore';

  /// Texto do lado direito do cabeçalho (tempo/XP).
  String get headerRight =>
      'XP $xpEarned · ${elapsed.inSeconds}s';

  /// Emoji do painel de resultado.
  String get resultEmoji;

  /// Título do painel de resultado.
  String get resultTitle => 'Fim da rodada';

  /// Subtítulo do painel de resultado.
  String? get resultSubtitle => null;

  /// Conteúdo específico do jogo (a base já fornece cabeçalho e resultado).
  Widget buildGameBody(BuildContext context);

  /// Linha de estatísticas padrão. Jogos podem substituir.
  Widget buildStats(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        ArcadeStatTile(label: 'Pontos', value: '$score', icon: Icons.stars),
        ArcadeStatTile(label: 'XP', value: '$xpEarned', icon: Icons.bolt),
        ArcadeStatTile(
          label: 'Tempo',
          value: '${elapsed.inSeconds}s',
          icon: Icons.timer_outlined,
        ),
      ],
    );
  }

  /// Shell comum a todos os minijogos: AppBar, cabeçalho, corpo e painel de
  /// resultado. Evita repetir a mesma árvore oito vezes.
  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final tint = engineColor(widget.game);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(widget.game.name)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              EngineHeader(
                title: '${widget.game.emoji} ${widget.game.name}',
                leftLabel: headerLeft,
                rightLabel: headerRight,
                tint: tint,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : finished
                    ? EngineResultPanel(
                        emoji: resultEmoji,
                        score: score,
                        maxScore: maxScore,
                        result: result,
                        title: resultTitle,
                        subtitle: resultSubtitle,
                        accentColor: tint,
                        onReplay: restart,
                        onClose: () => Navigator.of(context).pop(),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: buildGameBody(context),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cores e símbolos próprios do KLAY K usados nos rolos, cartas e grade.
class KlaykArcadeTheme {
  const KlaykArcadeTheme._();

  static const Color purple = Color(0xFFA855F7);
  static const Color purpleDeep = Color(0xFF6D28D9);
  static const Color neon = Color(0xFFE9D5FF);
  static const Color ink = Color(0xFF0D0D14);
  static const Color gold = Color(0xFFFFD700);

  /// Símbolos dos rolos. Criados para o KLAY K — nada copiado de cassino.
  static const List<String> slotSymbols = <String>[
    '🟣',
    '⭐',
    '💎',
    '🔥',
    '🌀',
    '🎯',
    '👑',
    '🌙',
  ];

  /// Valor em pontos de cada símbolo (índice = posição em [slotSymbols]).
  static const List<int> slotValues = <int>[3, 5, 8, 10, 12, 15, 25, 40];

  /// Cartas do Jogo de Cartas — figuras e naipes próprios.
  static const List<String> cardFaces = <String>[
    '🟣',
    '⭐',
    '💎',
    '🔥',
    '🌀',
    '🎯',
    '👑',
    '🌙',
  ];

  static const List<String> cardSuits = <String>['◆', '●', '▲', '■'];

  /// Cartas decoradas: figura + naipe + pontos.
  static List<KlaykCard> deck({int pairs = 6}) {
    final out = <KlaykCard>[];
    var i = 0;
    while (out.length < pairs * 2 && i < cardFaces.length * cardSuits.length) {
      final face = cardFaces[i % cardFaces.length];
      final suit = cardSuits[(i ~/ cardFaces.length) % cardSuits.length];
      final points = 5 * (i % 8 + 1);
      out.add(KlaykCard(face: face, suit: suit, points: points));
      out.add(KlaykCard(face: face, suit: suit, points: points));
      i++;
    }
    return out;
  }
}

/// Uma carta do Jogo de Cartas do KLAY K.
class KlaykCard {
  const KlaykCard({
    required this.face,
    required this.suit,
    required this.points,
  });

  final String face;
  final String suit;
  final int points;

  String get label => '$face$suit';

  @override
  bool operator ==(Object other) =>
      other is KlaykCard && other.face == face && other.suit == suit;

  @override
  int get hashCode => Object.hash(face, suit);
}

/// Botão JOGAR / REINICIAR no estilo do app.
class ArcadePlayButton extends StatelessWidget {
  const ArcadePlayButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.play_arrow_rounded,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: Icon(busy ? Icons.hourglass_empty_rounded : icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: KlaykArcadeTheme.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Cartão de estatística usado nos minijogos (pontos, XP, rodada).
class ArcadeStatTile extends StatelessWidget {
  const ArcadeStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KlaykArcadeTheme.purple.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: KlaykArcadeTheme.purple),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sorteio justo a partir de um [Random] injetável — permite testar mecânica
/// sem depender de `Random()` global.
T pickWeighted<T>(Random rnd, List<T> items) {
  return items[rnd.nextInt(items.length)];
}

/// Embaralhamento Fisher-Yates (determinístico com a semente fornecida).
List<T> shuffled<T>(List<T> input, Random rnd) {
  final out = List<T>.of(input);
  for (var i = out.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/// Curva suave usada nos multiplicadores e rodas (subida e queda).
double easeOutCubic(double t) {
  final x = t.clamp(0.0, 1.0);
  return 1 - math.pow(1 - x, 3).toDouble();
}
