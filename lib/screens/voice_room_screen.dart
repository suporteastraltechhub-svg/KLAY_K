import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/audio_room_models.dart';
import '../services/audio_room_service.dart';
import '../services/live_kit_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Sala de voz real do KLAY K: grid de participantes, lista de falantes,
/// botão de microfone (só áudio) e saída. Conecta via LiveKit.
class VoiceRoomScreen extends StatefulWidget {
  final AudioRoom room;
  final bool isOwner;
  final bool joinWithMic;

  const VoiceRoomScreen({
    super.key,
    required this.room,
    required this.joinWithMic,
    required this.isOwner,
  });

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  LiveKitService get _lk => LiveKitService.instance;
  bool _connected = false;
  bool _failed = false;
  bool _micOn = false;
  int _participants = 1;
  int _speakers = 1;
  bool _leaving = false;
  bool _joining = true;

  @override
  void initState() {
    super.initState();
    _participants = widget.room.participantCount;
    _speakers = widget.room.speakerCount;
    _lk.participantsCount.addListener(_onStats);
    _lk.activeSpeakers.addListener(_onStats);
    _lk.lastError.addListener(_onConnectionError);
    _lk.reconnecting.addListener(_onReconnecting);
    _join();
  }

  @override
  void dispose() {
    _lk.participantsCount.removeListener(_onStats);
    _lk.activeSpeakers.removeListener(_onStats);
    _lk.lastError.removeListener(_onConnectionError);
    _lk.reconnecting.removeListener(_onReconnecting);
    super.dispose();
  }

  void _onStats() {
    if (!mounted) return;
    setState(() {
      _participants = _lk.participantsCount.value;
      _speakers = _lk.activeSpeakers.value;
    });
  }

  /// Detecta queda de conexão no meio da sessão (LiveKit já estava conectado):
  /// em vez de ficar preso no estado antigo, marca como falha e dá "Tentar de novo".
  void _onConnectionError() {
    if (!mounted) return;
    final err = _lk.lastError.value;
    if (err == null) return;
    setState(() {
      _connected = false;
      _joining = false;
      _failed = true;
    });
  }

  /// Enquanto o LiveKit tenta restabelecer a conexão, mostra transparência de
  /// reconexão no lugar do grid de participantes (sem deslogar o usuário).
  void _onReconnecting() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _failed = false;
    });
    try {
      await AudioRoomService.instance.joinRoom(
        widget.room,
        asSpeaker: widget.joinWithMic || widget.isOwner,
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _joining = false;
        _micOn = widget.joinWithMic || widget.isOwner;
        _participants = _lk.participantsCount.value;
        _speakers = _lk.activeSpeakers.value;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _joining = false;
        _failed = true;
      });
    }
  }

  Future<void> _toggleMic() async {
    final next = !_micOn;
    setState(() => _micOn = next);
    await AudioRoomService.instance.toggleMicrophone(enabled: next);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    if (widget.isOwner && _connected) {
      await AudioRoomService.instance.endRoom(widget.room);
    } else {
      await _lk.disconnectFromLive();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String get _ownerInitial {
    final name = widget.room.ownerName.trim();
    return name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Row(
          children: [
            const Icon(Icons.waves_rounded, color: _kAccent, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.room.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _leaving ? null : _leave,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(l10n.leaveRoom),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatus(),
                const SizedBox(height: 28),
                _buildStageGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final l10n = AppLocalizations.of(context)!;
    if (_joining) {
      return Column(
        children: [
          const CircularProgressIndicator(color: _kAccent),
          const SizedBox(height: 16),
          Text(l10n.joiningRoom, style: const TextStyle(color: Colors.white70)),
        ],
      );
    }
    if (_lk.reconnecting.value) {
      return Column(
        children: [
          const CircularProgressIndicator(color: _kAccent),
          const SizedBox(height: 16),
          Text(
            l10n.reconnecting,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.reconnectingBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      );
    }
    if (_failed) {
      return Column(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.white38, size: 44),
          const SizedBox(height: 12),
          Text(
            l10n.joinRoomFail,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: _join,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _statTile(
              '$_participants',
              Icons.people_outline_rounded,
              l10n.participantsCountLabel,
            ),
            _statTile('$_speakers', Icons.mic_rounded, l10n.speakersCountLabel),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          widget.isOwner
              ? l10n.youAreRoomOwner
              : (widget.joinWithMic
                    ? l10n.youJoinedToSpeak
                    : l10n.youJoinedToListen),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _statTile(String value, IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: _kAccent, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildStageGrid() {
    final l10n = AppLocalizations.of(context)!;
    final others = _lk.guests;
    final total = _participants < 1 ? 1 : _participants;
    final slots = total.clamp(1, 6);
    return Column(
      children: [
        _avatarCard(
          _ownerInitial,
          widget.room.ownerName,
          speaker: _speakers > 0,
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < slots - 1; i++) ...[
          _avatarCard(
            '🙂',
            l10n.participantNumber(i + 2),
            speaker: i < (slots - 1) && _speakers > i,
          ),
          const SizedBox(height: 10),
        ],
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.othersInRoom(others.length),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        const SizedBox(height: 24),
        _buildControls(),
      ],
    );
  }

  Widget _avatarCard(String initial, String name, {required bool speaker}) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            speaker ? l10n.nameIsSpeaking(name) : l10n.nameInRoom(name),
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFA78BFA), Color(0xFF6D28D9)],
              ),
              border: Border.all(
                color: speaker ? _kAccent : const Color(0xFF2A2540),
                width: 3,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 26,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _controlButton(
          icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: _micOn ? l10n.mute : l10n.speak,
          highlighted: _micOn,
          onTap: _connected ? _toggleMic : null,
        ),
        const SizedBox(width: 16),
        _controlButton(
          icon: Icons.call_end_rounded,
          label: l10n.leaveRoom,
          danger: true,
          onTap: _leaving ? null : _leave,
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool highlighted = false,
    bool danger = false,
  }) {
    final color = danger
        ? Colors.redAccent
        : highlighted
        ? _kAccent
        : const Color(0xFF2A2540);
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}
