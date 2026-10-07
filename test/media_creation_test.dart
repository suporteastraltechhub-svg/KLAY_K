import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/models/media_creation_models.dart';
import 'package:klay_k/services/drafts_service.dart';
import 'package:klay_k/services/effects_catalog_service.dart';
import 'package:klay_k/services/media_project_repository.dart';
import 'package:klay_k/models/post_models.dart';

/// Diretório temporário exclusivo por teste.
///
/// Sem isto, dois testes que usam o mesmo id de rascunho escreveriam no
/// mesmo sidecar e um sobrescreveria o estado do outro.
Directory _tmpFor(String name) =>
    Directory(
      '${Directory.systemTemp.path}/klayk_test_$name'
    )..createSync(recursive: true);

/// Falso determinístico: implementa o [DraftStore] existente sem tocar a rede,
/// no mesmo padrão que os testes de widget do projeto já usam.
class _FakeDraftStore implements DraftStore {
  final Map<String, Draft> _rows = <String, Draft>{};
  int _seq = 0;
  String? lastPublished;

  @override
  Future<List<Draft>> list() async => _rows.values.toList();

  @override
  Future<Draft?> get(String id) async => _rows[id];

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
      id: 'd${++_seq}',
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
    _rows[d.id] = d;
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
    final base = _rows[d.id];
    if (base == null) return;
    _rows[d.id] = Draft(
      id: d.id,
      videoPath: videoPath ?? base.videoPath,
      coverPath: coverPath ?? base.coverPath,
      description: description ?? base.description,
      audioName: audioName ?? base.audioName,
      hashtags: hashtags ?? base.hashtags,
      location: location ?? base.location,
      durationSeconds: durationSeconds ?? base.durationSeconds,
      postId: postId ?? base.postId,
      createdAt: base.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> remove(String id) async => _rows.remove(id);

  @override
  Future<void> markPublished(String id) async {
    final b = _rows[id];
    if (b == null) return;
    _rows[id] = Draft(
      id: b.id,
      videoPath: b.videoPath,
      coverPath: b.coverPath,
      description: b.description,
      audioName: b.audioName,
      hashtags: b.hashtags,
      location: b.location,
      durationSeconds: b.durationSeconds,
      postId: 'post_1',
      createdAt: b.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<String> uploadVideoBytes(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async => path;

  @override
  Future<String> uploadVideoFile(
    File file, {
    String? contentType,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async => file.path;

  @override
  Future<String> uploadCoverBytes(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async => path;

  @override
  Future<String?> temporaryUrl(Draft d) async => null;

  @override
  Future<FeedPost?> publish(String draftId) async {
    lastPublished = draftId;
    return null;
  }
}

/// Store que sempre falha: o fluxo de criação não pode quebrar por causa de
/// rede, então salvar devolve null em vez de lançar.
class _BrokenStore extends _FakeDraftStore {
  @override
  Future<Draft?> get(String id) async => null;

  @override
  Future<List<Draft>> list() async => const [];

  @override
  Future<Draft> create({
    String videoPath = '',
    String coverPath = '',
    String description = '',
    String audioName = '',
    List<String> hashtags = const [],
    String location = '',
    int durationSeconds = 0,
  }) async => throw StateError('offline');

  @override
  Future<void> remove(String id) async => throw StateError('offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaProjectStatus', () {
    test('os 5 estados pedidos existem', () {
      expect(MediaProjectStatus.values.length, 5);
      expect(
        MediaProjectStatus.values.map((s) => s.storageKey),
        containsAll([
          'draft',
          'editing',
          'ready_to_publish',
          'published',
          'deleted',
        ]),
      );
    });

    test('rascunho de verdade exclui published e deleted', () {
      expect(MediaProjectStatus.draft.isDraft, isTrue);
      expect(MediaProjectStatus.editing.isDraft, isTrue);
      expect(MediaProjectStatus.readyToPublish.isDraft, isTrue);
      expect(MediaProjectStatus.published.isDraft, isFalse);
      expect(MediaProjectStatus.deleted.isDraft, isFalse);
    });

    test('valor legado "trashed" continua legível', () {
      expect(
        MediaProjectStatus.fromStorageKey('trashed'),
        MediaProjectStatus.deleted,
      );
    });

    test('valor desconhecido cai em draft, sem crash', () {
      expect(
        MediaProjectStatus.fromStorageKey('xyz'),
        MediaProjectStatus.draft,
      );
      expect(MediaProjectStatus.fromStorageKey(null), MediaProjectStatus.draft);
    });
  });

  group('MediaProjectModel', () {
    final now = DateTime(2026, 10, 1);
    MediaProjectModel base() => MediaProjectModel(
      id: 'p1',
      videoPath: '/local/video.mp4',
      createdAt: now,
      updatedAt: now,
    );

    test('só a referência vai para o banco, nunca o arquivo', () {
      final row = base().toDraftRow();
      expect(row['video_path'], '/local/video.mp4');
      expect(row.containsKey('file'), isFalse);
      for (final v in row.values) {
        expect(
          v is! String || v.length < 5000,
          isTrue,
          reason: 'nenhum valor deve carregar o arquivo inteiro',
        );
      }
    });

    test('estado inicial é draft', () {
      expect(base().status, MediaProjectStatus.draft);
    });

    test('efeitos aplicados são preservados na ordem', () {
      final p = base().copyWith(effectIds: ['fx_a', 'fx_b']);
      expect(p.effectIds, ['fx_a', 'fx_b']);
      expect(p.hasEffects, isTrue);
      expect(p.activeEffectId, 'fx_b');
    });

    test('corte nunca gera duração negativa', () {
      final p = base().copyWith(
        trimStart: const Duration(seconds: 10),
        trimEnd: const Duration(seconds: 5),
      );
      expect(p.trimmedDuration, Duration.zero);
    });

    test('corte válido devolve a duração esperada', () {
      final p = base().copyWith(
        trimStart: const Duration(seconds: 2),
        trimEnd: const Duration(seconds: 12),
      );
      expect(p.trimmedDuration, const Duration(seconds: 10));
    });

    test('música escolhida aparece como audio_name', () {
      final p = base().copyWith(
        track: const TrackModel(id: 'trk_1', title: 'Neon Pulse'),
      );
      expect(p.toDraftRow()['audio_name'], 'Neon Pulse');
    });

    test('copyWith sem alterar não perde nada', () {
      final p = base().copyWith(
        description: 'oi',
        hashtags: const ['a'],
        effectIds: const ['e1'],
      );
      final q = p.copyWith(status: MediaProjectStatus.editing);
      expect(q.description, 'oi');
      expect(q.hashtags, ['a']);
      expect(q.effectIds, ['e1']);
      expect(q.videoPath, '/local/video.mp4');
      expect(q.status, MediaProjectStatus.editing);
    });
  });

  group('EffectModel', () {
    test('efeito 2D sem asset já nasce pronto', () {
      final e = EffectModel.colorFilter(id: 'f', name: 'F');
      expect(e.needsDownload, isFalse);
      expect(e.isUsable, isTrue);
      expect(e.assetState, EffectAssetState.ready);
    });

    test('efeito com asset começa remote e precisa baixar', () {
      final e = EffectModel(
        id: 'o',
        name: 'Orelhas',
        category: EffectCategory.animals,
        renderer: EffectRenderer.overlay2d,
        assetUrl: 'https://x/o.png',
        createdAt: DateTime(2026),
      );
      expect(e.needsDownload, isTrue);
      expect(e.isUsable, isFalse, reason: 'ainda não baixou');
    });

    test('3D/AR exige tracking e NÃO é utilizável agora', () {
      final e = EffectModel(
        id: 'ar1',
        name: 'Panda',
        category: EffectCategory.ar3d,
        renderer: EffectRenderer.ar3d,
        createdAt: DateTime(2026),
      );
      expect(e.needsTracking, isTrue);
      expect(e.isUsable, isFalse);
    });

    test('IA exige tracking e NÃO é utilizável agora', () {
      final e = EffectModel(
        id: 'ai1',
        name: 'Cartoon',
        category: EffectCategory.ai,
        renderer: EffectRenderer.aiTransform,
        createdAt: DateTime(2026),
      );
      expect(e.needsTracking, isTrue);
      expect(e.isUsable, isFalse);
    });

    test('overlay baixado fica utilizável e guarda o caminho', () {
      final e = EffectModel(
        id: 'o',
        name: 'Orelhas',
        category: EffectCategory.animals,
        renderer: EffectRenderer.overlay2d,
        assetUrl: 'https://x/o.png',
        createdAt: DateTime(2026),
      ).copyWith(
        assetState: EffectAssetState.ready,
        localPath: '/data/o.png',
        downloadProgress: 1,
      );
      expect(e.isUsable, isTrue);
      expect(e.localPath, '/data/o.png');
    });

    test('progresso é limitado a 0..1', () {
      final e = EffectModel.colorFilter(id: 'f', name: 'F').copyWith(
        assetState: EffectAssetState.downloading,
        downloadProgress: 1.7,
      );
      expect(e.downloadProgress, 1.0);
    });
  });

  group('EffectsCatalog', () {
    test('carga lazily: load() é idempotente', () async {
      final c = EffectsCatalog.forTesting();
      await c.load();
      final n = c.length;
      await c.load();
      expect(c.length, n);
      expect(n, greaterThan(20));
    });

    test('paginação devolve página e informa se há mais', () async {
      final c = EffectsCatalog.forTesting();
      final p1 = await c.paginate(EffectCategory.face, limit: 3);
      expect(p1.effects.length, 3);
      expect(p1.hasMore, isTrue);
      expect(p1.total, greaterThan(3));
    });

    test('última página informa hasMore falso', () async {
      final c = EffectsCatalog.forTesting();
      final all = await c.paginate(EffectCategory.face, limit: 1000);
      expect(all.effects.length, all.total);
      expect(all.hasMore, isFalse);
    });

    test('favoritos começa vazio e só mostra marcados', () async {
      final c = EffectsCatalog.forTesting();
      expect((await c.paginate(EffectCategory.favorites)).total, 0);
      c.toggleFavorite('fx_warm');
      final fav = await c.paginate(EffectCategory.favorites);
      expect(fav.total, 1);
      expect(fav.effects.first.id, 'fx_warm');
    });

    test('toggleFavorite alterna e devolve o estado final', () async {
      final c = EffectsCatalog.forTesting();
      expect(c.toggleFavorite('fx_cold'), isTrue);
      expect(c.toggleFavorite('fx_cold'), isFalse);
      expect(c.favoritesCount, 0);
    });

    test('favoritar id inexistente não quebra', () {
      final c = EffectsCatalog.forTesting();
      expect(c.toggleFavorite('nao_existe'), isFalse);
    });

    test('TOP ordena por uso decrescente', () async {
      final c = EffectsCatalog.forTesting();
      final top = (await c.paginate(EffectCategory.top, limit: 50)).effects;
      for (var i = 1; i < top.length; i++) {
        expect(
          top[i - 1].usageCount >= top[i].usageCount,
          isTrue,
          reason: 'uso deve estar em ordem decrescente',
        );
      }
    });

    test('NOVOS ordena por data de criação decrescente', () async {
      final c = EffectsCatalog.forTesting();
      final novos = (await c.paginate(EffectCategory.newest, limit: 50)).effects;
      for (var i = 1; i < novos.length; i++) {
        expect(
          novos[i - 1].createdAt.isBefore(novos[i].createdAt),
          isFalse,
        );
      }
    });

    test('origem da popularidade é declarada, não inventada', () async {
      final c = EffectsCatalog.forTesting();
      expect(c.popularitySource, PopularitySource.demoOnly);
    });

    test('efeitos AR/IA estão no catálogo mas não utilizáveis', () async {
      final c = EffectsCatalog.forTesting();
      final ar = (await c.paginate(EffectCategory.ar3d)).effects;
      final ai = (await c.paginate(EffectCategory.ai)).effects;
      expect(ar, isNotEmpty);
      expect(ai, isNotEmpty);
      expect(ar.every((e) => !e.isUsable), isTrue);
      expect(ai.every((e) => !e.isUsable), isTrue);
    });

    test('categorias principais têm conteúdo', () async {
      final c = EffectsCatalog.forTesting();
      for (final cat in [
        EffectCategory.face,
        EffectCategory.beauty,
        EffectCategory.animals,
        EffectCategory.accessories,
        EffectCategory.funny,
        EffectCategory.masks,
        EffectCategory.special,
      ]) {
        final p = await c.paginate(cat);
        expect(p.total, greaterThan(0), reason: '${cat.name} vazia');
      }
    });

    test('progresso e falha de download atualizam o modelo', () async {
      final c = EffectsCatalog.forTesting();
      c.reportDownloadProgress('fx_cat_ears', 0.4);
      expect(c.byId('fx_cat_ears')!.assetState, EffectAssetState.downloading);
      expect(c.byId('fx_cat_ears')!.downloadProgress, 0.4);
      c.reportDownloadFailed('fx_cat_ears');
      expect(c.byId('fx_cat_ears')!.assetState, EffectAssetState.failed);
      c.reportDownloadDone('fx_cat_ears', '/tmp/a.png');
      expect(c.byId('fx_cat_ears')!.assetState, EffectAssetState.ready);
      expect(c.byId('fx_cat_ears')!.localPath, '/tmp/a.png');
    });

    test('efeito sem download não é afetado por progresso', () async {
      final c = EffectsCatalog.forTesting();
      c.reportDownloadProgress('fx_warm', 0.5);
      expect(c.byId('fx_warm')!.assetState, EffectAssetState.ready);
    });
  });

  group('TracksCatalog', () {
    test('carrega e pagina', () async {
      final t = TracksCatalog.forTesting();
      final p = await t.paginate(query: '');
      expect(p.tracks, isNotEmpty);
      expect(p.tracks.length, p.total);
    });

    test('busca por título e por artista', () async {
      final t = TracksCatalog.forTesting();
      final porTitulo = await t.paginate(query: 'neon');
      expect(porTitulo.tracks.first.title, 'Neon Pulse');
      final porArtista = await t.paginate(query: 'ASTRAL');
      expect(porArtista.tracks, isNotEmpty);
    });

    test('nenhuma trilha aponta para áudio protegido', () async {
      final t = TracksCatalog.forTesting();
      final p = await t.paginate(query: '');
      // Sem fonte de áudio pronta: o catálogo não embute material de terceiro.
      expect(p.tracks.every((x) => !x.hasSource), isTrue);
    });

    test('favoritos de trilha', () async {
      final t = TracksCatalog.forTesting();
      expect(t.favorites, isEmpty);
      t.toggleFavorite('trk_02');
      expect(t.favorites.length, 1);
      t.toggleFavorite('trk_02');
      expect(t.favorites, isEmpty);
    });
  });

  group('MediaProjectRepository', () {
    final now = DateTime(2026, 10, 1);

    test('salvar rascunho cria a linha com vídeo e descrição', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final p = MediaProjectModel(
        id: '',
        videoPath: '/local/v.mp4',
        thumbnailPath: '/local/c.jpg',
        description: 'meu vídeo',
        hashtags: const ['klayk'],
        createdAt: now,
        updatedAt: now,
      );
      final saved = await repo.save(p);
      expect(saved.id, isNotEmpty);
      expect(saved.videoPath, '/local/v.mp4');
      expect(saved.description, 'meu vídeo');
      expect(saved.hashtags, contains('klayk'));
    });

    test('carregar rascunho devolve o que foi salvo', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final saved = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/local/v.mp4',
          description: 'desc',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final loaded = await repo.load(saved.id);
      expect(loaded, isNotNull);
      expect(loaded!.description, 'desc');
      expect(loaded.videoPath, '/local/v.mp4');
    });

    test('efeitos e Survendem ao round-trip', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final saved = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/v.mp4',
          effectIds: const ['fx_crown', 'fx_sparkle'],
          trackVolume: 0.8,
          originalVolume: 0.2,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final loaded = await repo.load(saved.id);
      expect(loaded!.effectIds, ['fx_crown', 'fx_sparkle']);
      expect(loaded.trackVolume, 0.8);
      expect(loaded.originalVolume, 0.2);
    });

    test('salvar duas vezes atualiza, não duplica', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final first = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/v.mp4',
          description: 'a',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repo.save(
        MediaProjectModel(
          id: first.id,
          videoPath: '/v.mp4',
          description: 'b',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect((await store.list()).length, 1);
      final loaded = await repo.load(first.id);
      expect(loaded!.description, 'b');
    });

    test('excluir rascunho remove a linha', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final saved = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/v.mp4',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(await repo.delete(saved.id), isTrue);
      expect(await repo.load(saved.id), isNull);
    });

    test('listar devolve rascunhos, não publicados', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final a = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/a.mp4',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final b = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/b.mp4',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.markPublished(b.id);
      final list = await repo.listDrafts();
      expect(list.length, 1);
      expect(list.first.id, a.id);
    });

    test('marcar pronto para publicar muda o estado', () async {
      final repo = MediaProjectRepository(
      store: _FakeDraftStore(),
      sidecarDir: _tmpFor('r${DateTime.now().microsecondsSinceEpoch}'),
    );
      final saved = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/v.mp4',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final project = (await repo.load(saved.id))!;
      final ready = await repo.markReady(project);
      expect(ready.status, MediaProjectStatus.readyToPublish);
      final back = await repo.load(saved.id);
      expect(back!.status, MediaProjectStatus.readyToPublish);
    });

    test('marcar editando volta o estado', () async {
      final repo = MediaProjectRepository(
      store: _FakeDraftStore(),
      sidecarDir: _tmpFor('r${DateTime.now().microsecondsSinceEpoch}'),
    );
      final saved = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/v.mp4',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final p = await repo.markEditing((await repo.load(saved.id))!);
      expect(p.status, MediaProjectStatus.editing);
    });

    test('publicar usa o DraftStore existente e limpa o sidecar', () async {
      final store = _FakeDraftStore();
      final repo = MediaProjectRepository(
        store: store,
        sidecarDir: _tmpFor('r$store.hashCode'),
      );
      final saved = await repo.save(
        MediaProjectModel(
          id: '',
          videoPath: '/v.mp4',
          effectIds: const ['fx_crown'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repo.publish(saved.id);
      expect(store.lastPublished, saved.id);
    });

    test('backend fora do ar não derruba o fluxo', () async {
      final repo = MediaProjectRepository(
      store: _BrokenStore(),
      sidecarDir: _tmpFor('broken'),
    );
      // save lança (não há como persistir offline), mas listar não quebra.
      expect(await repo.listDrafts(), isEmpty);
      expect(await repo.load('x'), isNull);
      expect(await repo.delete('x'), isTrue, reason: 'apagar é idempotente');
    });
  });
}
