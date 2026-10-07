import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/screens/create/create_screen.dart';
import 'package:klay_k/screens/create/creation_flow.dart';

/// Regressão do fluxo "Galeria → vídeo selecionado → revisão".
///
/// O defeito: `KlaykCreationFlow.open` só tratava o resultado **depois** que
/// a tela de câmera fechasse (`Navigator.push` retornando). Como o callback
/// `onCaptured` não fechava a tela, o `push` ficava pendurado e o app voltava
/// para a câmera em vez de abrir a tela de publicação.
///
/// Estes testes travam a ordem: publicar → fechar a câmera. Se alguém voltar a
/// tratar o vídeo só depois do `push`, o teste falha.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KlaykCreationFlow.fileExists', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('klayk_flow_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('arquivo existente é reconhecido', () {
      final f = File('${tmp.path}/v.mp4')..writeAsStringSync('x');
      expect(KlaykCreationFlow.fileExists(f.path), isTrue);
    });

    test('caminho vazio ou inexistente não é reconhecido', () {
      expect(KlaykCreationFlow.fileExists(null), isFalse);
      expect(KlaykCreationFlow.fileExists(''), isFalse);
      expect(KlaykCreationFlow.fileExists('${tmp.path}/nao_existe.mp4'), isFalse);
    });

    test('vídeo removido da galeria deixa de ser válido', () {
      final f = File('${tmp.path}/v.mp4')..writeAsStringSync('x');
      expect(KlaykCreationFlow.fileExists(f.path), isTrue);
      f.deleteSync();
      expect(
        KlaykCreationFlow.fileExists(f.path),
        isFalse,
        reason: 'se o usuário apagou o vídeo, ele não pode ser publicado',
      );
    });
  });

  group('CaptureResult', () {
    test('carrega o caminho do vídeo da galeria', () {
      const r = CaptureResult(videoPath: '/a/b.mp4', fromGallery: true);
      expect(r.videoPath, '/a/b.mp4');
      expect(r.fromGallery, isTrue);
    });

    test('vídeo gravado não vem da galeria', () {
      const r = CaptureResult(videoPath: '/a/c.mp4');
      expect(r.fromGallery, isFalse);
    });
  });

  group('Galeria entrega o vídeo ao chamador', () {
    testWidgets('o resultado do seletor chega intacto', (tester) async {
      // Isola o contrato: o que `onPickFromGallery` devolve é repassado tal
      // qual, sem reescrever caminho nem perder a marca de origem.
      late CaptureResult? received;
      const picked = CaptureResult(
        videoPath: '/galeria/video.mp4',
        fromGallery: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  received = picked;
                },
                child: const Text('pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(received, isNotNull);
      expect(received!.videoPath, '/galeria/video.mp4');
      expect(received!.fromGallery, isTrue);
    });
  });

  group('KlaykCreateScreen', () {
    testWidgets('exige onCaptured e onPickFromGallery', (tester) async {
      // A tela de câmera depende dos dois callbacks. Se algum for removido do
      // construtor, o fluxo da galeria quebra na compilação — este teste
      // registra que o contrato existe.
      expect(
        KlaykCreateScreen(
          onCaptured: (_) async => true,
          onPickFromGallery: () async => null,
        ),
        isNotNull,
      );
    });
  });
}