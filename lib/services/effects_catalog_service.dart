import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_creation_models.dart';

/// Catálogo de efeitos com paginação e cache local.
///
/// Decisões de arquitetura:
///  * O catálogo é uma lista simples e pode crescer para milhares de itens —
///    a UI pede **páginas**, nunca o catálogo inteiro ([paginate]).
///  * Os números de popularidade têm origem declarada ([PopularitySource]).
///    Enquanto não houver tabela de uso no backend, ficam marcados como
///    demonstração e o app informa isso, em vez de fingir dado real.
///  * Efeitos 3D/AR e de IA entram no catálogo com o renderer correto e
///    `isUsable == false`. Não são apresentados como se funcionassem.
class EffectsCatalog {
  EffectsCatalog._();

  /// Construtor para testes: instância isolada, sem estado global.
  @visibleForTesting
  EffectsCatalog.forTesting();

  static final EffectsCatalog instance = EffectsCatalog._();

  /// Tamanho de página. Pequeno de propósito: cada página carrega thumbnails.
  static const int pageSize = 24;

  /// Origem dos números de popularidade. Sem tabela de uso no backend, é
  /// [PopularitySource.demoOnly] — e a UI avisa que são dados de demonstração.
  PopularitySource popularitySource = PopularitySource.demoOnly;

  final Map<String, EffectModel> _byId = <String, EffectModel>{};
  final List<EffectModel> _order = <EffectModel>[];

  int get length => _order.length;

  bool get isEmpty => _order.isEmpty;

  /// Carrega o catálogo base. Idempotente.
  Future<void> load() async {
    if (_order.isEmpty) _seedSync();
  }

  /// Semeia em memória: mantém as leituras síncronas (favoritos, update)
  /// consistentes mesmo antes do primeiro [paginate].
  void _seedSync() {
    if (_order.isNotEmpty) return;
    for (final e in _seedCatalog()) {
      _byId[e.id] = e;
      _order.add(e);
    }
  }

  EffectModel? byId(String id) {
    // Sem isto, uma leitura antes do primeiro [paginate] devolveria null.
    if (_order.isEmpty) _seedSync();
    return _byId[id];
  }

  /// Substitui o estado de um efeito e notifica via [watch] se houver.
  void _put(EffectModel effect) {
    if (_order.isEmpty) _seedSync();
    _byId[effect.id] = effect;
    final i = _order.indexWhere((e) => e.id == effect.id);
    if (i >= 0) _order[i] = effect;
  }

  /// Uma página de [category], filtrada e ordenada.
  ///
  /// `offset`/`limit` existem para a faixa horizontal carregar por partes.
  Future<EffectPage> paginate(
    EffectCategory category, {
    int offset = 0,
    int limit = pageSize,
  }) async {
    await load();
    final filtered = _byCategory(category);
    final slice = filtered.skip(offset).take(limit).toList();
    return EffectPage(
      effects: slice,
      hasMore: offset + slice.length < filtered.length,
      total: filtered.length,
    );
  }

  List<EffectModel> _byCategory(EffectCategory category) {
    switch (category) {
      case EffectCategory.favorites:
        return _order.where((e) => e.isFavorite).toList();
      case EffectCategory.top:
        // Real: ordena por uso. Em demo, os números são de demonstração e a
        // origem está declarada em [popularitySource].
        final list = [..._order]..sort((a, b) => b.usageCount.compareTo(a.usageCount));
        return list;
      case EffectCategory.newest:
        final list = [..._order]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      default:
        return _order.where((e) => e.category == category).toList();
    }
  }

  /// Aplica um estado novo (download concluído, favorito, etc.).
  void update(EffectModel effect) => _put(effect);

  /// Alterna favorito. Devolve o estado final.
  bool toggleFavorite(String id) {
    if (_order.isEmpty) _seedSync();
    final e = _byId[id];
    if (e == null) return false;
    final next = e.copyWith(isFavorite: !e.isFavorite);
    _put(next);
    return next.isFavorite;
  }

  /// Contagem de favoritos, para decidir se a aba aparece.
  int get favoritesCount => _order.where((e) => e.isFavorite).length;

