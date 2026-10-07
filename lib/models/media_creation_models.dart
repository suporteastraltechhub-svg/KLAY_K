

/// Como o efeito é renderizado sobre a câmera.
///
/// A distinção importa: [overlay2d] funciona de verdade no preview (é uma
/// camada Flutter sobre o vídeo). [ar3d] e [aiTransform] exigem rastreamento
/// facial que o projeto **não tem** — ver [EffectModel.needsTracking].
/// Nada de imagem estática é apresentado como se fosse AR.
enum EffectRenderer {
  /// Camada 2D real: PNG/SVG sobreposto ao preview, com blend.
  overlay2d,

  /// 3D/AR: precisa de ARCore/ARKit + motor de renderização.
  ar3d,

  /// IA: precisa de um provedor de processamento de imagem/vídeo.
  aiTransform,

  /// Filtro de cor real, aplicado via ColorFilter.
  colorFilter;

  /// Só [overlay2d] e [colorFilter] rodam hoje sem dependência nova.
  bool get isAvailableOffline =>
      this == EffectRenderer.overlay2d || this == EffectRenderer.colorFilter;
}

/// Categoria do efeito. A barra horizontal usa estes rótulos.
enum EffectCategory {
  favorites,
  top,
  newest,
  ai,
  face,
  beauty,
  masks,
  animals,
  accessories,
  funny,
  ar3d,
  special;

  String get storageKey => name;

  static EffectCategory fromStorageKey(String? raw) {
    for (final c in EffectCategory.values) {
      if (c.name == raw) return c;
    }
    return EffectCategory.face;
  }
}

/// Estado local do recurso de um efeito.
///
/// [remote] ainda não foi baixado. [downloading] está em progresso com
/// [EffectDownload.progress] (0..1). [ready] está no disco local.
enum EffectAssetState { remote, downloading, ready, failed }

/// Efeito do catálogo.
///
/// A arquitetura não limita a quantidade: o catálogo é uma lista simples e o
/// carregamento é paginado/lazy (ver `EffectsCatalog.paginate`).
class EffectModel {
  final String id;

  /// Nome exibido. Mantido no modelo já traduzido pelo catálogo.
  final String name;

  final EffectCategory category;

  /// Ícone/ilustração local do efeito na faixa horizontal.
  final String? thumbnailUrl;

  /// Recurso do efeito. Null para efeitos que não precisam de download
  /// (filtros de cor built-in, por exemplo).
  final String? assetUrl;

  final EffectRenderer renderer;

  /// SHA-256 do recurso, para validar o download e evitar arquivo corrompido.
  final String? assetSha256;

  /// Tamanho estimado em bytes, mostrado antes de baixar.
  final int estimatedBytes;

  final DateTime createdAt;

  /// Contagem de usos. Vem do backend quando existe; em DEBUG sem backend,
  /// `EffectsCatalog` marca a origem como demonstração (ver [demoPopularity]).
  final int usageCount;

  /// Preenchido localmente pelo usuário. Ainda não sincroniza com backend.
  final bool isFavorite;

  final EffectAssetState assetState;

  /// Progresso 0..1 quando [assetState] é [EffectAssetState.downloading].
  final double downloadProgress;

  /// Caminho no cache local quando [assetState] é [EffectAssetState.ready].
  final String? localPath;

  /// Este efeito depende de rastreamento facial/AR que ainda não existe.
  bool get needsTracking => !renderer.isAvailableOffline;

  /// Precisa baixar antes de usar.
  bool get needsDownload =>
      assetUrl != null && assetState == EffectAssetState.remote;

  /// Pode ser aplicado agora.
  bool get isUsable =>
      renderer.isAvailableOffline &&
      (assetUrl == null || assetState == EffectAssetState.ready);

  const EffectModel({
    required this.id,
    required this.name,
    required this.category,
    required this.renderer,
    this.thumbnailUrl,
    this.assetUrl,
    this.assetSha256,
    this.estimatedBytes = 0,
    required this.createdAt,
    this.usageCount = 0,
    this.isFavorite = false,
    this.assetState = EffectAssetState.remote,
    this.downloadProgress = 0,
    this.localPath,
  });

