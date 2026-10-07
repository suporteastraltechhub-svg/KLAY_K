import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 1. MODELO DE DADOS DOS PRESENTES (GIFT MODEL)
enum GiftCurrency { gold, diamond }

enum GiftCategory { baratos, gamer, animacoes, veiculos, miticos }

class GiftItem {
  final String id;
  final String name;
  final int price;
  final GiftCurrency currency;
  final GiftCategory category;
  final String emoji; // Emoji nativo usado na loja e na animação de tela cheia.
  final GiftAnimStyle animStyle; // Estilo da animação nativa na live.

  const GiftItem({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.category,
    required this.emoji,
    this.animStyle = GiftAnimStyle.emojiRain,
  });
}

/// Estilo de animação de tela cheia (100% nativa, sem assets).
enum GiftAnimStyle {
  emojiRain, // chuva de emojis subindo
  vehicle, // retângulo neon cruzando a tela com rastro
  cinematic, // flash + zoom gigante no centro (ex.: Titanic)
}

GiftAnimStyle _styleForId(String id) {
  if (id == 'titanic_lendario') return GiftAnimStyle.cinematic;
  if (id == 'heli_executivo' ||
      id == 'tanque_guerra' ||
      id == 'jato_supersonico' ||
      id == 'iate_monaco' ||
      id == 'carro_luxo' ||
      id == 'moto_ninja') {
    return GiftAnimStyle.vehicle;
  }
  return GiftAnimStyle.emojiRain;
}

/// Moeda + ícone da moeda.
const Color kGold = Color(0xFFFFD700);
const Color kDiamond = Color(0xFF4FC3F7);
const Color kCyan = Color(0xFF00E5FF);

String currencyLabel(GiftCurrency c) =>
    c == GiftCurrency.gold ? 'Ouro' : 'Diamante';

(Color, String) currencyStyle(GiftCurrency c) =>
    c == GiftCurrency.gold ? (kGold, '🪙') : (kDiamond, '💎');

/// 2. BANCO DE DADOS LOCAL - LISTA MASSIVA DE PRESENTES DO KLAY K
const List<GiftItem> klayKGifts = [
  // === CATEGORIA: BARATOS (Ouro) ===
  GiftItem(
    id: 'cafe_quente',
    name: 'Café Quente',
    price: 5,
    currency: GiftCurrency.gold,
    category: GiftCategory.baratos,
    emoji: '☕',
  ),
  GiftItem(
    id: 'estrela_cadente',
    name: 'Estrela Cadente',
    price: 10,
    currency: GiftCurrency.gold,
    category: GiftCategory.baratos,
    emoji: '🌠',
  ),
  GiftItem(
    id: 'rosa_fogo',
    name: 'Rosa de Fogo',
    price: 15,
    currency: GiftCurrency.gold,
    category: GiftCategory.baratos,
    emoji: '🌹',
  ),

  // === CATEGORIA: GAMER ===
  GiftItem(
    id: 'controle_neon',
    name: 'Controle Neon',
    price: 20,
    currency: GiftCurrency.gold,
    category: GiftCategory.gamer,
    emoji: '🎮',
  ),
  GiftItem(
    id: 'headset_rgb',
    name: 'Headset RGB',
    price: 150,
    currency: GiftCurrency.gold,
    category: GiftCategory.gamer,
    emoji: '🎧',
  ),
  GiftItem(
    id: 'placa_video',
    name: 'Placa de Vídeo',
    price: 2000,
    currency: GiftCurrency.gold,
    category: GiftCategory.gamer,
    emoji: '🖥️',
  ),
  GiftItem(
    id: 'pc_gamer_ultimate',
    name: 'PC Gamer Ultimate',
    price: 500,
    currency: GiftCurrency.diamond,
    category: GiftCategory.gamer,
    emoji: '🖥️',
  ),

  // === CATEGORIA: ANIMAÇÕES & PARÓDIAS DE DESENHOS ===
  GiftItem(
    id: 'cao_detetive',
    name: 'Cão Detetive',
    price: 250,
    currency: GiftCurrency.gold,
    category: GiftCategory.animacoes,
    emoji: '🐶',
  ),
  GiftItem(
    id: 'gato_rato',
    name: 'Rivalidade Eterna',
    price: 180,
    currency: GiftCurrency.gold,
    category: GiftCategory.animacoes,
    emoji: '🐱',
  ),
  GiftItem(
    id: 'passaro_maluco',
    name: 'Pássaro Maluco',
    price: 300,
    currency: GiftCurrency.gold,
    category: GiftCategory.animacoes,
    emoji: '🐦',
  ),
  GiftItem(
    id: 'corrida_ninja',
    name: 'Estilo Ninja',
    price: 1500,
    currency: GiftCurrency.gold,
    category: GiftCategory.animacoes,
    emoji: '🥷',
  ),
  GiftItem(
    id: 'liga_jovem',
    name: 'Torre dos Jovens',
    price: 50,
    currency: GiftCurrency.diamond,
    category: GiftCategory.animacoes,
    emoji: '🏙️',
  ),
  GiftItem(
    id: 'raio_energy',
    name: 'Kame-Ataque',
    price: 150,
    currency: GiftCurrency.diamond,
    category: GiftCategory.animacoes,
    emoji: '⚡',
  ),

  // === CATEGORIA: SUPER MÁQUINAS & VEÍCULOS (Diamante) ===
  GiftItem(
    id: 'bike_premium',
    name: 'Bike de Carbono',
    price: 100,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '🚲',
  ),
  GiftItem(
    id: 'moto_ninja',
    name: 'Super Moto Ninja',
    price: 300,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '🏍️',
  ),
  GiftItem(
    id: 'carro_luxo',
    name: 'Superesportivo',
    price: 1000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '🏎️',
  ),
  GiftItem(
    id: 'heli_executivo',
    name: 'Helicóptero Black',
    price: 2500,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '🚁',
  ),
  GiftItem(
    id: 'tanque_guerra',
    name: 'Blindado de Elite',
    price: 5000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '🛡️',
  ),
  GiftItem(
    id: 'jato_supersonico',
    name: 'Caça Supersônico',
    price: 8000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '✈️',
  ),
  GiftItem(
    id: 'iate_monaco',
    name: 'Iate Real Mônaco',
    price: 12000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.veiculos,
    emoji: '🛥️',
  ),

  // === CATEGORIA: MÍTICOS / ULTRA-RAROS ⇒ Automático style cinematic p/ Titanic
  GiftItem(
    id: 'tita_ouro',
    name: 'O Titã de Ouro',
    price: 20000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.miticos,
    emoji: '🏆',
  ),
  GiftItem(
    id: 'reino_ninja',
    name: 'Raposa Ancestral',
    price: 35000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.miticos,
    emoji: '🦊',
  ),
  GiftItem(
    id: 'titanic_lendario',
    name: 'O Lendário Titanic',
    price: 100000,
    currency: GiftCurrency.diamond,
    category: GiftCategory.miticos,
    emoji: '🚢',
    animStyle: GiftAnimStyle.cinematic,
  ),
];

