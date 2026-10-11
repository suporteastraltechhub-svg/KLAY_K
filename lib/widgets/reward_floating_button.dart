import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/wallet_sheet.dart';
import '../services/reward_service.dart';
import '../services/supabase_service.dart';
import 'bubble_dismissal.dart';
import 'klayk_coin_bubble.dart';

/// Botão flutuante premium de "Ganhar Moedas" do feed.
///
/// Substitui a antiga bolinha de nível: usa exclusivamente a imagem
/// `assets/images/btn_ganhar_moedas.png` (PNG com transparência — sem fundo, sem
/// número sobreposto) e um anel circular fino `{CircularRewardProgress}` ao
/// redor, sem cobrir a arte.
///
/// O ciclo (20s) é controlado pelo [RewardTimerController] e pausa quando o
/// app está em background, o feed não está ativo ou o vídeo não reproduz. A
/// recompensa (15 moedas) é sempre validada no backend (`claim_watch_cycle_reward`);
/// o saldo é sempre o devolvido pelo servidor.
class RewardFloatingButton extends StatefulWidget {
  const RewardFloatingButton({
    super.key,
    required this.visibleTab,
    this.paused,
  });

  /// Índice da aba: exibimos somente no Feed (0).
  final int visibleTab;

  /// Sinal opcional que força a pausa do ciclo enquanto nenhum vídeo está de
  /// fato sendo assistido (ex.: o Feed está numa sub-abas que não reproduz o
  /// feed de vídeos, ou o usuário pausou o vídeo ativo). Quando `true`, o
  /// ciclo pausa; quando `false`/nulo, depende apenas dos demais sinais
  /// (aba ativa, app em foreground, autenticado).
  final ValueListenable<bool>? paused;

  static const double size = 66;
  static const double ringWidth = 5;
  static const String _asset = 'assets/images/btn_ganhar_moedas.png';

  @override
  State<RewardFloatingButton> createState() => _RewardFloatingButtonState();
}

