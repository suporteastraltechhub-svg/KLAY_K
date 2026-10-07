import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_config.dart';
import '../services/content_service.dart';
import '../services/live_kit_service.dart';
import '../services/supabase_service.dart';
import '../models/klayk_live_models.dart';
import '../l10n/app_localizations.dart';
import 'audio_rooms_screen.dart';
import 'live_room_screen.dart';

/// Seletor de capa injetável (o app usa [ImagePicker]; testes injetam um fake
/// para não depender do plugin de plataforma).
typedef CoverFilePicker = Future<XFile?> Function(ImageSource source);

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF171717);

const List<String> _kCategories = [
  '🎮 Jogos',
  '📹 Vídeo',
  '🎙️ Áudio',
  '🎬 Conteúdo',
  '👥 Amigos',
  '🎟️ Eventos',
];

const Map<String, String> _kCategoryEmojis = {
  '🎮 Jogos': '🎮',
  '📹 Vídeo': '📹',
  '🎙️ Áudio': '🎙️',
  '🎬 Conteúdo': '🎬',
  '👥 Amigos': '👥',
  '🎟️ Eventos': '🎟️',
};

const List<String> _kLiveTypes = [
  '🎮 Jogos',
  '📹 Vídeo',
  '🎙️ Áudio',
  '🎬 Conteúdo',
  '👥 Amigos',
  '🎟️ Eventos',
];

/// Modo de transmissão escolhido antes de iniciar a live.
enum LiveMode {
  /// Câmera frontal do celular, transmissão tradicional em tela cheia.
  camera,

  /// Captura de tela (jogos); o app é minimizado e uma bolinha flutuante
  /// controla a transmissão (igual ao Kwai).
  screen,
}

/// Resultado do seletor de formato ("Como você quer transmitir?"): o modo
/// de transmissão escolhido (câmera/tela) e, opcionalmente, uma categoria
/// forçada (ex.: "Filmes"). Formatos que a própria seleção já encaminha para
/// outra tela real (Áudio/Amigos) não retornam nada.
class _PickedOption {
  final LiveMode? mode;
  final String? forcedCategory;

  const _PickedOption({this.mode, this.forcedCategory});
}

/// Configuração de uma nova transmissão ao vivo (real, via Supabase + LiveKit).
class StartLiveScreen extends StatefulWidget {
  const StartLiveScreen({
    super.key,
    this.coverPicker,
    this.forceGame = false,
    this.initialCategory,
    this.title,
    this.initialGameName,
    this.initialGamePackage,
  });

  /// Seletor de imagem da capa. Quando nulo, usa [ImagePicker] de verdade.
  final CoverFilePicker? coverPicker;

  /// Quando verdadeiro, pré-seleciona a categoria "Jogos" e abre a sala como
  /// uma Live de Jogo (com captura de tela) ao iniciar.
  final bool forceGame;

  /// Pré-seleciona a categoria (ex.: "Filmes") ao abrir a configuração.
  final String? initialCategory;

  /// Título do app bar quando vindo de um formato específico.
  final String? title;

  /// Nome do jogo pré-selecionado (ex.: escolhido na grade de jogos
  /// instalados). Equivale a [forceGame] + nome do jogo no formulário.
  final String? initialGameName;

  /// Package name do jogo instalado a ser aberto quando a live entrar no ar.
  final String? initialGamePackage;

  @override
  State<StartLiveScreen> createState() => _StartLiveScreenState();
}