  /// Filtro de cor embutido: funciona sem download nem asset.
///
/// A matriz de cor é resolvida pelo id em [EffectColorFilters]; o modelo
/// guarda só a identidade, o que mantém o catálogo leve mesmo com milhares
/// de filtros.
  factory EffectModel.colorFilter({
    required String id,
    required String name,
    EffectCategory category = EffectCategory.beauty,
  }) => EffectModel(
    id: id,
    name: name,
    category: category,
    renderer: EffectRenderer.colorFilter,
    createdAt: DateTime(2026, 1, 1),
    // Filtro embutido: não tem asset, então já nasce pronto e utilizável.
    assetState: EffectAssetState.ready,
    downloadProgress: 1,
  );

  EffectModel copyWith({
    EffectAssetState? assetState,
    // Limitado aqui, e não só no catálogo: qualquer chamadas de progresso
    // fora de 0..1 é um bug, e aqui ele vira um valor inofensivo em vez de
    // chegar na barra de progresso da câmera.
    double? downloadProgress,
    String? localPath,
    bool? isFavorite,
    int? usageCount,
  }) => EffectModel(
    id: id,
    name: name,
    category: category,
    renderer: renderer,
    thumbnailUrl: thumbnailUrl,
    assetUrl: assetUrl,
    assetSha256: assetSha256,
    estimatedBytes: estimatedBytes,
    createdAt: createdAt,
    usageCount: usageCount ?? this.usageCount,
    isFavorite: isFavorite ?? this.isFavorite,
    assetState: assetState ?? this.assetState,
    downloadProgress: (downloadProgress ?? this.downloadProgress).clamp(0.0, 1.0),
    localPath: localPath ?? this.localPath,
  );

  @override
  bool operator ==(Object other) => other is EffectModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Uma faixa de página do catálogo.
///
/// A UI nunca recebe o catálogo inteiro: pede páginas. Isso mantém a memória
/// estável mesmo com milhares de efeitos.
class EffectPage {
  final List<EffectModel> effects;
  final bool hasMore;
  final int total;

  const EffectPage({
    required this.effects,
    required this.hasMore,
    required this.total,
  });
}

/// Página de trilhas de música, paginada pelo mesmo motivo.
class TrackPage {
  final List<TrackModel> tracks;
  final bool hasMore;
  final int total;

  const TrackPage({
    required this.tracks,
    required this.hasMore,
    required this.total,
  });
}

/// Fonte da qual os números de popularidade vêm.
///
/// Importante para não inventar estatística: enquanto o backend não tiver
/// tabela de uso, o catálogo marca explicitamente que os números são de
/// demonstração e o app sabe dizer isso ao usuário.
enum PopularitySource { backend, demoOnly }

/// Rótulos de categoria, resolvidos fora do modelo para o modelo não depender
/// de `BuildContext`.
class EffectCategoryLabels {
  final Map<EffectCategory, String> labels;

  const EffectCategoryLabels(this.labels);

  String call(EffectCategory c) => labels[c] ?? c.name;
}

/// Música selecionável na criação.
///
/// Nenhum áudio protegido por direitos autorais entra como asset: o catálogo
/// de desenvolvimento usa apenas trilhas próprias/liberadas, e os campos
/// apontam para um backend de áudio quando existir.
class TrackModel {
  final String id;
  final String title;
  final String artist;

  /// Caminho/URL do áudio. Vazio = ainda sem fonte real.
  final String? audioUrl;

  /// Segundos. Permite selecionar o trecho (início/duração) na edição.
  final Duration? duration;

  final bool isFavorite;
  final int usageCount;

  const TrackModel({
    required this.id,
    required this.title,
    this.artist = '',
    this.audioUrl,
    this.duration,
    this.isFavorite = false,
    this.usageCount = 0,
  });

  bool get hasSource => (audioUrl ?? '').isNotEmpty;

  TrackModel copyWith({bool? isFavorite}) => TrackModel(
    id: id,
    title: title,
    artist: artist,
    audioUrl: audioUrl,
    duration: duration,
    isFavorite: isFavorite ?? this.isFavorite,
    usageCount: usageCount,
  );
}

/// Estado do projeto de mídia durante o fluxo de criação.
///
/// É isto que vira rascunho: o arquivo fica no disco e **só a referência vai
/// para o banco**.
enum MediaProjectStatus {
  draft,
  editing,
  readyToPublish,
  published,
  deleted;

