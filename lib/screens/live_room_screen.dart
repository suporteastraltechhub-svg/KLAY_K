import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gift_models.dart';
import '../models/klayk_live_models.dart';
import '../services/account_service.dart';
import '../services/content_service.dart';
import '../services/experience_settings.dart';
import '../services/gift_service.dart';
import '../services/live_game_overlay.dart';
import '../services/live_kit_service.dart';
import '../services/live_premium_service.dart';
import '../services/security_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../widgets/verified_badge.dart';
import '../widgets/gift_animations.dart';
import '../widgets/live_diagnostics_panel.dart';
import '../widgets/live_bot/live_bot_panel.dart';
import '../services/live_bot_speech_queue.dart';
import '../services/live_bot_tts.dart';
import 'profile/user_profile_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kLiveRed = Color(0xFFFF2E4D);

/// Tela real da live: vídeo/áudio via LiveKit Cloud, chat via Supabase
/// Realtime, eventos, presentes e moderação básica. Sublinhado preto + roxo
/// neon, mantendo o visual do KLAY K.
class LiveRoomScreen extends StatefulWidget {
  final RealLive live;
  final LiveRole role;

  /// Define se esta live é uma Live de Jogo (gameplay + captura de tela).
  /// Quando `true` e o participante é o streamer, o app solicita a captura de
  /// tela e oferece a bolinha flutuante de controles sobre outros apps.
  final bool isGameLive;
  final String? gamePackage;

  const LiveRoomScreen({
    super.key,
    required this.live,
    this.role = LiveRole.viewer,
    this.isGameLive = false,
    this.gamePackage,
  });

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

enum _ModerationAction {
  report,
  block,
  silence,
  delete,
  banLive,
  muteLive,
  edit,
  copy,
  readOutLoud,
}

/// Ciclo de vida da transmissão: ANTES (aguardando início, configuração da
/// captura), DURANTE (ao vivo) e DEPOIS (encerrada/recap).
enum LivePhase { waiting, live, ended }

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final LiveKitService _lk = LiveKitService.instance;
  final SupabaseService _db = SupabaseService.instance;

  late RealLive _live;
  late final String _liveId;
  late final String _roomName;

  String? _myId;
  bool _connected = false;
  String? _error;
  bool _camOn = false;
  bool _micOn = false;
  bool _shareOn = false;
  bool _voiceBotOn = false;
  bool _videoListenOn = true;
  bool _audioListenOn = true;
  bool _liked = false;
  bool _following = false;
  bool _ended = false;

  // Estados da live (antes / durante / depois).
  LivePhase _phase = LivePhase.waiting;
  final DateTime _joinedAt = DateTime.now();
  int _peakViewers = 0;
  bool _recapDismissed = false;

  bool _chatOpen = false;

  /// Mede a altura do rodapé (lista + barra) para a área de "tocar fora".
  ///
  /// A altura muda conforme o estado (compositor ativo/inativo, uma ou várias
  /// mensagens, teclado aberto). Medir em runtime é mais seguro do que um valor
  /// fixo: se o valor chutado errasse, a área de toque invadiria a lista ou os
  /// botões.
  final GlobalKey _chatOverlayKey = GlobalKey(debugLabel: 'liveChatOverlay');
  double? _chatOverlayHeight;

  final List<LiveChatMessage> _messages = [];
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocus = FocusNode();
  String? _editingMessageId;
  final Set<String> _blockedUsers = {};
  final Set<String> _mutedUsers = {};
  bool _isModerator = false;

  final List<RealtimeChannel> _channels = [];
  EventsListener<RoomEvent>? _roomListener;

  Gift? _activeGiftAnim;
  String _activeGiftSender = '';
  int _activeGiftAmount = 1;
  String? _lastGiftTxId;
  int _wallet = 0;
  bool _walletLoaded = false;
  String? _walletError;
  bool _chatRealtimeReady = false;
  bool _liveRealtimeReady = false;
  String? _realtimeError;
  int _subscribedRealtimeChannels = 0;
  String? _pendingGiftRequestId;
  String? _pendingGiftFingerprint;
  final List<String> _diagnosticEvents = [];

  // Premium: reações rápidas (contadores por mensagem + minhas reações).
  final Map<String, Map<String, int>> _reactions = {};
  final Set<String> _myReactions = {};
  String? _burstEmoji;
  Timer? _burstTimer;
  RealtimeChannel? _reactionsChannel;

  // Premium: top apoiadores neon + alertas automáticos da sala.
  List<LiveRankRecord> _topSupporters = const [];
  final List<_RoomAlert> _alerts = [];

  int get _viewerCount {
    if (_lk.isConnected) {
      if (widget.role == LiveRole.streamer) return _lk.guests.length;
      return _lk.guests
          .where((participant) => participant.identity != _live.streamerId)
          .length;
    }
    return _live.viewerCount;
  }

  @override
  void initState() {
    super.initState();
    _live = widget.live;
    _liveId = widget.live.id;
    _roomName = widget.live.roomName;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Tocar direto no campo também precisa ativar o composer: é o que faz a
    // barra subir junto com o teclado.
    _chatFocus.addListener(_onChatFocusChanged);
    _join();
  }

