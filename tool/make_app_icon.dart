// Gera o ícone oficial do KLAY K a partir do arquivo de arte.
//
// Contexto: `assets/images/klay_k_icon.png` chegou como JPEG (784x1168) com
// extensão .png, moldura branca e proporção retrato. Ícone de launcher precisa
// ser um PNG quadrado real, então a arte precisa ser normalizada.
//
// O que esta ferramenta faz, nesta ordem:
//  1. decodifica a arte original (preservada em tool/klay_k_icon_original.jpeg);
//  2. remove a moldura branca e a fumaça externa mais fraca, calculando a caixa
//     real do logo por limiar de luminância — a coroa nunca é cortada;
//  3. monta essa caixa num quadrado, preenchendo o excedente com a PRÓPRIA cor
//     de fundo da arte (#000000 medido na borda), o que deixa a emenda
//     invisível — usar uma cor fixa criaria uma tarja visível;
//  4. grava um PNG 1024x1024 com transparência preservada.
//
// Uso: dart run tool/make_app_icon.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const String source = 'assets/images/klay_k_icon.png';
const String output = 'assets/images/klay_k_icon.png';
const String originalBackup = 'tool/klay_k_icon_original.jpeg';

/// Limiar de luminância: acima disso o pixel pertence ao logo. Descarta o
/// branco da moldura e a fumaça externa quase preta.
const int _logoThreshold = 120;

/// Margem em % do lado maior da arte, para o logo respirar no ícone.
const double _marginRatio = 0.02;

void main() {
  // A fonte é SEMPRE o original preservado. Se a ferramenta já rodou, ela
  // reprocessa a arte original — nunca a própria saída — para o resultado ser
  // idempotente e o ícone não degradir a cada execução.
  final backup = File(originalBackup);
  if (!backup.existsSync()) {
    final current = File(source);
    if (!current.existsSync()) {
      stderr.writeln('ERRO: $source não encontrado.');
      exitCode = 1;
      return;
    }
    backup.parent.createSync(recursive: true);
    current.copySync(backup.path);
    stdout.writeln('Original preservado em $originalBackup');
  }

  final src = backup;
  final decoded = img.decodeImage(src.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('ERRO: não foi possível decodificar $src.');
    exitCode = 1;
    return;
  }
  final art = img.Image.from(decoded);

  final bounds = _logoBounds(art);
  final crop = img.copyCrop(
    art,
    x: bounds.left,
    y: bounds.top,
    width: math.max(1, bounds.width),
    height: math.max(1, bounds.height),
  );

  final padColor = _backgroundColor(art);

  final longest = math.max(crop.width, crop.height);
  final margin = (longest * _marginRatio).round();
  final boxSide = longest + margin * 2;

  final canvas = img.Image(width: boxSide, height: boxSide, numChannels: 4);
  img.fill(canvas, color: padColor);
  img.compositeImage(
    canvas,
    crop,
    dstX: (boxSide - crop.width) ~/ 2,
    dstY: (boxSide - crop.height) ~/ 2,
  );

  final resized = img.copyResize(
    canvas,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.cubic,
  );

  File(output).writeAsBytesSync(img.encodePng(resized, level: 6));
  stdout.writeln(
    'Ícone gerado: $output (1024x1024 PNG)\n'
    '  fonte ${art.width}x${art.height} · '
    'logo ${crop.width}x${crop.height} · '
    'fundo #$padColor · margem $margin px',
  );

  _writeRoundIcons(resized);
}

/// Launcher icons are also requested as `ic_launcher_round`: launchers that
/// ask for a round icon and run on API < 26 (where there is no adaptive icon)
/// would otherwise fall back to a square or missing resource. On API 26+ the
/// `mipmap-anydpi-v26` variant below is used and the launcher masks the art
/// itself. Everything is derived from the same official 1024x1024 asset.
void _writeRoundIcons(img.Image square) {
  const resDir = 'android/app/src/main/res';
  const densities = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  for (final entry in densities.entries) {
    final size = entry.value;
    final resized = img.copyResize(
      square,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    _applyCircularMask(resized);
    final path = '$resDir/mipmap-${entry.key}/ic_launcher_round.png';
    File(path).writeAsBytesSync(img.encodePng(resized, level: 6));
  }

  // Adaptive variant: same background/foreground as ic_launcher.xml, with the
  // launcher applying its own circular mask.
  const adaptive =
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '  <background android:drawable="@color/ic_launcher_background"/>\n'
      '  <foreground>\n'
      '      <inset\n'
      '          android:drawable="@drawable/ic_launcher_foreground"\n'
      '          android:inset="16%" />\n'
      '  </foreground>\n'
      '</adaptive-icon>\n';
  File(
    '$resDir/mipmap-anydpi-v26/ic_launcher_round.xml',
  ).writeAsStringSync(adaptive);

  stdout.writeln(
    'Ícones redondos: ${densities.length} densidades + adaptive xml',
  );
}

/// Alpha-mask [image] into a circle with 4x4 supersampled edges, so pre-API-26
/// launchers get a smooth round icon instead of a hard square.
void _applyCircularMask(img.Image image) {
  const samples = 4;
  final cx = image.width / 2;
  final cy = image.height / 2;
  final radius = image.width / 2;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      var inside = 0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          final px = x + (sx + 0.5) / samples;
          final py = y + (sy + 0.5) / samples;
          final dx = px - cx;
          final dy = py - cy;
          if (dx * dx + dy * dy <= radius * radius) inside++;
        }
      }
      final coverage = inside / (samples * samples);
      if (coverage <= 0) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      final p = image.getPixel(x, y);
      p.a = (p.a * coverage).round().clamp(0, 255);
      image.setPixel(x, y, p);
    }
  }
}

int _luminance(img.Pixel p) =>
    (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

/// Caixa que contém o logo, ignorando branco e fumaça externa tênue.
_Rect _logoBounds(img.Image image) {
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (_luminance(image.getPixel(x, y)) < _logoThreshold) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < minX || maxY < minY) {
    return _Rect(0, 0, image.width, image.height);
  }
  return _Rect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

/// Cor de fundo real da arte (mediana das bordas), usada no preenchimento para
/// não criar emenda visível entre a arte e o quadrado.
img.Color _backgroundColor(img.Image image) {
  final rs = <int>[];
  final gs = <int>[];
  final bs = <int>[];

  void add(img.Pixel p) {
    rs.add(p.r.toInt());
    gs.add(p.g.toInt());
    bs.add(p.b.toInt());
  }

  for (var x = 0; x < image.width; x += 2) {
    add(image.getPixel(x, 0));
    add(image.getPixel(x, image.height - 1));
  }
  for (var y = 0; y < image.height; y += 2) {
    add(image.getPixel(0, y));
    add(image.getPixel(image.width - 1, y));
  }

  int median(List<int> values) {
    values.sort();
    return values[values.length ~/ 2];
  }

  return img.ColorRgb8(median(rs), median(gs), median(bs));
}

class _Rect {
  final int left;
  final int top;
  final int width;
  final int height;

  const _Rect(this.left, this.top, this.width, this.height);
}