class _RewardFloatingButtonState extends State<RewardFloatingButton>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final RewardTimerController _controller;
  late final AnimationController _plusAnim;

  /// Timer do texto flutuante (+N moedas), cancelado em [dispose].
  Timer? _floatingTimer;
  Offset _pos = const Offset(16, 200);
  bool _loaded = false;
  bool _bubbleLoaded = false;
  String? _floatingText;
  final BubbleDismissal _dismissal = BubbleDismissal('reward_btn_hidden_until');

  static const String _posKey = 'reward_btn_pos';

  @override
  void initState() {
    super.initState();
    _controller = RewardTimerController(onClaimed: _onClaimed);
    _plusAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.paused?.addListener(_onPausedChanged);
    _dismissal.ensureLoaded().then((_) {
      if (mounted) {
        setState(() => _bubbleLoaded = true);
        _controller.setActive(_shouldRun());
      }
    });
    _loadPos();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pausa o ciclo quando o app vai para background.
    _controller.setActive(_shouldRun() && state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(covariant RewardFloatingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Só troca o listener quando o notifier é realmente outro. Antes, o
    // `removeListener` rodava em todo rebuild — mesmo com o mesmo notifier —
    // e o `ValueNotifier` repetia a mesma notificação.
    if (!identical(oldWidget.paused, widget.paused)) {
      oldWidget.paused?.removeListener(_onPausedChanged);
      widget.paused?.addListener(_onPausedChanged);
    }
    if (!mounted) return;
    _controller.setActive(_shouldRun());
  }

  void _onPausedChanged() {
    if (!mounted) return;
    _controller.setActive(_shouldRun());
  }

  bool get _pausedBySignal => widget.paused?.value ?? false;

  bool _shouldRun() {
    if (!_bubbleLoaded) return false;
    // X com cooldown (igual QuestBubble): esconde temporariamente e a bolinha
    // volta sozinha após o período — nunca desabilita o recurso para sempre.
    if (_dismissal.isHidden()) return false;
    if (_pausedBySignal) return false;
    if (widget.visibleTab != 0) return false;
    if (!SupabaseService.instance.isConfigured) return false;
    final user = SupabaseService.instance.client.auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    return true;
  }

  Future<void> _loadPos() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getString(_posKey);
      if (saved != null) {
        final parts = saved.split(',');
        if (parts.length == 2) {
          _pos = Offset(
            double.tryParse(parts[0]) ?? 16,
            double.tryParse(parts[1]) ?? 200,
          );
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loaded = true);
    _controller.setActive(_shouldRun());
  }

  Future<void> _persistPos() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_posKey, '${_pos.dx},${_pos.dy}');
    } catch (_) {}
  }

  @override
  void dispose() {
    widget.paused?.removeListener(_onPausedChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _floatingTimer?.cancel();
    _plusAnim.dispose();
    super.dispose();
  }

  /// Reação ao resultado do backend. O servidor decide `ok`/`reward`/`balance`.
  void _onClaimed(RewardClaimResult result) {
    if (!mounted) return;
    if (result.ok) {
      _showFloating('+${result.reward} moedas');
    } else if (result.error != null && result.error!.isNotEmpty) {
      _showFloating(result.error!);
      // Não adicionamos moedas localmente; se o saldo estiver dessincronizado,
      // o usuário pode conferir na carteira. Sem alteração local de saldo.
    }
  }

  void _showFloating(String text) {
    setState(() => _floatingText = text);
    _plusAnim
      ..reset()
      ..forward();
    // Timer guardado em campo: o antigo ficava órfão e disparava setState
    // depois do dispose. Com o ciclo de 20s isso acontecia a cada recompensa.
    _floatingTimer?.cancel();
    _floatingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _floatingText == text) {
        setState(() => _floatingText = null);
      }
    });
  }

  Future<void> _open() async {
    // Toca manualmente? A recompensa é automática por ciclo. Abrimos a carteira
    // para o usuário ver o saldo real (sempre vindo do servidor).
    await WalletSheet.show(context);
  }

  /// Fecha a bolinha por um cooldown local (padrão 4h), como a QuestBubble —
  /// ela volta a aparecer sozinha depois; nunca desabilitamos o recurso.
  void _hide() {
    setState(() {
      _pos = const Offset(16, 200);
    });
    _persistPos();
    _dismissal.dismiss();
    _controller.setActive(false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_shouldRun()) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final maxX = (size.width - RewardFloatingButton.size).clamp(
      0.0,
      double.infinity,
    );
    final maxY = (size.height - 120 - RewardFloatingButton.size).clamp(
      0.0,
      double.infinity,
    );
    final pos = Offset(_pos.dx.clamp(12.0, maxX), _pos.dy.clamp(120.0, maxY));

    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: size.width,
        height: size.height - 120,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    key: const ValueKey('reward_btn'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _open,
                    onPanUpdate: (d) {
                      setState(
                        () => _pos = Offset(
                          pos.dx + d.delta.dx,
                          pos.dy + d.delta.dy,
                        ),
                      );
                    },
                    onPanEnd: (_) => _persistPos(),
                    child: _buildButton(),
                  ),
                  // X com cooldown: fecha a bolinha temporariamente.
                  GestureDetector(
                    key: const ValueKey('reward_btn_close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _hide,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.close, size: 14, color: Colors.white38),
                    ),
                  ),
                  // Texto flutuante premium "+15 moedas".
                  AnimatedBuilder(
                    animation: _plusAnim,
                    builder: (context, _) {
                      if (_floatingText == null) return const SizedBox.shrink();
                      final t = Curves.easeOut.transform(_plusAnim.value);
                      return Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -(24 * t)),
                          child: Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              _floatingText!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: RewardFloatingButton.size,
          height: RewardFloatingButton.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Anel neon + brilhos + estrela ao redor da moeda.
              // Fica ATRÁS do anel de progresso, então o progresso de 20s
              // continua legível por cima e nenhum dos dois some.
              KlaykCoinBubble(
                size: RewardFloatingButton.size,
                coinAsset: RewardFloatingButton._asset,
                paused: _pausedBySignal,
              ),
              CircularRewardProgress(
                ringWidth: RewardFloatingButton.ringWidth,
                progress: _controller.progress,
                size: RewardFloatingButton.size,
                claiming: _controller.isClaiming,
                child: Image.asset(
                  RewardFloatingButton._asset,
                  fit: BoxFit.contain,
                  width: RewardFloatingButton.size,
                  height: RewardFloatingButton.size,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.monetization_on_rounded,
                    color: Color(0xFFFFD700),
                    size: RewardFloatingButton.size * 0.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Anel circular fino ao redor da imagem do botão (não cobre a arte).
class CircularRewardProgress extends StatelessWidget {
  final double size;
  final double ringWidth;
  final double progress;
  final bool claiming;
  final Widget child;

  const CircularRewardProgress({
    super.key,
    required this.size,
    required this.ringWidth,
    required this.progress,
    required this.child,
    this.claiming = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          ringWidth: ringWidth,
          claiming: claiming,
        ),
        child: Center(
          // Margem interna para o anel não encostar/cobrir a arte.
          child: Padding(padding: EdgeInsets.all(ringWidth + 2), child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double ringWidth;
  final bool claiming;

  _RingPainter({
    required this.progress,
    required this.ringWidth,
    required this.claiming,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const accent = Color(0xFF38BDF8);
    const purple = Color(0xFF8B5CF6);
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - ringWidth) / 2;

    // Trilho sutil.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.25);
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    // Arco de progresso com gradiente suave (roxo → azul neon).
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [purple, accent],
      ).createShader(rect);

    canvas.drawArc(
      rect.deflate(ringWidth / 2),
      -90 * 3.1415927 / 180,
      2 * 3.1415927 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.claiming != claiming ||
      oldDelegate.ringWidth != ringWidth;
}