  String get storageKey => switch (this) {
    MediaProjectStatus.draft => 'draft',
    MediaProjectStatus.editing => 'editing',
    MediaProjectStatus.readyToPublish => 'ready_to_publish',
    MediaProjectStatus.published => 'published',
    MediaProjectStatus.deleted => 'deleted',
  };

  static MediaProjectStatus fromStorageKey(String? raw) {
    // `trashed` é o valor legado da constraint antiga; continua mapeado
    // para que nenhum rascunho existente fique ilegível.
    switch ((raw ?? 'draft').toLowerCase()) {
      case 'editing':
        return MediaProjectStatus.editing;
      case 'ready_to_publish':
        return MediaProjectStatus.readyToPublish;
      case 'published':
        return MediaProjectStatus.published;
      case 'deleted':
      case 'trashed':
        return MediaProjectStatus.deleted;
      default:
        return MediaProjectStatus.draft;
    }
  }

  /// Rascunho de verdade (ainda não publicado).
  bool get isDraft =>
      this != MediaProjectStatus.published &&
      this != MediaProjectStatus.deleted;
}

/// Projeto de mídia: o conteúdo sendo criado.
///
/// [videoPath] é um caminho **local**; só a referência vai para o Supabase.
class MediaProjectModel {
  final String id;
  final String? videoPath;
  final String? thumbnailPath;
  final String description;
  final List<String> hashtags;

  /// IDs dos efeitos aplicados, na ordem.
  final List<String> effectIds;

  /// Efeito ativo na câmera (o último da lista).
  String? get activeEffectId => effectIds.isEmpty ? null : effectIds.last;

  final TrackModel? track;
  final double trackVolume;
  final double originalVolume;
  final Duration? trimStart;
  final Duration? trimEnd;

  final MediaProjectStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MediaProjectModel({
    required this.id,
    this.videoPath,
    this.thumbnailPath,
    this.description = '',
    this.hashtags = const [],
    this.effectIds = const [],
    this.track,
    this.trackVolume = 0.6,
    this.originalVolume = 0.3,
    this.trimStart,
    this.trimEnd,
    this.status = MediaProjectStatus.draft,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasVideo => (videoPath ?? '').isNotEmpty;

  bool get hasEffects => effectIds.isNotEmpty;

  /// Duração efetiva depois do corte.
  Duration? get trimmedDuration {
    final total = trimEnd;
    if (total == null) return null;
    final start = trimStart ?? Duration.zero;
    final d = total - start;
    return d.isNegative ? Duration.zero : d;
  }

  MediaProjectModel copyWith({
    /// Substitui o id. Existe para o primeiro salvamento: o projeto nasce sem
    /// id e só recebe um depois que o banco devolve a linha criada.
    String? id,
    String? videoPath,
    String? thumbnailPath,
    String? description,
    List<String>? hashtags,
    List<String>? effectIds,
    TrackModel? track,
    double? trackVolume,
    double? originalVolume,
    Duration? trimStart,
    Duration? trimEnd,
    MediaProjectStatus? status,
    DateTime? updatedAt,
    bool clearTrack = false,
  }) => MediaProjectModel(
    id: id ?? this.id,
    videoPath: videoPath ?? this.videoPath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    description: description ?? this.description,
    hashtags: hashtags ?? this.hashtags,
    effectIds: effectIds ?? this.effectIds,
    track: clearTrack ? null : (track ?? this.track),
    trackVolume: trackVolume ?? this.trackVolume,
    originalVolume: originalVolume ?? this.originalVolume,
    trimStart: trimStart ?? this.trimStart,
    trimEnd: trimEnd ?? this.trimEnd,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Serializa para a linha `drafts` do Supabase.
  ///
  /// Só referências e metadados: **nunca** o arquivo de vídeo, que pode ter
  /// dezenas de MB.
  Map<String, dynamic> toDraftRow() => {
    'video_path': videoPath,
    'cover_path': thumbnailPath,
    'description': description,
    'audio_name': track?.title ?? '',
    'hashtags': hashtags,
    'duration_seconds': (trimmedDuration?.inSeconds) ?? 0,
    'status': status.storageKey,
  };
}