  // ---------------------------------------------------------------------------
  // Cache local dos recursos baixados
  // ---------------------------------------------------------------------------
  // Layout em disco: <appSupport>/klayk_effects/<id>/<arquivo>
  // Verificar a existência do arquivo no disco é a fonte da verdade — o
  // registro em memória pode mentir se o app foi limpo.

  Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/klayk_effects');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _dirOf(String id) async {
    final root = await _root();
    final dir = Directory('${root.path}/$id');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Caminho do recurso, ou null se ainda não baixado.
  Future<String?> localAssetPath(String id) async {
    try {
      final dir = await _dirOf(id);
      if (!await dir.exists()) return null;
      await for (final e in dir.list()) {
        if (e is File && await e.length() > 0) return e.path;
      }
    } catch (_) {}
    return null;
  }

  /// Marca como disponível se o arquivo já estiver em disco.
  ///
  /// Chamado ao abrir a câmera: um efeito baixado continua offline mesmo que
  /// o processo anterior tenha morrido.
  Future<EffectModel> refreshAssetState(String id) async {
    final e = _byId[id];
    if (e == null || e.assetUrl == null) return (throw StateError('id desconhecido'));
    final path = await localAssetPath(id);
    if (path == null) {
      return _byId[id] = e.copyWith(
        assetState: EffectAssetState.remote,
        localPath: null,
        downloadProgress: 0,
      );
    }
    return _byId[id] = e.copyWith(
      assetState: EffectAssetState.ready,
      localPath: path,
      downloadProgress: 1,
    );
  }

  /// Registra progresso real de download.
  void reportDownloadProgress(String id, double progress) {
    if (_order.isEmpty) _seedSync();
    final e = _byId[id];
    if (e == null) return;
    // Efeito sem asset (filtro embutido) não tem download: ignorar, senão ele
    // apareceria como "baixando" para sempre na faixa.
    if (e.assetUrl == null) return;
    _put(
      e.copyWith(
        assetState: EffectAssetState.downloading,
        downloadProgress: progress.clamp(0.0, 1.0),
      ),
    );
  }

  void reportDownloadFailed(String id) {
    if (_order.isEmpty) _seedSync();
    final e = _byId[id];
    if (e == null) return;
    _put(
      e.copyWith(
        assetState: EffectAssetState.failed,
        downloadProgress: 0,
        localPath: null,
      ),
    );
  }

  /// Marca pronto e guarda o caminho local.
  EffectModel? reportDownloadDone(String id, String path) {
    if (_order.isEmpty) _seedSync();
    final e = _byId[id];
    if (e == null) return null;
    final next = e.copyWith(
      assetState: EffectAssetState.ready,
      downloadProgress: 1,
      localPath: path,
    );
    _put(next);
    return next;
  }

  /// Quantos efeitos já estão em disco (para o badge "offline").
  Future<int> downloadedCount() async {
    await load();
    var n = 0;
    for (final e in _order) {
      if (e.assetUrl == null) continue;
      if (await localAssetPath(e.id) != null) n++;
    }
    return n;
  }

