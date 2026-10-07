import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import 'supabase_service.dart';

/// Papel do participante na sala.
enum LiveRole { streamer, viewer }

/// Erro específico de captura de tela NEGADA pelo usuário no seletor do
/// Android. A UI diferencia este caso para exibir a tela de negação (motivo +
/// tentar novamente + abrir configurações) em vez de um snackbar genérico.
class ScreenCapturePermissionDeniedException implements Exception {
  const ScreenCapturePermissionDeniedException();
}

/// Fachada do KLAY K para o LiveKit Cloud.
///
/// O token de acesso é SEMPRE obtido da Edge Function `livekit-token` (via
/// Supabase) e usado apenas para conectar. O aplicativo nunca recebe — nem
/// armazena — a LIVEKIT_API_KEY/LIVEKIT_API_SECRET, que existem somente nos
/// Secrets das Edge Functions e no serviço do bot (backend).
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  Room? _room;
  LiveRole? _role;

  final ValueNotifier<int> participantsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> activeSpeakers = ValueNotifier<int>(0);

  /// Exposição real do estado de reconexão do livekit_client: `true` enquanto
  /// a sala tenta reconectar, `false` quando conectada ou desconectada.
  final ValueNotifier<bool> reconnecting = ValueNotifier<bool>(false);

  /// Último erro de conexão para a UI (mensagem legível, SEM expor tokens ou
  /// chaves). Alimentado em falhas de conexão e desconexões espontâneas.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// Estado real do compartilhamento de tela. Também reflete o native→Dart:
  /// quando o Android encerra o service de captura fora do app, volta a `false`
  /// aqui e a UI sincroniza o botão de compartilhamento.
  final ValueNotifier<bool> screenShareActive = ValueNotifier<bool>(false);

  static const MethodChannel _captureChannel = MethodChannel(
    'klayk/media_projection',
  );

  bool _captureHandlerArmed = false;
  bool _projectionRequested = false;

  DisconnectReason? _lastDisconnectReason;

  /// Motivo da última desconexão — só para diagnóstico; nunca vira UI com
  /// detalhes internos.
  DisconnectReason? get lastDisconnectReason => _lastDisconnectReason;

  bool _disconnecting = false;

  bool get isEnabled => SupabaseService.instance.isConfigured;

  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  ConnectionState? get connectionState => _room?.connectionState;

  LiveRole? get role => _role;

  /// Estado REAL da câmera da sessão: `true` quando há uma track de câmera
  /// publicada pelo participante local (nunca simulado).
  bool get cameraInUse {
    final lp = localParticipant;
    if (lp == null) return false;
    for (final pub in lp.videoTrackPublications) {
      if (!pub.isScreenShare && !pub.muted) return true;
    }
    return false;
  }

  /// Estado REAL do microfone da sessão: `true` quando há áudio do local
  /// participante publicado e não-mudado (nunca simulado).
  bool get micInUse {
    final lp = localParticipant;
    if (lp == null) return false;
    for (final pub in lp.audioTrackPublications) {
      if (!pub.muted) return true;
    }
    return false;
  }

  bool get localScreenSharePublished =>
      localParticipant?.isScreenShareEnabled() ?? false;

  bool get localScreenShareAudioPublished =>
      localParticipant?.isScreenShareAudioEnabled() ?? false;

  bool get localVideoPublished {
    final lp = localParticipant;
    if (lp == null) return false;
    return lp.videoTrackPublications.any(
      (pub) => pub.track != null && !pub.muted,
    );
  }

  bool get localAudioPublished {
    final lp = localParticipant;
    if (lp == null) return false;
    return lp.audioTrackPublications.any(
      (pub) => pub.track != null && !pub.muted,
    );
  }

  bool get remoteVideoPublished => guests.any(
    (participant) =>
        participant.isCameraEnabled() || participant.isScreenShareEnabled(),
  );

  bool get remoteAudioPublished => guests.any(
    (participant) =>
        participant.isMicrophoneEnabled() ||
        participant.isScreenShareAudioEnabled(),
  );

  bool get remoteScreenSharePublished =>
      guests.any((participant) => participant.isScreenShareEnabled());

  bool get remoteScreenShareAudioPublished =>
      guests.any((participant) => participant.isScreenShareAudioEnabled());

  Room get room {
    final r = _room;
    if (r == null) {
      throw StateError('LiveKit: ainda não conectado à sala.');
    }
    return r;
  }

  bool get connectionFailed =>
      _room != null && _room!.connectionState == ConnectionState.reconnecting;

  LocalParticipant? get localParticipant => _room?.localParticipant;

  List<RemoteParticipant> get guests {
    final r = _room;
    if (r == null) return const [];
    return r.remoteParticipants.values.toList();
  }

  /// Vídeo do próprio participante (streamer vê o próprio preview).
  ///
  /// Prefere a câmera; em uma Live de Jogo a track de TELA é tratada à parte
  /// ([localScreenShareTrack]) e nunca vira o conteúdo "local" deste getter.
  VideoTrack? get localVideoTrack {
    final lp = localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      if (!pub.isScreenShare) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    for (final pub in lp.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack) return t;
    }
    return null;
  }

  /// Track local de TELA (Game Live): o gameplay publicado via MediaProjection.
  /// É o conteúdo principal de uma Live de Jogo — nunca a câmera.
  VideoTrack? get localScreenShareTrack {
    final lp = localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      if (pub.isScreenShare) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    return null;
  }

  /// Track local de CÂMERA (quando publicada). Em uma Live de Jogo a câmera é
  /// OPCIONAL e aparece apenas em uma janela pequena — nunca como conteúdo
  /// principal.
  VideoTrack? get localCameraTrack {
    final lp = localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      if (!pub.isScreenShare) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    return null;
  }

  /// Track de vídeo (TELA ou CÂMERA) de um participante remoto, já assinada.
  VideoTrack? videoTrackOf(
    RemoteParticipant participant, {
    required bool screenShare,
  }) {
    for (final pub in participant.videoTrackPublications) {
      if (pub.isScreenShare == screenShare && pub.subscribed) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    return null;
  }

  /// Publicação da CÂMERA de um participante remoto (para assinar/cancelar a
  /// janelinha sem desligar a tela do jogo).
  RemoteTrackPublication? remoteCameraPublication(RemoteParticipant p) {
    for (final pub in p.videoTrackPublications) {
      if (!pub.isScreenShare) return pub;
    }
    return null;
  }

  /// Principal vídeo remoto pra quem assiste.
  ///
  /// Em transmissões de jogo o espectador deve priorizar a track de **tela**
  /// (screen share) — é o conteúdo principal. Em lives de câmera comum esse
  /// filtro não encontra nada (`isScreenShare == false`) e cai no vídeo de
  /// câmera, preservando o comportamento atual.
  RemoteParticipant? get primaryRemoteVideo {
    for (final p in guests) {
      for (final pub in p.videoTrackPublications) {
        if (pub.isScreenShare && pub.subscribed && !pub.muted) return p;
      }
    }
    for (final p in guests) {
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && !pub.muted) return p;
      }
    }
    return null;
  }

  /// Há uma track de tela assinada (Game Live) entre os participantes remotos?
  bool get anyScreenShareSubscribed {
    for (final p in guests) {
      for (final pub in p.videoTrackPublications) {
        if (pub.isScreenShare && pub.subscribed) return true;
      }
    }
    return false;
  }

  /// Participante remoto que está compartilhando a tela (Game Live).
  RemoteParticipant? get screenShareBroadcaster {
    for (final p in guests) {
      for (final pub in p.videoTrackPublications) {
        if (pub.isScreenShare && pub.subscribed && !pub.muted) return p;
      }
    }
    return null;
  }

  /// Mensagem amigável para o último erro, mapeada sem detalhes de SDK/tokens.
  String? get lastErrorMessage => lastError.value;

  // ---------------------------------------------------------------------------
  // Token temporário (sempre via Edge Function).
  // ---------------------------------------------------------------------------

  Future<LiveKitCredentials> getLiveKitToken({
    required String roomName,
    required bool isStreamer,
    String? displayName,
    String? liveId,
  }) {
    return SupabaseService.instance.getLiveKitCredentials(
      roomName: roomName,
      isStreamer: isStreamer,
      displayName: displayName,
      liveId: liveId,
    );
  }

  Future<void> connectToLive({
    required String roomName,
    required bool isStreamer,
    String? displayName,
    String? liveId,
  }) async {
    final creds = await getLiveKitToken(
      roomName: roomName,
      isStreamer: isStreamer,
      displayName: displayName,
      liveId: liveId,
    );
    // Espectador que entra no exato momento em que a sala do streamer ainda
    // está subindo recebe "room not found" do LiveKit. Um retry curto com
    // backoff resolve esse race sem travar a UI (bounded, nunca infinito).
    await connectToLiveWithCredentials(creds, allowRetry: !isStreamer);
    _role = isStreamer ? LiveRole.streamer : LiveRole.viewer;
  }

  Future<void> connectToLiveWithCredentials(
    LiveKitCredentials creds, {
    bool allowRetry = false,
  }) async {
    const maxAttempts = 3;
    lastError.value = null;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final r = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      _room = r;
      _disconnecting = false;
      reconnecting.value = false;
      _listen(r);

      try {
        await r.connect(
          creds.serverUrl,
          creds.participantToken,
          connectOptions: const ConnectOptions(autoSubscribe: true),
        );
        return;
      } on Exception catch (e) {
        _teardownFailedConnection(r);
        if (!allowRetry || attempt == maxAttempts || _shouldNotRetry(e)) {
          lastError.value = _friendlyError(e);
          rethrow;
        }
        // Backoff curto entre tentativas; a primeira falha de sala não
        // carregada costuma passar em ~1s.
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
  }

  /// Se o erro for de token/permissão ou timeout, tentar de novo só piora
  /// (cada tentativa faz uma nova chamada à edge `livekit-token`).
  bool _shouldNotRetry(Object error) {
    if (error is ConnectException) {
      if (error.reason == ConnectionErrorReason.Timeout) return true;
      if (error.statusCode == 401 || error.statusCode == 403) return true;
    }
    return false;
  }

  /// Limpa o estado da tentativa que falhou antes de uma nova conexão.
  void _teardownFailedConnection(Room r) {
    if (identical(_room, r)) _room = null;
    reconnecting.value = false;
    participantsCount.value = 0;
    activeSpeakers.value = 0;
  }

  /// Mescla o motivo num texto honesto para a UI (nunca expõe o token).
  String _friendlyError(Object error) {
    if (error is ConnectException) {
      switch (error.reason) {
        case ConnectionErrorReason.NotAllowed:
          if (error.statusCode == 401 || error.statusCode == 403) {
            return 'Conexão recusada: sessão/token inválido.';
          }
          return 'Não foi possível entrar na transmissão neste momento.';
        case ConnectionErrorReason.Timeout:
          return 'A conexão demorou demais. Verifique sua internet e tente novamente.';
        case ConnectionErrorReason.InternalError:
          return 'A conexão com a LiveKit falhou (erro interno). Tente novamente.';
      }
    }
    if (error is TrackCreateException) {
      return 'Não foi possível ativar a câmera/microfone.';
    }
    if (error is TrackPublishException) {
      return 'Não foi possível publicar o áudio/vídeo.';
    }
    final msg = error.toString();
    // LiveKit Exception: [ClassName] tissue... → mantém apenas o essencial.
    return msg
        .replaceFirst('LiveKit Exception: [', '')
        .replaceFirst('] ', ': ')
        .replaceFirst('Exception: ', '');
  }

  String _disconnectFriendly(DisconnectReason? reason) {
    switch (reason) {
      case DisconnectReason.roomClosed:
      case DisconnectReason.roomDeleted:
        return 'A transmissão foi encerrada.';
      case DisconnectReason.serverShutdown:
        return 'O servidor da Live ficou indisponível. Tente novamente em instantes.';
      case DisconnectReason.duplicateIdentity:
        return 'Sua sessão foi substituída em outro dispositivo.';
      case DisconnectReason.participantRemoved:
        return 'Você foi removido da transmissão.';
      case DisconnectReason.reconnectAttemptsExceeded:
        return 'Não foi possível reconectar. Verifique sua internet e tente novamente.';
      case DisconnectReason.connectionTimeout:
        return 'A conexão demorou demais para ser restabelecida.';
      case DisconnectReason.signalingConnectionFailure:
        return 'Falha ao estabelecer o sinal da transmissão.';
      case DisconnectReason.mediaFailure:
        return 'Falha de áudio/vídeo durante a transmissão.';
      default:
        return 'A conexão com a Live foi encerrada.';
    }
  }

  EventsListener<RoomEvent>? _roomListener;

  void _listen(Room r) {
    // Dispara o listener anterior (se existir) para não acumular listeners
    // a cada nova conexão (leak da auditoria de performance).
    _roomListener?.dispose();
    final listener = r.createListener();
    _roomListener = listener;
    listener
      ..on<ParticipantConnectedEvent>((_) => _refresh(r))
      ..on<ParticipantDisconnectedEvent>((_) => _refresh(r))
      ..on<ActiveSpeakersChangedEvent>((e) {
        activeSpeakers.value = e.speakers.isNotEmpty ? e.speakers.length : 0;
      })
      ..on<RoomReconnectingEvent>((_) {
        // O livekit_client 2.11 já faz auto-reconnect interno; o KLAY K apenas
        // reflete o estado real do SDK (nunca simula reconexão).
        reconnecting.value = true;
      })
      ..on<RoomResumingEvent>((_) {
        reconnecting.value = false;
      })
      ..on<RoomReconnectedEvent>((_) {
        reconnecting.value = false;
      })
      ..on<RoomDisconnectedEvent>((e) {
        _lastDisconnectReason = e.reason;
        _room = null;
        participantsCount.value = 0;
        activeSpeakers.value = 0;
        reconnecting.value = false;
        // Desconexão espontânea (sala encerrada, servidor caiu, reconexão
        // esgotada) precisa aparecer pra UI. Desligamento manual é ignorado.
        if (!_disconnecting) {
          lastError.value = _disconnectFriendly(e.reason);
        }
      });
  }

  void _refresh(Room r) {
    if (_disconnecting) return;
    participantsCount.value = r.remoteParticipants.length;
  }

  // ---------------------------------------------------------------------------
  // Publicação / assistir.
  // ---------------------------------------------------------------------------

  Future<void> publishCamera() async {
    final lp = localParticipant;
    if (lp == null) return;
    // Publica em 720p (16:9) — resolução pedida na transmissão.
    await lp.setCameraEnabled(
      true,
      cameraCaptureOptions: const CameraCaptureOptions(),
    );
  }

  Future<void> publishMicrophone() async {
    final lp = localParticipant;
    if (lp == null) return;
    await lp.setMicrophoneEnabled(true);
  }

  Future<void> stopCamera() async {
    final lp = localParticipant;
    if (lp == null) return;
    await lp.setCameraEnabled(false);
  }

  /// Desativa o compartilhamento de tela e encerra o service de captura.
  Future<void> stopScreenShare() async {
    await setScreenShareEnabled(false);
  }

  Future<void> stopMicrophone() async {
    final lp = localParticipant;
    if (lp == null) return;
    await lp.setMicrophoneEnabled(false);
  }

  /// Troca a câmera local entre frontal e traseira durante a transmissão.
  ///
  /// Usa a API real do livekit_client (`LocalVideoTrack.setCameraPosition` com
  /// `CameraPosition.switched()`), que reinicia a captura na nova posição e
  /// republica a track no Room. Vira um no-op (sem erro) quando ainda não há
  /// uma câmera publicada — nunca simula o estado.
  Future<void> toggleCameraSwitch() async {
    final track = localCameraTrack;
    if (track is! LocalVideoTrack) return;
    final options = track.currentOptions;
    if (options is! CameraCaptureOptions) return;
    await track.setCameraPosition(options.cameraPosition.switched());
  }

  /// Ativa/desativa o compartilhamento de tela (MediaProjection no Android).
  ///
  /// O `livekit_client`/`flutter_webrtc` abre o seletor nativo
  /// (`createScreenCaptureIntent`) por conta própria e guarda o token; e o
  /// Android 14+ (API 34) exige que um foreground service do tipo
  /// `mediaProjection` esteja em primeiro plano ANTES de chamar
  /// `getMediaProjection()`. Por isso a ordem correta aqui é:
  ///   1. `requestCapturePermission()` → seletor ÚNICO de captura (o usuário
  ///      concede uma vez; o token fica guardado no flutter_webrtc).
  ///   2. Sobe o foreground service `mediaProjection` — como o consentimento
  ///      já foi concedido no passo 1, o Android 14+ aceita `startForeground`.
  ///   3. `setScreenShareEnabled(true)` reaproveita o token já solicitado e
  ///      publica a track de tela, sem abrir um segundo diálogo.
  ///
  /// Antes, o app abria um seletor próprio e desconectado (MainActivity +
  /// ScreenCaptureService) e depois o LiveKit abria OUTRO seletor — o fluxo
  /// duplo travava a transmissão. Este caminho único resolve isso.
  Future<void> setScreenShareEnabled(bool on) async {
    final lp = localParticipant;
    if (lp == null) return;
    if (on) {
      // Evita reabrir o seletor do Android numa retomada (pausar/retomar): o
      // primeiro `requestCapturePermission` guarda o token no flutter_webrtc;
      // retomar apenas reaproveita o token já concedido. O seletor só abre
      // UMA vez por sessão (na primeira ativação).
      if (!_projectionRequested) {
        await _ensureCaptureChannelHandler();
        _log('[KLayK][GameLive] requesting screen capture');
        final granted = await Hardware.instance.requestCapturePermission(
          fullScreenOnly: true,
        );
        if (!granted) {
          _log('[KLayK][GameLive] permission denied');
          lastError.value =
              'Permissão de captura de tela negada. O seletor do Android reabre na próxima tentativa.';
          throw const ScreenCapturePermissionDeniedException();
        }
        _projectionRequested = true;
        _log('[KLayK][GameLive] permission granted');
      }
      // Erros aqui NÃO são engolidos: se o foreground service de projeção
      // falhar, a transmissão de tela não pode prosseguir e o usuário precisa
      // saber o motivo real.
      await _invokeCapture('startCaptureService');
      _log('[KLayK][GameLive] enabling screen share');
      // captureScreenAudio: true — habilita áudio do sistema quando o
      // Android permitir. Em muitos dispositivos o áudio interno é
      // limitado; a LIVE continua com vídeo + microfone nesse caso.
      _log('[KLayK][GameAudio] requesting system audio capture');
      try {
        await lp.setScreenShareEnabled(
          on,
          captureScreenAudio: true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            // 720p@5fps — equilíbrio entre qualidade e performance móvel.
            params: VideoParametersPresets.screenShareH720FPS5,
          ),
        );
        _log('[KLayK][GameAudio] system audio available');
      } catch (_) {
        _log('[KLayK][GameAudio] system audio unavailable');
        rethrow;
      }
      screenShareActive.value = on;
      _log('[KLayK][GameLive] screen share enabled');
    } else {
      screenShareActive.value = on;
      _log('[KLayK][GameLive] screen share disabled');
    }
    if (!on) {
      _projectionRequested = false;
      try {
        await _invokeCapture('stopCaptureService');
      } catch (_) {
        // Desligar é best-effort: o service pode já ter sido encerrado
        // pela notificação do Android.
      }
    }
  }

  /// Log temporário de diagnóstico (não registra segredos).
  static void _log(String message) {
    debugPrint(message);
  }

  /// Abre a página de configurações do app no Android.
  ///
  /// A captura de tela (MediaProjection) não tem uma tela de configuração
  /// própria — a permissão é concedida pelo seletor oficial do Android. Esta
  /// página de detalhes permite corrigir permissões que bloqueiam a
  /// transmissão (ex.: notificações no Android 13+, exigidas pelo foreground
  /// service de projeção).
  Future<void> openScreenCaptureSettings() async {
    if (kIsWeb) return;
    try {
      await _invokeCapture('openAppSystemSettings');
    } catch (_) {
      // Best-effort: se o canal nativo não existir, apenas ignora.
    }
  }

  Future<void> _ensureCaptureChannelHandler() async {
    if (_captureHandlerArmed) return;
    _captureHandlerArmed = true;
    _captureChannel.setMethodCallHandler(_onCaptureCall);
  }

  /// Native → Dart: o service de captura foi encerrado sem o app pedir
  /// (swipe na notificação, sistema). A transmissão de tela caiu junto — a UI
  /// precisa sincronizar o botão de compartilhamento.
  Future<void> _onCaptureCall(MethodCall call) async {
    if (call.method == 'screenShareStopped') {
      screenShareActive.value = false;
      _projectionRequested = false;
    }
  }

  Future<void> _invokeCapture(String method, {Object? args}) async {
    if (kIsWeb) return;
    await _captureChannel.invokeMethod(method, args);
  }

  /// Modo espectador: apenas assina áudio/vídeo. (AutoSubsno atendido pelo
  /// ConnectOptions.) Força o desligamento de câmera/mic como garantia.
  Future<void> watchLive() async {
    await stopCamera();
    await stopMicrophone();
  }

  /// Streamer: conecta e publica câmera + microfone.
  Future<void> startLive({
    required String roomName,
    String? displayName,
    String? liveId,
  }) async {
    await connectToLive(
      roomName: roomName,
      isStreamer: true,
      displayName: displayName,
      liveId: liveId,
    );
    // Aguarda o connect efetivar antes de publicar as mídias.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await publishCamera();
    await publishMicrophone();
  }

  // ---------------------------------------------------------------------------
  // Salas de voz (Áudio) — reutiliza toda a infra de LiveKit, mas publica/ouye
  // apenas ÁUDIO (nunca câmera). Não altera o fluxo das lives de vídeo.
  // ---------------------------------------------------------------------------

  /// Dono de sala de voz: conecta com grant de streamer e publica mic opcional.
  /// `withMic=false` permite abrir a sala ainda sem publicar (se levantar a
  /// mano depois). NUNCA publica cámara.
  Future<void> startAudioRoom({
    required String roomName,
    String? displayName,
    bool withMic = true,
  }) async {
    await connectToLive(
      roomName: roomName,
      isStreamer: true,
      displayName: displayName,
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await stopCamera();
    if (withMic) {
      await publishMicrophone();
    }
  }

  /// Participante de sala de voz com rol de "speaker" (publica áudio, pero no
  /// crea la sala) — vía `livekit-token` con `role: 'speaker'`.
  Future<void> connectToVoiceRoomAsSpeaker({
    required String roomName,
    String? displayName,
    bool withMic = true,
  }) async {
    final creds = await SupabaseService.instance.getLiveKitCredentials(
      roomName: roomName,
      isStreamer: false,
      displayName: displayName,
      role: 'speaker',
    );
    await connectToLiveWithCredentials(creds);
    _role = LiveRole.streamer;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await stopCamera();
    if (withMic) {
      await publishMicrophone();
    } else {
      await stopMicrophone();
    }
  }

  /// Oiente de sala de voz (só assina áudio). Grant: `role: 'listener'`.
  Future<void> connectToVoiceRoomAsListener({
    required String roomName,
    String? displayName,
  }) async {
    final creds = await SupabaseService.instance.getLiveKitCredentials(
      roomName: roomName,
      isStreamer: false,
      displayName: displayName,
      role: 'listener',
    );
    await connectToLiveWithCredentials(creds);
    _role = LiveRole.viewer;
    await stopCamera();
    await stopMicrophone();
  }

  Future<void> disconnectFromLive() async {
    final r = _room;
    if (r == null) return;
    _disconnecting = true;
    try {
      await _invokeCapture('stopCaptureService');
    } catch (_) {
      // Desligamento best-effort: o service nativo já pode ter sido encerrado.
    }
    try {
      await r.disconnect();
    } catch (_) {
      // desconexão best-effort
    }
    _room = null;
    participantsCount.value = 0;
    activeSpeakers.value = 0;
    reconnecting.value = false;
    screenShareActive.value = false;
    _projectionRequested = false;
    lastError.value = null;
    _lastDisconnectReason = null;
  }

  // ---------------------------------------------------------------------------
  // RTMP/RTMPS — Transmissão para plataformas externas (YouTube, Twitch, etc.)
  // ---------------------------------------------------------------------------

  /// Retorna a URL RTMP e a chave de stream para o streamer configurar a saída
  /// em software de captura (OBS, Streamlabs, etc.).
  Future<Map<String, String>> getRtmpStreamInfo(String roomName) async {
    final creds = await getLiveKitToken(roomName: roomName, isStreamer: true);
    final liveId = _roomLiveId() ?? '';
    return {
      'room_name': roomName,
      'token': creds.participantToken,
      'live_id': liveId,
    };
  }

  /// Lê o `live_id` do metadata da sala. A edge `create-live` grava esse
  /// metadata como JSON (Room.metadata é `String?`).
  String? _roomLiveId() {
    final raw = _room?.metadata;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final id = decoded['live_id'];
        if (id != null) return '$id';
      }
    } catch (_) {
      // Metadata inválido — segue sem live_id.
    }
    return null;
  }

  /// Inicia transmissão RTMP com a URL e chave fornecidas.
  Future<void> startRtmpStream({
    required String rtmpUrl,
    required String streamKey,
  }) async {
    if (!isConnected) {
      throw UnexpectedStateException('Not connected to a room');
    }
    _rtmpInfo = {'rtmp_url': rtmpUrl, 'stream_key': streamKey};
  }

  /// Para a transmissão RTMP ativa.
  Future<void> stopRtmpStream() async {
    _rtmpInfo = null;
  }

  Map<String, String>? _rtmpInfo;
  Map<String, String>? get rtmpInfo => _rtmpInfo;
}
