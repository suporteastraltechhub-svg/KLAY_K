import 'package:flutter/material.dart';

import '../../models/live_bot_models.dart';
import '../../services/live_bot_service.dart';
import '../../services/live_bot_speech_queue.dart';
import '../../services/live_bot_tts.dart';

typedef SettingsCallback = void Function(LiveBotSettings next);

const _voiceOptions = [
  (value: 'auto', label: 'Automático', hint: 'Voz padrão do dispositivo'),
  (value: 'female', label: 'Feminina', hint: 'pt-BR feminina'),
  (value: 'male', label: 'Masculina', hint: 'pt-BR masculina'),
];

Widget _sectionTitle(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );

Widget _card({required Widget child}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17141F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );

Widget _label(String t) => Text(t,
    style: const TextStyle(
        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600));

class _TabScaffold extends StatelessWidget {
  final Widget child;
  const _TabScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 90),
      child: child,
    );
  }
}

// ===========================================================================
// VOZ
// ===========================================================================
class VoiceTab extends StatelessWidget {
  final LiveBotSettings settings;
  final LiveBotSpeechQueue queue;
  final VoidCallback onPreview;
  final SettingsCallback? onChange;

  const VoiceTab({
    super.key,
    required this.settings,
    required this.queue,
    required this.onPreview,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final tts = LiveBotTts.instance;
    return _TabScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Voz para leitura em voz alta'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Tipo de voz (fallback automático)'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in _voiceOptions)
                      ChoiceChip(
                        label: Text(o.label,
                            style: TextStyle(
                              color: o.value == (settings.voice.voiceType ?? 'auto')
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            )),
                        selected: o.value == (settings.voice.voiceType ?? 'auto'),
                        selectedColor: const Color(0xFF8B5CF6),
                        backgroundColor: const Color(0xFF1E1A2B),
                        side: BorderSide(
                            color: o.value == (settings.voice.voiceType ?? 'auto')
                                ? const Color(0xFF8B5CF6)
                                : Colors.white12),
                        onSelected: onChange == null
                            ? null
                            : (_) => onChange!(settings.copyWithVoiceType(o.value)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('O bot escolhe a melhor voz em português automaticamente.',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _label('Velocidade'),
                    const Spacer(),
                    Text('${settings.voice.speed.toStringAsFixed(1)}x',
                        style: const TextStyle(
                            color: Color(0xFF8B5CF6), fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  value: settings.voice.speed.clamp(0.5, 2.0),
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  activeColor: const Color(0xFF8B5CF6),
                  inactiveColor: Colors.white12,
                  onChanged: onChange == null
                      ? null
                      : (v) => onChange!(settings.copyWithSpeed(v)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _label('Volume'),
                    const Spacer(),
                    Text('${(settings.voice.volume * 100).round()}%',
                        style: const TextStyle(
                            color: Color(0xFF8B5CF6), fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  value: settings.voice.volume.clamp(0.1, 1.0),
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  activeColor: const Color(0xFF38BDF8),
                  inactiveColor: Colors.white12,
                  onChanged: onChange == null
                      ? null
                      : (v) => onChange!(settings.copyWithVolume(v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (onChange != null)
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Voz atual do dispositivo'),
                  const SizedBox(height: 6),
                  Text(
                    tts.currentVoiceName?.isNotEmpty == true
                        ? tts.currentVoiceName!
                        : 'Verificando…',
                    style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPreview,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF38BDF8)),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
            label: const Text('TESTAR VOZ',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 8),
          const Text('Prévia usa TTS gratuito do dispositivo. A transmissão aos espectadores é feita pelo bot na sala.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}

// ===========================================================================
// COMENTÁRIOS
// ===========================================================================
class CommentsTab extends StatelessWidget {
  final LiveBotSettings settings;
  final VoidCallback onTestRead;
  final SettingsCallback? onChange;

  const CommentsTab({
    super.key,
    required this.settings,
    required this.onTestRead,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final mode = settings.commentMode;
    return _TabScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Como ler comentários em voz alta'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Modo de leitura'),
                const SizedBox(height: 8),
                ...LiveBotCommentMode.values.map((m) {
                  final sel = m == mode;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      m.icon,
                      color: sel ? const Color(0xFF8B5CF6) : Colors.white30,
                    ),
                    title: Text(m.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    subtitle: Text(m.description,
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 11)),
                    trailing: sel
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF22C55E), size: 20)
                        : null,
                    onTap: onChange == null
                        ? null
                        : () => onChange!(settings.copyWithCommentMode(m)),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _card(
            child: Row(
              children: [
                Icon(settings.commentsEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                    color: settings.commentsEnabled
                        ? const Color(0xFF38BDF8)
                        : Colors.white30),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Ler comentários',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                Switch(
                  value: settings.commentsEnabled,
                  activeThumbColor: const Color(0xFF38BDF8),
                  onChanged: onChange == null
                      ? null
                      : (v) => onChange!(settings.copyWithCommentsEnabled(v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTestRead,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.record_voice_over_rounded, size: 20),
            label: const Text('TESTAR LEITURA EM VOZ ALTA',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          const Text('Selecione um comentário no chat para o bot lê-lo. O bot de backend fala na sala.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}

// ===========================================================================
// MODERAÇÃO
// ===========================================================================
class ModerationTab extends StatelessWidget {
  final LiveBotSettings settings;
  final void Function(String text) onTestSpeak;
  final SettingsCallback? onChange;

  const ModerationTab({
    super.key,
    required this.settings,
    required this.onTestSpeak,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return _TabScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Moderação automática'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_rounded,
                        color: Color(0xFF8B5CF6), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text('Moderação ativa',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                    Switch(
                      value: settings.moderationEnabled,
                      activeThumbColor: const Color(0xFF8B5CF6),
                      onChanged: onChange == null
                          ? null
                          : (v) => onChange!(settings.copyWithModerationEnabled(v)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Avisos e punições de violadores são anunciados pelo bot em voz alta '
                  'com prioridade máxima sobre outros conteúdos.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _card(
            child: const Row(
              children: [
                Icon(Icons.priority_high_rounded,
                    color: Color(0xFFFFD700), size: 22),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Avisos têm prioridade máxima',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700))),
                Icon(Icons.arrow_upward_rounded,
                    color: Color(0xFFFFD700), size: 20),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => onTestSpeak('Atenção, esta é uma moderação de teste.'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFD700),
              side: const BorderSide(color: Color(0xFFFFD700)),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.campaign_rounded, size: 20),
            label: const Text('TESTAR AVISO',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          const Text('Os logs de moderação são registrados no backend e visíveis apenas a moderadores/staff.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}

// ===========================================================================
// ANÚNCIOS
// ===========================================================================
class AnnouncementsTab extends StatefulWidget {
  final LiveBotService service;
  final String liveId;
  final List<LiveBotAnnouncement> announcements;
  final void Function(List<LiveBotAnnouncement> next) onChange;

  const AnnouncementsTab({
    super.key,
    required this.service,
    required this.liveId,
    required this.announcements,
    required this.onChange,
  });

  @override
  State<AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<AnnouncementsTab> {
  final _controller = TextEditingController();
  int _interval = 120;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.service.addAnnouncement(
          widget.liveId, text, intervalSeconds: _interval);
      final updated = await widget.service.listAnnouncements(widget.liveId);
      widget.onChange(updated);
      _controller.clear();
    } catch (_) {
      _toast('Não foi possível adicionar o anúncio.');
    }
  }

  Future<void> _toggle(LiveBotAnnouncement a, bool enabled) async {
    try {
      await widget.service.setAnnouncementEnabled(a.id, enabled);
      final updated = await widget.service.listAnnouncements(widget.liveId);
      widget.onChange(updated);
    } catch (_) {
      _toast('Não foi possível atualizar o anúncio.');
    }
  }

  Future<void> _delete(LiveBotAnnouncement a) async {
    try {
      await widget.service.deleteAnnouncement(a.id);
      final updated = await widget.service.listAnnouncements(widget.liveId);
      widget.onChange(updated);
    } catch (_) {
      _toast('Não foi possível remover o anúncio.');
    }
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
  Widget build(BuildContext context) {
    return _TabScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Anúncios automáticos'),
          if (widget.announcements.isEmpty)
            _card(
              child: const Row(
                children: [
                  Icon(Icons.campaign_rounded, color: Colors.white24, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text('Nenhum anúncio ainda. Crie um para o bot anunciar na sala.',
                          style: TextStyle(color: Colors.white54, fontSize: 12))),
                ],
              ),
            )
          else
            for (final a in widget.announcements)
              _card(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.message,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('A cada ${a.intervalSeconds}s',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                    Switch(
                      value: a.enabled,
                      activeThumbColor: const Color(0xFF38BDF8),
                      onChanged: (v) => _toggle(a, v),
                    ),
                    IconButton(
                      onPressed: () => _delete(a),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFFF4D6A), size: 20),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Novo anúncio'),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLength: 240,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ex.: Siga o perfil oficial!',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E1A2B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _label('Intervalo'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _interval,
                      dropdownColor: const Color(0xFF1E1A2B),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 60, child: Text('1 min')),
                        DropdownMenuItem(value: 120, child: Text('2 min')),
                        DropdownMenuItem(value: 300, child: Text('5 min')),
                        DropdownMenuItem(value: 600, child: Text('10 min')),
                      ],
                      onChanged: (v) => setState(() => _interval = v ?? 120),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _add,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('ADICIONAR ANÚNCIO',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// CONFIGURAÇÕES
// ===========================================================================
class SettingsTab extends StatelessWidget {
  final LiveBotSettings settings;
  final SettingsCallback? onChange;

  const SettingsTab({super.key, required this.settings, this.onChange});

  @override
  Widget build(BuildContext context) {
    return _TabScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Comportamento geral'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded,
                        color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text('Anúncios automáticos',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                    Switch(
                      value: settings.announcementsEnabled,
                      activeThumbColor: const Color(0xFF38BDF8),
                      onChanged: onChange == null
                          ? null
                          : (v) => onChange!(settings.copyWithAnnouncementsEnabled(v)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: Color(0xFF8B5CF6), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text('Respostas automáticas',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                    Switch(
                      value: settings.autoRepliesEnabled,
                      activeThumbColor: const Color(0xFF8B5CF6),
                      onChanged: onChange == null
                          ? null
                          : (v) => onChange!(settings.copyWithAutoRepliesEnabled(v)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionTitle('Respostas automáticas'),
          if (settings.autoReplies.isEmpty)
            _card(
              child: const Row(
                children: [
                  Expanded(
                      child: Text('Nenhuma resposta configurada.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12))),
                ],
              ),
            )
          else
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final ar in settings.autoReplies)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.question_answer_rounded,
                              color: Color(0xFF8B5CF6), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Q: ${ar.question}',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                Text('R: ${ar.answer}',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const Text('As respostas automáticas e anúncios são processados pelo bot de backend na sala.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