const List<(GiftCategory, String, String)> _categoryTabs = [
  (GiftCategory.baratos, 'Baratos', '🛍️'),
  (GiftCategory.gamer, 'Gamer', '🎮'),
  (GiftCategory.animacoes, 'Animações', '🎬'),
  (GiftCategory.veiculos, 'Veículos', '🏎️'),
  (GiftCategory.miticos, 'Míticos', '👑'),
];

/// 3. INTERFACE DA LOJA DE PRESENTES (GIFT PANEL COMPONENT)
class KlayKGiftPanel extends StatefulWidget {
  final Function(GiftItem) onGiftSent;

  const KlayKGiftPanel({super.key, required this.onGiftSent});

  @override
  State<KlayKGiftPanel> createState() => _KlayKGiftPanelState();
}

class _KlayKGiftPanelState extends State<KlayKGiftPanel> {
  String selectedGiftId = '';
  GiftCategory _tab = GiftCategory.baratos;

  List<GiftItem> get _items =>
      klayKGifts.where((g) => g.category == _tab).toList();

  void _send(GiftItem gift) {
    HapticFeedback.selectionClick();
    setState(() => selectedGiftId = gift.id);
    Timer(const Duration(milliseconds: 160), () {
      if (mounted) widget.onGiftSent(gift);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF120E1E),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabs(),
          const SizedBox(height: 10),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final gift = _items[index];
                return _GiftCard(
                  gift: gift,
                  selected: selectedGiftId == gift.id,
                  onTap: () => _send(gift),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (cat, label, emoji) in _categoryTabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  '$emoji $label',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                selected: _tab == cat,
                backgroundColor: const Color(0xFF1C1C26),
                selectedColor: kCyan.withValues(alpha: 0.25),
                side: BorderSide(
                  color: _tab == cat ? kCyan : Colors.white12,
                  width: _tab == cat ? 1.4 : 1,
                ),
                showCheckmark: false,
                onSelected: (_) => setState(() => _tab = cat),
              ),
            ),
        ],
      ),
    );
  }
}

class _GiftCard extends StatefulWidget {
  final GiftItem gift;
  final bool selected;
  final VoidCallback onTap;

