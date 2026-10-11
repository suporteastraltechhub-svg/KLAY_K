import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/game_service.dart';
import 'arcade_base.dart';

// ============================================================================
// 1. SLOT KLAY K
// ============================================================================

/// Caça-níquel arcade de 3 rolos com símbolos próprios do KLAY K.
/// Sem aposta e sem custo por giro: o jogador só toca em GIRAR e as combinações
/// rendem pontos virtuais.
class SlotEngineScreen extends ArcadeGameBase {
  const SlotEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _SlotEngineState();
}

class _SlotEngineState extends ArcadeGameStateBase {
  static const int _reelCount = 3;

  late List<int> _reels;
  int _stopped = 0;

  @override
  String get resultEmoji => '🎰';

  @override
  String? get resultSubtitle =>
      _stopped == _reelCount ? 'Rodada completa' : 'Partida encerrada';

  @override
  void buildRound() {
    final rnd = math.Random();
    _reels = List<int>.generate(
      _reelCount,
      (_) => rnd.nextInt(KlaykArcadeTheme.slotSymbols.length),
    );
    _stopped = 0;
    startRound();
  }

  /// Pagamento por nº de símbolos iguais: 3 → 40, 4 → 120, 5 → 400, 6+ → 1000.
  /// [match] é quantos rolos pararam no mesmo símbolo.
  static int payout(int match) {
    const table = <int>[40, 120, 400, 1000];
    return match >= 3 ? table[match - 3] : 0;
  }

  void _spin() {
    if (finished || _stopped < _reelCount) return;
    final rnd = math.Random();
    setState(() {
      _stopped = 0;
    });

    // Cada rolo para em instantes diferentes → sensação de giro único.
    for (var i = 0; i < _reelCount; i++) {
      final spins = 6 + rnd.nextInt(4);
      Timer(Duration(milliseconds: 90 * (i + 1)), () {
        if (!mounted) return;
        setState(() {
          _reels[i] = rnd.nextInt(KlaykArcadeTheme.slotSymbols.length);
        });
        _tickReel(i, spins, rnd);
      });
    }
  }

