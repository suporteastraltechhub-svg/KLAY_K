import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Um jogo/app com atividade de launcher instalado no dispositivo.
class InstalledGame {
  final String package;
  final String label;

  /// Ícone do app em base64 PNG (vindo do canal nativo) ou vazio.
  final String iconBase64;

  const InstalledGame({
    required this.package,
    required this.label,
    this.iconBase64 = '',
  });

  /// Decodifica o ícone para bytes usáveis pelo decodificador de imagem.
  Uint8List? get iconBytes {
    if (iconBase64.isEmpty) return null;
    try {
      return base64Decode(iconBase64);
    } catch (_) {
      return null;
    }
  }

  factory InstalledGame.fromMap(Map<Object?, Object?> map) {
    String s(Object? v) => (v as String?) ?? '';
    return InstalledGame(
      package: s(map['package']),
      label: s(map['label']),
      iconBase64: s(map['icon']),
    );
  }
}

/// Controlador Dart dos jogos/apps instalados.
///
/// Encapsula o canal nativo `klayk/games` do [MainActivity]: lista os apps
/// com launcher (ícone + nome) e abre um jogo pelo package name. Usado pela
/// tela "🎮 JOGOS" para deixar o usuário escolher o jogo instalado e iniciar
/// uma Live de Jogo (captura de tela + bolinha) tocando nele.
class KlayGames {
  KlayGames._();

  static final KlayGames instance = KlayGames._();

  static const MethodChannel _channel = MethodChannel('klayk/games');

  bool _listedOnce = false;
  List<InstalledGame>? _cache;

  /// Lista os apps/jogos instalados (atividade de launcher).
  ///
  /// Faz cache da primeira listagem e permite forçar uma nova com
  /// [forceRefresh]. Entidades com package vazio são descartadas (defesa
  /// contra payloads malformados do canal nativo).
  Future<List<InstalledGame>> listInstalledGames({
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) return const [];
    if (_listedOnce && !forceRefresh && _cache != null) return _cache!;

    try {
      final raw = await _channel.invokeListMethod<Object?>('listApps');
      final apps = <InstalledGame>[];
      for (final item in raw ?? const []) {
        if (item is Map<Object?, Object?>) {
          final game = InstalledGame.fromMap(item);
          if (game.package.isEmpty) continue;
          if (game.label.isEmpty) continue;
          apps.add(game);
        }
      }
      _cache = apps;
      _listedOnce = true;
      return apps;
    } catch (_) {
      // Canal nativo ausente (web/teste) ou falha ao listar: sem grade.
      return const [];
    }
  }

  /// Abre um jogo/app pelo package name. Retorna `false` quando não há
  /// atividade de launcher ou o sistema recusa a abertura.
  Future<bool> launchPackage(String package) async {
    if (kIsWeb || package.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('launchPackage', {
        'package': package,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Limpa o cache (ex.: depois de instalar/desinstalar um app).
  void clearCache() {
    _cache = null;
    _listedOnce = false;
  }
}
