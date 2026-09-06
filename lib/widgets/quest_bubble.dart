import 'package:flutter/material.dart';

import '../screens/missions_screen.dart';
import '../services/admin_service.dart';
import '../services/supabase_service.dart';
import 'bubble_dismissal.dart';

/// Bolha flutuante do KLAY K: mostra missões/nível e pode ser arrastada.
///
/// A posição e o estado (ligado/desligado) são persistidos em
/// `user_settings` pelo dono (RLS). Aparece nas abas Feed e Perfil.
///
/// O X fecha a bolinha por um COOLDOWN (4h, local) — ela NUNCA é desabilitada
/// para sempre e volta a aparecer sozinha depois do período (ou em condições
/// válidas futuras).
class QuestBubble extends StatefulWidget {
  const QuestBubble({super.key, required this.visibleTab});

  final int visibleTab;

  @override
  State<QuestBubble> createState() => _QuestBubbleState();
}

class _QuestBubbleState extends State<QuestBubble>
    with SingleTickerProviderStateMixin {
  static const double _size = 58;

  bool? _enabled;
  Offset _pos = const Offset(16, 120);
  Map<String, dynamic> _progress = const {};
  bool _loading = true;
  final BubbleDismissal _dismissal = BubbleDismissal('quest_bubble_hidden_until');

  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _dismissal.ensureLoaded().then((_) {
      if (mounted) _syncPulse();
    });
    _load();
  }

  @override
  void didUpdateWidget(QuestBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleTab != widget.visibleTab) _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// O ticker de pulso só roda quando a bolha está realmente visível
  /// (economia de CPU — antes ficava a 60fps mesmo invisível).
  void _syncPulse() {
    if (_visible()) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  bool _visible() {
    if (_loading || _enabled != true) return false;
    if (!SupabaseService.instance.isConfigured) return false;
    // Cooldown local: enquanto o X estiver "selando" a bolinha ela fica
    // oculta, mas SEMPRE volta depois do período.
    if (_dismissal.isHidden()) return false;
    // Mostrar no Feed (0) e no Perfil (4).
    if (widget.visibleTab != 0 && widget.visibleTab != 4) return false;
    return true;
  }

  Future<void> _load() async {
    final admin = AdminService.instance;
    try {
      final settings = await admin.fetchBubbleSettings();
      // X não desabilita a bolinha permanentemente: sempre tratamos como
      // ligada e o cooldown local decide quando esconder/voltar.
      final x = (settings['bubble_x'] as num?)?.toDouble() ?? 16;
      final y = (settings['bubble_y'] as num?)?.toDouble() ?? 120;
      final progress = await admin.myProgress();
      if (mounted) {
        setState(() {
          _enabled = true;
          _pos = Offset(x, y);
          _progress = progress;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _enabled = false;
          _loading = false;
        });
      }
    }
    _syncPulse();
  }

  void _persist() {
    AdminService.instance
        .saveBubbleSettings(enabled: true, x: _pos.dx, y: _pos.dy)
        .catchError((_) {});
  }

  Future<void> _open() async {
    await MissionsScreen.show(context);
    _load();
  }

  void _hide() {
    setState(() {
      _pos = const Offset(16, 120);
    });
    // Cooldown local (4h): a bolinha fica oculta por um tempo e volta
    // sozinha — nunca desativamos a funcionalidade para sempre.
    _dismissal.dismiss();
    _syncPulse();
    AdminService.instance
        .saveBubbleSettings(enabled: true, x: 16, y: 120)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible()) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final maxX = (size.width - _size).clamp(0.0, double.infinity);
    final maxY = (size.height - 96 - _size).clamp(0.0, double.infinity);
    final pos = Offset(
      _pos.dx.clamp(0.0, maxX),
      _pos.dy.clamp(0.0, maxY),
    );

    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: size.width,
        height: size.height - 96,
        child: Stack(
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _open,
                    onPanUpdate: (d) {
                      setState(() => _pos = Offset(
                            pos.dx + d.delta.dx,
                            pos.dy + d.delta.dy,
                          ));
                    },
                    onPanEnd: (_) => _persist(),
                    child: _bubbleWidget(),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _hide,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white38,
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

  Widget _bubbleWidget() {
    final level = (_progress['level'] as num?)?.toInt() ?? 1;
    final xpTotal = (_progress['xp_total'] as num?)?.toInt() ?? 0;
    final xpStart = (_progress['xp_level_start'] as num?)?.toInt() ?? 0;
    final xpNext = (_progress['xp_next_level'] as num?)?.toInt();
    final hasNext = xpNext != null && xpNext > 0;
    final ratio = hasNext
        ? (((xpTotal - xpStart) / (xpNext - xpStart)).clamp(0.0, 1.0))
        : 1.0;

    Widget bubble = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFFC084F0)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.55),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(3),
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 3,
              backgroundColor: Colors.black26,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          Text(
            '$level',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    return ScaleTransition(scale: _scale, child: bubble);
  }
}