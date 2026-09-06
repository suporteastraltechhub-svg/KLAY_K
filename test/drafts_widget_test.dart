// Testes WIDGET offline do módulo de rascunhos:
//  - DraftsScreen._edit: abre diálogo pré-preenchido, salva descrição/#tags
//    (parse de tokens `#`) e recarrega a lista — com DraftStore fake
//    injetado (sem rede);
//  - UploadScreen._saveDraft: sem vídeo → aviso claro; no modo local (sem
//    Supabase configurado) → "Rascunho salvo!" e descrição limpa;
//  - UploadScreen._saveDraft com DraftStore INJETADO: exercita a orquestração
//    completa do ramo real (bytes do vídeo → upload → create → snackbar →
//    limpar descrição), sem rede.
//
// O fluxo E2E de verdade (Supabase real) fica em test/e2e_drafts_flow_test.dart
// (KLAY_E2E=true); rodar rede real dentro do relógio fake do testWidgets é
// instável/indeterminado, então o contrato também é validado por E2E a nível
// de serviço.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/main.dart';
import 'package:klay_k/models/post_models.dart';
import 'package:klay_k/screens/drafts_screen.dart';
import 'package:klay_k/services/drafts_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

/// Armazenamento fake em memória: registra chamadas e "persiste" edições,
/// sem tocar na rede (mesmo contrato do [DraftsService] real).
class FakeDraftStore implements DraftStore {
  final List<Draft> drafts;
  int listCalls = 0;
  final List<Map<String, dynamic>> updates = [];

  FakeDraftStore(this.drafts);

  @override
  Future<List<Draft>> list() async {
    listCalls++;
    return List.of(drafts);
  }

