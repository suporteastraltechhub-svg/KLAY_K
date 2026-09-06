// E2E da CAPA PERSONALIZADA da live.
//
//  - Testes de UI (preview, trocar/remover, validação de formato e tamanho)
//    rodam SEMPRE (não tocam rede nem plugin de plataforma: o seletor é
//    injetado por injeção de dependência) — cobertura offline.
//  - O teste de armazenamento/backend (upload real → createLive → cover_url
//    na listagem) só roda com `KLAY_E2E=true` (rede real, opt-in).
//
// Harness idêntico ao do E2E de autenticação:
//  - o primeiro teste (test(), não testWidgets) inicializa o singleton do
//    Supabase na zona REAL — sem isso o HTTP do login fica preso no FakeAsync;
//  - operações de rede vão todas dentro de `tester.runAsync` (loop real).
//
//   KLAY_E2E=true flutter test test/e2e_cover_flow_test.dart --timeout 300s
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/models/klayk_live_models.dart';
import 'package:klay_k/screens/start_live_screen.dart';
import 'package:klay_k/services/content_service.dart';
import 'package:klay_k/services/supabase_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

const _adminEmail = 'founder.admin+test@klayk.app';
const _password = 'KlayKTest#2026!';

/// PNG válido (1x1 vermelho) usado como "imagem da galeria" nos testes.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  final isE2E = Platform.environment['KLAY_E2E'] == 'true';
  bool? skipUnlessE2E() => isE2E ? null : true;

  setUpAll(() {
    // O flutter_test troca o HttpClient global por um mock que responde 400.
    // No E2E (rede real) restauramos o IOClient padrão; este isolate é o único
    // afetado (cada arquivo de teste roda em um isolate separado).
    if (isE2E) {
      HttpOverrides.global = null;
    }
  });

  Future<T?> runReal<T>(WidgetTester tester, Future<T> Function() action) =>
      tester.runAsync(action);

  group('🎨 E2E CAPA DA LIVE (KLAY_E2E)', () {
    // Inicializa o singleton do Supabase na zona REAL antes de qualquer
    // testWidgets — sem isso o HTTP do login fica preso no FakeAsync.
    test('(setup) inicializa Supabase na zona real', () async {
      SharedPreferences.setMockInitialValues(const {});
      await SupabaseService.instance.ensureReady();
      expect(SupabaseService.instance.isConfigured, isTrue,
          reason: 'E2E exige Supabase configurado (rede real habilitada).');
    }, skip: skipUnlessE2E());

    testWidgets('preview, trocar e remover capa (sem rede)', (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // IO síncrono: `fromData` carrega os bytes em memória e o XFile informa
      // `length` sem I/O (o construtor `XFile(path, length:)` ignora length no
      // IO e faria leitura assíncrona real, que não completa na zona fake-async).
      final tmp = File(
          '${Directory.systemTemp.path}/klay_cover_preview_${DateTime.now().millisecondsSinceEpoch}.png');
      tmp.writeAsBytesSync(_tinyPng);
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

      Future<XFile?> pickCover(ImageSource source) async =>
          XFile.fromData(_tinyPng, path: tmp.path);

      await tester.pumpWidget(
        MaterialApp(theme: KlaykTheme.dark(), home: StartLiveScreen(coverPicker: pickCover)),
      );
      await tester.pump();

      // Estado vazio: placeholder original.
      expect(find.text('Adicionar capa (opcional)'), findsOneWidget);

      // "Selecionar" → preview com a imagem.
      await tester.tap(find.text('Adicionar capa (opcional)'));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Trocar capa'), findsOneWidget);
      expect(find.byTooltip('Remover capa'), findsOneWidget);

      // "Remover" → volta ao placeholder (sem imagem).
      await tester.tap(find.byTooltip('Remover capa'));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Adicionar capa (opcional)'), findsOneWidget);

      // "Trocar" (re-pick) → preview de novo.
      await tester.tap(find.text('Adicionar capa (opcional)'));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('valida formato e tamanho da imagem (sem rede)',
        (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final gif = File(
          '${Directory.systemTemp.path}/klay_cover_bad_${DateTime.now().millisecondsSinceEpoch}.gif');
      gif.writeAsBytesSync(_tinyPng);
      addTearDown(() => gif.existsSync() ? gif.deleteSync() : null);

      final huge = File(
          '${Directory.systemTemp.path}/klay_cover_huge_${DateTime.now().millisecondsSinceEpoch}.png');
      final hugeBytes = Uint8List(10 * 1024 * 1024 + 1); // > 10 MB
      huge.writeAsBytesSync(hugeBytes);
      addTearDown(() => huge.existsSync() ? huge.deleteSync() : null);

      var next = gif.path;
      Future<XFile?> pickNext(ImageSource source) async =>
          XFile.fromData(
          next == gif.path ? _tinyPng : hugeBytes,
          path: next,
        );

      await tester.pumpWidget(
        MaterialApp(theme: KlaykTheme.dark(), home: StartLiveScreen(coverPicker: pickNext)),
      );
      await tester.pump();

      // .gif → erro de formato, sem preview.
      await tester.tap(find.text('Adicionar capa (opcional)'));
      await tester.pump();
      expect(find.text('Formato não suportado. Use PNG, JPG ou WEBP.'),
          findsOneWidget);
      expect(find.byType(Image), findsNothing);

      // >10MB → erro de tamanho, sem preview.
      next = huge.path;
      await tester.tap(find.text('Adicionar capa (opcional)'));
      await tester.pumpAndSettle();
      expect(find.text('Imagem muito grande (máx. 10 MB). Escolha outra.'),
          findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    }, skip: kIsWeb ? true : false);

    testWidgets('upload real→criar live→cover_url na listagem',
        (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(const {});
      final db = SupabaseService.instance;

      // Login real (mesmo serviço que a tela de login usa).
      await runReal(tester, () => db.signInWithEmail(_adminEmail, _password));
      expect(db.hasSession, isTrue,
          reason: 'sessão real do admin para a capa E2E');

      final tmp = File(
          '${Directory.systemTemp.path}/klay_cover_real_${DateTime.now().millisecondsSinceEpoch}.png');
      tmp.writeAsBytesSync(_tinyPng);

      String? createdCoverUrl;
      String? liveId;
      try {
        // Upload REAL para o bucket público `covers` (mesma chamada do app).
        createdCoverUrl =
            await runReal(tester, () => ContentService.instance.uploadCover(
                  tmp,
                  coverExtension: 'png',
                ));
        expect(createdCoverUrl, isNotNull);
        expect(createdCoverUrl,
            startsWith('https://oysyuialaelzcxxkfdsl.supabase.co/storage/v1/object/public/covers/'));

        // Cria a live REAL com a capa (createLive repassa cover_url).
        final suffix = DateTime.now().millisecondsSinceEpoch;
        final liveResult = await runReal(tester, () => db.createLive(
              title: 'E2E capa $suffix',
              description: '',
              category: 'Jogos',
              hashtags: const ['e2e'],
              privacy: 'public',
              coverUrl: createdCoverUrl,
            ));
        final live = liveResult!;
        liveId = live.id;
        expect(live.coverUrl, createdCoverUrl);

        // A capa aparece na listagem oficial de lives ativas.
        final rows = await runReal(tester, db.fetchActiveLives);
        final found = (rows ?? const <RealLive>[])
            .where((l) => l.id == liveId)
            .toList();
        expect(found, hasLength(1),
            reason: 'live recém-criada deve estar em fetchActiveLives');
        expect(found.first.coverUrl, createdCoverUrl,
            reason: 'cover_url persistido no registro chega à listagem');
      } finally {
        // Cleanup real: encerra a live e remove o objeto do storage.
        if (liveId != null) {
          try {
            await runReal(tester, () => db.endLive(liveId!));
          } catch (_) {}
        }
        if (createdCoverUrl != null) {
          await runReal(tester, () => ContentService.instance
              .removeCoverObject(createdCoverUrl!));
        }
        await runReal(tester, db.signOut);
        tmp.existsSync() ? tmp.deleteSync() : null;
      }
    }, skip: skipUnlessE2E());
  });
}