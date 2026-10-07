import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_creation_models.dart';
import '../../services/effects_catalog_service.dart';
import '../../theme/klayk_theme.dart';

/// Resultado de uma criação: o arquivo local e os efeitos aplicados.
///
/// A tela devolve **caminhos locais**. Quem decide o destino (publicar ou
/// rascunho) é o chamador — nada é enviado ao servidor aqui.
class CaptureResult {
  final String videoPath;
  final String? thumbnailPath;
  final List<String> effectIds;
  final Duration duration;
  final bool fromGallery;

  const CaptureResult({
    required this.videoPath,
    this.thumbnailPath,
    this.effectIds = const [],
    this.duration = Duration.zero,
    this.fromGallery = false,
  });
}

/// Efeitos que exigem rastreamento facial/AR.
///
/// Nenhum item deste catálogo é aplicado ao preview: eles aparecem marcados e
/// a UI explica que ainda não estão disponíveis. Não há imagem estática
/// sobreposta fingindo ser AR.
class UnavailableEffectsNotice extends StatelessWidget {
  final int count;

  const UnavailableEffectsNotice({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF8B5CF6),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'KLAY K Labs · $count efeitos 3D/IA em preparação',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faixa horizontal de efeitos.
///
/// Carrega **página a página** ([EffectsCatalog.paginate]) — o catálogo pode
/// crescer para milhares sem inflar a memória.
class EffectsCarousel extends StatefulWidget {
  final String? activeId;

  /// Só categorias que funcionam hoje offline (2D + filtro de cor).
  final bool hideUnavailable;

  final ValueChanged<EffectModel> onSelected;
  final ValueChanged<EffectModel> onDownload;

  /// Chamado quando o usuário toca num efeito bloqueado (3D/AR, IA).
  ///
  /// Não aplica nada ao preview — serve só para avisar que o recurso ainda
  /// não está disponível.
  final ValueChanged<EffectModel>? onBlocked;

  const EffectsCarousel({
    super.key,
    required this.activeId,
    required this.onSelected,
    required this.onDownload,
    this.hideUnavailable = false,
    this.onBlocked,
  });

  @override
  State<EffectsCarousel> createState() => _EffectsCarouselState();
}

class _EffectsCarouselState extends State<EffectsCarousel> {
  static const _categories = [
    EffectCategory.newest,
    EffectCategory.top,
    EffectCategory.favorites,
    EffectCategory.face,
    EffectCategory.beauty,
    EffectCategory.animals,
    EffectCategory.accessories,
    EffectCategory.funny,
    EffectCategory.masks,
    EffectCategory.ar3d,
    EffectCategory.ai,
    EffectCategory.special,
  ];

  EffectCategory _category = EffectCategory.newest;
  List<EffectModel> _items = const [];
  int _offset = 0;
  bool _hasMore = false;
  bool _loading = false;
  int _unavailableCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPage(reset: true));
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) {
      _offset = 0;
      _items = const [];
    }
    final page = await EffectsCatalog.instance.paginate(
      _category,
      offset: _offset,
    );
    if (!mounted) return;
    setState(() {
      var list = page.effects;
      if (widget.hideUnavailable) {
        _unavailableCount = page.effects.where((e) => !e.isUsable).length;
        list = list.where((e) => e.isUsable).toList();
      }
      _items = reset ? list : [..._items, ...list];
      _offset += page.effects.length;
      _hasMore = page.hasMore;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _categories[i];
              final sel = c == _category;
              return GestureDetector(
                onTap: () {
                  setState(() => _category = c);
                  unawaited(_loadPage(reset: true));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? colors.primary : Colors.white12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _label(c),
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.hideUnavailable)
          UnavailableEffectsNotice(count: _unavailableCount),
        SizedBox(
          height: 86,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Carrega a próxima página ao chegar perto do fim: paginação sem
              // carregar o catálogo inteiro.
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 120 &&
                  _hasMore &&
                  !_loading) {
                unawaited(_loadPage());
              }
              return false;
            },
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _tile(_items[i]),
            ),
          ),
        ),
      ],
    );
  }

  String _label(EffectCategory c) => switch (c) {
    EffectCategory.newest => 'Novos',
    EffectCategory.top => 'Top',
    EffectCategory.favorites => 'Favoritos',
    EffectCategory.face => 'Rosto',
    EffectCategory.beauty => 'Beleza',
    EffectCategory.animals => 'Animais',
    EffectCategory.accessories => 'Acessórios',
    EffectCategory.funny => 'Engraçados',
    EffectCategory.masks => 'Máscaras',
    EffectCategory.ar3d => '3D/AR',
    EffectCategory.ai => 'IA',
    EffectCategory.special => 'Especiais',
  };

  Widget _tile(EffectModel e) {
    final selected = e.id == widget.activeId;
    final colors = kcolors(context);
    // Indisponível = precisa de tracking/AR que o app ainda não tem. Nunca é
    // aplicado ao preview.
    final disabled = !e.isUsable;

    return GestureDetector(
      onTap: () {
        if (disabled) {
          // Só avisa que está em preparação. Nada é aplicado.
          widget.onBlocked?.call(e);
          return;
        }
        if (e.needsDownload) {
          widget.onDownload(e);
          return;
        }
        widget.onSelected(e);
      },
      child: Opacity(
        // Indisponível fica esmaecido: comunica sem precisar ler o texto.
        opacity: disabled ? 0.4 : 1,
        child: Container(
          width: 68,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colors.primary, colors.primaryFaint],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        disabled
                            ? Icons.lock_rounded
                            : Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    if (disabled)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.hourglass_empty_rounded,
                            color: Colors.white70,
                            size: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                disabled ? 'Em preparação' : e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: disabled ? Colors.white54 : Colors.white70,
                  fontSize: 9,
                  fontWeight: disabled ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (e.needsDownload)
                const Icon(
                  Icons.download_rounded,
                  color: Colors.white54,
                  size: 11,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tela de criação de vídeo.
///
/// Câmera real (`camera`), troca frontal/traseira, flash, temporizador,
/// gravação, faixa de efeitos e entrada pela galeria.
///
/// Identidade: preto, roxo neon, cantos arredondados.
class KlaykCreateScreen extends StatefulWidget {
  /// Chamado quando a gravação termina. Devolve `false` se o chamador
  /// recusou o arquivo (ex.: disco cheio).
  final Future<bool> Function(CaptureResult result) onCaptured;

  /// Abre a galeria (usa `image_picker`, já existente no projeto).
  final Future<CaptureResult?> Function() onPickFromGallery;

  /// Abre o seletor de música.
  final VoidCallback? onPickMusic;

  const KlaykCreateScreen({
    super.key,
    required this.onCaptured,
    required this.onPickFromGallery,
    this.onPickMusic,
  });

  @override
  State<KlaykCreateScreen> createState() => _KlaykCreateScreenState();
}

class _KlaykCreateScreenState extends State<KlaykCreateScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  bool _initializing = true;
  bool _recording = false;
  bool _front = false;
  bool _flashOff = true;
  bool _effectsOpen = false;
  String? _error;

  /// Trava enquanto `_bind` está em andamento. Impede duas trocas
  /// simultâneas, que criariam controllers concorrentes.
  bool _binding = false;

  int _timerSeconds = 0;
  Timer? _timer;
  int _elapsedSeconds = 0;

  final List<String> _appliedEffects = <String>[];
  EffectModel? _active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initCamera());
    // Efeitos já baixados continuam disponíveis offline.
    unawaited(_rehydrateAssets());
  }

  @override
  void dispose() {
    // Liberar a câmera é obrigatório: deixar o controller vivo vaza a
    // hardware e mata o app em segundo plano.
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_camera?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    // Sem isso o preview fica preto ao voltar do segundo plano.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(cam.dispose());
      _camera = null;
      if (mounted) setState(() => _initializing = true);
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  Future<void> _rehydrateAssets() async {
    final cat = EffectsCatalog.instance;
    for (final page in [
      await cat.paginate(EffectCategory.face, limit: 999),
      await cat.paginate(EffectCategory.beauty, limit: 999),
      await cat.paginate(EffectCategory.animals, limit: 999),
    ]) {
      for (final e in page.effects) {
        if (e.assetUrl != null) await cat.refreshAssetState(e.id);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Nenhuma câmera encontrada neste aparelho.';
            _initializing = false;
          });
        }
        return;
      }
      await _bind(
        _front ? CameraLensDirection.front : CameraLensDirection.back,
      );
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível iniciar a câmera: ${e.code}';
          _initializing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível iniciar a câmera.';
          _initializing = false;
        });
      }
    }
  }

  /// Troca/liga a câmera de forma segura.
  ///
  /// Invariante que este método garante: [_camera] **nunca** aponta para um
  /// controller não inicializado. O controller novo é criado local, só entra em
  /// [_camera] depois do `await initialize()`, e o anterior é descartado antes.
  /// Se a tela sair no meio do await, o controller novo é descartado aqui em vez
  /// de vazar.
  Future<void> _bind(CameraLensDirection direction) async {
    // Trava reentrante: dois toques rápidos em "trocar câmera" criariam dois
    // controllers concorrentes, e um deles ficaria órfão.
    if (_binding) return;
    _binding = true;

    final old = _camera;
    // Limpa já: o preview deixa de existir durante a troca, em vez de
    // tentar desenhar um controller descartado.
    if (mounted && old != null) {
      setState(() {
        _camera = null;
        _initializing = true;
      });
    }
    try {
      if (old != null) await old.dispose();

      final desc =
          _cameras.where((c) => c.lensDirection == direction).firstOrNull ??
          _cameras.first;
      final cam = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      // Fora da tela no meio do await: descarta o que foi criado e não
      // publica nada.
      if (!mounted) {
        await cam.dispose();
        return;
      }

      await cam.initialize();

      if (!mounted) {
        await cam.dispose();
        return;
      }

      // Só agora o controller entra no estado, já pronto para o preview.
      setState(() => _camera = cam);

      // Flash pode não existir no aparelho: falha aqui não pode derrubar a
      // câmera, que já está funcionando.
      try {
        await cam.setFlashMode(FlashMode.off);
        if (mounted) setState(() => _flashOff = true);
      } on CameraException {
        // sem flash: segue com o vídeo
      }
      if (mounted) {
        setState(() {
          _error = null;
          _initializing = false;
        });
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _camera = null;
          _error = 'Não foi possível iniciar a câmera: ${e.code}';
          _initializing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _camera = null;
          _error = 'Não foi possível iniciar a câmera.';
          _initializing = false;
        });
      }
    } finally {
      _binding = false;
    }
  }

  Future<void> _toggleCamera() async {
    if (_recording) return;
    setState(() => _front = !_front);
    await _bind(_front ? CameraLensDirection.front : CameraLensDirection.back);
  }

  Future<void> _toggleFlash() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    final next = _flashOff ? FlashMode.torch : FlashMode.off;
    try {
      await cam.setFlashMode(next);
      if (mounted) setState(() => _flashOff = !_flashOff);
    } on CameraException {
      // Aparelho sem flash: silencioso, sem crash.
    }
  }

  Future<void> _pickTimer() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF17141F),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in const [0, 3, 10])
              ListTile(
                onTap: () => Navigator.of(ctx).pop(s),
                title: Text(
                  s == 0 ? 'Sem temporizador' : '$s segundos',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _timerSeconds = choice);
  }

  Future<void> _record() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;

    if (_recording) {
      // Encerrar: o arquivo fica em disco e devolvemos o caminho local.
      final x = await cam.stopVideoRecording();
      _timer?.cancel();
      // XFile não expõe duração: usamos o contador do preview, que é o
      // mesmo relógio que o usuário viu na tela.
      final ms = Duration(seconds: _elapsedSeconds);
      if (!mounted) return;
      setState(() => _recording = false);
      await widget.onCaptured(
        CaptureResult(
          videoPath: x.path,
          effectIds: List.of(_appliedEffects),
          duration: ms,
        ),
      );
      return;
    }

    if (_timerSeconds > 0) {
      final ok = await _runCountdown();
      if (!ok) return;
    }

    try {
      await cam.startVideoRecording();
      setState(() => _elapsedSeconds = 0);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
      if (mounted) setState(() => _recording = true);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gravar: ${e.code}')),
        );
      }
    }
  }

  Future<bool> _runCountdown() async {
    for (var i = _timerSeconds; i > 0; i--) {
      if (!mounted) return false;
      setState(() {});
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() {});
    return true;
  }

  void _applyEffect(EffectModel e) {
    setState(() {
      _active = e;
      _appliedEffects
        ..remove(e.id)
        ..add(e.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        // A ordem importa: no Stack, quem vem DEPOIS fica por cima e
        // recebe o toque primeiro. O preview é a camada de fundo e os
        // controles ficam acima dele.
        //
        // A folha de efeitos vem por último de propósito: quando abre, ela
        // cobre a barra inferior por completo. Antes desta ordem ficava
        // *abaixo* de `_bottomBar` e engolia os toques de flash, timer,
        // galeria e gravação.
        children: [
          _preview(),
          _topBar(),
          _bottomBar(),
          if (_effectsOpen) _effectsSheet(colors),
        ],
      ),
    );
  }

  Widget _preview() {
    final cam = _camera;
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      );
    }
    // Última barreira: `CameraPreview` NUNCA recebe um controller não
    // inicializado. É o que elimina "CameraController was used before
    // initialization" / "was not initialized", mesmo que um caminho futuro
    // esqueça de marcar `_initializing`.
    //
    // Sem erro e sem controller pronto = transição silenciosa (preto), sem
    // ícone de falha e sem texto vermelho.
    if (_error == null && (cam == null || !cam.value.isInitialized)) {
      return const ColoredBox(color: Colors.black);
    }
    if (_error != null || cam == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_rounded,
                color: Colors.white38,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Câmera indisponível',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: cam.value.previewSize?.height ?? 1080,
        height: cam.value.previewSize?.width ?? 1920,
        child: CameraPreview(cam),
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _roundButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (_recording)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'REC ${_elapsedSeconds}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const Spacer(),
              _roundButton(
                icon: Icons.flip_camera_ios_rounded,
                onTap: _toggleCamera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _bottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // SafeArea empurra os controles para ACIMA da barra de navegação do
      // sistema. Sem isto o botão de gravação ficava atrás dela em aparelhos
      // com gesture bar. `top: false` porque a barra só existe embaixo.
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sideButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Galeria',
                    onTap: () async {
                      final r = await widget.onPickFromGallery();
                      if (r != null) await widget.onCaptured(r);
                    },
                  ),
                  GestureDetector(
                    onTap: _record,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _recording
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFFE4183C),
                        ),
                        child: _recording
                            ? const Icon(
                                Icons.stop_rounded,
                                color: Colors.white,
                                size: 30,
                              )
                            : null,
                      ),
                    ),
                  ),
                  _sideButton(
                    icon: Icons.timer_outlined,
                    label: _timerSeconds == 0
                        ? 'Temporizador'
                        : '${_timerSeconds}s',
                    onTap: _pickTimer,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pill(
                    icon: _flashOff
                        ? Icons.flash_off_rounded
                        : Icons.flash_on_rounded,
                    onTap: _toggleFlash,
                  ),
                  const SizedBox(width: 10),
                  _pill(
                    icon: Icons.auto_awesome_rounded,
                    label: _active?.name ?? 'Efeitos',
                    active: _effectsOpen,
                    onTap: () => setState(() => _effectsOpen = !_effectsOpen),
                  ),
                  if (widget.onPickMusic != null) ...[
                    const SizedBox(width: 10),
                    _pill(
                      icon: Icons.music_note_rounded,
                      label: 'Música',
                      onTap: widget.onPickMusic!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required VoidCallback onTap,
    String? label,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF8B5CF6) : Colors.black38,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

    Widget _effectsSheet(dynamic colors) {
      final l10n = AppLocalizations.of(context)!;
      return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // SafeArea para o X e a faixa não ficarem atrás da barra de
      // navegação do Android. `top: false` porque a folha é ancorada embaixo.
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: Color(0xF212101A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho: puxa para fechar + X explícito no canto.
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _effectsOpen = false),
                      child: const SizedBox(height: 20),
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: IconButton(
                      onPressed: () => setState(() => _effectsOpen = false),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      constraints: const BoxConstraints(),
                      tooltip: l10n.closeEffectsLabel,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              EffectsCarousel(
                activeId: _active?.id,
                // 3D/IA aparecem marcados, mas nunca são aplicados ao preview.
                hideUnavailable: false,
                onSelected: _applyEffect,
                onDownload: (e) => _startDownload(e),
                onBlocked: _showBlockedEffectMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Aviso discreto ao tocar num efeito bloqueado (3D/AR ou IA).
  ///
  /// Nenhum efeito é aplicado ao preview — é só o aviso de que o recurso
  /// ainda não existe. Sem imagem estática fingindo ser AR.
  void _showBlockedEffectMessage(EffectModel e) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // Sem `const`: o texto vem do contexto localizado.
        duration: const Duration(seconds: 2),
        content: Text(l10n.effectInPreparation),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startDownload(EffectModel e) {
    // Sem CDN real, o download não é simulado: o usuário recebe aviso honesto.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ainda não foi possível baixar este efeito.'),
      ),
    );
  }
}
