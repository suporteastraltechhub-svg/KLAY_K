import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/live_bot_models.dart';
import 'live_bot_tts.dart';

/// Fila de fala do Live Bot.
///
/// Regras:
///   * Uma mensagem por vez (nunca sobrepõe áudios).
///   * Prioridade (LiveBotSpeechPriority): avisos > moderação > comentário
///     selecionado > resposta automática > anúncio.
///   * Cancelar, pausar/continuar, e limite de itens na fila.
///
/// Este componente controla a PRÉVIA/TESTE local. A transmissão real para a
/// sala é feita pelo bot de backend; a mesma semântica de fila é usada lá.
class _Queued {
  _Queued(this.item, this.seq);
  final LiveBotSpeechItem item;
  final int seq;
}

class LiveBotSpeechQueue extends ChangeNotifier {
  /// TTS local para prévia/teste (opcional; pode ser nulo em modo "somente
  /// transmissão", ex.: quando apenas o bot de backend fala).
  final LiveBotTts? _tts;

  final SplayTreeSet<_Queued> _queue = SplayTreeSet<_Queued>((a, b) {
    final byPrio = a.item.priority.rank.compareTo(b.item.priority.rank);
    if (byPrio != 0) return byPrio;
    return a.seq.compareTo(b.seq);
  });

  int _seq = 0;
  bool _paused = false;
  bool _processing = false;
  bool _talking = false;
  int _maxQueue = 20;

  LiveBotSpeechQueue({LiveBotTts? tts}) : _tts = tts;

  /// Instância compartilhada usada pela tela da live e pelo painel, de modo
  /// que "ler comentário selecionado" e os testes de voz usem a mesma fila.
  static LiveBotSpeechQueue? _shared;

  static LiveBotSpeechQueue shared({LiveBotTts? tts}) {
    _shared ??= LiveBotSpeechQueue(tts: tts ?? LiveBotTts.instance);
    return _shared!;
  }

  bool get isTalking => _talking;
  bool get isPaused => _paused;
  bool get isEmpty => _queue.isEmpty;
  int get length => _queue.length;
  int get maxQueue => _maxQueue;
  set maxQueue(int v) {
    _maxQueue = v < 1 ? 1 : v;
    _trim();
  }

  /// Reenvia um texto falado (ex.: um comentário selecionado pelo moderador).
  void selectComment(String author, String text) {
    enqueue(
      LiveBotSpeechItem(
        text: text,
        commentAuthor: author,
        priority: LiveBotSpeechPriority.selectedComment,
      ),
    );
  }

  /// Envia uma mensagem para a fila respeitando prioridade e limite.
  void enqueue(LiveBotSpeechItem item) {
    if (item.text.trim().isEmpty) return;
    _queue.add(_Queued(item, _seq++));
    _trim();
    _drain();
  }

  void cancelAll() {
    _queue.clear();
    _tts?.stop();
    _talking = false;
    notifyListeners();
  }

  void pause() {
    _paused = true;
    _tts?.stop();
    _talking = false;
    notifyListeners();
  }

  void resume() {
    _paused = false;
    _drain();
    notifyListeners();
  }

  void _trim() {
    while (_queue.length > _maxQueue) {
      _queue.last; // remove a de menor prioridade (última da ordenação).
      final last = _queue.last;
      _queue.remove(last);
    }
  }

  Future<void> _drain() async {
    if (_processing || _paused || _tts == null) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty && !_paused) {
        final item = _queue.first.item;
        _queue.remove(_queue.first);
        _talking = true;
        notifyListeners();
        await _tts.speak(item.display);
        _talking = false;
        notifyListeners();
      }
    } finally {
      _processing = false;
      _talking = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _tts?.stop();
    _queue.clear();
    super.dispose();
  }
}