class _StartLiveScreenState extends State<StartLiveScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _gameNameController = TextEditingController();

  String _category = _kCategories.first;
  String _privacy = 'public';
  bool _adultOnly = false;
  bool _saving = false;
  String _liveType = _kLiveTypes.first;
  bool _rtmpEnabled = false;

  /// Package name do jogo instalado escolhido (quando a live vem da grade de
  /// jogos instalados). É repassado à sala para abrir o jogo no início da
  /// transmissão de tela.
  late final String? _gamePackage = widget.initialGamePackage;

  /// Modo de transmissão. Quando ainda não escolhido (`null`), a tela abre o
  /// seletor de modo (câmera vs. jogos) antes de permitir iniciar a live.
  LiveMode? _liveMode;
  bool get _modeChosen => _liveMode != null;
  bool get _isScreenMode => _liveMode == LiveMode.screen;

  @override
  void initState() {
    super.initState();
    final isFilm =
        widget.initialCategory != null &&
        widget.initialCategory!.toLowerCase() == 'filmes';
    if (widget.forceGame || widget.initialGameName != null) {
      _liveMode = LiveMode.screen;
      _category = '🎮 Jogos';
      _liveType = '🎮 Jogos';
      _gameNameController.text = widget.initialGameName ?? 'Meu Jogo';
    } else if (isFilm) {
      // Formato "Filmes": usa captura de tela igual aos jogos (sem rosto).
      _liveMode = LiveMode.screen;
      _category = 'Filmes';
      _liveType = 'Filmes';
    } else if (widget.initialCategory != null &&
        _kCategories.contains(widget.initialCategory)) {
      _category = widget.initialCategory!;
    }
  }

  File? _coverFile;
  String? _coverExtension;
  String? _coverError;
  bool _uploadingCover = false;

  static const int _maxTitle = 80;
  static const int _maxTags = 10;
  static const int _maxTagLength = 30;
  static const int _maxCoverBytes =
      10 * 1024 * 1024; // mesmo cap do storage-init
  static const List<String> _allowedCoverExt = ['png', 'jpg', 'jpeg', 'webp'];

  List<String> get _tags {
    final parts = _tagsController.text
        .split(RegExp(r'[,\s]+'))
        .map((t) => t.replaceAll('#', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return parts;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _gameNameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_modeChosen) {
      await _showModePicker();
      if (!mounted || !_modeChosen) return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _snack(l10n.liveTitleRequired);
      return;
    }
    if (title.length > _maxTitle) {
      _snack(l10n.liveTitleTooLong(_maxTitle));
      return;
    }
    final tags = _tags;
    if (tags.length > _maxTags) {
      _snack(l10n.maxTagsExceeded(_maxTags));
      return;
    }
    if (tags.any((t) => t.length > _maxTagLength)) {
      _snack(l10n.tagTooLong(_maxTagLength));
      return;
    }
    final isScreenMode = _isScreenMode;
    final isFilmLive = isScreenMode && _category.toLowerCase() == 'filmes';
    final isGame = isScreenMode && !isFilmLive;
    if (isGame) _category = '🎮 Jogos';
    final gameName = isGame ? _gameNameController.text.trim() : null;
    if (isGame && (gameName == null || gameName.isEmpty)) {
      _snack(l10n.gameNameRequired);
      return;
    }

    if (!AppConfig.isSupabaseConfigured) {
      _snack(l10n.configureSupabaseToStartLive);
      return;
    }

    await _confirmAndStart(l10n);
  }

  /// Cria REALMENTE a capa (se houver) e o registro de live no Supabase.
  /// Retorna o registro [KlayKLive] criado (nunca simulado).
  Future<RealLive> _createLiveRecord(AppLocalizations l10n) async {
    final db = SupabaseService.instance;
    String? coverUrl;
    if (_coverFile != null) {
      if (mounted) setState(() => _uploadingCover = true);
      try {
        coverUrl = await ContentService.instance.uploadCover(
          _coverFile!,
          coverExtension: _coverExtension,
        );
      } catch (_) {
        if (mounted) setState(() => _uploadingCover = false);
        throw const CoverUploadFailedException();
      }
      if (mounted) setState(() => _uploadingCover = false);
    }
    final live = await db.createLive(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _category,
      hashtags: _tags,
      privacy: _privacy,
      gameName: _isScreenMode && _category.toLowerCase() != 'filmes'
          ? _gameNameController.text.trim()
          : null,
      coverUrl: coverUrl,
      ageRestricted: _adultOnly,
      liveType: _liveType,
      rtmpEnabled: _rtmpEnabled,
    );
    return live;
  }

  /// Diálogo "Pronto para começar?" com verificações REAIS: autenticação e
  /// acesso ao backend do KLAY K na abertura; criação da sala LiveKit + token
  /// REAL do backend ao confirmar o início.
  Future<void> _confirmAndStart(AppLocalizations l10n) async {
    final db = SupabaseService.instance;
    var preflightRan = false;
    var authOk = false;
    var backendOk = false;
    var working = false;
    var roomOk = false;
    var tokenOk = false;
    String? fatal;

    Widget checkRow({
      required bool ok,
      required bool busy,
      String? fail,
      required String title,
      required String sub,
    }) {
      Widget lead;
      if (ok) {
        lead = const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF22C55E),
          size: 22,
        );
      } else if (busy) {
        lead = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _kAccent),
        );
      } else if (fail != null) {
        lead = const Icon(
          Icons.error_rounded,
          color: Color(0xFFF87171),
          size: 22,
        );
      } else {
        lead = const Icon(
          Icons.check_circle_outline_rounded,
          color: Colors.white24,
          size: 22,
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: lead),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1C1C26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: _kAccent.withValues(alpha: 0.45)),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 48),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: StatefulBuilder(
            builder: (dlgCtx, setSheet) {
              if (!preflightRan) {
                preflightRan = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    await db.ensureAuthenticated();
                    if (!mounted) return;
                    setSheet(() => authOk = true);
                  } catch (e) {
                    if (!mounted) return;
                    setSheet(() {
                      fatal = e is SupabaseAuthUnavailableException
                          ? e.message
                          : l10n.liveStartFail;
                    });
                    return;
                  }
                  try {
                    await db.client.from('lives').select('id').limit(1);
                    if (!mounted) return;
                    setSheet(() => backendOk = true);
                  } catch (_) {
                    if (!mounted) return;
                    setSheet(() {
                      fatal =
                          'Backend do KLAY K fora do ar. Verifique sua conexão.';
                    });
                  }
                });
              }

              Future<void> startNow() async {
                setSheet(() => working = true);
                if (mounted) setState(() => _saving = true);
                try {
                  final live = await _createLiveRecord(l10n);
                  if (!mounted) return;
                  setSheet(() => roomOk = true);
                  await db.getLiveKitCredentials(
                    roomName: live.roomName,
                    isStreamer: true,
                  );
                  if (!mounted) return;
                  setSheet(() => tokenOk = true);
                  _notifyFollowersLiveStarted(live);
                  await Future<void>.delayed(const Duration(milliseconds: 400));
                  if (!mounted) return;
                  if (dlgCtx.mounted) Navigator.of(dlgCtx).pop();
                  if (!mounted) return;
                  await Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => LiveRoomScreen(
                        live: live,
                        role: LiveRole.streamer,
                        isGameLive: _isScreenMode,
                        gamePackage: _gamePackage,
                      ),
                    ),
                  );
                } catch (e) {
                  if (mounted) setState(() => _saving = false);
                  setSheet(() {
                    working = false;
                    fatal = e is CoverUploadFailedException
                        ? l10n.coverUploadFail
                        : l10n.liveStartFail;
                  });
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kAccent, Color(0xFFA78BFA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pronto para começar?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Confirmamos o estado real do backend antes de iniciar — '
                    'sem verificações simuladas.',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                  checkRow(
                    ok: authOk,
                    busy: !authOk && fatal == null,
                    fail: !authOk ? fatal : null,
                    title: 'Autenticação do KLAY K',
                    sub: authOk
                        ? 'Sessão autenticada no Supabase.'
                        : 'Verificando seu login...',
                  ),
                  checkRow(
                    ok: backendOk,
                    busy: authOk && !backendOk && fatal == null,
                    fail: authOk ? fatal : null,
                    title: 'Backend do KLAY K acessível',
                    sub: backendOk
                        ? 'Conexão com o servidor confirmada.'
                        : 'Checando conexão com o servidor...',
                  ),
                  checkRow(
                    ok: tokenOk,
                    busy: working && !tokenOk,
                    title: 'Sala LiveKit + Token do backend',
                    sub: tokenOk
                        ? 'Sala criada e token gerado.'
                        : roomOk
                        ? 'Gerando token do backend...'
                        : 'A sala e o token são gerados ao iniciar.',
                  ),
                  if (fatal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_rounded,
                            color: Color(0xFFF87171),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fatal!,
                              style: const TextStyle(
                                color: Color(0xFFF87171),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _kAccent.withValues(alpha: 0.5),
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: working
                                ? null
                                : () => Navigator.of(dlgCtx).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _kAccent,
                              disabledBackgroundColor: _kAccent.withValues(
                                alpha: 0.25,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: (!authOk || !backendOk || working)
                                ? null
                                : startNow,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (working) ...[
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ] else
                                  const Icon(
                                    Icons.videocam_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  working ? 'Iniciando...' : 'Iniciar LIVE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Estado REAL das permissões de transmissão (câmera/mic via LiveKit, tela
  /// via screen share ativa, notificações via Firebase) — nunca simulado.
  Future<void> _openPermissionsSheet() async {
    final lk = LiveKitService.instance;
    var notifGranted = false;
    if (!kIsWeb) {
      try {
        final settings = await FirebaseMessaging.instance
            .getNotificationSettings();
        final s = settings.authorizationStatus;
        notifGranted =
            s == AuthorizationStatus.authorized ||
            s == AuthorizationStatus.provisional;
      } catch (_) {
        notifGranted = false;
      }
    }
    if (!mounted) return;
    final camOk = lk.cameraInUse;
    final micOk = lk.micInUse;
    final scrOk = lk.screenShareActive.value;

    Widget permTile(IconData icon, String title, bool granted, String sub) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: granted
                    ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                    : _kAccent.withValues(alpha: 0.12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: granted ? const Color(0xFF22C55E) : _kAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              granted ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 22,
              color: granted ? const Color(0xFF22C55E) : Colors.white38,
            ),
          ],
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141420),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Permissões de transmissão',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Só mostramos o que o app já verificou de verdade.',
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              permTile(
                Icons.videocam_rounded,
                'Câmera',
                camOk,
                camOk
                    ? 'Câmera ativa na transmissão.'
                    : 'Será solicitada ao iniciar a transmissão.',
              ),
              permTile(
                Icons.mic_rounded,
                'Microfone',
                micOk,
                micOk
                    ? 'Microfone ativo na transmissão.'
                    : 'Será solicitado ao iniciar a transmissão.',
              ),
              permTile(
                Icons.screen_share_rounded,
                'Tela / Jogos',
                scrOk,
                scrOk
                    ? 'Compartilhamento de tela ativo.'
                    : 'Ativado durante a Live de Jogo.',
              ),
              permTile(
                Icons.notifications_rounded,
                'Notificações',
                notifGranted,
                notifGranted
                    ? 'Notificações permitidas no Android.'
                    : 'Serão solicitadas pelo Android.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Notifica seguidores REAIS quando o streamer inicia uma live (evento
  /// verdadeiro do sistema; nunca gera aviso se não houver seguidores).
  Future<void> _notifyFollowersLiveStarted(RealLive live) async {
    try {
      final me = SupabaseService.instance.client.auth.currentUser?.id;
      if (me == null || me.isEmpty) return;
      final rows = await SupabaseService.instance.client
          .from('follows')
          .select('follower_id')
          .eq('following_id', me)
          .limit(200);
      for (final row in rows) {
        final follower = row['follower_id'] as String?;
        if (follower == null || follower.isEmpty || follower == me) continue;
        try {
          await SupabaseService.instance.client.from('notifications').insert({
            'user_id': follower,
            'actor_id': me,
            'type': 'live',
            'ref_id': live.id,
            'message': live.title,
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _pickCover() async {
    final l10n = AppLocalizations.of(context)!;
    if (_uploadingCover) return;
    final pick =
        widget.coverPicker ??
        (ImageSource source) => ImagePicker().pickImage(
          source: source,
          maxWidth: 1440,
          imageQuality: 85,
        );
    final XFile? picked;
    try {
      picked = await pick(ImageSource.gallery);
    } catch (_) {
      _snack(l10n.galleryOpenFail);
      return;
    }
    if (!mounted || picked == null) return;

    // Validação de formato e tamanho ANTES de qualquer upload.
    final ext = _extensionOfName(picked.name);
    if (!_allowedCoverExt.contains(ext)) {
      setState(() {
        _coverError = l10n.coverFormatUnsupported;
      });
      return;
    }
    final bytes = await picked.length();
    if (bytes <= 0 || bytes > _maxCoverBytes) {
      setState(() {
        _coverError = l10n.coverTooLarge;
      });
      return;
    }

    final path = picked.path;
    setState(() {
      _coverFile = File(path);
      _coverExtension = ext;
      _coverError = null;
    });
  }

  void _removeCover() {
    if (_uploadingCover) return;
    setState(() {
      _coverFile = null;
      _coverExtension = null;
      _coverError = null;
    });
  }

  static String _extensionOfName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Seletor elegante dos formatos REAIS de transmissão. Vídeo/Jogos/Filmes
  /// retornam o modo da live (câmera/tela) e aplicam a categoria adequada;
  /// Áudio e Amigos encaminham para as salas de áudio reais (fluxo existente).
  Future<void> _showModePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showModalBottomSheet<_PickedOption>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.howToTransmitTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.howToTransmitSubtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ..._kLiveTypes.map((type) {
                final isScreen = type == '🎮 Jogos' || type == 'Filmes';
                final accent = isScreen ? _kAccent : const Color(0xFFEC4899);
                return _formatCard(
                  emoji: _kCategoryEmojis[type] ?? '🎥',
                  title: type,
                  subtitle: _getTypeDescription(type),
                  accent: accent,
                  selected: _liveType == type,
                  onTap: () {
                    if (type == '🎙️ Áudio') {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AudioRoomsScreen(),
                        ),
                      );
                      return;
                    }
                    if (type == '👥 Amigos') {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AudioRoomsScreen(
                            autoCreate: true,
                            friendsMode: true,
                          ),
                        ),
                      );
                      return;
                    }
                    final mode = isScreen ? LiveMode.screen : LiveMode.camera;
                    Navigator.of(
                      ctx,
                    ).pop(_PickedOption(mode: mode, forcedCategory: type));
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final forcedCategory = result.forcedCategory;
      if (forcedCategory != null) {
        if (forcedCategory.toLowerCase() == 'filmes') {
          // Formato "Filmes": captura de tela igual aos jogos, sem rosto.
          _category = 'Filmes';
          _liveType = 'Filmes';
          _liveMode = LiveMode.screen;
        } else if (_kCategories.contains(forcedCategory)) {
          _category = forcedCategory;
          _liveType = forcedCategory;
        }
      }
      final mode = result.mode;
      if (mode == null) return;
      _liveMode = mode;
      if (mode == LiveMode.screen && _category == '🎮 Jogos') {
        if (_gameNameController.text.isEmpty) {
          _gameNameController.text = 'Meu Jogo';
        }
      }
    });
  }

  String _getTypeDescription(String type) {
    switch (type) {
      case '🎮 Jogos':
        return 'Captura de tela ou câmera';
      case '📹 Vídeo':
        return 'Transmissão de vídeo';
      case '🎙️ Áudio':
        return 'Sala de áudio';
      case '🎬 Conteúdo':
        return 'Vídeos e conteúdo';
      case '👥 Amigos':
        return 'Sala com amigos';
      case '🎟️ Eventos':
        return 'Transmissão de eventos';
      default:
        return 'Transmissão ao vivo';
    }
  }

  /// Cartão elegante de formato no seletor: emoji neon + título + descrição
  /// curta + estado "selecionado" quando já é o modo atual da live.
  Widget _formatCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : const Color(0xFF1C1C26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white10,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.5)),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: selected ? accent : Colors.white24,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Resumo do modo escolhido no topo do formulário (estado selecionado
  /// elegante + ação para trocar).
  Widget _buildModeSummary() {
    final l10n = AppLocalizations.of(context)!;
    final isScreen = _isScreenMode;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAccent.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: _kAccent.withValues(alpha: 0.5)),
            ),
            child: Text(
              isScreen ? '🎮' : '📹',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isScreen ? l10n.gameModeSummary : l10n.videoModeSummary,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isScreen
                      ? l10n.screenModeDesc
                      : l10n.videoModeDesc(_category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showModePicker,
            style: TextButton.styleFrom(
              foregroundColor: _kAccent,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(l10n.changeModeLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.title ?? l10n.createLiveTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_liveMode != null) ...[
              const SizedBox(height: 4),
              _buildModeSummary(),
              const SizedBox(height: 16),
            ],
            _sectionTitle(l10n.titleLabel),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              maxLength: _maxTitle,
              style: const TextStyle(color: Colors.white),
              cursorColor: _kAccent,
              decoration: _inputDec(l10n.titleHint),
            ),
            const SizedBox(height: 12),
            _sectionTitle(l10n.categoryLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _kCategories)
                  ChoiceChip(
                    label: Text(c, style: const TextStyle(color: Colors.white)),
                    selected: _category == c,
                    backgroundColor: _kCard,
                    selectedColor: _kAccent.withValues(alpha: 0.85),
                    side: BorderSide(
                      color: _category == c ? _kAccent : Colors.white10,
                    ),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (_category == '🎮 Jogos') ...[
              const SizedBox(height: 12),
              _sectionTitle(l10n.gameSectionTitle),
              const SizedBox(height: 8),
              TextField(
                controller: _gameNameController,
                maxLength: 60,
                style: const TextStyle(color: Colors.white),
                cursorColor: _kAccent,
                decoration: _inputDec(l10n.gameNameHint),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle(l10n.hashtagsLabel),
            const SizedBox(height: 4),
            Text(
              l10n.tagsSeparatedHint(_maxTags),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tagsController,
              style: const TextStyle(color: Colors.white),
              cursorColor: _kAccent,
              decoration: _inputDec(l10n.tagsHint),
              onChanged: (_) => setState(() {}),
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _kAccent.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        '#$t',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle(l10n.descriptionLabel),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 200,
              style: const TextStyle(color: Colors.white),
              cursorColor: _kAccent,
              decoration: _inputDec(l10n.liveDescriptionHint),
            ),
            const SizedBox(height: 8),
            _sectionTitle(l10n.coverLabel),
            const SizedBox(height: 8),
            if (_coverError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _coverError!,
                  style: const TextStyle(
                    color: Color(0xFFFF5A7A),
                    fontSize: 12,
                  ),
                ),
              ),
            _buildCoverPicker(),
            const SizedBox(height: 20),
            _sectionTitle(l10n.privacyLabel),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _privacyOption(
                      l10n.privacyPublic,
                      'public',
                      Icons.public_rounded,
                    ),
                  ),
                  Expanded(
                    child: _privacyOption(
                      l10n.privacyPrivate,
                      'private',
                      Icons.lock_rounded,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile(
                value: _adultOnly,
                onChanged: (v) => setState(() => _adultOnly = v),
                activeThumbColor: _kAccent,
                title: Text(
                  l10n.adultLiveTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: Text(
                  l10n.adultLiveSwitchSubtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile(
                value: _rtmpEnabled,
                onChanged: (v) => setState(() => _rtmpEnabled = v),
                activeThumbColor: _kAccent,
                activeTrackColor: const Color(
                  0xFF8B5CF6,
                ).withValues(alpha: 0.6),
                secondary: const Icon(
                  Icons.live_tv_rounded,
                  color: Color(0xFF8FA3F0),
                ),
                title: const Text(
                  'RTMP / RTMPS',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: const Text(
                  'Enviar para YouTube, Twitch, etc.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.shield_rounded,
                  color: Color(0xFF8B5CF6),
                ),
                title: const Text(
                  'Permissões de transmissão',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                subtitle: const Text(
                  'Câmera, microfone, tela e notificações',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                ),
                onTap: _openPermissionsSheet,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sensors_rounded),
              label: Text(
                _uploadingCover
                    ? l10n.uploadingCoverLabel
                    : _saving
                    ? l10n.startingLiveLabel
                    : l10n.startLiveButton,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPicker() {
    final l10n = AppLocalizations.of(context)!;
    final hasCover = _coverFile != null;
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        height: 140,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D1D1D), Color(0xFF111111)],
          ),
          border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              Image.file(
                _coverFile!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFF171717)),
              ),
            if (hasCover)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x99000000)],
                  ),
                ),
              ),
            if (hasCover)
              Positioned(
                right: 6,
                top: 6,
                child: Tooltip(
                  message: l10n.removeCoverTooltip,
                  child: IconButton(
                    onPressed: _uploadingCover ? null : _removeCover,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xA6000000),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: hasCover
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.cached_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.changeCoverLabel,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_photo_alternate_rounded,
                              color: _kAccent,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.addCoverLabel,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            if (_uploadingCover)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _kAccent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: _kCard,
    counterStyle: const TextStyle(color: Colors.white30),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.white10),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.white10),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _kAccent),
    ),
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _privacyOption(String label, String value, IconData icon) {
    final selected = _privacy == value;
    return GestureDetector(
      onTap: () => setState(() => _privacy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _kAccent.withValues(alpha: 0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Falha no upload da capa durante a criação da live (exceção interna real,
/// traduzida para a mensagem l10n no diálogo de confirmação).
class CoverUploadFailedException implements Exception {
  const CoverUploadFailedException();
}