  Future<void> _join() async {
    try {
      final user = await _db.ensureAuthenticated();
      if (!mounted) return;
      _myId = user.id;
      _recordDiagnostic('Sessão autenticada para $_myId.');

      // Estado real §1/§16: se a live já terminou no backend, não conecta e
      // mostra "Esta Live terminou" (nunca uma sala simulada).
      final status = await _db.fetchLiveStatus(_liveId);
      if (!mounted) return;
      if (status == 'ended') {
        await _showLiveEnded();
        return;
      }

      if (widget.role == LiveRole.viewer && _live.ageRestricted) {
        final allowed = await SecurityService.instance.liveViewAllowed(_liveId);
        if (!mounted) return;
        if (!allowed) {
          await _showAgeGate();
          return;
        }
      }

      try {
        _following = await ContentService.instance.isFollowing(
          _live.streamerId,
        );
        if (mounted) setState(() {});
      } catch (_) {}

      try {
        _wallet = await GiftService.instance.fetchWallet();
        _walletLoaded = true;
        _walletError = null;
        _recordDiagnostic('Carteira carregada: $_wallet créditos.');
      } catch (error) {
        _walletError = 'Falha ao ler o saldo real.';
        _recordDiagnostic('Carteira indisponível: ${error.runtimeType}');
      }

      await _db.recordParticipant(
        _liveId,
        isStreamer: widget.role == LiveRole.streamer,
      );

      _channels.add(
        _db.subscribeToChat(
          _liveId,
          _onChatInserted,
          onStatus: (status, error) => _onRealtimeStatus('chat', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToLiveEvents(
          _liveId,
          _onRoomEvent,
          onStatus: (status, error) =>
              _onRealtimeStatus('events', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToBroadcast(
          _liveId,
          'gift',
          _onGiftBroadcast,
          onStatus: (status, error) => _onRealtimeStatus('gift', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToBroadcast(
          _liveId,
          'chat:delete',
          _onChatDelete,
          onStatus: (status, error) =>
              _onRealtimeStatus('chat:delete', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToBroadcast(
          _liveId,
          'chat:edit',
          _onChatEdit,
          onStatus: (status, error) =>
              _onRealtimeStatus('chat:edit', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToBroadcast(
          _liveId,
          'chat:ban',
          _onChatBan,
          onStatus: (status, error) =>
              _onRealtimeStatus('chat:ban', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToBroadcast(
          _liveId,
          'chat:mute',
          _onChatMute,
          onStatus: (status, error) =>
              _onRealtimeStatus('chat:mute', status, error),
        ),
      );
      _channels.add(
        _db.subscribeToLiveChanges(
          _liveId,
          _onLiveRowChanged,
          onStatus: (status, error) => _onRealtimeStatus('live', status, error),
        ),
      );
      _subscribeReactions();

      if (widget.role != LiveRole.viewer ||
          await SocialService.instance.isLiveModerator(_liveId)) {
        _isModerator = true;
      }
      final banned = await SocialService.instance.fetchLiveBannedIds(_liveId);
      final muted = await SocialService.instance.fetchLiveMutedIds(_liveId);
      if (mounted) {
        setState(() {
          _blockedUsers.addAll(banned);
          _mutedUsers.addAll(muted);
        });
      }

      final recent = await _db.loadRecentChat(_liveId);
      if (!mounted) return;
      setState(() => _messages.addAll(recent));
      _applyChatFilters();

      try {
        final reactions = await LivePremiumService.instance.fetchRoomReactions(
          _liveId,
        );
        if (mounted) setState(() => _reactions.addAll(reactions));
      } catch (_) {}

      _refreshTopSupporters();

      await _connectLiveKit();
      if (!mounted) return;
      _lk.participantsCount.addListener(_onParticipantsChanged);
      // Espelha reconexões do LiveKit (§16) → overlay "Reconectando...".
      // removeListener antes evita duplicidade num eventual retry (§16).
      _lk.reconnecting.removeListener(_onReconnectingChanged);
      _lk.reconnecting.addListener(_onReconnectingChanged);
      _lk.lastError.removeListener(_onLiveKitError);
      _lk.lastError.addListener(_onLiveKitError);
      _recordDiagnostic(
        'Sala conectada: $_roomName (${_lk.connectionState?.toString().split('.').last ?? 'connected'}).',
      );
    } catch (error) {
      _recordDiagnostic('Falha ao entrar na Live: ${error.runtimeType}');
      if (!mounted) return;
      setState(() {
        _connected = false;
        _error = 'Não foi possível entrar na Live. Tente novamente.';
      });
    }
  }

  void _recordDiagnostic(String message) {
    if (!kDebugMode) return;
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '$stamp $message';
    _diagnosticEvents.add(entry);
    if (_diagnosticEvents.length > 40) {
      _diagnosticEvents.removeRange(0, _diagnosticEvents.length - 40);
    }
    debugPrint('[KLayK][Live] $entry');
  }

  void _onRealtimeStatus(
    String name,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    if (!kDebugMode) return;
    final subscribed = status == RealtimeSubscribeStatus.subscribed;
    if (subscribed) {
      _subscribedRealtimeChannels++;
      if (name == 'chat') _chatRealtimeReady = true;
      if (name == 'events' || name == 'live') _liveRealtimeReady = true;
      _realtimeError = null;
      _recordDiagnostic('Realtime $name: subscribed');
    } else {
      if (name == 'chat') _chatRealtimeReady = false;
      if (name == 'events' || name == 'live') _liveRealtimeReady = false;
      _realtimeError = error == null
          ? '$name: ${status.toString().split('.').last}'
          : '$name: ${error.runtimeType}';
      _recordDiagnostic('Realtime $name: ${_realtimeError!}');
    }
    if (mounted) setState(() {});
  }

  List<LiveDiagnosticItem> _diagnosticItems() {
    final connectionState =
        _lk.connectionState?.toString().split('.').last ?? 'sem sala';
    final connectionStatus = _lk.isConnected
        ? LiveDiagnosticStatus.healthy
        : _lk.reconnecting.value
        ? LiveDiagnosticStatus.warning
        : LiveDiagnosticStatus.error;
    final cameraActive = widget.role == LiveRole.streamer
        ? _lk.cameraInUse
        : _lk.remoteVideoPublished;
    final micActive = widget.role == LiveRole.streamer
        ? _lk.micInUse
        : _lk.remoteAudioPublished;
    final screenActive = widget.role == LiveRole.streamer
        ? _lk.localScreenSharePublished
        : _lk.remoteScreenSharePublished;
    final screenAudioActive = widget.role == LiveRole.streamer
        ? _lk.localScreenShareAudioPublished
        : _lk.remoteScreenShareAudioPublished;
    return [
      LiveDiagnosticItem(
        label: 'Conexão LiveKit',
        value: _lk.isConnected ? 'conectado' : connectionState,
        icon: _lk.isConnected
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_rounded,
        status: connectionStatus,
      ),
      LiveDiagnosticItem(
        label: 'Câmera / vídeo',
        value: cameraActive ? 'publicada e ativa' : 'sem publicação',
        icon: cameraActive
            ? Icons.videocam_rounded
            : Icons.videocam_off_rounded,
        status: cameraActive
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.warning,
      ),
      LiveDiagnosticItem(
        label: 'Microfone / áudio',
        value: micActive ? 'publicado e ativo' : 'sem publicação',
        icon: micActive ? Icons.mic_rounded : Icons.mic_off_rounded,
        status: micActive
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.warning,
      ),
      LiveDiagnosticItem(
        label: 'Tela / áudio do jogo',
        value: screenActive
            ? 'vídeo${screenAudioActive ? ' + áudio' : ' sem áudio'}'
            : 'sem captura',
        icon: screenActive
            ? Icons.screen_share_rounded
            : Icons.screen_share_outlined,
        status: screenActive
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.info,
      ),
      LiveDiagnosticItem(
        label: 'Chat Realtime',
        value: _chatRealtimeReady
            ? 'inscrito'
            : (_realtimeError ?? 'aguardando'),
        icon: _chatRealtimeReady ? Icons.forum_rounded : Icons.forum_outlined,
        status: _chatRealtimeReady
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.warning,
      ),
      LiveDiagnosticItem(
        label: 'Eventos da sala',
        value: _liveRealtimeReady
            ? '$_subscribedRealtimeChannels canais inscritos'
            : 'aguardando inscrição',
        icon: Icons.bolt_rounded,
        status: _liveRealtimeReady
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.warning,
      ),
      LiveDiagnosticItem(
        label: 'Espectadores',
        value: '$_viewerCount conectado${_viewerCount == 1 ? '' : 's'}',
        icon: Icons.people_rounded,
        status: _lk.isConnected
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.warning,
      ),
      LiveDiagnosticItem(
        label: 'Carteira de créditos',
        value: _walletLoaded
            ? '$_wallet créditos'
            : (_walletError ?? 'carregando'),
        icon: Icons.account_balance_wallet_rounded,
        status: _walletLoaded
            ? LiveDiagnosticStatus.healthy
            : LiveDiagnosticStatus.error,
      ),
      LiveDiagnosticItem(
        label: 'Presentes',
        value: widget.role == LiveRole.streamer
            ? 'criador não pode enviar para si mesmo'
            : 'envio validado pelo backend',
        icon: Icons.card_giftcard_rounded,
        status: LiveDiagnosticStatus.info,
      ),
    ];
  }

  Future<void> _probeConnection() async {
    if (!_lk.isConnected) {
      throw StateError(
        _lk.reconnecting.value
            ? 'LiveKit ainda está reconectando.'
            : 'LiveKit não está conectado.',
      );
    }
    _recordDiagnostic(
      'Probe conexão: ${_lk.guests.length} participantes remotos.',
    );
  }

  Future<void> _probeCamera() async {
    final active = widget.role == LiveRole.streamer
        ? _lk.cameraInUse
        : _lk.remoteVideoPublished;
    if (!active) throw StateError('Nenhuma publicação de vídeo ativa.');
    _recordDiagnostic('Probe câmera: publicação de vídeo confirmada.');
  }

  Future<void> _probeMicrophone() async {
    final active = widget.role == LiveRole.streamer
        ? _lk.micInUse
        : _lk.remoteAudioPublished;
    if (!active) throw StateError('Nenhuma publicação de áudio ativa.');
    _recordDiagnostic('Probe microfone: publicação de áudio confirmada.');
  }

  Future<void> _probeScreen() async {
    final active = widget.role == LiveRole.streamer
        ? _lk.localScreenSharePublished
        : _lk.remoteScreenSharePublished;
    if (!active) throw StateError('Nenhuma publicação de tela ativa.');
    final audio = widget.role == LiveRole.streamer
        ? _lk.localScreenShareAudioPublished
        : _lk.remoteScreenShareAudioPublished;
    _recordDiagnostic(
      'Probe tela: captura confirmada; áudio ${audio ? 'ativo' : 'inativo'}.',
    );
  }

  Future<void> _probeChat() async {
    final messages = await _db.loadRecentChat(_liveId);
    _recordDiagnostic('Probe chat: ${messages.length} mensagens carregadas.');
  }

  Future<void> _probeRealtime() async {
    if (!_chatRealtimeReady || !_liveRealtimeReady) {
      throw StateError(_realtimeError ?? 'Realtime ainda não inscrito.');
    }
    _recordDiagnostic('Probe Realtime: chat e eventos inscritos.');
  }

  Future<void> _probeGifts() async {
    final gifts = await GiftService.instance.fetchGifts(pageSize: 1);
    if (gifts.isEmpty) throw StateError('Catálogo de presentes vazio.');
    _recordDiagnostic(
      'Probe presentes: catálogo respondeu com ${gifts.length}.',
    );
  }

  Future<void> _probeWallet() async {
    final balance = await GiftService.instance.fetchWallet();
    if (!mounted) return;
    setState(() {
      _wallet = balance;
      _walletLoaded = true;
      _walletError = null;
    });
    _recordDiagnostic('Probe carteira: saldo real $balance.');
  }

  Future<void> _openDiagnostics() async {
    if (!kDebugMode || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: LiveDiagnosticsPanel(
            snapshotBuilder: _diagnosticItems,
            recentEvents: _diagnosticEvents,
            quickTests: [
              LiveDiagnosticQuickTest(
                label: 'Conexão',
                icon: Icons.cloud_sync_rounded,
                callback: _probeConnection,
              ),
              LiveDiagnosticQuickTest(
                label: 'Câmera',
                icon: Icons.videocam_rounded,
                callback: _probeCamera,
              ),
              LiveDiagnosticQuickTest(
                label: 'Microfone',
                icon: Icons.mic_rounded,
                callback: _probeMicrophone,
              ),
              LiveDiagnosticQuickTest(
                label: 'Tela',
                icon: Icons.screen_share_rounded,
                callback: _probeScreen,
              ),
              LiveDiagnosticQuickTest(
                label: 'Chat',
                icon: Icons.forum_rounded,
                callback: _probeChat,
              ),
              LiveDiagnosticQuickTest(
                label: 'Realtime',
                icon: Icons.bolt_rounded,
                callback: _probeRealtime,
              ),
              LiveDiagnosticQuickTest(
                label: 'Presentes',
                icon: Icons.card_giftcard_rounded,
                callback: _probeGifts,
              ),
              LiveDiagnosticQuickTest(
                label: 'Carteira',
                icon: Icons.account_balance_wallet_rounded,
                callback: _probeWallet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estado "Esta Live terminou" — sem conexão, sem tela estática: informa e
  /// retorna à tela anterior.
  Future<void> _showLiveEnded() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        title: const Text(
          'Esta Live terminou',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'A transmissão encerrou e não está mais disponível.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(true);
            },
            child: const Text('OK', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  /// Gate de faixa etária para lives [ageRestricted]: se o backend negar o
  /// acesso (menor com idade provada ou sem data de nascimento), o app NÃO
  /// conecta à live e explica de forma honesta o motivo.
  Future<void> _showAgeGate() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        icon: const Icon(Icons.lock_rounded, color: Colors.orange, size: 40),
        title: const Text(
          'Live para maiores de 18',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'Esta live é restrita. O backend exige idade provada de 18+ (data '
          'de nascimento cadastrada) — consentimento não substitui a '
          'verificação para este conteúdo.\n\n'
          'Cadastre sua data de nascimento em Configurações › Modo Jovem e '
          'segurança.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Entendi',
              style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _connectLiveKit() async {
    if (widget.role == LiveRole.streamer) {
      await _lk.startLive(roomName: _roomName, liveId: _liveId);
      if (!mounted) return;
      setState(() {
        _connected = _lk.isConnected;
        _camOn = _lk.cameraInUse;
        _micOn = _lk.micInUse;
        // DURANTE: câmera e áudio já publicados; a fase de jogo entra no
        // estado "live" assim que a captura de tela for iniciada.
        if (!widget.isGameLive) _phase = LivePhase.live;
      });
      _recordDiagnostic(
        'Transmissão iniciada. Câmera=${_lk.cameraInUse}, mic=${_lk.micInUse}.',
      );
      // Live de Jogo: sobe a bolinha flutuante e solicita a captura de tela.
      if (widget.isGameLive) {
        unawaited(_startGameLive());
      }
    } else {
      await _lk.connectToLive(
        roomName: _roomName,
        isStreamer: false,
        liveId: _liveId,
      );
      if (!mounted) return;
      setState(() {
        _connected = _lk.isConnected;
        _phase = LivePhase.live;
      });
      _wireRoomEvents();
      _recordDiagnostic('Entrada como espectador concluída.');
    }
  }

  void _wireRoomEvents() {
    _roomListener = _lk.room.createListener();
    _roomListener!
      ..on<TrackSubscribedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnsubscribedEvent>((_) {
        if (mounted) setState(() {});
      });
  }

  void _onParticipantsChanged() {
    final v = _viewerCount;
    if (v > _peakViewers) _peakViewers = v;
    if (mounted) setState(() {});
  }

  /// Reflexo real do agente de reconexão do LiveKit (§16): quando o
  /// `ConnectionState` fica `reconnecting`, o overlay "Reconectando..." é
  /// exibido; ao voltar, some e o vídeo retorna sozinho.
  void _onReconnectingChanged() {
    _recordDiagnostic(
      _lk.reconnecting.value
          ? 'LiveKit reconectando automaticamente.'
          : 'LiveKit saiu do estado de reconexão.',
    );
    if (mounted) setState(() {});
  }

  void _onLiveKitError() {
    final message = _lk.lastError.value;
    if (message == null || message.isEmpty) return;
    _recordDiagnostic('LiveKit erro: $message');
    if (!mounted) return;
    setState(() {
      _connected = _lk.isConnected;
      if (!_lk.reconnecting.value) _error = message;
    });
  }

  void _onChatInserted(LiveChatMessage msg) {
    if (!mounted) return;
    if (_blockedUsers.contains(msg.userId)) return;
    if (_mutedUsers.contains(msg.userId)) return;
    setState(() {
      if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      if (_messages.length > 250) {
        _messages.removeRange(0, _messages.length - 250);
      }
    });
  }

  void _subscribeReactions() {
    try {
      _reactionsChannel = _db.client
          .channel('live-reactions-$_liveId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'live_message_reactions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'live_id',
              value: _liveId,
            ),
            callback: (payload) =>
                _onReactionChanged(payload.newRecord, added: true),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'live_message_reactions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'live_id',
              value: _liveId,
            ),
            callback: (payload) =>
                _onReactionChanged(payload.oldRecord, added: false),
          )
          .subscribe();
      _channels.add(_reactionsChannel!);
    } catch (_) {}
  }

  void _onReactionChanged(Map<dynamic, dynamic> record, {required bool added}) {
    if (!mounted) return;
    final mid = record['message_id']?.toString();
    final emoji = record['emoji']?.toString();
    if (mid == null || emoji == null || !kLiveReactionEmojis.contains(emoji)) {
      return;
    }
    setState(() {
      final m = _reactions.putIfAbsent(mid, () => {});
      final cur = (m[emoji] ?? 0) + (added ? 1 : -1);
      if (cur <= 0) {
        m.remove(emoji);
        if (m.isEmpty) _reactions.remove(mid);
      } else {
        m[emoji] = cur;
      }
    });
  }

  Future<void> _toggleReaction(LiveChatMessage msg, String emoji) async {
    final key = '${msg.id}:$emoji';
    final wasMine = _myReactions.contains(key);
    setState(() {
      if (wasMine) {
        _myReactions.remove(key);
      } else {
        _myReactions.add(key);
      }
      _burstEmoji = emoji;
    });
    _burstTimer?.cancel();
    if (!ExperienceSettings.instance.reduceAnimations) {
      _burstTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _burstEmoji = null);
      });
    }
    try {
      final res = await LivePremiumService.instance.toggleReaction(
        msg.id,
        emoji,
      );
      final removed = res['removed'] == true;
      final total = (res['total'] as num?)?.toInt();
      if (!mounted) return;
      setState(() {
        if (removed) {
          _myReactions.remove(key);
        } else {
          _myReactions.add(key);
        }
        if (total != null) {
          final m = _reactions.putIfAbsent(msg.id, () => {});
          if (removed) {
            m[emoji] = total;
            if (m[emoji] == 0) m.remove(emoji);
          } else {
            m[emoji] = total;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasMine) {
          _myReactions.add(key);
        } else {
          _myReactions.remove(key);
        }
        _burstEmoji = null;
      });
    }
  }

  void _refreshTopSupporters() async {
    try {
      final top = await LivePremiumService.instance.fetchTopSupporters(
        liveId: _liveId,
        limit: 5,
      );
      if (!mounted) return;
      setState(() => _topSupporters = top);
    } catch (_) {}
  }

  void _showRoomAlert(_RoomAlert alert) {
    if (!mounted) return;
    setState(() {
      if (_alerts.length > 2) _alerts.removeAt(0);
      _alerts.add(alert);
    });
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _alerts.remove(alert));
    });
  }

  void _openTopSupporters() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141420),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(child: _TopSupportersSheet(liveId: _liveId)),
    );
  }

  void _onGiftBroadcast(Map<String, dynamic> payload) {
    if (!mounted) return;
    final txId = payload['tx_id'] as String?;
    if (txId != null && txId == _lastGiftTxId) return;
    if (txId != null) _lastGiftTxId = txId;
    _showGiftOverlay(
      gift: Gift.fromJson(payload),
      sender: payload['sender'] as String? ?? 'Alguém',
      amount: payload['gift_amount'] as int? ?? 1,
      senderId: payload['sender_id'] as String?,
    );
  }

  void _showGiftOverlay({
    required Gift gift,
    required String sender,
    required int amount,
    String? senderId,
  }) {
    if (!mounted) return;
    setState(() {
      _activeGiftAnim = gift;
      _activeGiftSender = sender;
      _activeGiftAmount = amount;
    });
  }

  void _clearGiftOverlay() {
    if (!mounted) return;
    setState(() => _activeGiftAnim = null);
  }

  void _onChatDelete(Map<String, dynamic> payload) {
    final id = payload['message_id'] as String?;
    if (id == null || !mounted) return;
    setState(() => _messages.removeWhere((m) => m.id == id));
  }

  void _onChatEdit(Map<String, dynamic> payload) {
    final id = payload['message_id'] as String?;
    final text = payload['message'] as String?;
    if (id == null || text == null || !mounted) return;
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        if (_messages[i].id == id) {
          final old = _messages[i];
          _messages[i] = LiveChatMessage(
            id: old.id,
            liveId: old.liveId,
            userId: old.userId,
            message: text,
            createdAt: old.createdAt,
            editedAt: DateTime.now(),
            senderDisplayName: old.senderDisplayName,
            senderUsername: old.senderUsername,
            senderAvatar: old.senderAvatar,
            mine: old.mine,
          );
        }
      }
    });
  }

  void _onRoomEvent(LiveRoomEvent event) {
    if (event.type == 'LIVE_ENDED') {
      _markEnded();
      return;
    }
    final who = event.username ?? '';
    switch (event.type) {
      case 'GIFT_RECEIVED':
        final giftName = event.metadata['gift_name']?.toString() ?? 'presente';
        final giftAmount = event.metadata['gift_amount'] as num? ?? 0;
        _showRoomAlert(
          _RoomAlert(
            title: 'Presente na live!',
            subtitle: '$who enviou $giftName x$giftAmount',
            icon: Icons.card_giftcard_rounded,
            color: const Color(0xFFFFD700),
          ),
        );
        return;
      case 'FOLLOW':
        _showRoomAlert(
          _RoomAlert(
            title: 'Novo seguidor',
            subtitle: '$who começou a seguir',
            icon: Icons.favorite_rounded,
            color: const Color(0xFFFF2E4D),
          ),
        );
        return;
      case 'USER_JOINED':
        _showRoomAlert(
          _RoomAlert(
            title: 'Entrou na live',
            subtitle: '$who está assistindo',
            icon: Icons.person_add_alt_1_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        );
        return;
      case 'SHARE':
        _showRoomAlert(
          _RoomAlert(
            title: 'Compartilhou',
            subtitle: '$who compartilhou a live',
            icon: Icons.share_rounded,
            color: const Color(0xFF00E5FF),
          ),
        );
        return;
      case 'LIKE':
        _showRoomAlert(
          _RoomAlert(
            title: 'Nova curtida',
            subtitle: '$who curtiu a transmissão',
            icon: Icons.thumb_up_rounded,
            color: const Color(0xFFFFFFFF),
          ),
        );
        return;
      default:
        return;
    }
  }

  void _onLiveRowChanged(Map<String, dynamic> record) {
    final status = record['status'] as String?;
    final count = (record['viewer_count'] as num?)?.toInt();
    if (status == 'ended') {
      _markEnded();
      return;
    }
    if (count == null) return;
    if (mounted) setState(() => _live = _live.copyWith(viewerCount: count));
  }

  void _markEnded() {
    if (_ended) return;
    _ended = true;
    if (!mounted) return;
    setState(() => _live = _live.copyWith(ended: true));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        title: const Text(
          'Ao vivo encerrado',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Essa transmissão terminou.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(true);
            },
            child: const Text('OK', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  void _applyChatFilters() {
    setState(() {
      _messages.removeWhere(
        (m) =>
            _blockedUsers.contains(m.userId) || _mutedUsers.contains(m.userId),
      );
    });
  }

  void _onChatBan(Map<String, dynamic> payload) {
    final id = payload['user_id'] as String?;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _blockedUsers.add(id);
      _mutedUsers.remove(id);
    });
    _applyChatFilters();
  }

  void _onChatMute(Map<String, dynamic> payload) {
    final id = payload['user_id'] as String?;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _mutedUsers.add(id);
    });
    _applyChatFilters();
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    try {
      final msg = await _db.insertChat(_liveId, text);
      if (mounted) {
        setState(() {
          if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
        });
      }
    } on LiveChatSendException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyChatError(e))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
    }
  }

  String _friendlyChatError(LiveChatSendException e) {
    switch (e.code) {
      case 'rate_limited':
        return 'Calma! Você está enviando mensagens rápido demais.';
      case 'banned_from_live':
        return 'Você foi banido desta live.';
      case 'muted_in_live':
        return 'Você está silenciado nesta live.';
      case 'empty_message':
        return 'Digite algo para comentar.';
      case 'message_too_long':
        return 'A mensagem excede 240 caracteres.';
      case 'live_not_active':
        return 'A live não está mais ativa.';
      case 'blocked_spam':
      case 'blocked':
        return 'Conteúdo bloqueado nesta live.';
      default:
        return e.code != null && e.code!.isNotEmpty
            ? e.message
            : 'Não foi possível enviar a mensagem.';
    }
  }

  Future<void> _openModeration(LiveChatMessage msg) async {
    final isMine = msg.userId == _myId;
    final canDelete = isMine || _isModerator;
    final action = await showModalBottomSheet<_ModerationAction>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile(
              Icons.flag_rounded,
              'Denunciar mensagem',
              _ModerationAction.report,
              const Color(0xFFFFA53D),
            ),
            _sheetTile(
              Icons.block_rounded,
              'Bloquear usuário',
              _ModerationAction.block,
              Colors.white,
            ),
            _sheetTile(
              Icons.volume_off_rounded,
              'Silenciar usuário',
              _ModerationAction.silence,
              Colors.white,
            ),
            if (isMine) ...[
              _sheetTile(
                Icons.copy_rounded,
                'Copiar mensagem',
                _ModerationAction.copy,
                Colors.white,
              ),
              _sheetTile(
                Icons.edit_rounded,
                'Editar mensagem',
                _ModerationAction.edit,
                const Color(0xFF8B5CF6),
              ),
            ],
            if (canDelete && msg.userId != _myId) ...[
              _sheetTile(
                Icons.remove_circle_rounded,
                'Banir da live',
                _ModerationAction.banLive,
                _kLiveRed,
              ),
              _sheetTile(
                Icons.hearing_disabled_rounded,
                'Silenciar na live',
                _ModerationAction.muteLive,
                _kLiveRed,
              ),
            ],
            if (canDelete)
              _sheetTile(
                Icons.delete_rounded,
                'Apagar mensagem',
                _ModerationAction.delete,
                _kLiveRed,
              ),
            if (_isModerator)
              _sheetTile(
                Icons.record_voice_over_rounded,
                'Ler comentário em voz alta',
                _ModerationAction.readOutLoud,
                const Color(0xFF38BDF8),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _ModerationAction.report:
        if (msg.userId != null) {
          await SocialService.instance.reportItem(
            targetId: msg.id,
            targetType: 'comment',
            reason: 'Mensagem de chat da live',
            details: msg.message,
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mensagem denunciada. Obrigado!')),
        );
        break;
      case _ModerationAction.block:
        if (msg.userId != null) {
          await AccountService.instance.blockUser(msg.userId!);
          await SocialService.instance.logModerationAction(
            liveId: _liveId,
            action: 'block',
            reason: 'Bloqueado no chat da live',
          );
          setState(() => _blockedUsers.add(msg.userId!));
          _applyChatFilters();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário bloqueado no chat.')),
        );
        break;
      case _ModerationAction.silence:
        if (msg.userId != null) {
          await SocialService.instance.muteUser(msg.userId!);
          await SocialService.instance.logModerationAction(
            liveId: _liveId,
            action: 'mute',
            reason: 'Silenciado no chat da live',
          );
          setState(() => _mutedUsers.add(msg.userId!));
          _applyChatFilters();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário silenciado no chat.')),
        );
        break;
      case _ModerationAction.banLive:
        if (msg.userId != null) {
          await SocialService.instance.liveModBan(
            _liveId,
            msg.userId!,
            reason: 'Banido da live',
          );
          await SocialService.instance.logModerationAction(
            liveId: _liveId,
            action: 'live_ban',
            reason: 'Banido da live',
          );
          await _db.sendBroadcast(_liveId, 'chat:ban', {'user_id': msg.userId});
          setState(() {
            _blockedUsers.add(msg.userId!);
            _mutedUsers.remove(msg.userId!);
          });
          _applyChatFilters();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário banido da live.')),
        );
        break;
      case _ModerationAction.muteLive:
        if (msg.userId != null) {
          await SocialService.instance.liveModMute(
            _liveId,
            msg.userId!,
            minutes: 10,
            reason: 'Silenciado na live',
          );
          await SocialService.instance.logModerationAction(
            liveId: _liveId,
            action: 'live_mute',
            reason: 'Silenciado na live por 10 min',
          );
          await _db.sendBroadcast(_liveId, 'chat:mute', {
            'user_id': msg.userId,
          });
          setState(() => _mutedUsers.add(msg.userId!));
          _applyChatFilters();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário silenciado na live.')),
        );
        break;
      case _ModerationAction.delete:
        await _db.deleteChatMessage(msg.id);
        await _db.sendBroadcast(_liveId, 'chat:delete', {'message_id': msg.id});
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m.id == msg.id));
        }
        break;
      case _ModerationAction.copy:
        await _copyText(msg.message);
        break;
      case _ModerationAction.edit:
        await _startEditingChat(msg);
        break;
      case _ModerationAction.readOutLoud:
        await _readCommentOutLoud(msg);
        break;
    }
  }

  /// Lê um comentário em voz alta (prévia local gratuita). A transmissão aos
  /// espectadores é feita pelo bot de backend; aqui apenas confirma-se ao criador.
  Future<void> _readCommentOutLoud(LiveChatMessage msg) async {
    if (!mounted || !_isModerator) return;
    final tts = LiveBotTts.instance;
    await tts.init();
    await tts.applySettings(speed: 0.5, volume: 1.0);
    LiveBotSpeechQueue.shared().selectComment(
      msg.senderDisplayName ?? msg.senderUsername ?? 'Alguém',
      msg.message,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comentário lido em voz alta.')),
    );
  }

  Future<void> _copyText(String text) async {
    if (text.isEmpty || !mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensagem copiada.')));
  }

  Future<void> _startEditingChat(LiveChatMessage msg) async {
    if (!mounted) return;
    setState(() {
      _editingMessageId = msg.id;
      _chatController.text = msg.message;
      _chatController.selection = TextSelection.collapsed(
        offset: _chatController.text.length,
      );
    });
    _chatFocus.requestFocus();
  }

  Future<void> _cancelEditingChat() async {
    if (!mounted) return;
    setState(() {
      _editingMessageId = null;
      _chatController.clear();
    });
    _chatFocus.unfocus();
  }

  Future<void> _applyChatEdit() async {
    final id = _editingMessageId;
    if (id == null) return;
    final text = _chatController.text.trim();
    if (text.isEmpty) {
      await _cancelEditingChat();
      return;
    }
    final applied = await _db.editChat(id, text);
    if (!mounted) return;
    if (!applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Edição indisponível no momento. Tente mais tarde.'),
        ),
      );
      return;
    }
    final editedAt = DateTime.now();
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        if (_messages[i].id == id) {
          final old = _messages[i];
          _messages[i] = LiveChatMessage(
            id: old.id,
            liveId: old.liveId,
            userId: old.userId,
            message: text,
            createdAt: old.createdAt,
            editedAt: editedAt,
            senderDisplayName: old.senderDisplayName,
            senderUsername: old.senderUsername,
            senderAvatar: old.senderAvatar,
            mine: old.mine,
          );
        }
      }
      _editingMessageId = null;
      _chatController.clear();
    });
    await _db.sendBroadcast(_liveId, 'chat:edit', {
      'message_id': id,
      'message': text,
    });
    _chatFocus.unfocus();
  }

  Widget _sheetTile(
    IconData icon,
    String label,
    _ModerationAction value,
    Color color,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGiftPicker() async {
    if (widget.role == LiveRole.streamer || _myId == _live.streamerId) {
      _snack('Você não pode enviar um presente para si mesmo nesta Live.');
      return;
    }
    final gift = await showModalBottomSheet<Gift>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: _LiveGiftGrid(
          wallet: _wallet,
          onRefreshWallet: () async {
            try {
              final w = await GiftService.instance.fetchWallet();
              if (ctx.mounted) _wallet = w;
            } catch (_) {}
          },
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (gift == null || !mounted) return;
    await _pickGiftAmount(gift);
  }

  Future<void> _pickGiftAmount(Gift gift) async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${gift.icon} ${gift.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${gift.credits} créditos cada',
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Saldo: $_wallet',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [1, 5, 10, 66, 99].map((n) {
                  final ok = n * gift.credits <= _wallet;
                  return ChoiceChip(
                    label: Text(
                      'x$n',
                      style: const TextStyle(color: Colors.white),
                    ),
                    selected: false,
                    backgroundColor: const Color(0xFF2A2A35),
                    selectedColor: _kAccent,
                    onSelected: ok ? (_) => Navigator.of(ctx).pop(n) : null,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (amount == null || !mounted) return;
    await _sendGift(gift, amount);
  }

  String _giftErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('cannot_send_to_self')) {
      return 'Você não pode enviar um presente para si mesmo.';
    }
    if (raw.contains('insufficient_credits')) {
      return 'Saldo insuficiente para este presente.';
    }
    if (raw.contains('live_not_active') || raw.contains('live_not_found')) {
      return 'Esta Live não está mais ativa.';
    }
    if (raw.contains('receiver_not_streamer') ||
        raw.contains('receiver_id_required')) {
      return 'O criador desta Live não está mais disponível.';
    }
    if (raw.contains('gift_unavailable') || raw.contains('gift_not_found')) {
      return 'Este presente não está mais disponível.';
    }
    if (raw.contains('creator_earnings_failed')) {
      return 'O presente não foi concluído. Nenhum crédito foi descontado.';
    }
    if (raw.contains('duplicate_in_progress') || raw.contains('409')) {
      return 'Este presente já está sendo processado. Tente novamente em instantes.';
    }
    if (raw.contains('401') || raw.contains('unauthorized')) {
      return 'Faça login novamente para enviar o presente.';
    }
    return 'Não foi possível enviar o presente. Tente novamente.';
  }

  bool _retryGiftWithSameRequest(Object error) {
    final raw = error.toString();
    return !raw.contains('cannot_send_to_self') &&
        !raw.contains('insufficient_credits') &&
        !raw.contains('live_not_active') &&
        !raw.contains('live_not_found') &&
        !raw.contains('receiver_not_streamer') &&
        !raw.contains('gift_unavailable') &&
        !raw.contains('gift_not_found') &&
        !raw.contains('creator_earnings_failed');
  }

  Future<void> _sendGift(Gift gift, int amount) async {
    if (widget.role == LiveRole.streamer || _myId == _live.streamerId) {
      _snack('Você não pode enviar um presente para si mesmo nesta Live.');
      return;
    }
    final fingerprint = '${gift.id}:$amount';
    if (_pendingGiftFingerprint != fingerprint) {
      _pendingGiftFingerprint = fingerprint;
      _pendingGiftRequestId = null;
    }
    final requestId = _pendingGiftRequestId ??=
        '${_myId ?? 'anon'}-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final result = await GiftService.instance.sendGift(
        gift: gift,
        amount: amount,
        liveId: _liveId,
        receiverId: _live.streamerId,
        requestId: requestId,
      );
      _pendingGiftRequestId = null;
      _pendingGiftFingerprint = null;
      if (!mounted) return;
      if (result.transactionId != null) _lastGiftTxId = result.transactionId;
      setState(() {
        _wallet = result.balance;
        _walletLoaded = true;
        _walletError = null;
        _activeGiftAnim = gift;
        _activeGiftSender = kAppIdentity.displayName;
        _activeGiftAmount = amount;
      });
      _recordDiagnostic(
        'Presente ${gift.id} x$amount confirmado (${result.creditsSpent} créditos).',
      );
      if (!result.duplicate) {
        try {
          await _db.sendBroadcast(_liveId, 'gift', {
            'tx_id': result.transactionId ?? '',
            'id': gift.id,
            'name': gift.name,
            'icon': gift.icon,
            'glyph': gift.glyph,
            'animation_key': gift.animationKey,
            'effects': gift.effects,
            'is_exclusive': gift.isExclusive,
            'gift_amount': amount,
            'sender': kAppIdentity.displayName,
            'sender_id': _myId,
          });
        } catch (error) {
          _recordDiagnostic(
            'Presente confirmado, mas broadcast falhou: ${error.runtimeType}',
          );
        }
        _refreshTopSupporters();
      }
    } on GiftDuplicateInProgressException {
      _recordDiagnostic('Presente em processamento; mantendo idempotência.');
      if (!mounted) return;
      _snack('Presente já em processamento. Aguarde e tente de novo.');
    } catch (error) {
      if (!_retryGiftWithSameRequest(error)) {
        _pendingGiftRequestId = null;
        _pendingGiftFingerprint = null;
      }
      _recordDiagnostic('Falha ao enviar presente: ${error.runtimeType}');
      if (!mounted) return;
      _snack(_giftErrorMessage(error));
    }
  }

  Future<void> _toggleLike() async {
    setState(() => _liked = !_liked);
    await _db.logEvent(_liveId, 'LIKE');
  }

  Future<void> _toggleFollow() async {
    final wasFollowing = _following;
    setState(() => _following = !_following);
    try {
      final svc = ContentService.instance;
      if (wasFollowing) {
        await svc.unfollowUser(_live.streamerId);
      } else {
        await svc.followUser(_live.streamerId);
      }
      await _db.logEvent(_liveId, 'FOLLOW');
    } catch (e) {
      setState(() => _following = wasFollowing);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(
          _following
              ? 'Você começou a seguir a live!'
              : 'Você deixou de seguir a live.',
        ),
      ),
    );
  }

  Future<void> _share() async {
    final url = 'https://klayk.app/live/$_roomName';
    await Share.share(url, subject: _live.title);
    await _db.logEvent(_liveId, 'SHARE');
  }

  /// Abre o perfil REAL do criador (dados do backend — nunca inventados).
  void _openStreamerProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(userId: _live.streamerId),
      ),
    );
  }

  Future<void> _toggleCamera() async {
    if (_camOn) {
      await _lk.stopCamera();
    } else {
      await _lk.publishCamera();
    }
    if (!mounted) return;
    setState(() => _camOn = _lk.cameraInUse);
    _recordDiagnostic('Câmera alternada: $_camOn.');
  }

  Future<void> _toggleMicrophone() async {
    if (_micOn) {
      await _lk.stopMicrophone();
    } else {
      await _lk.publishMicrophone();
    }
    if (!mounted) return;
    setState(() => _micOn = _lk.micInUse);
    _recordDiagnostic('Microfone alternado: $_micOn.');
  }

  Future<void> _toggleScreenShare() async {
    final next = !_shareOn;
    try {
      if (next) {
        await _lk.setScreenShareEnabled(true);
      } else {
        await _lk.stopScreenShare();
      }
      if (!mounted) return;
      setState(() => _shareOn = _lk.localScreenSharePublished);
      _recordDiagnostic(
        'Compartilhamento de tela: $_shareOn (áudio ${_lk.localScreenShareAudioPublished}).',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            _shareOn
                ? 'Compartilhando sua tela. Escolha a aba/janela e toque em iniciar.'
                : 'Compartilhamento de tela desativado.',
          ),
        ),
      );
    } catch (error) {
      _recordDiagnostic('Falha na captura de tela: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível compartilhar a tela. Verifique a permissão.',
            ),
          ),
        );
      }
    }
  }

  /// Fluxo de Live de Jogo (streamer): solicita a permissão de exibição sobre
  /// outros apps, informa que a tela será compartilhada, inicia a captura de
  /// tela oficial do Android (via LiveKit/flutter_webrtc) e sobe a bolinha
  /// flutuante de controles.
  /// Prepara o estado ANTES de uma Live de Jogo: pede a permissão de overlay
  /// (bolinha sobre outros apps) e registra os controles do painel. A captura
  /// de tela em si só começa quando o usuário toca em "INICIAR TRANSMISSÃO"
  /// no overlay de pronto (estado DURANTE), via [_toggleScreenShareOn].
  Future<void> _startGameLive() async {
    if (widget.role != LiveRole.streamer || !widget.isGameLive) return;

    // 1. Permissão de overlay (SYSTEM_ALERT_WINDOW) — explicando o motivo.
    //    Tenta iniciar; se faltar permissão, abre o guia de configurações e,
    //    quando o usuário voltar, tenta de novo — assim a bolinha aparece
    //    assim que a permissão é concedida.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      final granted = await KlayLiveGameOverlay.instance.start();
      if (granted) break;
      final go = await _requestOverlayPermission();
      if (go != true || !mounted) return;
    }
    if (!mounted) return;

    // 2. Registra os controles do painel → LiveKit real.
    KlayLiveGameOverlay.instance.listen(_onOverlayAction);

    // 3. Permanece no estado ANTES (waiting); o overlay "Pronto" pede o
    //    "INICIAR TRANSMISSÃO" antes de começar a captura de tela.
  }

  Future<void> _toggleScreenShareOn() async {
    try {
      await _lk.setScreenShareEnabled(true);
      if (mounted) {
        setState(() {
          _shareOn = _lk.localScreenSharePublished;
          // DURANTE: começa oficialmente a live de jogo (captura no ar).
          if (_shareOn) _phase = LivePhase.live;
        });
        _recordDiagnostic(
          'Captura de tela iniciada: $_shareOn (áudio ${_lk.localScreenShareAudioPublished}).',
        );
      }
    } catch (error) {
      _recordDiagnostic('Falha ao iniciar captura: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível iniciar a captura de tela. Verifique a permissão.',
            ),
          ),
        );
      }
    }
  }

  /// Roteia ações vindas do painel da bolinha flutuante para o LiveKit e a UI.
  void _onOverlayAction(String action, Map<String, dynamic>? payload) {
    switch (action) {
      case 'micToggled':
        _setMicFromOverlay(payload?['enabled'] as bool? ?? !_micOn);
        break;
      case 'pauseToggled':
        _setPausedFromOverlay(payload?['paused'] as bool? ?? false);
        break;
      case 'voiceBotToggled':
        // O bot de voz real fica em um serviço externo; aqui apenas refletimos
        // a preferência no painel (a integração de STT/TTS é plugável).
        _voiceBotOn = payload?['enabled'] as bool? ?? !_voiceBotOn;
        if (mounted) setState(() {});
        break;
      case 'endRequested':
        _endLive();
        break;
      case 'morePressed':
        _showOverlayMoreOptions();
        break;
      case 'chatRequested':
        _openChatFromOverlay();
        break;
    }
  }

  /// Abre o chat da live a partir da bolinha flutuante.
  Future<void> _openChatFromOverlay() async {
    // Garante que o app venha para o primeiro plano antes de exibir o chat.
    await _bringAppToFront();
    if (!mounted) return;
    setState(() => _chatOpen = true);
  }

  /// Traz o KLAY K para o primeiro plano de forma segura (usado quando o
  /// usuário abre o chat a partir da bolinha enquanto joga em outro app).
  Future<void> _bringAppToFront() async {
    try {
      await const MethodChannel(
        'klayk/live_game_overlay',
      ).invokeMethod('bringToFront');
    } catch (_) {}
  }

  Future<void> _setMicFromOverlay(bool on) async {
    try {
      if (on) {
        await _lk.publishMicrophone();
      } else {
        await _lk.stopMicrophone();
      }
      if (!mounted) return;
      setState(() => _micOn = _lk.micInUse);
      _recordDiagnostic('Mic via overlay: $_micOn.');
    } catch (error) {
      _recordDiagnostic('Falha no mic via overlay: ${error.runtimeType}');
    }
  }

  Future<void> _setPausedFromOverlay(bool paused) async {
    // "Pausar" a transmissão: desliga câmera+mic+share localmente (simula) e
    // informa o painel. O fluxo de pausa real despublica as mídias; aqui
    // desligamos mic/share para evitar captura de POSTERIOR e mantemos a sala.
    try {
      if (paused) {
        await _lk.stopMicrophone();
        await _lk.stopScreenShare();
        if (mounted) {
          setState(() {
            _micOn = _lk.micInUse;
            _shareOn = _lk.localScreenSharePublished;
          });
        }
      } else {
        await _lk.publishMicrophone();
        if (widget.isGameLive) await _lk.setScreenShareEnabled(true);
        if (mounted) {
          setState(() {
            _micOn = _lk.micInUse;
            _shareOn = _lk.localScreenSharePublished;
          });
        }
      }
      _recordDiagnostic('Overlay pausado=$paused; estado sincronizado.');
    } catch (error) {
      _recordDiagnostic('Falha ao pausar/retomar: ${error.runtimeType}');
    }
  }

  Future<void> _showOverlayMoreOptions() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Mais opções da Live de Jogo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: _kAccent),
              title: const Text('Chat', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(ctx).pop();
                if (mounted) setState(() => _chatOpen = true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: _kAccent),
              title: const Text(
                'Configurações da live',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _openGameSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGameSettings() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        title: const Text(
          'Configurações da live',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              value: _voiceBotOn,
              onChanged: (v) {
                setState(() => _voiceBotOn = v);
                KlayLiveGameOverlay.instance.setVoiceBot(v);
              },
              activeThumbColor: _kAccent,
              title: const Text(
                'Bot de voz',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Ligar/desligar assitência por voz',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            if (_isModerator) ...[
              const Divider(color: Color(0xFF2A2540), height: 1),
              ListTile(
                leading: const Icon(Icons.smart_toy_rounded, color: _kAccent),
                title: const Text(
                  'KLAY K LIVE BOT',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Painel completo de voz, comentários, moderação e anúncios',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openLiveBotPanel();
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Fechar',
              style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre o painel premium do KLAY K LIVE BOT (apenas criador/moderador).
  Future<void> _openLiveBotPanel() async {
    if (!mounted) return;
    await LiveBotPanel.show(
      context,
      liveId: _liveId,
      canModerate: _isModerator,
    );
  }

  /// Abre o guia de permissão de overlay. Retorna `true` se o usuário escolheu
  /// "Abrir configurações" (para o chamador tentar iniciar de novo depois).
  Future<bool?> _requestOverlayPermission() async {
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        icon: const Icon(
          Icons.settings_suggest_rounded,
          color: _kAccent,
          size: 36,
        ),
        title: const Text(
          'Permitir exibição sobre outros apps',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Para mostrar a bolinha 🎮 de controles da live de jogo sobre outros '
          'aplicativos, o KLAY K precisa da permissão "Exibir sobre outros '
          'apps". Você pode concedê-la nas configurações do sistema.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Agora não',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            child: const Text(
              'Abrir configurações',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (go == true) {
      await KlayLiveGameOverlay.instance.openOverlaySettings();
    }
    return go;
  }

  Future<void> _toggleViewerVideo() async {
    final on = !_videoListenOn;
    for (final p in _lk.guests) {
      for (final pub in p.videoTrackPublications) {
        if (on && !pub.subscribed) {
          await pub.subscribe();
        } else if (!on && pub.subscribed) {
          await pub.unsubscribe();
        }
      }
    }
    setState(() => _videoListenOn = on);
  }

  Future<void> _toggleViewerAudio() async {
    final on = !_audioListenOn;
    for (final p in _lk.guests) {
      for (final pub in p.audioTrackPublications) {
        if (on && !pub.subscribed) {
          await pub.subscribe();
        } else if (!on && pub.subscribed) {
          await pub.unsubscribe();
        }
      }
    }
    setState(() => _audioListenOn = on);
  }

  Future<void> _endLive() async {
    if (widget.role != LiveRole.streamer) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        title: const Text(
          'Encerrar live',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Todos os espectadores serão desconectados.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Encerrar', style: TextStyle(color: _kLiveRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _db.endLive(_liveId);
      _recordDiagnostic('Backend confirmou encerramento da Live.');
    } catch (error) {
      _recordDiagnostic('Falha ao encerrar no backend: ${error.runtimeType}');
    }
    if (widget.isGameLive) {
      await _lk.stopScreenShare();
      await KlayLiveGameOverlay.instance.stop();
    }
    await _lk.disconnectFromLive();
    await _db.recordParticipantLeft(_liveId);
    if (!mounted) return;
    // DEPOIS: entra na fase de recap (estatísticas da live encerrada). O
    // usuário fecha pela tela de recap (ou pop normal em lives não-jogo).
    setState(() {
      _ended = true;
      _phase = LivePhase.ended;
    });
    if (!widget.isGameLive) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _burstTimer?.cancel();
    _roomListener?.dispose();
    _lk.participantsCount.removeListener(_onParticipantsChanged);
    _lk.reconnecting.removeListener(_onReconnectingChanged);
    _lk.lastError.removeListener(_onLiveKitError);
    _chatController.dispose();
    _chatFocus.dispose();
    if (_myId != null) {
      unawaited(_db.recordParticipantLeft(_liveId));
    }
    unawaited(_lk.disconnectFromLive());
    if (widget.isGameLive) {
      KlayLiveGameOverlay.instance.stopListening();
      unawaited(KlayLiveGameOverlay.instance.stop());
    }
    for (final c in _channels) {
      _db.removeChannel(c);
    }
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      // Crítico para o composer ficar embaixo. O padrão (true) faz o Scaffold
      // encolher o body inteiro pela altura do teclado; como o composer também
      // sobe por `bottom: viewInsets`, a compensação acontecia duas vezes e o
      // campo "Diga algo" aparecia no meio da LIVE em vez de logo acima do
      // teclado. Com false o body (e o vídeo) mantêm o tamanho e só o composer
      // sobe, pela altura exata do teclado.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoLayer(),
          _buildGradientScrim(),
          // Tocar fora do composer fecha o teclado e desativa o composer.
          //
          // Fica ACIMA do vídeo (então tocar no vídeo fecha o composer em vez
          // de alternar o vídeo) e ABAIXO da barra superior e dos botões
          // laterais (então continuar/X/like/share seguem funcionando enquanto
          // se comenta). Não é uma barreira que engole a tela.
          if (_chatOpen)
            Positioned.fill(
              // O rodapé sobe com o teclado e tem altura variável, então a
              // área de toque para fora vai do topo dele até o topo da tela.
              // Medir em runtime (e não um número fixo) garante que a lista
              // e a barra continuem clicáveis em qualquer estado.
              bottom:
                  MediaQuery.of(context).viewInsets.bottom +
                  (_chatOverlayHeight ?? 0),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeChatField,
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildInfoRow(),
                ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 70, bottom: 12),
                  child: _buildMiniActions(),
                ),
              ),
            ),
          ),
          if (_activeGiftAnim != null)
            Positioned.fill(
              child: GiftAnimationOverlay(
                gift: _activeGiftAnim!,
                senderName: _activeGiftSender,
                amount: _activeGiftAmount,
                onComplete: _clearGiftOverlay,
              ),
            ),
          if (_burstEmoji != null &&
              !ExperienceSettings.instance.reduceAnimations)
            Positioned.fill(
              child: IgnorePointer(
                child: _ReactionBurstOverlay(emoji: _burstEmoji!),
              ),
            ),
          if (_alerts.isNotEmpty) _buildAlertsLayer(),
          if (_live.gameName != null && _live.gameName!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).size.height * 0.18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      '🎮 ${_live.gameName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // O rodapé é sempre visível: a barra fica na borda inferior e a lista
          // cresce de baixo para cima. Só a ativação do composer é condicional.
          _buildChatOverlay(),
          if (_buildingConnecting()) _buildConnectingOverlay(),
          if (_buildingReconnecting()) _buildReconnectingOverlay(),
          if (_error != null) _buildErrorOverlay(_error!),
          if (_shouldShowWaitingReady()) _buildGameReadyOverlay(),
          if (_phase == LivePhase.ended && !_recapDismissed)
            _buildRecapOverlay(),
        ],
      ),
    );
  }

  /// Estado de conexão real §16: mostrando "Conectando à Live..." enquanto a
  /// sala ainda não conectou no LiveKit (viewer). No streamer o overlay de
  /// "INICIAR TRANSMISSÃO" já cobre o estado de preparação.
  bool _buildingConnecting() {
    if (_error != null) return false;
    if (_ended || _phase == LivePhase.ended) return false;
    return widget.role == LiveRole.viewer && !_connected;
  }

  Widget _buildConnectingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _kAccent),
              const SizedBox(height: 14),
              const Text(
                'Conectando à Live...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _live.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estado de reconexão real §16: reflexo do `ConnectionState.reconnecting`
  /// do livekit_client (que faz auto-reconnect interno).
  bool _buildingReconnecting() {
    if (_error != null) return false;
    if (_ended || _phase == LivePhase.ended) return false;
    return _lk.reconnecting.value;
  }

  Widget _buildReconnectingOverlay() {
    return const Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _kAccent),
              SizedBox(height: 14),
              Text(
                'Reconectando...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'A conexão caiu e estamos tentando restabelecê-la.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Overlay de estado ANTES (aguardando início) para uma Live de Jogo do
  /// streamer: avisa que a captura está em preparação e pede confirmação.
  bool _shouldShowWaitingReady() {
    return widget.isGameLive &&
        widget.role == LiveRole.streamer &&
        _phase == LivePhase.waiting &&
        _connected;
  }

  Widget _buildGameReadyOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.screen_share_rounded,
                    color: _kAccent,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Live de Jogo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sua tela será compartilhada ao vivo com os espectadores.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  '🎮 ${_live.gameName ?? _live.title}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _toggleScreenShareOn,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    minimumSize: const Size(220, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    '🔴 INICIAR TRANSMISSÃO',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Sair sem transmitir',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Overlay de estado DEPOIS (recap) — estatísticas da live encerrada.
  Widget _buildRecapOverlay() {
    final duration = DateTime.now().difference(_joinedAt);
    final minutes = duration.inMinutes;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final timeLabel = h > 0
        ? '$h h ${m.toString().padLeft(2, '0')} min'
        : '$m min';
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF22C55E),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Live encerrada',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _live.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                _recapStat('⏱️ Duração', timeLabel),
                const SizedBox(height: 10),
                _recapStat('👥 Pico de espectadores', '$_peakViewers'),
                if (widget.isGameLive) ...[
                  const SizedBox(height: 10),
                  _recapStat('🎮 Jogo', _live.gameName ?? '—'),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    setState(() => _recapDismissed = true);
                    Navigator.of(context).pop(true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    minimumSize: const Size(220, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Concluir',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recapStat(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsLayer() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 12,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _alerts.reversed.map((a) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xE6191924),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: a.color.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: a.color.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(a.icon, color: a.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        a.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (_error != null) return const SizedBox.shrink();
    Widget content;
    if (widget.role == LiveRole.streamer) {
      final track = _lk.localVideoTrack;
      content = track != null
          ? VideoTrackRenderer(track, fit: VideoViewFit.cover)
          : _buildPlaceholder('Você está ao vivo', Icons.videocam_rounded);
    } else {
      final primary = _lk.primaryRemoteVideo;
      VideoTrack? track;
      if (primary != null) {
        for (final pub in primary.videoTrackPublications) {
          if (pub.subscribed && !pub.muted && pub.track is VideoTrack) {
            track = pub.track as VideoTrack;
            break;
          }
        }
      }
      content = track != null
          ? VideoTrackRenderer(track, fit: VideoViewFit.cover)
          : _buildPlaceholder('Aguardando sinal...', Icons.tv_rounded);
    }
    return GestureDetector(
      onDoubleTap: widget.role == LiveRole.viewer ? _toggleLike : null,
      onTap: _toggleViewerVideo,
      child: content,
    );
  }

  Widget _buildPlaceholder(String text, IconData icon) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1226), Color(0xFF0D0D14)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _kAccent.withValues(alpha: 0.8), size: 56),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientScrim() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
            Colors.transparent,
            Colors.black87,
          ],
          stops: [0, 0.3, 0.6, 1],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(false),
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _kLiveRed,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: _kLiveRed.withValues(alpha: 0.6),
                blurRadius: 10,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: Colors.white, size: 8),
              SizedBox(width: 4),
              Text(
                'AO VIVO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.group_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$_viewerCount espectadores',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_live.category.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      _live.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.role == LiveRole.streamer)
          PopupMenuButton<String>(
            color: const Color(0xFF1C1C26),
            onSelected: (v) {
              if (v == 'end') _endLive();
              if (v == 'diagnostics') _openDiagnostics();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'end',
                child: Row(
                  children: [
                    Icon(Icons.stop_circle_rounded, color: _kLiveRed),
                    SizedBox(width: 8),
                    Text('Encerrar live', style: TextStyle(color: _kLiveRed)),
                  ],
                ),
              ),
              if (kDebugMode)
                const PopupMenuItem(
                  value: 'diagnostics',
                  child: Row(
                    children: [
                      Icon(Icons.monitor_heart_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Diagnóstico da Live',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 24,
            ),
          )
        else
          PopupMenuButton<String>(
            color: const Color(0xFF1C1C26),
            onSelected: _onViewerMenuSelected,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Compartilhar Live',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Copiar link', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(
                      _audioListenOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _audioListenOn ? 'Silenciar' : 'Ativar áudio',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, color: Color(0xFFFFA53D)),
                    SizedBox(width: 8),
                    Text('Denunciar', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Bloquear usuário',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: _kLiveRed),
                    SizedBox(width: 8),
                    Text('Sair da Live', style: TextStyle(color: _kLiveRed)),
                  ],
                ),
              ),
              if (kDebugMode)
                const PopupMenuItem(
                  value: 'diagnostics',
                  child: Row(
                    children: [
                      Icon(Icons.monitor_heart_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Diagnóstico da Live',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// Ações reais do menu ⋮ do espectador. Somente funções implementadas no
  /// backend/plataforma são oferecidas (§8/§9).
  Future<void> _onViewerMenuSelected(String value) async {
    switch (value) {
      case 'share':
        await _share();
        break;
      case 'copy':
        final url = 'https://klayk.app/live/$_roomName';
        await Clipboard.setData(ClipboardData(text: url));
        _snack('Link da live copiado.');
        break;
      case 'mute':
        await _toggleViewerAudio();
        break;
      case 'report':
        await SocialService.instance.reportItem(
          targetId: _liveId,
          targetType: 'live',
          reason: 'Live reportada pelo espectador',
          details: _live.title,
        );
        _snack('Denúncia enviada. Obrigado!');
        break;
      case 'block':
        await AccountService.instance.blockUser(_live.streamerId);
        _snack('Usuário bloqueado.');
        break;
      case 'diagnostics':
        await _openDiagnostics();
        break;
      case 'leave':
        if (mounted) Navigator.of(context).pop(true);
        break;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildInfoRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _openStreamerProfile,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: _kAccent.withValues(alpha: 0.3),
              backgroundImage: _live.streamerAvatar != null
                  ? NetworkImage(_live.streamerAvatar!)
                  : null,
              child: const Icon(Icons.person, color: Colors.white70, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _openStreamerProfile,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _live.streamerDisplayName ?? _live.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_live.streamerUsername != null &&
                          _live.streamerUsername!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '@${_live.streamerUsername}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _live.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_live.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _live.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (_live.hashtags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _live.hashtags.map((h) => '#$h').join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniAction(
          Icons.people_rounded,
          '$_viewerCount',
          () => _openParticipants(),
        ),
        _miniAction(
          _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          'Curtir',
          _toggleLike,
          color: _liked ? _kLiveRed : Colors.white,
        ),
        _miniAction(
          Icons.chat_bubble_rounded,
          'Comentários',
          _toggleChatField,
          color: _chatOpen ? _kAccent : Colors.white,
        ),
        _miniAction(
          Icons.card_giftcard_rounded,
          'Presente',
          _openGiftPicker,
          color: const Color(0xFFFFA53D),
        ),
        _miniAction(
          _topSupporters.isEmpty
              ? Icons.emoji_events_rounded
              : Icons.emoji_events,
          'Top',
          _openTopSupporters,
          color: _topSupporters.isNotEmpty
              ? const Color(0xFFFFD700)
              : Colors.white,
        ),
        _miniAction(Icons.share_rounded, 'Compartilhar', _share),
        if (widget.role == LiveRole.streamer) ...[
          _miniAction(
            _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            _camOn ? 'Câmera' : 'Off',
            _toggleCamera,
            color: _camOn ? _kAccent : Colors.white54,
          ),
          _miniAction(
            _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            _micOn ? 'Mic' : 'Off',
            _toggleMicrophone,
            color: _micOn ? _kAccent : Colors.white54,
          ),
          _miniAction(
            Icons.screen_share_rounded,
            _shareOn ? 'Tela' : 'Tela',
            _toggleScreenShare,
            color: _shareOn ? _kAccent : Colors.white54,
          ),
        ] else ...[
          _miniAction(
            _videoListenOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            _videoListenOn ? 'Vídeo' : 'Off',
            _toggleViewerVideo,
            color: _videoListenOn ? _kAccent : Colors.white54,
          ),
          _miniAction(
            _audioListenOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            _audioListenOn ? 'Áudio' : 'Off',
            _toggleViewerAudio,
            color: _audioListenOn ? _kAccent : Colors.white54,
          ),
        ],
        const SizedBox(height: 28),
        GestureDetector(
          onTap: _toggleFollow,
          child: Column(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _following ? Colors.black54 : _kAccent,
                child: Icon(
                  _following ? Icons.check_rounded : Icons.add_rounded,
                  color: _following ? _kAccent : Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Seguir',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _miniAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, color: color ?? Colors.white, size: 28),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _openParticipants() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Participantes',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _kAccent.withValues(alpha: 0.4),
                    backgroundImage: _live.streamerAvatar != null
                        ? NetworkImage(_live.streamerAvatar!)
                        : null,
                    child: const Icon(
                      Icons.person,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_live.streamerDisplayName ?? 'Streamer'} (host)',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
              ..._lk.guests.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: _kAccent.withValues(alpha: 0.3),
                        child: Text(
                          (p.name.isNotEmpty
                                  ? String.fromCharCodes(p.name.runes.take(1))
                                  : '?')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        p.name.isNotEmpty ? p.name : p.identity,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_lk.guests.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Nenhum espectador no momento.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rodapé da LIVE: lista de comentários + barra do composer.
  ///
  /// Posicionamento (a única coisa alterada aqui):
  ///  * a lista de mensagens fica sobre a REGIÃO INFERIOR do vídeo e cresce de
  ///    baixo para cima — nunca no centro da tela, nunca no topo;
  ///  * a barra do composer é fixa na borda inferior da LIVE, com o campo
  ///    "Diga algo" na horizontal e os botões de emoji e envio dentro dela;
  ///  * com o teclado aberto o conjunto sobe e fica ancorado logo acima dele,
  ///    sem reorganizar mais nada;
  ///  * com o teclado fechado volta para a borda inferior.
  ///
  /// Não é painel, janela central, caixa no topo nem tela separada.
  Widget _buildChatOverlay() {
    // Medido depois do frame, quando a altura final já está definida.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChatOverlay());

    // IMPORTANTE: este método é chamado direto como filho do `Stack`, então o
    // `Positioned` tem que ser retornado na raiz. Envolver em `LayoutBuilder`
    // (ou qualquer outro widget) quebra o posicionamento: o Stack deixa de
    // ver o `Positioned`, passa a tratar o filho como comum e o composer
    // aparece no TOPO da tela em vez de fixado embaixo.
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    // Só sobe quando o composer está ativo e há teclado na tela.
    final bottomInset = _chatOpen && viewInsets > 0
        ? viewInsets.toDouble()
        : 0.0;

    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: bottomInset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: PopScope(
        // O primeiro Voltar do Android fecha teclado/composer; só um
        // segundo Voltar executa a ação normal de sair da LIVE.
        canPop: !_chatOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _closeChatField();
        },
        child: SafeArea(
          top: false,
          // Com o teclado aberto quem cuida da borda de baixo é o teclado.
          bottom: bottomInset == 0,
          child: Column(
            key: _chatOverlayKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_buildChatMessageList(), _buildComposerBar()],
          ),
        ),
      ),
    );
  }

  /// Comentários recebidos em tempo real, sobre a região inferior da LIVE.
  ///
  /// `reverse: true` com índice invertido põe a mensagem mais nova na borda de
  /// baixo, encostada no composer — assim o texto nunca fica por cima do campo
  /// de digitação — e as anteriores sobem. O teto de altura impede que a lista
  /// vire o centro da tela.
  Widget _buildChatMessageList() {
    if (_messages.isEmpty) return const SizedBox.shrink();
    final total = _messages.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 210),
      child: ListView.builder(
        reverse: true,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        itemCount: total,
        itemBuilder: (context, index) {
          final m = _messages[total - 1 - index];
          return GestureDetector(
            onLongPress: () => _openModeration(m),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: _kAccent.withValues(alpha: 0.35),
                    backgroundImage: m.senderAvatar != null
                        ? NetworkImage(m.senderAvatar!)
                        : null,
                    child: const Icon(
                      Icons.person,
                      color: Colors.white70,
                      size: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                m.senderDisplayName ??
                                    m.senderUsername ??
                                    'Alguém',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (m.senderVerified) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(size: 11),
                            ],
                            const SizedBox(width: 6),
                            Text(
                              _timeLabel(m.createdAt),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          m.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.3,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 4),
                            ],
                          ),
                        ),
                        _buildMessageReactions(m),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Barra fixa inferior: campo "Diga algo" na horizontal + emoji + envio.
  ///
  /// Só o campo e os dois botões. "Comentários" e "Presente" continuam nos
  /// controles laterais da direita (_buildMiniActions) e não são duplicados
  /// aqui — não existe segunda barra de comentários.
  Widget _buildComposerBar() {
    final editing = _editingMessageId != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xB3121018),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 92),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _chatController,
                focusNode: _chatFocus,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: _kAccent,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => editing ? _applyChatEdit() : _sendChat(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: editing ? 'Editando comentário' : 'Diga algo',
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _pickComposerEmoji,
            icon: const Icon(
              Icons.emoji_emotions_outlined,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Emoji',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: editing ? _applyChatEdit : _sendChat,
            icon: const Icon(Icons.send_rounded, color: _kAccent, size: 22),
            tooltip: 'Enviar',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Emoji do composer. Reusa a mesma lista e o mesmo visual do seletor de
  /// reação (_openEmojiPicker) — nenhum sistema novo.
  Future<void> _pickComposerEmoji() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: kLiveReactionEmojis
                .map(
                  (e) => InkWell(
                    onTap: () => Navigator.of(ctx).pop(e),
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (!mounted || emoji == null) return;
    _chatFocus.requestFocus();
    _chatController.text = '${_chatController.text}$emoji';
    _chatController.selection = TextSelection.collapsed(
      offset: _chatController.text.length,
    );
  }

  /// Ativa ou desativa o composer inferior. Chamado pelo botão "Comentários"
  /// dos controles laterais.
  void _toggleChatField() {
    if (_chatOpen) {
      _closeChatField();
      return;
    }
    setState(() => _chatOpen = true);
    _chatFocus.requestFocus();
  }

  /// Tocar fora do composer (ou o Voltar do Android) fecha o teclado e
  /// desativa o composer.
  void _closeChatField() {
    // A limpeza vem antes de soltar o foco: o listener ajusta `_chatOpen`
    // durante o `unfocus`, e depois disso a condição abaixo não valeria mais.
    if (_chatOpen || _editingMessageId != null) {
      setState(() {
        _chatOpen = false;
        // Sem isto um "editar" antigo continuaria valendo e o próximo envio
        // editaria a mensagem antiga em vez de publicar uma nova.
        _editingMessageId = null;
        _chatController.clear();
      });
    }
    _chatFocus.unfocus();
  }

  /// Mantém o estado do composer em sincronia com o foco do campo.
  void _onChatFocusChanged() {
    final focused = _chatFocus.hasFocus;
    if (focused == _chatOpen || !mounted) return;
    setState(() => _chatOpen = focused);
  }

  /// Altura real do rodapé (lista + barra), usada pela área de "tocar fora".
  ///
  /// Só chama `setState` quando o valor muda de fato, senão
  /// build → postFrame → setState → build vira laço.
  void _measureChatOverlay() {
    final size = _chatOverlayKey.currentContext?.size;
    if (size == null || size.height <= 0) return;
    final current = _chatOverlayHeight;
    if (current != null && (size.height - current).abs() < 0.5) return;
    if (!mounted) return;
    setState(() => _chatOverlayHeight = size.height);
  }

  String _timeLabel(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildMessageReactions(LiveChatMessage m) {
    final counts = _reactions[m.id];
    final hasAny = counts != null && counts.isNotEmpty;
    final chips = <Widget>[
      for (final emoji in kLiveReactionEmojis)
        if (counts != null && counts.containsKey(emoji))
          _reactionChip(m, emoji, counts[emoji]!),
      _reactionQuickAdd(m, hasAny),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _reactionChip(LiveChatMessage m, String emoji, int total) {
    final mine = _myReactions.contains('${m.id}:$emoji');
    return InkWell(
      onTap: () => _toggleReaction(m, emoji),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? _kAccent.withValues(alpha: 0.35) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: mine ? _kAccent : Colors.white24),
        ),
        child: Text(
          '$emoji $total',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }

  Widget _reactionQuickAdd(LiveChatMessage m, bool hasAny) {
    if (hasAny) return const SizedBox.shrink();
    return InkWell(
      onTap: () => _openEmojiPicker(m),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: const Text(
          '+ 😍',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
    );
  }

  Future<void> _openEmojiPicker(LiveChatMessage m) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: kLiveReactionEmojis.map((e) {
              return InkWell(
                onTap: () => Navigator.of(ctx).pop(e),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    await _toggleReaction(m, emoji);
  }

  Widget _buildErrorOverlay(String error) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, color: _kLiveRed, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'Não foi possível conectar à Live',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _retryJoin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    minimumSize: const Size(200, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'Tentar novamente',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Sair da Live',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Nova tentativa de conexão real: limpa o erro local, desconecta o que
  /// pôde ter ficado parado e refaz o join (sem duplicar canais — a rotina
  /// _join sempre desconecta antes de reconectar).
  Future<void> _retryJoin() async {
    _lk.participantsCount.removeListener(_onParticipantsChanged);
    _lk.reconnecting.removeListener(_onReconnectingChanged);
    _lk.lastError.removeListener(_onLiveKitError);
    for (final channel in _channels) {
      _db.removeChannel(channel);
    }
    _channels.clear();
    _reactionsChannel = null;
    setState(() {
      _error = null;
      _connected = false;
      _chatRealtimeReady = false;
      _liveRealtimeReady = false;
      _realtimeError = null;
      _subscribedRealtimeChannels = 0;
    });
    await _lk.disconnectFromLive();
    if (!mounted) return;
    await _join();
  }
}

/// Grade de presentes reais dentro do seletor da live. Lazy load + paginação
/// via `GiftService` (fonte: backend, nada de mock). Toca num item → devolve o
/// presente escolhido para a tela da live.
class _RoomAlert {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _RoomAlert({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _LiveGiftGrid extends StatefulWidget {
  final int wallet;
  final Future<void> Function() onRefreshWallet;
  final VoidCallback onClose;

  const _LiveGiftGrid({
    required this.wallet,
    required this.onRefreshWallet,
    required this.onClose,
  });

  @override
  _LiveGiftGridState createState() => _LiveGiftGridState();
}

class _LiveGiftGridState extends State<_LiveGiftGrid> {
  final _scroll = ScrollController();
  final List<Gift> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String? _error;
  String _filter = 'todos';
  static const _pageSize = 40;

  static const _filters = [
    (id: 'todos', label: 'Todos'),
    (id: 'popular', label: 'Popular'),
    (id: 'exclusivo', label: 'Exclusivo'),
    (id: 'barato', label: 'Barato'),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      if (_hasMore) _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loadingMore) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      setState(() {
        _items.clear();
        _loading = true;
        _error = null;
      });
    } else {
      _page += 1;
      setState(() => _loadingMore = true);
    }
    try {
      final gift = GiftService.instance;
      List<Gift> newItems;
      switch (_filter) {
        case 'popular':
          newItems = await gift.fetchPopular(limit: _pageSize);
          _hasMore = false;
        case 'exclusivo':
          newItems = await gift.fetchExclusives(limit: _pageSize);
          _hasMore = false;
        case 'barato':
          // "Barato": todos em ordem de preço (da página corrente).
          newItems = await gift.fetchGifts(page: _page, pageSize: _pageSize);
          _hasMore = newItems.length >= _pageSize;
          newItems.sort((a, b) => a.credits.compareTo(b.credits));
        default:
          newItems = await gift.fetchGifts(page: _page, pageSize: _pageSize);
          _hasMore = newItems.length >= _pageSize;
      }
      if (!mounted) return;
      setState(() {
        _items.addAll(newItems);
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.68;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '🎁 Presentes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '🪙 ${widget.wallet}',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: widget.onClose,
                visualDensity: VisualDensity.compact,
                tooltip: 'Fechar',
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        f.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      selected: _filter == f.id,
                      selectedColor: _kAccent,
                      backgroundColor: const Color(0xFF2A2A35),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        if (_filter == f.id) return;
                        setState(() => _filter = f.id);
                        _load(reset: true);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Text(
          'Não foi possível carregar os presentes.\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum presente disponível.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final g = _items[index];
        final afford = widget.wallet >= g.credits;
        return InkWell(
          onTap: () => Navigator.of(context).pop(g),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF23232E),
              borderRadius: BorderRadius.circular(12),
              border: g.isExclusive
                  ? Border.all(color: const Color(0xFF00E5FF), width: 1)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(g.icon, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 4),
                Text(
                  g.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '🪙 ${g.credits}',
                  style: TextStyle(
                    color: afford
                        ? const Color(0xFFFFD700)
                        : const Color(0xFFFF5252),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Reação (emoji) flutuando no centro da tela após tocar numa reação.
class _ReactionBurstOverlay extends StatelessWidget {
  final String emoji;

  const _ReactionBurstOverlay({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: _kAccent, width: 2),
            boxShadow: [
              BoxShadow(color: _kAccent.withValues(alpha: 0.5), blurRadius: 30),
            ],
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 52)),
        ),
      ),
    );
  }
}

/// Top apoiadores reais da live (moedas realmente gastas em presentes),
/// com medalhas neon por posição.
class _TopSupportersSheet extends StatefulWidget {
  final String liveId;

  const _TopSupportersSheet({required this.liveId});

  @override
  State<_TopSupportersSheet> createState() => _TopSupportersSheetState();
}

class _TopSupportersSheetState extends State<_TopSupportersSheet> {
  List<LiveRankRecord> _top = const [];
  bool _loading = true;
  String? _error;

  static const List<Color> _medals = [
    Color(0xFFFFD700),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final top = await LivePremiumService.instance.fetchTopSupporters(
        liveId: widget.liveId,
        limit: 10,
      );
      if (!mounted) return;
      setState(() {
        _top = top;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🏆 Top apoiadores',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Baseado nas moedas reais gastas em presentes nesta live.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: _kAccent),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Não foi possível carregar o top.\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            )
          else if (_top.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ninguém enviou presentes nesta live ainda.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ..._top.map((r) {
              final color = r.rank > 0 && r.rank <= _medals.length
                  ? _medals[r.rank - 1]
                  : Colors.white38;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '#${r.rank}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _kAccent.withValues(alpha: 0.35),
                      backgroundImage: r.avatarUrl != null
                          ? NetworkImage(r.avatarUrl!)
                          : null,
                      child: const Icon(
                        Icons.person,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              r.displayName ?? r.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (r.isVerified) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(size: 14),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '${_formatValue(r.value)} 💎',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatValue(double v) {
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1).replaceFirst('.0', '')}M';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1).replaceFirst('.0', '')}k';
    }
    return v.toStringAsFixed(0);
  }
}
