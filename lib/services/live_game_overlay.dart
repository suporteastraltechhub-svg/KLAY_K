import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Callback de ações vindas do painel nativo da bolinha flutuante.
typedef OverlayAction =
    void Function(String action, Map<String, dynamic>? payload);

/// Controlador Dart da bolinha flutuante da Live de Jogo.
///
/// Encapsula a comunicação com o Android ([LiveGameOverlayService] nativo) via
/// MethodChannel `klayk/live_game_overlay`. Os controles do painel (mic,
/// pausar, voz, encerrar, mais, ocultar) chegam aqui por callback e são
/// repassados ao [onAction] registrado pelo chamador (tipicamente o
/// LiveKitService / LiveRoomScreen) para acionar o estado real da transmissão.
class KlayLiveGameOverlay {
  KlayLiveGameOverlay._();

  static final KlayLiveGameOverlay instance = KlayLiveGameOverlay._();

  static const MethodChannel _overlayChannel = MethodChannel(
    'klayk/live_game_overlay',
  );

  OverlayAction? _onAction;
  bool _listening = false;

  bool _micEnabled = true;
  bool _paused = false;
  bool _voiceBotEnabled = false;

  bool get micEnabled => _micEnabled;
  bool get paused => _paused;
  bool get voiceBotEnabled => _voiceBotEnabled;

  /// Registra o callback de ações vindo do painel (mic/pausar/voz/encerrar/mais).
  void listen(OverlayAction onAction) {
    _onAction = onAction;
    if (!_listening) {
      _listening = true;
      _overlayChannel.setMethodCallHandler(_handleCall);
    }
  }

  /// Remove o callback. O painel nativo continua mostrando a bolinha, mas
  /// deixa de repassar eventos.
  void stopListening() {
    _onAction = null;
  }

  Future<void> _handleCall(MethodCall call) async {
    final action = _onAction;
    if (action == null) return;
    Map<String, dynamic>? payload;
    if (call.arguments is Map) {
      payload = Map<String, dynamic>.from(call.arguments as Map);
    }
    switch (call.method) {
      case 'micToggled':
        _micEnabled = payload?['enabled'] as bool? ?? !_micEnabled;
        break;
      case 'pauseToggled':
        _paused = payload?['paused'] as bool? ?? !_paused;
        break;
      case 'voiceBotToggled':
        _voiceBotEnabled = payload?['enabled'] as bool? ?? !_voiceBotEnabled;
        break;
    }
    action(call.method, payload);
  }

  /// Inicia o service de overlay (bolinha flutuante).
  ///
  /// Verifica/reconhece a permissão SYSTEM_ALERT_WINDOW antes de subir o
  /// service. Se a permissão não estiver concedida (o canal responde com erro
  /// `overlay_permission_denied`), retorna `false` — o chamador exibe o guia
  /// para o usuário abrir as configurações. Nunca lança exceção aqui.
  Future<bool> start() async {
    if (kIsWeb) return false;
    try {
      await _overlayChannel.invokeMethod('setup');
    } catch (_) {
      return false;
    }
    try {
      await _overlayChannel.invokeMethod('start');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Encerra o service de overlay.
  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await _overlayChannel.invokeMethod('stop');
    } catch (_) {}
    _onAction = null;
    _listening = false;
  }

  /// Atualiza o estado do mic no painel.
  Future<void> setMic(bool enabled) async {
    _micEnabled = enabled;
    await _safeInvoke('setMic', {'enabled': enabled});
  }

  /// Atualiza o estado de pausa no painel.
  Future<void> setPaused(bool paused) async {
    _paused = paused;
    await _safeInvoke('setPaused', {'paused': paused});
  }

  /// Atualiza o estado do bot de voz no painel.
  Future<void> setVoiceBot(bool enabled) async {
    _voiceBotEnabled = enabled;
    await _safeInvoke('setVoiceBot', {'enabled': enabled});
  }

  /// Oculta a bolinha (sem encerrar a live).
  Future<void> hide() => _safeInvoke('hide');

  /// Restaura a bolinha após ocultar.
  Future<void> restore() => _safeInvoke('restore');

  /// Abre a tela de configurações do Android para a permissão de exibição
  /// sobre outros apps.
  Future<void> openOverlaySettings() async {
    if (kIsWeb) return;
    try {
      await _overlayChannel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  Future<void> _safeInvoke(String method, [Object? args]) async {
    if (kIsWeb) return;
    try {
      await _overlayChannel.invokeMethod(method, args);
    } catch (_) {}
  }
}