  @override
  Future<Draft?> get(String id) async {
    for (final d in drafts) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Future<Draft> create({
    String videoPath = '',
    String coverPath = '',
    String description = '',
    String audioName = '',
    List<String> hashtags = const [],
    String location = '',
    int durationSeconds = 0,
  }) async {
    final now = DateTime.now();
    final d = Draft(
      id: 'fake-${drafts.length + 1}',
      videoPath: videoPath,
      coverPath: coverPath,
      description: description,
      audioName: audioName,
      hashtags: hashtags,
      location: location,
      durationSeconds: durationSeconds,
      createdAt: now,
      updatedAt: now,
    );
    drafts.add(d);
    return d;
  }

  @override
  Future<void> update(
    Draft d, {
    String? videoPath,
    String? coverPath,
    String? description,
    String? audioName,
    List<String>? hashtags,
    String? location,
    int? durationSeconds,
    String? postId,
  }) async {
    updates.add({'id': d.id, 'description': description, 'hashtags': hashtags});
    for (var i = 0; i < drafts.length; i++) {
      if (drafts[i].id != d.id) continue;
      drafts[i] = Draft(
        id: drafts[i].id,
        videoPath: videoPath ?? drafts[i].videoPath,
        coverPath: coverPath ?? drafts[i].coverPath,
        description: description ?? drafts[i].description,
        audioName: audioName ?? drafts[i].audioName,
        hashtags: hashtags ?? drafts[i].hashtags,
        location: location ?? drafts[i].location,
        durationSeconds: durationSeconds ?? drafts[i].durationSeconds,
        postId: postId ?? drafts[i].postId,
        createdAt: drafts[i].createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> remove(String id) async {
    drafts.removeWhere((d) => d.id == id);
  }

  @override
  Future<void> markPublished(String id) async {}

  @override
  Future<String> uploadVideoBytes(
    String path,
    Uint8List bytes, {
    String contentType = 'video/mp4',
  }) async =>
      'fake/videos/$path';

  @override
  Future<String> uploadVideoFile(
    File file, {
    String? contentType,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(0.5);
    onProgress?.call(1.0);
    final name = file.path.split('/').last;
    return 'fake/videos/$name';
  }

  @override
  Future<String> uploadCoverBytes(
    String path,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async =>
      'fake/covers/$path';

  @override
  Future<String?> temporaryUrl(Draft d) async => null;

  @override
  Future<FeedPost?> publish(String draftId) async => null;
}

Draft sampleDraft(String id,
    {String description = '', List<String> hashtags = const []}) {
  final now = DateTime.now();
  return Draft(
    id: id,
    description: description,
    hashtags: hashtags,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('rascunhos: lista vazia mostra o estado vazio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: KlaykTheme.dark(), home: DraftsScreen(store: FakeDraftStore([]))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhum rascunho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('_edit: abre diálogo pré-preenchido, salva descrição e #tags e '
      'recarrega a lista', (tester) async {
    final store = FakeDraftStore([
      sampleDraft('d1', description: 'viagem', hashtags: const ['klayk', 'amigo']),
    ]);
    await tester.pumpWidget(MaterialApp(theme: KlaykTheme.dark(), home: DraftsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('viagem'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();

    // Diálogo pré-preenchido com a descrição e as hashtags como #tokens.
    expect(find.text('Editar rascunho'), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'viagem');
    expect(
        tester.widget<TextField>(fields.at(1)).controller!.text, '#klayk #amigo');

    await tester.enterText(fields.at(0), 'viagem à praia');
    await tester.enterText(fields.at(1), '#klayk #nova');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(store.updates, hasLength(1), reason: 'Salvar chama _svc.update');
    expect(store.updates.single['description'], 'viagem à praia');
    expect(store.updates.single['hashtags'], ['klayk', 'nova']);
    expect(store.listCalls, greaterThanOrEqualTo(2),
        reason: '_edit recarrega a lista depois de salvar');
    expect(find.text('viagem à praia'), findsOneWidget,
        reason: 'tile reflete a edição após o reload');
    expect(tester.takeException(), isNull);
  });

  testWidgets('_edit: palavra sem # é descartada no parse de hashtags',
      (tester) async {
    final store = FakeDraftStore([sampleDraft('d1')]);
    await tester.pumpWidget(MaterialApp(theme: KlaykTheme.dark(), home: DraftsScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'meu vídeo');
    await tester.enterText(fields.at(1), '#klayk nãotag #e2e');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(store.updates.single['hashtags'], ['klayk', 'e2e'],
        reason: 'só tokens que começam com # viram hashtag');
    expect(tester.takeException(), isNull);
  });

  testWidgets('_saveDraft: modo local (sem backend) não exige vídeo e limpa '
      'a descrição', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
        theme: KlaykTheme.dark(), home: const UploadScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'meu vídeo #teste');
    await tester.ensureVisible(find.text('Salvar rascunho'));
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sem Supabase configurado o guard demo termina antes da checagem de
    // vídeo: simula o salvamento e limpa a descrição.
    expect(find.text('Rascunho salvo!'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: '_saveDraft limpa a descrição após salvar (modo local)',
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('_saveDraft: modo local salva com vídeo selecionado e cai no '
      'fallback do preview', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tmp = File(
        '${Directory.systemTemp.path}/klay_draft_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
    tmp.writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

    const channel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'pickVideo' ? tmp.path : null,
    );
    addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
        theme: KlaykTheme.dark(), home: const UploadScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'meu vídeo #teste');
    await tester.tap(find.text('Escolher da galeria'));
    await tester.pumpAndSettle();

    // O preview tenta inicializar o video_player (sem plataforma aqui) e deve
    // cair no fallback de erro — não pode vazar exceção nem travar.
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);

    await tester.ensureVisible(find.text('Salvar rascunho'));
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Rascunho salvo!'), findsOneWidget,
        reason: 'modo local simula o salvamento sem backend');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: '_saveDraft limpa a descrição após salvar (modo local)',
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('_saveDraft: with injected store, grava bytes->upload->create, '
      'parseia #tags e limpa a descrição', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = FakeDraftStore([]);
    final tmp = File(
        '${Directory.systemTemp.path}/klay_draft_inject_${DateTime.now().millisecondsSinceEpoch}.mp4');
    tmp.writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

    const channel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'pickVideo' ? tmp.path : null,
    );
    addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    await tester
        .pumpWidget(MaterialApp(
            theme: KlaykTheme.dark(), home: UploadScreen(draftsStore: store)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'meu vídeo #e2e #teste');
    await tester.tap(find.text('Escolher da galeria'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);

    await tester.ensureVisible(find.text('Salvar rascunho'));
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Rascunho salvo! Você pode finalizar em Rascunhos.'),
        findsOneWidget,
        reason: '_saveDraft do ramo real mostra a snackbar de sucesso');

    expect(store.drafts, hasLength(1),
        reason: 'injected store criou exatamente 1 rascunho');
    final created = store.drafts.single;
    expect(created.videoPath, startsWith('fake/videos/'),
        reason: '_saveDraft envia o vídeo ao bucket privado (via store)');
    expect(created.description, 'meu vídeo #e2e #teste');
    expect(created.hashtags, ['klayk', 'e2e', 'teste'],
        reason: '_saveDraft parseia as #tags da descrição (com klayk padrão)');

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: '_saveDraft limpa a descrição após salvar',
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}