  void _tickReel(int index, int remaining, math.Random rnd) {
    if (!mounted) return;
    if (remaining <= 0) {
      setState(() => _stopped++);
      if (_stopped == _reelCount) _settle();
      return;
    }
    Timer(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      setState(() {
        _reels[index] = rnd.nextInt(KlaykArcadeTheme.slotSymbols.length);
      });
      _tickReel(index, remaining - 1, rnd);
    });
  }

  /// Calcula a combinação quando todos os rolos param.
  void _settle() {
    final counts = <int, int>{};
    for (final r in _reels) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    var best = 0;
    for (final c in counts.values) {
      if (c > best) best = c;
    }
    final gain = payout(best);
    if (gain <= 0) return;
    addScore(gain);
    setState(() => xpEarned += gain);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$best iguais  +$gain pontos'),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget buildGameBody(BuildContext context) {
    final spinning = _stopped < _reelCount;
    return Column(
      children: <Widget>[
        buildStats(context),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(_reelCount, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 78,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: spinning
                        ? KlaykArcadeTheme.purple
                        : KlaykArcadeTheme.purple.withValues(alpha: 0.35),
                    width: spinning ? 2 : 1,
                  ),
                ),
                child: Text(
                  KlaykArcadeTheme.slotSymbols[_reels[i]],
                  style: const TextStyle(fontSize: 34),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        ArcadePlayButton(
          label: spinning ? 'GIRANDO...' : 'GIRAR',
          icon: Icons.casino_rounded,
          busy: spinning,
          onPressed: spinning || finished ? () {} : _spin,
        ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }
}

// ============================================================================
// 2. RODA KLAY K
// ============================================================================

/// Roda giratória com 8 segmentos de recompensa **virtual**. Sem compra de
/// giros e sem qualquer valor financeiro: o segmento só vira pontuação/XP.
class WheelEngineScreen extends ArcadeGameBase {
  const WheelEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _WheelEngineState();
}

class _WheelEngineState extends ArcadeGameStateBase {
  static const int _segments = 8;

  /// Rótulo e pontos de cada segmento (todos virtuais).
  static const List<(String, int)> table = <(String, int)>[
    ('+10 XP', 10),
    ('+25 pts', 25),
    ('BÔNUS ×2', 50),
    ('+5 XP', 5),
    ('+40 pts', 40),
    ('ITEM ✨', 30),
    ('+15 pts', 15),
    ('×3 pts', 90),
  ];

  double _angle = 0;
  Timer? _ticker;
  bool _spinning = false;
  int _picked = -1;

  @override
  String get resultEmoji => '🎡';

  @override
  String? get resultSubtitle => _picked < 0 ? null : table[_picked].$1;

  @override
  void buildRound() {
    _picked = -1;
    _spinning = false;
    startRound();
  }

  void _spin() {
    if (_spinning || finished) return;
    final rnd = math.Random();
    setState(() {
      _spinning = true;
      _picked = rnd.nextInt(_segments);
    });
    final turns = 4 + rnd.nextInt(3);
    const slice = 360 / _segments;
    // Mira o segmento sorteado sob o ponteiro fixo no topo.
    final target = turns * 360 + (360 - (_picked * slice + slice / 2));
    final from = _angle;
    var t = 0.0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) {
        _ticker?.cancel();
        return;
      }
      t += 0.016;
      final p = (t / 2.4).clamp(0.0, 1.0);
      setState(() => _angle = from + (target - from) * easeOutCubic(p));
      if (p < 1.0) return;
      _ticker?.cancel();
      _ticker = null;
      setState(() => _spinning = false);
      _applyPrize();
    });
  }

  void _applyPrize() {
    if (_picked < 0) return;
    final (label, points) = table[_picked];
    addScore(points);
    setState(() => xpEarned += points);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label  +$points pontos'),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Future<void> endRound() async {
    _ticker?.cancel();
    _ticker = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
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
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 230,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Transform.rotate(
                angle: _angle * math.pi / 180,
                child: const CustomPaint(
                  size: Size(210, 210),
                  painter: _WheelPainter(_segments),
                ),
              ),
              const Positioned(
                top: 0,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: KlaykArcadeTheme.neon,
                  size: 30,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: KlaykArcadeTheme.ink,
                  shape: BoxShape.circle,
                ),
                child: const Text('🎡', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ArcadePlayButton(
          label: _spinning ? 'GIRANDO...' : 'GIRAR',
          icon: Icons.rotate_right_rounded,
          busy: _spinning,
          onPressed: _spinning || finished ? () {} : _spin,
        ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }
}

/// Desenha a roda com 8 fatias roxo/preto do KLAY K.
class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.segments);

  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final slice = 2 * math.pi / segments;

    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        rect,
        i * slice,
        slice,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = i.isEven
              ? KlaykArcadeTheme.purple
              : KlaykArcadeTheme.purpleDeep,
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = KlaykArcadeTheme.neon.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.segments != segments;
}

// ============================================================================
// 3. DADOS KLAY K
// ============================================================================

/// Desafio de dados: escolhe "ímpar" ou "par" e a pontuação virtual depende do
/// acerto e da soma. Não existe aposta — nada é descontado.
class DiceEngineScreen extends ArcadeGameBase {
  const DiceEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _DiceEngineState();
}

class _DiceEngineState extends ArcadeGameStateBase {
  int _a = 3;
  int _b = 3;
  Timer? _timer;
  bool _rolling = false;
  bool? _pickOdd;

  @override
  String get resultEmoji => '🎲';

  @override
  String get resultSubtitle => 'Soma final ${_a + _b}';

  @override
  void buildRound() {
    _a = 3;
    _b = 3;
    _rolling = false;
    _pickOdd = null;
    startRound();
  }

  int get _sum => _a + _b;

