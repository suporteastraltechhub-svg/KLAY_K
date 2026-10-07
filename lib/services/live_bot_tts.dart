import 'package:flutter_tts/flutter_tts.dart';

/// Wrapper de TTS gratuito (motor de voz do dispositivo) para o Live Bot.
///
/// Responsável apenas pela PRÉVIA/TESTE de voz e pelo modo local. A transmissão
/// de áudio para os espectadores é feita pelo bot de backend (`services/livekit-bot`),
/// que lê as configurações salvas no Supabase — este wrapper não publica na sala.
class LiveBotTts {
  LiveBotTts._();

  static final LiveBotTts instance = LiveBotTts._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;
  String? _currentVoiceName;

  /// Inicializa e escolhe a melhor voz pt-BR disponível (automática).
  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      _selectVoiceFor('auto');
      _ready = true;
    } catch (_) {
      // Motor de voz indisponível (ex.: emulador sem TTS). Seguimos com false.
      _ready = true;
    }
  }

  /// Seleciona voz por tipo: 'auto' | 'female' | 'male'. Fallback:
  /// 1) voz pt-BR do tipo desejado, 2) qualquer voz pt-BR, 3) qualquer voz com
  /// 'pt', 4) voz padrão do sistema (sem forçar nome específico).
  Future<void> _selectVoiceFor(String type) async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      final list = voices
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      bool matches(Map<String, dynamic> v, String lang, String gender) {
        final l = (v['locale']?.toString() ?? v['name']?.toString() ?? '')
            .toLowerCase();
        final n = (v['name']?.toString() ?? '').toLowerCase();
        final localMatch = l.contains(lang) || n.contains(lang);
        final g = gender;
        final genderMatch =
            g == 'auto' ||
            n.contains(g) ||
            (v['gender']?.toString() ?? '').toLowerCase() == g;
        return localMatch && genderMatch;
      }

      Map<String, dynamic>? pick(String lang, String gender) {
        for (final v in list) {
          if (matches(v, lang, gender)) return v;
        }
        return null;
      }

      final wanted = type == 'female'
          ? 'female'
          : type == 'male'
          ? 'male'
          : 'auto';

      Map<String, dynamic>? chosen;
      // 1) pt-BR do tipo desejado.
      chosen = pick('pt-br', wanted);
      // 2) qualquer voz pt-BR.
      chosen ??= pick('pt-br', 'auto');
      // 3) qualquer voz em português.
      if (chosen == null) {
        for (final v in list) {
          final n = (v['name']?.toString() ?? '').toLowerCase();
          if (n.contains('pt') || n.contains('portugu')) {
            chosen = v;
            break;
          }
        }
      }
      if (chosen == null) return; // 4) voz padrão do sistema.

      final name = chosen['name']?.toString();
      if (name != null && name.isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': name});
        _currentVoiceName = name;
      }
    } catch (_) {}
  }

  bool get isReady => _ready;
  bool get isSpeaking => _speaking;
  String? get currentVoiceName => _currentVoiceName;

  /// Prévia/teste de voz (local, gratuito).
  Future<bool> speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
      _speaking = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
  }

  Future<void> applySettings({
    required double speed,
    required double volume,
    String voiceType = 'auto',
  }) async {
    try {
      await _tts.setSpeechRate(speed.clamp(0.0, 1.0));
      await _tts.setVolume(volume.clamp(0.0, 1.0));
      await _selectVoiceFor(voiceType);
    } catch (_) {}
  }

  static const String kPreviewText = 'Olá! Bem-vindos à live do KLAY K!';
}
