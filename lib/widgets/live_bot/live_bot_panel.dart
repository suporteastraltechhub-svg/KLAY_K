import 'package:flutter/material.dart';

import '../../models/live_bot_models.dart';
import '../../services/live_bot_service.dart';
import '../../services/live_bot_speech_queue.dart';
import '../../services/live_bot_tts.dart';
import '../../theme/klayk_theme.dart';
import 'live_bot_tabs.dart';

/// Painel premium de controle do KLAY K LIVE BOT.
///
/// Disponível apenas para o criador/moderador da live (a chamada de save é
/// validada no backend via `can_moderate_live`). O painel controla:
///  * Voz (prévia local gratuita + fallback)
///  * Comentários (modo de leitura, seleção)
///  * Moderação
///  * Anúncios
///  * Configurações
class LiveBotPanel extends StatefulWidget {
  const LiveBotPanel({
    super.key,
    required this.liveId,
    this.canModerate = true,
  });

  final String liveId;
  final bool canModerate;

  static Future<void> show(
    BuildContext context, {
    required String liveId,
    bool canModerate = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => LiveBotPanel(liveId: liveId, canModerate: canModerate),
    );
  }

  @override
  State<LiveBotPanel> createState() => _LiveBotPanelState();
}

class _LiveBotPanelState extends State<LiveBotPanel> {
  final LiveBotService _service = LiveBotService.instance;
  final LiveBotTts _tts = LiveBotTts.instance;

  int _tab = 0;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  LiveBotSettings _settings = const LiveBotSettings();
  List<LiveBotAnnouncement> _announcements = const [];
  late final LiveBotSpeechQueue _queue;

  @override
  void initState() {
    super.initState();
    _queue = LiveBotSpeechQueue.shared(tts: _tts);
    _init();
  }

  Future<void> _init() async {
    await _tts.init();
    await _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getSettings(widget.liveId),
        _service.listAnnouncements(widget.liveId),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as LiveBotSettings;
        _announcements = (results[1] as List<LiveBotAnnouncement>);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar as configurações do bot.';
      });
    }
  }

  Future<void> _save(LiveBotSettings next) async {
    setState(() {
      _settings = next;
      _saving = true;
    });
    final previous = _settings;
    try {
      await _service.saveSettings(widget.liveId, next);
      await _service.log(
        widget.liveId,
        eventType: 'config',
        message: 'Configurações do bot atualizadas',
        metadata: {'enabled': next.enabled},
      );
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _saving = false;
      });
      _toast('Sem permissão para alterar o bot.');
    }
  }

  Future<void> _testVoice() async {
    await _tts.applySettings(
      speed: _settings.voice.speed,
      volume: _settings.voice.volume,
      voiceType: _settings.voice.voiceType ?? 'auto',
    );
    await _tts.speak(LiveBotTts.kPreviewText);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1C1C26),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    // A fila é compartilhada com a tela da live; apenas interrompe a fala atual
    // em vez de destruir a instância compartilhada.
    _queue.cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<KlaykColors>() ?? KlaykColors.dark;
    final mq = MediaQuery.of(context);
    final height = mq.size.height * 0.82;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF0E0C16),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _handle(),
          _header(c),
          _statusHeader(c),
          _tabBar(c),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                  )
                : _error != null
                ? _errorView(c)
                : _buildTab(c),
          ),
        ],
      ),
    );
  }

  Widget _handle() => Container(
    margin: const EdgeInsets.only(top: 10),
    width: 44,
    height: 5,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _header(KlaykColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.smart_toy_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KLAY K LIVE BOT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Assistente de voz da sua live',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        if (widget.canModerate)
          IconButton(
            onPressed: _saving ? null : _load,
            icon: Icon(
              Icons.refresh_rounded,
              color: _saving ? c.primary : Colors.white70,
            ),
          ),
      ],
    ),
  );

  Widget _statusHeader(KlaykColors c) {
    final on = _settings.enabled;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: on
              ? [const Color(0xFF0E3B24), const Color(0xFF12201B)]
              : [const Color(0xFF2A1A2A), const Color(0xFF1A1220)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: on
              ? const Color(0xFF22C55E).withValues(alpha: 0.5)
              : Colors.white12,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? const Color(0xFF22C55E) : const Color(0xFFFF4D6A),
              boxShadow: [
                BoxShadow(
                  color:
                      (on ? const Color(0xFF22C55E) : const Color(0xFFFF4D6A))
                          .withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            on ? '🟢 ONLINE' : '🔴 OFFLINE',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (widget.canModerate && !_saving)
            Switch(
              value: on,
              activeThumbColor: const Color(0xFF22C55E),
              onChanged: (v) => _save(_settings.copyWith(enabled: v)),
            )
          else if (_saving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF22C55E),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBar(KlaykColors c) {
    const tabs = [
      (Icons.graphic_eq_rounded, 'VOZ'),
      (Icons.chat_bubble_rounded, 'COMENTÁRIOS'),
      (Icons.shield_rounded, 'MODERAÇÃO'),
      (Icons.campaign_rounded, 'ANÚNCIOS'),
      (Icons.settings_rounded, 'CONFIG'),
    ];
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < tabs.length; i++)
            _TabChip(
              icon: tabs[i].$1,
              label: tabs[i].$2,
              selected: _tab == i,
              onTap: () => setState(() => _tab = i),
            ),
        ],
      ),
    );
  }

  Widget _errorView(KlaykColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white38,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.primary,
              side: const BorderSide(color: Color(0xFF8B5CF6)),
            ),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );

  Widget _buildTab(KlaykColors c) {
    final write = widget.canModerate && !_saving;
    switch (_tab) {
      case 0:
        return VoiceTab(
          settings: _settings,
          queue: _queue,
          onPreview: _testVoice,
          onChange: write ? _save : null,
        );
      case 1:
        return CommentsTab(
          settings: _settings,
          onTestRead: _testVoice,
          onChange: write ? _save : null,
        );
      case 2:
        return ModerationTab(
          settings: _settings,
          onTestSpeak: (t) {
            _queue.cancelAll();
            _queue.enqueue(
              LiveBotSpeechItem(
                text: t,
                priority: LiveBotSpeechPriority.moderation,
              ),
            );
          },
          onChange: write ? _save : null,
        );
      case 3:
        return AnnouncementsTab(
          service: _service,
          liveId: widget.liveId,
          announcements: _announcements,
          onChange: (next) {
            setState(() => _announcements = next);
            _service.log(
              widget.liveId,
              eventType: 'announcement',
              message: 'Anúncio atualizado',
            );
          },
        );
      default:
        return SettingsTab(settings: _settings, onChange: write ? _save : null);
    }
  }
}

class _TabChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
                )
              : null,
          color: selected ? null : const Color(0xFF1E1A2B),
          borderRadius: BorderRadius.circular(12),
          border: selected ? null : Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : Colors.white54,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