  void _roll() {
    if (_rolling || _pickOdd == null || finished) return;
    final rnd = math.Random();
    setState(() => _rolling = true);
    var ticks = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      ticks++;
      setState(() {
        _a = rnd.nextInt(6) + 1;
        _b = rnd.nextInt(6) + 1;
      });
      if (ticks < 14) return;
      _timer?.cancel();
      _timer = null;
      setState(() => _rolling = false);
      _settle();
    });
  }

  void _settle() {
    final isOdd = _sum.isOdd;
    final hit = (_pickOdd ?? isOdd) == isOdd;
    // Faixa da soma pesa mais que o acerto puro de paridade.
    final gain = hit ? 20 + _sum * 5 : 5;
    addScore(gain);
    setState(() => xpEarned += gain);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Soma $_sum (${isOdd ? 'ímpar' : 'par'})  +$gain'),
        duration: const Duration(milliseconds: 1300),
      ),
    );
  }

  @override
  Future<void> endRound() async {
    _timer?.cancel();
    _timer = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
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
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _die(_a, _rolling),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '+',
                style: TextStyle(
                  color: KlaykArcadeTheme.neon,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _die(_b, _rolling),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Soma: $_sum',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: _pick('ÍMPAR', _pickOdd == true, () {
                setState(() => _pickOdd = true);
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pick('PAR', _pickOdd == false, () {
                setState(() => _pickOdd = false);
              }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ArcadePlayButton(
          label: _rolling
              ? 'ROLANDO...'
              : (_pickOdd == null ? 'ESCOLHA UMA OPÇÃO' : 'ROLAR'),
          icon: Icons.casino_outlined,
          busy: _rolling,
          onPressed: (_rolling || _pickOdd == null || finished) ? () {} : _roll,
        ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }

  Widget _die(int value, bool rolling) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KlaykArcadeTheme.purple.withValues(alpha: rolling ? 0.45 : 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KlaykArcadeTheme.purple, width: 2),
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _pick(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: finished ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.white54,
        backgroundColor: selected
            ? KlaykArcadeTheme.purple.withValues(alpha: 0.35)
            : null,
        side: BorderSide(
          color: selected
              ? KlaykArcadeTheme.purple
              : KlaykArcadeTheme.purple.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

// ============================================================================
// 4. CARTAS KLAY K
// ============================================================================

/// Memória com cartas próprias do KLAY K. Combos de acertos seguidos valem
/// multiplicador na pontuação virtual.
class CardsEngineScreen extends ArcadeGameBase {
  const CardsEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _CardsEngineState();
}

class _CardsEngineState extends ArcadeGameStateBase {
  List<KlaykCard> _deck = <KlaykCard>[];
  final Set<int> _open = <int>{};
  final Set<int> _matched = <int>{};
  int _first = -1;
  Timer? _lock;
  int _combo = 0;

  @override
  String get resultEmoji => '🃏';

  @override
  String get resultSubtitle => 'Combo final x${_combo + 1}';

  @override
  void buildRound() {
    final pairs = (maxScore / 25).clamp(4, 10).toInt();
    _deck = shuffled(KlaykArcadeTheme.deck(pairs: pairs), math.Random());
    _open.clear();
    _matched.clear();
    _first = -1;
    _combo = 0;
    startRound();
  }

  void _tap(int index) {
    if (finished || _lock != null) return;
    if (_matched.contains(index) || _open.contains(index)) return;
    if (_first == -1) {
      setState(() {
        _first = index;
        _open.add(index);
      });
      return;
    }
    final a = _first;
    final b = index;
    setState(() => _open.add(b));
    _resolve(a, b);
  }

  void _resolve(int a, int b) {
    if (_deck[a] == _deck[b]) {
      final gain = _deck[a].points * (_combo + 1);
      setState(() {
        _matched.add(a);
        _matched.add(b);
        _open.remove(a);
        _open.remove(b);
        _first = -1;
        _combo++;
      });
      addScore(gain);
      setState(() => xpEarned += gain);
      if (_matched.length >= _deck.length) addScore(30);
      return;
    }
    setState(() => _combo = 0);
    _lock = Timer(const Duration(milliseconds: 700), () {
      _lock = null;
      if (!mounted) return;
      setState(() {
        _open.remove(a);
        _open.remove(b);
        _first = -1;
      });
    });
  }

  @override
  Future<void> endRound() async {
    _lock?.cancel();
    _lock = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ArcadeStatTile(label: 'Pontos', value: '$score', icon: Icons.stars),
            ArcadeStatTile(
              label: 'Combo',
              value: 'x${_combo + 1}',
              icon: Icons.bolt,
            ),
            ArcadeStatTile(
              label: 'Pares',
              value: '${_matched.length ~/ 2}/${_deck.length ~/ 2}',
              icon: Icons.grid_view_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _deck.length,
          itemBuilder: (context, i) => _tile(i),
        ),
        const SizedBox(height: 16),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }

  Widget _tile(int i) {
    final show = _open.contains(i) || _matched.contains(i);
    return GestureDetector(
      onTap: () => _tap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: show
              ? KlaykArcadeTheme.purple.withValues(alpha: 0.25)
              : KlaykArcadeTheme.purpleDeep.withValues(alpha: 0.55),
          border: Border.all(
            color: _matched.contains(i)
                ? Colors.white38
                : KlaykArcadeTheme.purple.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          show ? _deck[i].label : '🂠',
          style: const TextStyle(fontSize: 22, color: Colors.white),
        ),
      ),
    );
  }
}

// ============================================================================
// 5. MINES KLAY K
// ============================================================================

/// Grade com bombas **virtuais**. Casa segura soma pontos e o jogador pode
/// ENCERRAR a rodada para guardar o que já ganhou. Não existe aposta nem
/// perda de dinheiro: a pontuação começa em zero e só mede desempenho.
class MinesEngineScreen extends ArcadeGameBase {
  const MinesEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _MinesEngineState();
}

class _MinesEngineState extends ArcadeGameStateBase {
  static const int _size = 5;
  static const int _mineCount = 4;

  List<bool> _mine = <bool>[];
  List<bool> _open = <bool>[];
  List<bool> _flag = <bool>[];
  int _safeFound = 0;
  bool _hitMine = false;
  Timer? _blow;

  @override
  String get resultEmoji => '💣';

  @override
  String get resultTitle => _hitMine ? 'Bomba virtual!' : 'Pontos guardados';

  @override
  String get resultSubtitle => '$_safeFound casas seguras';

  @override
  void buildRound() {
    _mine = List<bool>.filled(_size * _size, false);
    final rnd = math.Random();
    for (var i = 0; i < _mineCount; i++) {
      _mine[rnd.nextInt(_size * _size)] = true;
    }
    _open = List<bool>.filled(_size * _size, false);
    _flag = List<bool>.filled(_size * _size, false);
    _safeFound = 0;
    _hitMine = false;
    startRound();
  }

  void _tap(int index) {
    if (finished || _open[index] || _hitMine) return;
    if (_mine[index]) {
      setState(() {
        _hitMine = true;
        _open[index] = true;
      });
      _blow?.cancel();
      _blow = Timer(const Duration(milliseconds: 500), () {
        if (mounted) endRound();
      });
      return;
    }
    // Cada casa segura rende mais que a anterior: combo natural de risco.
    final gain = 10 + _safeFound * 2;
    setState(() {
      _open[index] = true;
      _safeFound++;
    });
    addScore(gain);
    setState(() => xpEarned += gain);
  }

  void _toggleFlag(int index) {
    if (finished || _open[index] || _hitMine) return;
    setState(() => _flag[index] = !_flag[index]);
  }

  @override
  Future<void> endRound() async {
    _blow?.cancel();
    _blow = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ArcadeStatTile(label: 'Pontos', value: '$score', icon: Icons.stars),
            ArcadeStatTile(
              label: 'Seguras',
              value: '$_safeFound',
              icon: Icons.grid_view_rounded,
            ),
            ArcadeStatTile(label: 'XP', value: '$xpEarned', icon: Icons.bolt),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _size,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: _size * _size,
          itemBuilder: (context, i) => _tile(i),
        ),
        const SizedBox(height: 16),
        ArcadePlayButton(
          label: 'GUARDAR PONTOS',
          icon: Icons.save_rounded,
          onPressed: endRound,
        ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'REINICIAR',
          icon: Icons.refresh_rounded,
          onPressed: restart,
        ),
      ],
    );
  }

  Widget _tile(int i) {
    final opened = _open[i];
    final flagged = _flag[i];
    return GestureDetector(
      onTap: () => _tap(i),
      onLongPress: () => _toggleFlag(i),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: opened
              ? (flagged
                    ? KlaykArcadeTheme.purple.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.4))
              : KlaykArcadeTheme.purpleDeep.withValues(alpha: 0.5),
          border: Border.all(
            color: KlaykArcadeTheme.purple.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          opened ? (_mine[i] ? '💣' : '✨') : (flagged ? '🚩' : ''),
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

// ============================================================================
// 6. CRASH KLAY K
// ============================================================================

/// Multiplicador crescente. COLETAR registra a pontuação virtual da rodada; se
/// o jogador não coletar, perde **apenas** a pontuação daquela rodada. Nunca há
/// dinheiro, aposta ou saldo negativo.
class CrashEngineScreen extends ArcadeGameBase {
  const CrashEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _CrashEngineState();
}

class _CrashEngineState extends ArcadeGameStateBase {
  Timer? _timer;
  double _mult = 1.0;
  bool _live = false;
  String _phase = 'PRONTO';

  @override
  String get resultEmoji => '🚀';

  @override
  String get resultSubtitle => 'Estado final: $_phase';

  @override
  void buildRound() {
    _mult = 1.0;
    _live = false;
    _phase = 'PRONTO';
    startRound();
  }

  void _startRound() {
    if (_live || finished) return;
    final rnd = math.Random();
    // Onde a rodada "acaba": 1.6x a 6x, sempre virtual.
    final crashAt = 1.6 + rnd.nextDouble() * 4.4;
    setState(() {
      _live = true;
      _mult = 1.0;
      _phase = 'EM VOO';
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted || !_live) {
        _timer?.cancel();
        return;
      }
      final next = 1.0 + _mult * 0.02 + 0.012 * _mult * _mult;
      setState(() => _mult = next);
      if (_mult < crashAt) return;
      _timer?.cancel();
      _timer = null;
      // Não coletar zera só a pontuação desta rodada (o total da partida fica).
      setState(() {
        _live = false;
        _phase = 'FIM';
      });
    });
  }

  void _collect() {
    if (!_live || finished) return;
    final gain = (10 * _mult).round();
    _timer?.cancel();
    _timer = null;
    setState(() {
      _live = false;
      _phase = 'COLETADO';
    });
    addScore(gain);
    setState(() => xpEarned += gain);
  }

  @override
  Future<void> endRound() async {
    _timer?.cancel();
    _timer = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
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
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _live
                  ? KlaykArcadeTheme.purple
                  : KlaykArcadeTheme.purple.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: <Widget>[
              Text(
                _phase,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_mult.toStringAsFixed(2)}x',
                style: const TextStyle(
                  color: KlaykArcadeTheme.neon,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_live)
          ArcadePlayButton(
            label: 'COLETAR ${_mult.toStringAsFixed(2)}x',
            icon: Icons.savings_rounded,
            onPressed: _collect,
          )
        else
          ArcadePlayButton(
            label: 'INICIAR RODADA',
            icon: Icons.rocket_launch_rounded,
            onPressed: finished ? () {} : _startRound,
          ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }
}

// ============================================================================
// 7. BAÚ SURPRESA
// ============================================================================

/// Baú com animação de abertura e recompensa virtual sorteada. Não existe
/// compra de baú: o único recurso é o sistema de recompensas do app.
class ChestEngineScreen extends ArcadeGameBase {
  const ChestEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _ChestEngineState();
}

class _ChestEngineState extends ArcadeGameStateBase {
  /// (ícone, rótulo, pontos) — tudo virtual.
  static const List<(String, String, int)> prizes = <(String, String, int)>[
    ('✨', 'XP', 25),
    ('🟣', 'Créditos virtuais', 40),
    ('🔥', 'XP extra', 60),
    ('👑', 'Bônus KLAY K', 120),
    ('💎', 'Item cosmético', 90),
    ('⭐', 'Pequena recompensa', 15),
  ];

  Timer? _timer;
  bool _opening = false;
  bool _opened = false;
  String _prizeLabel = '';
  String _prizeIcon = '';

  @override
  String get resultEmoji => '🎁';

  @override
  String? get resultSubtitle => _opened ? _prizeLabel : null;

  @override
  void buildRound() {
    _opened = false;
    _opening = false;
    _prizeLabel = '';
    _prizeIcon = '';
    startRound();
  }

  void _open() {
    if (_opening || _opened || finished) return;
    setState(() => _opening = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 900), () {
      _timer = null;
      if (!mounted) return;
      final rnd = math.Random();
      final (icon, label, points) = prizes[rnd.nextInt(prizes.length)];
      setState(() {
        _opening = false;
        _opened = true;
        _prizeIcon = icon;
        _prizeLabel = label;
      });
      addScore(points);
      setState(() => xpEarned += points);
    });
  }

  @override
  Future<void> endRound() async {
    _timer?.cancel();
    _timer = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
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
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _opening || _opened || finished ? null : _open,
          child: AnimatedScale(
            scale: _opening ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 260),
            child: Container(
              width: 150,
              height: 150,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    KlaykArcadeTheme.purpleDeep,
                    KlaykArcadeTheme.purple,
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: KlaykArcadeTheme.purple.withValues(
                      alpha: _opened ? 0.5 : 0.2,
                    ),
                    blurRadius: _opened ? 22 : 8,
                  ),
                ],
              ),
              child: Text(
                _opened ? _prizeIcon : (_opening ? '✨' : '🎁'),
                style: const TextStyle(fontSize: 52),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_opened)
          Text(
            _prizeLabel,
            style: const TextStyle(
              color: KlaykArcadeTheme.neon,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          )
        else
          const Text(
            'Toque para abrir',
            style: TextStyle(color: Colors.white54),
          ),
        const SizedBox(height: 16),
        ArcadePlayButton(
          label: _opening
              ? 'ABRINDO...'
              : (_opened ? 'JÁ ABERTO' : 'ABRIR BAÚ'),
          icon: Icons.card_giftcard_rounded,
          busy: _opening,
          onPressed: _opening || _opened || finished ? () {} : _open,
        ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }
}

// ============================================================================
// 8. CARA OU COROA
// ============================================================================

/// Partida curtíssima: escolhe cara ou coroa, a moeda gira e o acerto rende
/// pontos virtuais.
class CoinEngineScreen extends ArcadeGameBase {
  const CoinEngineScreen({super.key, required super.game});

  @override
  State<ArcadeGameBase> createState() => _CoinEngineState();
}

class _CoinEngineState extends ArcadeGameStateBase {
  Timer? _timer;
  bool _spinning = false;
  bool? _pickHeads;
  bool _heads = true;

  @override
  String get resultEmoji => '🪙';

  @override
  String get resultSubtitle => 'Último resultado: ${_heads ? 'CARA' : 'COROA'}';

  @override
  void buildRound() {
    _pickHeads = null;
    _spinning = false;
    _heads = true;
    startRound();
  }

  void _flip() {
    if (_spinning || _pickHeads == null || finished) return;
    final rnd = math.Random();
    setState(() => _spinning = true);
    var ticks = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      ticks++;
      setState(() => _heads = rnd.nextBool());
      if (ticks < 16) return;
      _timer?.cancel();
      _timer = null;
      setState(() => _spinning = false);
      _settle();
    });
  }

  void _settle() {
    final hit = _pickHeads == _heads;
    final gain = hit ? 20 : 5;
    addScore(gain);
    setState(() => xpEarned += gain);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_heads ? 'CARA' : 'COROA'}  ${hit ? '+' : ''}$gain'),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  @override
  Future<void> endRound() async {
    _timer?.cancel();
    _timer = null;
    await super.endRound();
  }

  @override
  Widget buildGameBody(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
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
        ),
        const SizedBox(height: 18),
        AnimatedRotation(
          turns: _spinning ? 12 : 0,
          duration: const Duration(milliseconds: 900),
          child: Container(
            width: 120,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KlaykArcadeTheme.gold.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: KlaykArcadeTheme.gold, width: 2),
            ),
            child: Text(
              _heads ? '🟣' : '★',
              style: const TextStyle(fontSize: 40),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: _btn('CARA', _pickHeads == true, () {
                setState(() => _pickHeads = true);
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _btn('COROA', _pickHeads == false, () {
                setState(() => _pickHeads = false);
              }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ArcadePlayButton(
          label: _spinning
              ? 'GIRANDO...'
              : (_pickHeads == null ? 'ESCOLHA UM LADO' : 'GIRAR'),
          icon: Icons.flip_rounded,
          busy: _spinning,
          onPressed: (_spinning || _pickHeads == null || finished)
              ? () {}
              : _flip,
        ),
        const SizedBox(height: 8),
        ArcadePlayButton(
          label: 'ENCERRAR RODADA',
          icon: Icons.flag_rounded,
          onPressed: endRound,
        ),
      ],
    );
  }

  Widget _btn(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: finished ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.white54,
        backgroundColor: selected
            ? KlaykArcadeTheme.purple.withValues(alpha: 0.35)
            : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

/// Registro das engines arcade — consumido pelo `game_router.dart`.
typedef KlaykArcadeBuilder = Widget Function({required GameInfo game});

Map<String, KlaykArcadeBuilder> buildKlaykArcadeEngines() {
  return <String, KlaykArcadeBuilder>{
    'slot': SlotEngineScreen.new,
    'roda': WheelEngineScreen.new,
    'dados': DiceEngineScreen.new,
    'cartas_arcade': CardsEngineScreen.new,
    'mines': MinesEngineScreen.new,
    'crash': CrashEngineScreen.new,
    'bau': ChestEngineScreen.new,
    'moeda': CoinEngineScreen.new,
  };
}
