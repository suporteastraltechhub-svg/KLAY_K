// Trilha persistente do startup do KLAY K.
//
// Objetivo: responder "em qual etapa o Release parou?" sem ADB e sem logcat.
//
// Cada etapa é anexada a um arquivo de TEXTO em modo append-only e descarregada
// com flush. Isso é deliberado: um JSON reescrito pode ficar truncado se o
// processo morrer no meio da escrita; uma linha anexada é atômica e sobra.
//
// A trilha é gravada em três níveis:
//   nativo (ContentProvider/Activity), depois Dart (binding, serviços) e por
//   fim o primeiro frame. Se a trilha estiver vazia ou parar no primeiro item,
//   o processo morreu ANTES do Dart — que é justamente o caso que hoje não
//   deixa prova nenhuma.

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Etapas do startup, na ordem em que acontecem.
class BootSteps {
  // --- nativo (roda antes do Dart) ---
  static const nativeStart = 'N0-native.processo';
  static const nativeProviders = 'N1-native.providers';
  static const nativeActivity = 'N2-native.activity';

  // --- Dart ---
  static const dartEnter = 'D0-dart.main';
  static const bindings = 'D1-dart.flutter_bindings';
  static const traceReady = 'D2-dart.trace_ready';
  static const systemChrome = 'D3-dart.system_chrome';
  static const sharedPrefs = 'D4-dart.shared_prefs';
  static const supabase = 'D5-dart.supabase';
  static const auth = 'D6-dart.auth';
  static const firebase = 'D7-dart.firebase';
  static const livekitDeferred = 'D8-dart.livekit(deferido)';
  static const zoneCheck = 'D9-dart.zone_check';
  static const runApp = 'D10-dart.run_app';
  static const firstFrame = 'D11-dart.first_frame';
}

/// Trilha append-only das etapas do startup.
class BootTrace {
  BootTrace._();
  static final BootTrace instance = BootTrace._();

  static const String logName = 'klayk_boot_trace.log';

  /// Trilha da abertura ANTERIOR (mostrada no relatório).
  List<String> previous = <String>[];

  /// Marcadores escritos pelo lado nativo (MainActivity).
  List<String> nativeMarkers = <String>[];

  /// Trilha desta abertura.
  final List<String> _lines = <String>[];

  int _open = 0;
  bool _appendFailed = false;
  Directory? _dir;
  String _pid = '?';

  bool get appendFailed => _appendFailed;
  int get open => _open;

  /// Prepara a trilha: resolve o diretório, lê a abertura anterior e abre uma
  /// nova. Chamar logo após o binding existir.
  Future<void> begin() async {
    _pid = '$pid';
    _dir = await _supportDir();
    if (_dir == null) return;
    final log = File('${_dir!.path}/$logName');

    // Lê (e consome) a trilha anterior: ela descreve a abertura que acabou de
    // morrer, que é justamente a que interessa.
    try {
      if (log.existsSync()) {
        previous = log.readAsLinesSync();
      }
      _open = _countOpens(previous) + 1;
    } catch (_) {
      previous = <String>[];
    }
    try {
      nativeMarkers = await _readNative();
    } catch (_) {
      nativeMarkers = <String>[];
    }
  }

  /// Registra uma etapa. [detail] recebe informação extra já redigida.
  void step(String phase, {String? detail}) {
    _dir ??= null;
    final stamp = DateTime.now().toIso8601String();
    final extra = (detail == null || detail.isEmpty) ? '' : ' | $detail';
    final line = '$stamp | pid=$_pid | open=$_open | $phase$extra';
    _lines.add(line);
    _append(line);
  }

  /// Escreve no arquivo, em append, com flush.
  void _append(String line) {
    final dir = _dir;
    if (dir == null) {
      _appendFailed = true;
      return;
    }
    try {
      final f = File('${dir.path}/$logName');
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      _appendFailed = true;
    }
  }

  /// Procura o arquivo escrito pelo MainActivity. Se o processo morreu antes do
  /// Dart, é a única prova que sobrou.
  Future<List<String>> _readNative() async {
    final dir = _dir;
    if (dir == null) return <String>[];
    final out = <String>[];
    for (final name in ['klayk_native.log', 'klayk_boot_diagnostics.json']) {
      final f = File('${dir.path}/$name');
      try {
        if (f.existsSync()) out.addAll(f.readAsLinesSync());
      } catch (_) {
        // best-effort
      }
    }
    return out;
  }

  static int _countOpens(List<String> lines) {
    var n = 0;
    for (final l in lines) {
      if (l.contains('| open=1 ') || l.contains(BootSteps.dartEnter)) n++;
    }
    // A trilha anterior tem no máximo um "open=1" por abertura; conta o maior
    // open= encontrado e soma 1 para a nova.
    var maxOpen = 0;
    for (final l in lines) {
      final i = l.indexOf('| open=');
      if (i < 0) continue;
      final rest = l.substring(i + 7);
      final sp = rest.indexOf(' ');
      if (sp < 0) continue;
      final v = int.tryParse(rest.substring(0, sp));
      if (v != null && v > maxOpen) maxOpen = v;
    }
    return maxOpen == 0 ? n : maxOpen;
  }

  /// Última etapa concluída da trilha anterior (a mais informativa).
  String? get previousLastStep {
    if (previous.isEmpty) return null;
    for (final l in previous.reversed) {
      final i = l.indexOf('| ');
      if (i < 0) continue;
      final rest = l.substring(i + 2);
      final parts = rest.split(' | ');
      if (parts.isEmpty) continue;
      final j = parts.first.indexOf(' | ');
      return j > 0
          ? parts.first.substring(0, j).split(' | ').last
          : parts.first;
    }
    return null;
  }

  static Future<Directory?> _supportDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }
}
