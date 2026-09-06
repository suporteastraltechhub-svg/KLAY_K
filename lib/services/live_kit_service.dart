import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import 'supabase_service.dart';

/// Papel do participante na sala.
enum LiveRole { streamer, viewer }

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

  bool _disconnecting = false;

  bool get isEnabled => SupabaseService.instance.isConfigured;

  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  LiveRole? get role => _role;

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
  VideoTrack? get localVideoTrack {
    final lp = localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack) return t;
    }
    return null;
  }

  /// Reenvia a lista de remotes com vídeo publicado (principal tela de quem
  /// assiste).
  RemoteParticipant? get primaryRemoteVideo {
    for (final p in guests) {
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && !pub.muted) return p;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Token temporário (sempre via Edge Function).
  // ---------------------------------------------------------------------------

  Future<LiveKitCredentials> getLiveKitToken({
    required String roomName,
    required bool isStreamer,
    String? displayName,
  }) {
    return SupabaseService.instance.getLiveKitCredentials(
      roomName: roomName,
      isStreamer: isStreamer,
      displayName: displayName,
    );
  }

  Future<void> connectToLive({
    required String roomName,
    required bool isStreamer,
    String? displayName,
  }) async {
    final creds = await getLiveKitToken(
      roomName: roomName,
      isStreamer: isStreamer,
      displayName: displayName,
    );
    await connectToLiveWithCredentials(creds);
    _role = isStreamer ? LiveRole.streamer : LiveRole.viewer;
  }

  Future<void> connectToLiveWithCredentials(LiveKitCredentials creds) async {
    final r = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );
    _room = r;
    _disconnecting = false;
    _listen(r);

    await r.connect(
      creds.serverUrl,
      creds.participantToken,
      connectOptions: const ConnectOptions(autoSubscribe: true),
    );
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
      ..on<RoomDisconnectedEvent>((_) {
        _room = null;
        participantsCount.value = 0;
        activeSpeakers.value = 0;
        reconnecting.value = false;
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
    await lp.setCameraEnabled(true);
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
      try {
        final granted =
            await Hardware.instance.requestCapturePermission(fullScreenOnly: true);
        if (!granted) return;
      } catch (_) {
        return;
      }
      await _invokeCapture('startCaptureService');
    }
    await lp.setScreenShareEnabled(on);
    if (!on) {
      await _invokeCapture('stopCaptureService');
    }
  }

  Future<void> _invokeCapture(String method, {Object? args}) async {
    try {
      if (!kIsWeb) {
        await const MethodChannel('klayk/media_projection')
            .invokeMethod(method, args);
      }
    } catch (_) {
      // O service nativo é um extra; o LiveKit/flutter_webrtc já pede a
      // permissão MediaProjection por conta própria.
    }
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
  }) async {
    await connectToLive(
      roomName: roomName,
      isStreamer: true,
      displayName: displayName,
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
    await _invokeCapture('stopCaptureService');
    try {
      await r.disconnect();
    } catch (_) {
      // desconexão best-effort
    }
    _room = null;
    participantsCount.value = 0;
    activeSpeakers.value = 0;
    reconnecting.value = false;
  }
}