  const _GiftCard({
    required this.gift,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends State<_GiftCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final (coinColor, coinEmoji) = currencyStyle(widget.gift.currency);
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected ? kCyan : Colors.white10,
              width: widget.selected ? 1.8 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: kCyan.withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.gift.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 4),
              Text(
                widget.gift.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                '$coinEmoji ${widget.gift.price}',
                style: TextStyle(
                  color: coinColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4. EFEITOS SONOROS/TÁTEIS NATIVOS (sem arquivos de áudio)
class GiftFeedback {
  static Future<void> play(GiftItem gift) async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}

/// 5. ANIMAÇÃO DE TELA CHEIA 100% NATIVA (usado na Stack da live)
class KlayGiftOverlay extends StatefulWidget {
  final GiftItem gift;
  final String senderName;
  final VoidCallback onComplete;

  const KlayGiftOverlay({
    super.key,
    required this.gift,
    this.senderName = '',
    required this.onComplete,
  });

  @override
  State<KlayGiftOverlay> createState() => _KlayGiftOverlayState();
}

class _KlayGiftOverlayState extends State<KlayGiftOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_FallingEmoji> _emoji;
  bool _cinematic = false;

  @override
  void initState() {
    super.initState();
    final style = widget.gift.animStyle == GiftAnimStyle.emojiRain
        ? _styleForId(widget.gift.id)
        : widget.gift.animStyle;
    _cinematic = style == GiftAnimStyle.cinematic;
    final vehicle = style == GiftAnimStyle.vehicle;

    final duration = _cinematic
        ? const Duration(seconds: 3)
        : vehicle
        ? const Duration(milliseconds: 2200)
        : const Duration(milliseconds: 2600);

    _controller = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onComplete();
      });

    final rnd = math.Random();
    final base = widget.gift.emoji;
    _emoji = List.generate(
      _cinematic ? 0 : (vehicle ? 14 : 34),
      (i) => _FallingEmoji(
        emoji: i % 3 == 0 ? '🪙' : (i % 5 == 0 ? '💎' : base),
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.5,
        speed: 0.7 + rnd.nextDouble() * 0.8,
        size: vehicle ? 14.0 : 18.0 + rnd.nextDouble() * 18,
      ),
    );

    GiftFeedback.play(widget.gift);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_cinematic)
            _buildCinematic()
          else
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = _controller.value;
                return CustomPaint(
                  painter: _EmojiRainPainter(
                    progress,
                    _emoji,
                    widget.gift.emoji,
                  ),
                );
              },
            ),
          // Header: nome do presente + remetente.
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 48),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOut,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.gift.emoji} ${widget.gift.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(blurRadius: 14, color: Colors.black87),
                          ],
                        ),
                      ),
                      if (widget.senderName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.senderName,
                            style: const TextStyle(
                              color: kCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCinematic() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Flash azul-escuro/branco sutil no início.
            Container(
              color: Color.lerp(
                Colors.transparent,
                const Color(0x66204A6B),
                Curves.easeOut.transform(
                  t < 0.25 ? t / 0.25 : (1 - (t - 0.25) / 0.2).clamp(0, 1),
                ),
              ),
            ),
            // Emoji gigante do navio com zoom brilhante.
            Center(
              child: Transform.scale(
                scale:
                    0.4 + Curves.easeOutBack.transform(t.clamp(0, 0.7)) * 1.6,
                child: Opacity(
                  opacity: (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0),
                  child: Text(
                    '🚢',
                    style: TextStyle(
                      fontSize: 200,
                      shadows: [
                        Shadow(
                          blurRadius: 40,
                          color: kCyan.withValues(alpha: 0.9),
                        ),
                        Shadow(
                          blurRadius: 120,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FallingEmoji {
  final String emoji;
  final double x;
  final double delay;
  final double speed;
  final double size;

  _FallingEmoji({
    required this.emoji,
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
  });
}

class _EmojiRainPainter extends CustomPainter {
  final double progress;
  final List<_FallingEmoji> emoji;
  final String base;

  _EmojiRainPainter(this.progress, this.emoji, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < emoji.length; i++) {
      final e = emoji[i];
      final local = ((progress - e.delay) / e.speed).clamp(-1.0, 1.0);
      if (local < 0) continue;
      final alpha = (1 - local).clamp(0.0, 1.0);
      final y = size.height * (1 - local);
      final wobble = math.sin((progress - e.delay) * 8 + i) * 12;
      final tp = TextPainter(
        text: TextSpan(
          text: e.emoji,
          style: TextStyle(
            fontSize: e.size,
            color: Colors.white.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(e.x * size.width + wobble, y));
    }
  }

  @override
  bool shouldRepaint(covariant _EmojiRainPainter old) =>
      old.progress != progress;
}