  /// Remove o recurso do disco e volta para [EffectAssetState.remote].
  Future<bool> removeAsset(String id) async {
    try {
      final dir = await _dirOf(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      return false;
    }
    final e = _byId[id];
    if (e != null) {
      _put(
        e.copyWith(
          assetState: EffectAssetState.remote,
          localPath: null,
          downloadProgress: 0,
        ),
      );
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Seed de desenvolvimento
  // ---------------------------------------------------------------------------
  // Efeitos reais = filtros de cor built-in (funcionam sem asset).
  // Efeitos com asset = continuam `remote` até serem baixados.
  // Efeitos 3D/AR e IA = listados com renderer correto e `isUsable == false`.

  static final DateTime _t0 = DateTime(2026, 1, 1);

  List<EffectModel> _seedCatalog() => [
    // ---- Filtros 2D que funcionam hoje, sem download ----
    _filter('fx_none', 'Original', EffectCategory.face, usageCount: 990),
    _filter('fx_warm', 'Quente', EffectCategory.face, usageCount: 820),
    _filter('fx_cold', 'Frio', EffectCategory.face, usageCount: 610),
    _filter('fx_fade', 'Esmaecido', EffectCategory.beauty, usageCount: 540),
    _filter('fx_bw', 'P&B', EffectCategory.beauty, usageCount: 470),
    _filter('fx_vivid', 'Vívido', EffectCategory.face, usageCount: 430),
    _filter('fx_night', 'Noturno', EffectCategory.face, usageCount: 300),
    _filter('fx_sepia', 'Sépia', EffectCategory.special, usageCount: 220),
    _filter('fx_pink', 'Rosa KLAY K', EffectCategory.face, usageCount: 950),
    _filter('fx_glow', 'Brilho roxo', EffectCategory.special, usageCount: 880),

    // ---- Overlays 2D: precisam de asset, mas são overlay real ----
    _overlay('fx_cat_ears', 'Orelhas de gato', EffectCategory.animals, 12, 3),
    _overlay('fx_dog_tongue', 'Focinho de cachorro', EffectCategory.animals, 9, 5),
    _overlay('fx_star_glasses', 'Óculos de estrela', EffectCategory.accessories, 8, 2),
    _overlay('fx_heart_eyes', 'Olhos de coração', EffectCategory.face, 10, 1),
    _overlay('fx_crown', 'Coroa', EffectCategory.accessories, 7, 4),
    _overlay('fx_flower', 'Flor no cabelo', EffectCategory.beauty, 6, 6),
    _overlay('fx_sparkle', 'Brilhos', EffectCategory.special, 11, 7),
    _overlay('fx_clown_nose', 'Nariz de palhaço', EffectCategory.funny, 5, 8),
    _overlay('fx_elf_ears', 'Orelhas de elfo', EffectCategory.masks, 6, 9),
    _overlay('fx_galaxy', 'Galáxia', EffectCategory.masks, 14, 10),
    _overlay('fx_mustache', 'Bigode', EffectCategory.funny, 4, 11),
    _overlay('fx_bunny_ears', 'Orelhas de coelho', EffectCategory.animals, 8, 12),

    // ---- 3D/AR: catalogados, porém isUsable == false até existir tracking ----
    _ar('ar_panda_head', 'Cabeça de panda 3D', EffectCategory.ar3d, 40),
    _ar('ar_tiger_head', 'Tigre 3D', EffectCategory.ar3d, 38),
    _ar('ar_planet', 'Planeta flutuante', EffectCategory.ar3d, 35),
    _ar('ar_dragon', 'Dragão', EffectCategory.ar3d, 33),
    _ar('ar_bunny_3d', 'Coelho 3D', EffectCategory.animals, 30),
    _ar('ar_mech', 'Mech', EffectCategory.ar3d, 28),

    // ---- IA: mesma situação, aguardando provedor ----
    _ai('ai_style_cartoon', 'Estilo cartoon', 44),
    _ai('ai_style_anime', 'Estilo anime', 42),
    _ai('ai_age', 'Envelhecer', 36),
    _ai('ai_style_vangogh', 'Pintura', 34),
    _ai('ai_recolor_hair', 'Trocar cor do cabelo', 31),
  ];

  static EffectModel _filter(
    String id,
    String name,
    EffectCategory category, {
    int usageCount = 0,
  }) => EffectModel(
    id: id,
    name: name,
    category: category,
    renderer: EffectRenderer.colorFilter,
    createdAt: _t0,
    usageCount: usageCount,
    // Sem assetUrl: não precisa download e já nasce pronto.
    assetState: EffectAssetState.ready,
    downloadProgress: 1,
  );

  static EffectModel _overlay(
    String id,
    String name,
    EffectCategory category,
    int daysAgo,
    int usageCount,
  ) => EffectModel(
    id: id,
    name: name,
    category: category,
    renderer: EffectRenderer.overlay2d,
    assetUrl: 'https://cdn.klayk.app/effects/$id.png',
    estimatedBytes: 180 * 1024,
    createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
    usageCount: usageCount,
  );

  static EffectModel _ar(
    String id,
    String name,
    EffectCategory category,
    int daysAgo,
  ) => EffectModel(
    id: id,
    name: name,
    category: category,
    renderer: EffectRenderer.ar3d,
    assetUrl: 'https://cdn.klayk.app/effects/$id.glb',
    estimatedBytes: 3 * 1024 * 1024,
    createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
  );

  static EffectModel _ai(String id, String name, int daysAgo) => EffectModel(
    id: id,
    name: name,
    category: EffectCategory.ai,
    renderer: EffectRenderer.aiTransform,
    assetUrl: 'https://cdn.klayk.app/effects/$id.model',
    estimatedBytes: 8 * 1024 * 1024,
    createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
  );
}

/// Trilhas de música do fluxo de criação.
///
/// Nenhum áudio protegido por direitos autorais entra como asset: os itens de
/// desenvolvimento apontam para `audioUrl` vazio e ficam marcados como
/// "sem fonte" até o backend de áudio existir. Isso evita distribute
/// material de terceiro dentro do aplicativo.
class TracksCatalog {
  TracksCatalog._();

  /// Construtor para testes: instância isolada, sem estado global.
  @visibleForTesting
  TracksCatalog.forTesting();

  static final TracksCatalog instance = TracksCatalog._();

  static const int pageSize = 20;

  final Map<String, TrackModel> _byId = <String, TrackModel>{};
  final List<TrackModel> _order = <TrackModel>[];

  int get length => _order.length;

  Future<void> load() async {
    if (_order.isEmpty) _seedTracksSync();
  }

  void _seedTracksSync() {
    if (_order.isNotEmpty) return;
    final seed = <TrackModel>[
      const TrackModel(id: 'trk_01', title: 'Original', artist: 'Sem música'),
      const TrackModel(
        id: 'trk_02',
        title: 'Neon Pulse',
        artist: 'KLAY K Studio',
      ),
      const TrackModel(id: 'trk_03', title: 'Violet Drive', artist: 'ASTRAL TECH'),
      const TrackModel(id: 'trk_04', title: 'Midnight Feed', artist: 'KLAY K Studio'),
      const TrackModel(id: 'trk_05', title: 'Glow Up', artist: 'ASTRAL TECH'),
      const TrackModel(id: 'trk_06', title: 'Slow Signal', artist: 'KLAY K Studio'),
      const TrackModel(id: 'trk_07', title: 'Hyper Loop', artist: 'ASTRAL TECH'),
      const TrackModel(id: 'trk_08', title: 'Quiet Room', artist: 'KLAY K Studio'),
      const TrackModel(
        id: 'trk_09',
        title: 'Purple Rain (instrumental livre)',
        artist: 'Domínio público',
      ),
      const TrackModel(id: 'trk_10', title: 'Bass Line', artist: 'ASTRAL TECH'),
    ];
    for (final t in seed) {
      _byId[t.id] = t;
      _order.add(t);
    }
  }

  TrackModel? byId(String id) {
    if (_order.isEmpty) _seedTracksSync();
    return _byId[id];
  }

  Future<TrackPage> paginate({
    required String query,
    int offset = 0,
    int limit = pageSize,
  }) async {
    await load();
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? [..._order]
        : _order
              .where(
                (t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q),
              )
              .toList();
    final slice = filtered.skip(offset).take(limit).toList();
    return TrackPage(
      tracks: slice,
      hasMore: offset + slice.length < filtered.length,
      total: filtered.length,
    );
  }

  /// Alterna favorito de uma trilha.
  bool toggleFavorite(String id) {
    if (_order.isEmpty) _seedTracksSync();
    final t = _byId[id];
    if (t == null) return false;
    final next = t.copyWith(isFavorite: !t.isFavorite);
    _byId[id] = next;
    final i = _order.indexWhere((x) => x.id == id);
    if (i >= 0) _order[i] = next;
    return next.isFavorite;
  }

  List<TrackModel> get favorites =>
      _order.where((t) => t.isFavorite).toList();

  void update(TrackModel track) {
    if (_order.isEmpty) _seedTracksSync();
    _byId[track.id] = track;
    final i = _order.indexWhere((x) => x.id == track.id);
    if (i >= 0) _order[i] = track;
  }
}