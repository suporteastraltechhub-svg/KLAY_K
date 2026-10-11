import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'l10n/app_localizations.dart';
import 'models/ad_models.dart';
import 'models/klayk_live_models.dart';
import 'models/post_models.dart';
import 'models/user_profile.dart';
import 'services/account_service.dart';
import 'services/admin_service.dart';
import 'services/ads_service.dart';
import 'services/boot_diagnostics.dart';
import 'services/boot_trace.dart';
import 'services/experience_settings.dart';
import 'services/locale_controller.dart';
import 'services/local_prefs_service.dart';
import 'screens/create/creation_flow.dart';
import 'screens/app_gate.dart';
import 'screens/auth_screen.dart';
import 'screens/boot_diagnostics_screen.dart';
import 'screens/live_room_screen.dart';
import 'screens/messages_hub_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/games/game_screen.dart';
import 'screens/games/game_leaderboard_screen.dart';
import 'screens/games/game_router.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/user_profile_screen.dart';
import 'screens/profile/video_preview_screen.dart';
import 'screens/live_games_screen.dart';
import 'screens/live_hub_screen.dart';
import 'screens/store/store_market_screen.dart';
import 'screens/start_live_screen.dart';
import 'screens/communities/communities_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/audio_rooms_screen.dart';
import 'screens/events_screen.dart';
import 'screens/moments_screen.dart';
import 'screens/rising_creators_screen.dart';
import 'widgets/live_premium_bubble.dart';
import 'widgets/verified_badge.dart';
import 'widgets/klay_live_feed_card.dart';
import 'widgets/content_actions.dart';
import 'widgets/live_hub_components.dart';
import 'services/app_config.dart';
import 'services/content_service.dart';
import 'services/drafts_service.dart';
import 'services/game_service.dart';
import 'services/message_service.dart';
import 'services/profile_service.dart';
import 'services/social_service.dart';
import 'services/storage_upload.dart';
import 'services/supabase_service.dart';
import 'services/push_service.dart';
import 'services/guardian_service.dart';
import 'services/live_kit_service.dart';
import 'theme/klayk_theme.dart';
import 'design/klayk_design.dart';
import 'widgets/klayk_ux.dart';
import 'widgets/search_result_opener.dart';
import 'widgets/ad_widgets.dart';
import 'widgets/ad_spot.dart';
import 'widgets/klayk_game_card.dart';
import 'widgets/reward_floating_button.dart';
import 'widgets/feed_loading_hud.dart';

/// A cada N vídeos, um anúncio aprovado entra no feed (intercalação
/// transparente com badge ANÚNCIO). Não afeta a lógica de vídeo existente.
const int kAdsFeedEveryN = 5;

/// A cada N vídeos, uma live REAL ativa entra no feed "Para você".
const int kFeedLiveEveryN = 4;

/// Zona em que o boot acontece. O Flutter guarda a zona do binding quando
/// `ensureInitialized()` roda e confere em `debugCheckZone` na hora do
/// `runApp`; por isso o handler de erro precisa voltar para cá para conseguir
/// mostrar a tela de diagnóstico sem recriar o mesmo erro de zone.
Zone? _bootZone;

/// `true` assim que um `runApp` deu certo — evita duas raízes de widget.
bool _appStarted = false;

Future<void> main() async {
  // TODO DO BOOT INTEIRO — binding e runApp na MESMA Zone.
  //
  // O bug anterior: `ensureInitialized()` rodava na zone raiz (dentro de
  // `main`) e o `runApp` rodava dentro de `runZonedGuarded`, ou seja, numa zone
  // filha. O Flutter guarda a zone do binding e, no `runApp`, compara:
  //
  //   The Flutter bindings were initialized in a different zone than is now
  //   being used.  -> BindingBase.debugCheckZone <- _runWidget <- runApp
  //
  // A correção NÃO é silenciar o assert (nem `debugZoneErrorsAreFatal`): é
  // estrutural — `ensureInitialized()`, todo o boot e o `runApp` acontecem
  // dentro da mesma zone, que é o padrão documentado do Flutter.
  runZonedGuarded<Future<void>>(_bootKlayK, _onBootZoneError);
}

/// Executa a inicialização inteira. Fica dentro de uma única Zone para que o
/// binding e o `runApp` compartilhem a mesma.
Future<void> _bootKlayK() async {
  final trace = BootTrace.instance;
  trace.step(BootSteps.dartEnter);

  // Binding primeiro: nada de canal de plataforma (nem path_provider) funciona
  // antes dele.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  _bootZone = Zone.current;
  trace.step(BootSteps.bindings, detail: 'zone=${_zoneId(Zone.current)}');

  // Abre a trilha: lê a abertura ANTERIOR (que é a que morreu) e passa a anexar
  // cada etapa com flush.
  await trace.begin();
  trace.step(
    BootSteps.traceReady,
    detail:
        'anterior=${trace.previous.length} linhas; '
        'marcadores_nativos=${trace.nativeMarkers.length}',
  );

  // Erros de build/layout e de canal de plataforma passam a ser registrados
  // em vez de derrubarem o processo.
  BootDiagnostics.installGlobalHandlers();
  BootDiagnostics.instance.markPhase(BootPhases.handlers);
  await BootDiagnostics.instance.loadPrevious();

  binding.addPostFrameCallback((_) {
    trace.step(BootSteps.firstFrame, detail: 'primeiro frame desenhado');
    BootDiagnostics.instance.markPhase(BootSteps.firstFrame);
  });

  try {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    trace.step(BootSteps.systemChrome);
  } catch (e, s) {
    BootDiagnostics.instance.record('boot', e, s, at: BootSteps.systemChrome);
    trace.step(BootSteps.systemChrome, detail: 'FALHOU: $e');
  }

  // SharedPreferences: primeiro uso real de canal de plataforma do app.
  // Cronometrado porque é onde o plugin responde — ou não.
  final spSw = Stopwatch()..start();
  try {
    await AppLanguageController.instance.initialize();
    trace.step(
      BootSteps.sharedPrefs,
      detail: 'idioma+shared_preferences em ${spSw.elapsedMilliseconds}ms',
    );
  } catch (e, s) {
    BootDiagnostics.instance.record('boot', e, s, at: BootSteps.sharedPrefs);
    trace.step(BootSteps.sharedPrefs, detail: 'FALHOU: $e');
  }
  BootDiagnostics.instance.markPhase(BootPhases.locale);

  try {
    await LocalPrefsService.instance.load();
  } catch (e, s) {
    BootDiagnostics.instance.record('boot', e, s, at: BootPhases.localPrefs);
  }
  BootDiagnostics.instance.markPhase(BootPhases.localPrefs);

  // Supabase e sessão.
  final sbSw = Stopwatch()..start();
  try {
    await SupabaseService.instance.ensureReady();
    trace.step(
      BootSteps.supabase,
      detail:
          '${SupabaseService.instance.isConfigured ? 'configurado' : 'desligado'} '
          'em ${sbSw.elapsedMilliseconds}ms',
    );
    try {
      final sessao = SupabaseService.instance.hasSession;
      trace.step(
        BootSteps.auth,
        detail: 'sessao=${sessao ? 'ativa' : 'nenhuma'}',
      );
    } catch (e) {
      trace.step(BootSteps.auth, detail: 'FALHOU ao ler sessao: $e');
    }
  } catch (e, s) {
    BootDiagnostics.instance.record('boot', e, s, at: BootSteps.supabase);
    trace.step(BootSteps.supabase, detail: 'FALHOU: $e');
  }
  BootDiagnostics.instance.markPhase(BootSteps.supabase);

  // Firebase (FCM so como transporte; o backend continua sendo o Supabase).
  final fbSw = Stopwatch()..start();
  try {
    await PushService.instance.init();
    trace.step(
      BootSteps.firebase,
      detail:
          'pronto=${PushService.instance.isReady} '
          'configurado=${AppConfig.isFirebaseConfigured} '
          'em ${fbSw.elapsedMilliseconds}ms',
    );
  } catch (e, s) {
    BootDiagnostics.instance.record('boot', e, s, at: BootSteps.firebase);
    trace.step(BootSteps.firebase, detail: 'FALHOU: $e');
  }
  BootDiagnostics.instance.markPhase(BootSteps.firebase);

  // LiveKit/WebRTC: conectar e SOB DEMANDA (so ao entrar numa live), portanto
  // nao faz parte do startup. Registrado para deixar isso explicito em vez de
  // deixar um buraco silencioso na trilha.
  trace.step(
    BootSteps.livekitDeferred,
    detail: 'conexao LiveKit e sob demanda, fora do startup',
  );

  // CONFERENCIA EXPLICITA DA ZONE. O assert do Flutter e removido em release,
  // entao o aviso nem aparece la: registramos a comparacao na trilha, que e a
  // unica forma de provar no aparelho que binding e runApp estao na mesma zone.
  final bindingZone = Zone.current;
  trace.step(
    BootSteps.zoneCheck,
    detail:
        'bindingCriadoEm=${_zoneId(bindingZone)} '
        'mesmaZone=${bindingZone == _bootZone}',
  );
  if (bindingZone != _bootZone) {
    BootDiagnostics.instance.record(
      'boot',
      StateError(
        'Zone do binding (${_zoneId(bindingZone)}) difere da zone do boot '
        '_zoneId(_bootZone ?? Zone.current) — causaria "zone mismatch" no runApp.',
      ),
      StackTrace.current,
      at: BootSteps.zoneCheck,
    );
  }

  // Erro em QUALQUER build da arvore vira a tela de diagnostico no lugar da
  // caixa cinza padrao, e fica registrado para a proxima abertura.
  ErrorWidget.builder = (details) => const BootErrorBox();

  try {
    _appStarted = true;
    // O fluxo de criação vive em lib/screens/create/ e não pode importar
    // este arquivo (UploadScreen é declarado aqui). Registramos a tela de
    // publicação para quebrar o ciclo sem duplicar nada.
    KlaykCreationFlow.instance.registerPublishScreen(
      (preselected) => UploadScreen(preselectedVideo: preselected),
    );
    runApp(const KlayKApp());
    trace.step(
      BootSteps.runApp,
      detail: 'runApp na zone ${_zoneId(Zone.current)}',
    );
    BootDiagnostics.instance.markPhase(BootSteps.runApp);
  } catch (e, s) {
    BootDiagnostics.instance.record('boot', e, s, at: BootSteps.runApp);
    trace.step(BootSteps.runApp, detail: 'FALHOU: $e');
    _appStarted = true;
    runApp(const BootDiagnosticsApp());
  }
}

/// Identificador curto e estavel da zone, para comparar na trilha.
String _zoneId(Zone z) => '0x${z.hashCode.toUnsigned(32).toRadixString(16)}';

/// Erro assíncrono que escapou do boot (fora dos try/catch por passo).
///
/// Este handler roda na zone PAI. Chamar `runApp` aqui recriaria o mesmo
/// "zone mismatch", então voltamos explicitamente para a zone do boot.
void _onBootZoneError(Object error, StackTrace stack) {
  BootDiagnostics.instance.record('zone', error, stack, at: BootSteps.runApp);

  final zone = _bootZone;
  if (zone == null || _appStarted) return;
  zone.run(() {
    if (_appStarted) return;
    _appStarted = true;
    runApp(const BootDiagnosticsApp());
  });
}

/// Raiz mínima usada quando o [runApp] normal não pode ser construído.
class BootDiagnosticsApp extends StatelessWidget {
  const BootDiagnosticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KlaykTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BootDiagnosticsScreen(),
    );
  }
}

/// Substitui a caixa cinza do Flutter quando um build da árvore falha, para que
/// o usuário veja o que deu errado em vez de uma tela vazia.
class BootErrorBox extends StatelessWidget {
  const BootErrorBox({super.key});

  @override
  Widget build(BuildContext context) {
    final d = BootDiagnostics.instance;
    final last = d.current.isEmpty ? null : d.current.last;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF1B1020),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            last == null
                ? 'Erro ao montar a tela.'
                : '${last.error}\n\n${last.stack}',
            style: const TextStyle(
              color: Color(0xFFFF8A80),
              fontSize: 10,
              fontFamily: 'monospace',
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// APP
// ============================================================

class KlayKApp extends StatefulWidget {
  const KlayKApp({super.key});

  @override
  State<KlayKApp> createState() => _KlayKAppState();
}

class _KlayKAppState extends State<KlayKApp> {
  // `true` enquanto o app está mostrando o diagnóstico em vez do conteúdo.
  bool _showingDiagnostics = false;

  @override
  void initState() {
    super.initState();
    // Houve falha nesta abertura ou na anterior? Então o primeiro que o usuário
    // vê é o relatório, com um botão para seguir para o app.
    if (BootDiagnostics.instance.hasFailure) {
      _showingDiagnostics = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguageController.instance,
      builder: (context, _) => AnimatedBuilder(
        animation: Listenable.merge([
          ExperienceSettings.instance.prefs,
          LocalPrefsService.instance.prefs,
        ]),
        builder: (context, child) {
          final reduceMotion = ExperienceSettings.instance.reduceAnimations;
          final local = LocalPrefsService.instance.prefs.value;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'KLAY K',
            onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appName,
            navigatorKey: kAppNavigatorKey,
            theme: KlaykTheme.dark(
              reduceMotion: reduceMotion,
              highContrast: local.highContrast,
            ),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final scale = (mq.textScaler.scale(1) * local.textScale).clamp(
                0.8,
                2.0,
              );
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            locale: AppLanguageController.instance.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routes: {
              '/login': (_) => const AuthScreen(),
              '/live/start': (_) => const StartLiveScreen(),
            },
            home: _showingDiagnostics
                ? BootDiagnosticsScreen(
                    onContinue: () =>
                        setState(() => _showingDiagnostics = false),
                  )
                : const _AppLifecycleHost(
                    child: AppGate(homeBuilder: _mainHome),
                  ),
          );
        },
      ),
    );
  }
}

Widget _mainHome() => const MainScreen();

/// Mantém a medição de tempo de uso em primeiro plano sem deixar timer
/// rodando quando o app não está visível.
class _AppLifecycleHost extends StatefulWidget {
  const _AppLifecycleHost({required this.child});

  final Widget child;

  @override
  State<_AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends State<_AppLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalPrefsService.instance.stopSession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      LocalPrefsService.instance.startSession();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      LocalPrefsService.instance.stopSession();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ============================================================
// CONTROLE DE ABA GLOBAL
// ============================================================

final ValueNotifier<int> kNavIndex = ValueNotifier<int>(0);

// ============================================================
// MODELOS
// ============================================================

/// Quantos comentários a cada página na sheet. Antes era um corte fixo
/// de 200 linhas, sem scroll incremental.
const int kCommentPageSize = 30;

class Comment {
  final String id;
  final String username;
  final String text;
  final DateTime timestamp;
  final String? replyTo;

  /// Id do autor (para abrir o perfil) — vazio em modo demo / sem autor.
  final String? authorId;
  final String? avatarUrl;

  int likes;
  bool liked;
  bool mine;
  bool edited;
  final bool isVerified;

  /// ID do comentário pai quando este é uma resposta — é o que permite
  /// desenhar a resposta recuada abaixo do comentário original.
  final String? parentCommentId;

  Comment({
    required this.id,
    required this.username,
    required this.text,
    required this.timestamp,
    this.replyTo,
    this.authorId,
    this.avatarUrl,
    this.likes = 0,
    this.liked = false,
    this.mine = false,
    this.edited = false,
    this.isVerified = false,
    this.parentCommentId,
  });

  /// Cópia com campos trocados — usado pela atualização otimista da curtida,
  /// que precisa reverter sem recarregar a lista inteira.
  Comment copyWith({int? likes, bool? liked, String? replyTo}) {
    return Comment(
      id: id,
      username: username,
      text: text,
      timestamp: timestamp,
      replyTo: replyTo ?? this.replyTo,
      authorId: authorId,
      avatarUrl: avatarUrl,
      likes: likes ?? this.likes,
      liked: liked ?? this.liked,
      mine: mine,
      edited: edited,
      isVerified: isVerified,
      parentCommentId: parentCommentId,
    );
  }
}

class KlayKVideo {
  final String id;
  final String? authorId;
  final String videoUrl;
  final String? coverUrl;
  final String username;
  final String displayName;
  final String description;
  final String avatarUrl;
  final String audioName;
  final bool isVerified;
  final List<String> hashtags;

  int likes;
  int comments;
  int shares;
  int followers;
  int followingCount;
  bool liked;
  bool following;
  bool saved;
  List<Comment> commentList;

  KlayKVideo({
    required this.id,
    this.authorId,
    required this.videoUrl,
    this.coverUrl,
    required this.username,
    required this.displayName,
    required this.description,
    required this.avatarUrl,
    this.audioName = 'Áudio original',
    this.isVerified = false,
    this.hashtags = const [],
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.followers = 1,
    this.followingCount = 120,
    this.liked = false,
    this.following = false,
    this.saved = false,
    this.commentList = const [],
  });
}

/// Converte um post real do Supabase (public.posts) no modelo de UI legado
/// [KlayKVideo], reaproveitando todos os widgets de apresentação do feed.
KlayKVideo _videoFromPost(FeedPost post) {
  return KlayKVideo(
    id: post.id,
    authorId: post.userId,
    videoUrl: post.videoUrl,
    coverUrl: post.coverUrl,
    username: post.author?.username != null
        ? '@${post.author!.username}'
        : '@usuario',
    displayName: post.author?.name ?? 'Usuário',
    description: post.description,
    avatarUrl: post.author?.avatarUrl ?? '',
    audioName: post.audioName ?? 'Áudio original',
    isVerified: post.author?.isVerified ?? false,
    hashtags: post.hashtags,
    likes: post.likesCount,
    comments: post.commentsCount,
    shares: post.sharesCount,
    followers: 1,
    followingCount: 0,
    liked: post.liked,
    following: post.following,
    saved: post.saved,
    commentList: const [],
  );
}

/// Reusa `_videoFromPost` trocando a URL pela resolvida (assinada/assinatura).
KlayKVideo _videoFromPostResolved(FeedPost post, String videoUrl) {
  final v = _videoFromPost(post);
  return KlayKVideo(
    id: v.id,
    authorId: v.authorId,
    videoUrl: videoUrl,
    coverUrl: v.coverUrl,
    username: v.username,
    displayName: v.displayName,
    description: v.description,
    avatarUrl: v.avatarUrl,
    audioName: v.audioName,
    isVerified: v.isVerified,
    hashtags: v.hashtags,
    likes: v.likes,
    comments: v.comments,
    shares: v.shares,
    followers: v.followers,
    followingCount: v.followingCount,
    liked: v.liked,
    following: v.following,
    saved: v.saved,
    commentList: v.commentList,
  );
}

/// Resolve URLs assinadas de posts em paralelo com concorrência limitada
/// (antes: chamada em série por post; lotes evitam estouro da edge function).
/// `onWave` (opcional) é chamado após CADA onda com o progresso parcial —
/// permite pintar o feed assim que os primeiros posts têm URL, sem esperar a
/// página inteira (primeiro vídeo toca mais cedo).
Future<List<KlayKVideo>> _resolvePostUrls(
  List<FeedPost> posts, {
  void Function(List<KlayKVideo> partial)? onWave,
}) async {
  final out = <KlayKVideo>[];
  if (posts.isEmpty) return out;
  const batch = 5;
  const itemTimeout = Duration(seconds: 8);
  for (var i = 0; i < posts.length; i += batch) {
    final end = i + batch > posts.length ? posts.length : i + batch;
    final chunk = posts.sublist(i, end);
    // Cada item tem teto próprio: uma edge de signed-URL lenta/fora não
    // segura a onda inteira nem espera a página toda — o item cai para a URL
    // crua e o restante do feed continua (requisito: feed não depende da
    // resolução de todas as URLs para sair do loading).
    final urls = await Future.wait(
      chunk.map((post) async {
        try {
          return await ContentService.instance
              .resolveVideoUrl(post)
              .timeout(itemTimeout);
        } catch (_) {
          return post.videoUrl;
        }
      }),
    );
    for (var j = 0; j < urls.length; j++) {
      out.add(_videoFromPostResolved(chunk[j], urls[j]));
    }
    onWave?.call(List.of(out));
  }
  return out;
}

class KlayKLive {
  final String id;
  final bool isGame;
  final String title;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String videoUrl;
  final String gameName;
  final int viewers;
  final int likes;
  final int giftCount;
  final bool isVerified;
  final bool own;
  final List<String> comments;

  KlayKLive({
    required this.id,
    required this.isGame,
    required this.title,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.videoUrl,
    this.gameName = '',
    this.viewers = 0,
    this.likes = 0,
    this.giftCount = 0,
    this.isVerified = false,
    this.own = false,
    this.comments = const [],
  });
}

// ============================================================
// DENÚNCIA (posts e comentários)
// ============================================================

/// Abre o fluxo de denúncia (motivo + opcional detalhe) e persiste via
/// `SocialService.reportItem` na tabela `public.reports` para o painel de
/// moderação (target_type aceita 'post', 'comment', 'user', 'live', ...).
Future<void> showReportDialog(
  BuildContext context, {
  required String targetId,
  required String targetType,
  String targetLabel = 'conteúdo',
}) async {
  final l10n = AppLocalizations.of(context)!;
  final reasons = [
    l10n.reportReasonInappropriate,
    l10n.reportReasonHarassment,
    l10n.reportReasonSpam,
    l10n.reportReasonMisinfo,
    l10n.reportReasonViolence,
    l10n.reportReasonRights,
    l10n.reportReasonOther,
  ];

  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1C1C26),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        children: [
          Text(
            l10n.reportContent(targetLabel),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.reportReasonIntro,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          for (final r in reasons)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined, color: Colors.white38),
              title: Text(r, style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, r),
            ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;

  final detailsCtrl = TextEditingController();
  final details = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C26),
      title: Text(
        l10n.reportContent(targetLabel),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reportReasonLabel(reason),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: detailsCtrl,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.reportDetailsHint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF17151F),
              border: const OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            l10n.cancel,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, detailsCtrl.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE4183C),
          ),
          child: Text(l10n.sendReport),
        ),
      ],
    ),
  );
  detailsCtrl.dispose();
  if (details == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await SocialService.instance.reportItem(
      targetId: targetId,
      targetType: targetType,
      reason: reason,
      details: details,
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.sentReportFull)));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.reportError(e.toString()))),
    );
  }
}

// ============================================================
// (Removido: kChatList/KChat — lista falsa de conversas. O envio
// de vídeo para amigos agora usa conversas reais via MessageService.)
// ============================================================

final List<KlayKLive> kAllLives = [
  KlayKLive(
    id: 'l1',
    isGame: false,
    title: 'Bom dia KLAY K!',
    username: '@klaykoficial',
    displayName: 'KLAY K OFICIAL',
    avatarUrl: 'https://i.pravatar.cc/150?img=32',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    viewers: 1240,
    likes: 3200,
    giftCount: 86,
    isVerified: false,
    own: true,
    comments: ['Ao vivo!!!', 'Genuinamente', 'Muito bom'],
  ),
  KlayKLive(
    id: 'l2',
    isGame: true,
    title: 'Semana no FreeFire',
    username: '@semnocaotv',
    displayName: 'SEM NOÇÃO TV',
    avatarUrl: 'https://i.pravatar.cc/150?img=12',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    gameName: 'FreeFire',
    viewers: 890,
    likes: 4100,
    giftCount: 132,
    isVerified: false,
    comments: ['Que plays!', 'GG', 'Invita'],
  ),
  KlayKLive(
    id: 'l3',
    isGame: false,
    title: 'Reagindo aos comentários',
    username: '@maria_k',
    displayName: 'Maria K',
    avatarUrl: 'https://i.pravatar.cc/150?img=47',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    viewers: 340,
    likes: 980,
    giftCount: 22,
    comments: ['Melhor live', 'Kkkkk', 'Fofo demais'],
  ),
  KlayKLive(
    id: 'l4',
    isGame: true,
    title: 'Rankeando no LOL',
    username: '@criadoreskk',
    displayName: 'CRIADORES KLAY K',
    avatarUrl: 'https://i.pravatar.cc/150?img=45',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    gameName: 'League of Legends',
    viewers: 2100,
    likes: 7800,
    giftCount: 274,
    comments: ['Top 1 oq', 'Bora', 'Sai de casa kk'],
  ),
  KlayKLive(
    id: 'l5',
    isGame: false,
    title: 'Truques e dicas do app',
    username: '@pedro_l',
    displayName: 'Pedro L',
    avatarUrl: 'https://i.pravatar.cc/150?img=59',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    viewers: 520,
    likes: 2100,
    giftCount: 64,
    comments: ['Dicas top', '100%', 'Valeu!'],
  ),
  KlayKLive(
    id: 'l6',
    isGame: true,
    title: 'Campeonato KLAY K',
    username: '@klaykesports',
    displayName: 'KLAY K ESPORTS',
    avatarUrl: 'https://i.pravatar.cc/150?img=15',
    videoUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    gameName: 'Valorant',
    viewers: 5300,
    likes: 15400,
    giftCount: 610,
    isVerified: false,
    comments: ['Final insana!', 'GGWP', 'Obrigado KLAY K'],
  ),
];

// ============================================================
// MAIN SCREEN
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _messagesUnread = 0;
  bool _showOnboarding = false;

  // True quando o feed NÃO está reproduzindo vídeos (pausa o ciclo de
  // recompensa). Atualizado pelo FeedScreen conforme a sub-aba/vídeo ativo.
  final ValueNotifier<bool> _rewardPaused = ValueNotifier<bool>(false);

  // IndexedStack nasce e morre junto (não em const) para o Feed saber quando
  // perde foco (pausa vídeo/áudio ao trocar de aba — economia real).
  late List<Widget>
  _screens; // setado em initState (estável) com tabActive atual.

  @override
  void initState() {
    super.initState();
    _screens = _buildScreens();
    kNavIndex.addListener(_syncFromGlobal);
    _currentIndex = kNavIndex.value;
    _refreshUnread();
    kNavIndex.addListener(_refreshUnread);
    _checkOnboarding();
  }

  /// Mostra o guia do iniciante apenas para contas novas reais
  /// (gate persistido em `user_settings.onboarding_done`).
  Future<void> _checkOnboarding() async {
    if (!SupabaseService.instance.isConfigured) {
      return;
    }
    final user = SupabaseService.instance.client.auth.currentUser;
    // Visitante anônimo não vê onboarding (flui direto para o feed).
    final isAnonymous = user?.isAnonymous ?? false;
    if (user == null || isAnonymous) {
      return;
    }
    try {
      final settings = await AccountService.instance.fetchSettings().catchError(
        (_) => const AccountSettings(),
      );
      final needsOnboarding = !settings.onboardingDone;
      if (mounted && needsOnboarding) {
        setState(() {
          _showOnboarding = true;
        });
      }
    } catch (_) {}
  }

  void _finishOnboarding() {
    setState(() => _showOnboarding = false);
  }

  List<Widget> _buildScreens() => [
    FeedScreen(tabActive: _currentIndex == 0, rewardPaused: _rewardPaused),
    const LiveHubScreen(),
    const GameScreen(),
    const UploadScreen(),
    MessagesHubScreen(onUnreadChanged: _refreshUnread),
    ProfileScreen(onCreateVideo: _openUploadForProfile),
  ];

  /// Abre o fluxo de publicação (aba Upload) como rota — usado pelo estado
  /// vazio da aba Perfil ("Criar vídeo").
  Future<void> _openUploadForProfile() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const UploadScreen()));
  }

  Future<void> _refreshUnread([int? _]) async {
    if (!SupabaseService.instance.isConfigured) return;
    final dm = await MessageService.instance.unreadCount().catchError((_) => 0);
    final nf = await ContentService.instance
        .unreadNotificationCount()
        .catchError((_) => 0);
    final c = dm + nf;
    if (mounted && c != _messagesUnread) {
      setState(() => _messagesUnread = c);
    }
  }

  @override
  void dispose() {
    kNavIndex.removeListener(_syncFromGlobal);
    kNavIndex.removeListener(_refreshUnread);
    _rewardPaused.dispose();
    super.dispose();
  }

  void _syncFromGlobal() {
    if (!mounted) return;
    final value = kNavIndex.value.clamp(0, _screens.length - 1);
    if (value != _currentIndex) {
      setState(() {
        _currentIndex = value;
        _screens = _buildScreens();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return OnboardingScreen(onDone: _finishOnboarding);
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
          const LivePremiumBubble(),
          const MaintenanceLayer(),
          // Bolinha de moedas/recompensa (20s) — abre a carteira real.
          RewardFloatingButton(
            visibleTab: _currentIndex,
            paused: _rewardPaused,
          ),
          // A bolinha roxa de missões/nível (QuestBubble) foi removida do
          // overlay. Ela flutuava sobre as demais abas — inclusive sobre a de
          // Mensagens — com o anel de progresso e o X logo abaixo.
          //
          // Nada de Missões foi perdido: `MissionsScreen` continua acessível
          // pelo Central de Recompensas, que é alcançado pelas Configurações
          // e pela tela de Jogos. O sistema de nível/XP segue intacto, só
          // perdeu a renderização flutuante.
        ],
      ),
      bottomNavigationBar: KlayKBottomNavigation(
        currentIndex: _currentIndex,
        messageUnread: _messagesUnread,
        onTap: (index) {
          kNavIndex.value = index;
          setState(() {
            _currentIndex = index;
            _screens = _buildScreens();
          });
          if (index == 3) {
            _refreshUnread();
          }
        },
      ),
    );
  }
}

// ============================================================
// NAVEGAÇÃO
// ============================================================

/// Camada de manutenção do KLAY GUARDIAN.
///
/// Lê o status real do backend (`guardian_status`, público) e:
/// - janela GLOBAL ou EMERGÊNCIA → overlay bloqueante cobrindo o app;
/// - janela por recurso → banner informativo no topo.
/// A decisão de bloqueio é dada pelo backend; o app nunca decide sozinho.
class MaintenanceLayer extends StatefulWidget {
  const MaintenanceLayer({super.key});

  @override
  State<MaintenanceLayer> createState() => _MaintenanceLayerState();
}

class _MaintenanceLayerState extends State<MaintenanceLayer> {
  List<GuardianWindow> _windows = const [];
  bool _checked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!SupabaseService.instance.isConfigured) return;
    final windows = await GuardianService.instance.status();
    if (!mounted) return;
    setState(() {
      _windows = windows;
      _checked = true;
    });
  }

  GuardianWindow? get _blocking {
    for (final w in _windows) {
      if (w.isGlobal || w.isEmergency) return w;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    final block = _blocking;
    if (block != null) return _blockingOverlay(block);
    return _WindowsBanner(windows: _windows);
  }

  Widget _blockingOverlay(GuardianWindow w) {
    final emergency = w.isEmergency;
    final color = emergency ? const Color(0xFFFF6B81) : const Color(0xFFF59E0B);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC08070D).withValues(alpha: 0.96),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    emergency
                        ? Icons.crisis_alert_rounded
                        : Icons.engineering_rounded,
                    color: color,
                    size: 52,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    emergency
                        ? AppLocalizations.of(context)!.maintenanceEmergency
                        : AppLocalizations.of(context)!.maintenanceMode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    w.message.isEmpty
                        ? AppLocalizations.of(context)!.maintenanceSoonBack
                        : w.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.maintenanceModeInfo(
                      w.mode,
                      w.isGlobal
                          ? AppLocalizations.of(context)!.maintenanceGlobalScope
                          : '',
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _tick,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faixa superior discreta quando há manutenção por recurso (não-bloqueante).
class _WindowsBanner extends StatelessWidget {
  final List<GuardianWindow> windows;
  const _WindowsBanner({required this.windows});

  @override
  Widget build(BuildContext context) {
    if (windows.isEmpty) return const SizedBox.shrink();
    final w = windows.first;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2012),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.construction_rounded,
                color: Color(0xFFF59E0B),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(
                        context,
                      )!.featureMaintenance(w.isGlobal ? 'KLAY K' : w.feature) +
                      (w.message.isEmpty ? '.' : ': ${w.message}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KlayKBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int messageUnread;

  const KlayKBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.messageUnread = 0,
  });

  void _showPublishMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(ctx)!.createOnKlayK,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              _publishTile(
                ctx,
                Icons.video_library_rounded,
                AppLocalizations.of(ctx)!.publishVideoTile,
                onTap: () {
                  Navigator.of(ctx).pop();
                  // Gravar/pick + efeitos + gravação + publicação.
                  // Sem Supabase não há upload possível: caímos na aba de
                  // publicação, que já mostra o aviso de "não configurado".
                  if (AppConfig.isSupabaseConfigured) {
                    unawaited(KlaykCreationFlow.instance.open(context));
                  } else {
                    onTap(3);
                  }
                },
              ),
              _publishTile(
                ctx,
                Icons.sensors_rounded,
                AppLocalizations.of(ctx)!.publishLiveTile,
                iconColor: const Color(0xFFFF2E4D),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (AppConfig.isSupabaseConfigured) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StartLiveScreen(),
                      ),
                    );
                  } else {
                    _liveNotConfigured(context);
                  }
                },
              ),
              _publishTile(
                ctx,
                Icons.sports_esports_rounded,
                AppLocalizations.of(ctx)!.publishGameTile,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onTap(2);
                },
              ),
              _publishTile(
                ctx,
                Icons.mic_rounded,
                AppLocalizations.of(ctx)!.publishAudioTile,
                iconColor: const Color(0xFFAB47BC),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (AppConfig.isSupabaseConfigured) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AudioRoomsScreen(),
                      ),
                    );
                  } else {
                    _liveNotConfigured(context);
                  }
                },
              ),
              _publishTile(
                ctx,
                Icons.group_rounded,
                AppLocalizations.of(ctx)!.publishFriendsTile,
                iconColor: const Color(0xFF00BFA5),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (AppConfig.isSupabaseConfigured) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AudioRoomsScreen(
                          autoCreate: true,
                          friendsMode: true,
                        ),
                      ),
                    );
                  } else {
                    _liveNotConfigured(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _liveNotConfigured(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.livesNeedConfig),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _publishTile(
    BuildContext ctx,
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Color iconColor = const Color(0xFF8B5CF6),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Color(0xFF252525), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_home.png',
                  label: l10n.homeTab,
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_jogo.png',
                  label: l10n.gamesTab,
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showPublishMenu(context),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8B5CF6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_mensagens.png',
                  label: l10n.messagesTab,
                  selected: currentIndex == 4,
                  badge: messageUnread,
                  onTap: () => onTap(4),
                ),
              ),
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_perfil_aba.png',
                  label: l10n.profileTab,
                  selected: currentIndex == 5,
                  onTap: () => onTap(5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final String? asset;
  final String label;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.asset,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _StyledAssetIcon(
                  asset: asset!,
                  size: 24,
                  tint: selected
                      ? const Color(0xFFA78BFA)
                      : const Color(0xFF8E8E8E),
                ),
                if (badge != null && badge! > 0)
                  Positioned(
                    right: -12,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5C5C),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: selected ? 16 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFFE9E9FF) : Colors.grey,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// FEED
// ============================================================

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.tabActive = true, this.rewardPaused});

  /// `false` quando o Feed não é a aba ativa (ex.: usuário foi para outra
  /// aba) — o estado pausa os vídeos para não tocar áudio em segundo plano.
  final bool tabActive;

  /// Notifica o ciclo de recompensas quando nenhum vídeo do feed está de
  /// fato sendo assistido (o ciclo de recompensa pausa nesses casos).
  final ValueNotifier<bool>? rewardPaused;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  late final PageController _pageController;

  int _currentPage = 0;
  int _feedTab = _FeedTopBar.forYouIndex;

  /// `false` quando o app vai para background — o vídeo ativo pausa e o
  /// preload do próximo é interrompido (nenhum download/áudio sem necessidade).
  bool _appActive = true;

  /// Resolução em ondas das URLs do lote inicial: a primeira onda pinta o
  /// feed (primeiro vídeo toca cedo) enquanto o restante é resolvido em
  /// background. Bloqueia paginação/duplicatas durante a resolução.
  bool _resolvingInitial = false;

  /// Evita consultas duplicadas de anúncios no boot (initState + fim do load).
  bool _adsLoading = false;

  // Pull-to-refresh APENAS no primeiro vídeo (índice 0): o PageView usa
  // BouncingScrollPhysics para o overscroll acompanhar o dedo em qualquer
  // plataforma; o NotificationListener detecta o arrasto além do topo, mostra
  // um indicador compacto e executa o refresh real preservando posição,
  // controllers e vídeo atual.
  final ValueNotifier<double> _pullExtent = ValueNotifier(0);
  bool _refreshingPull = false;
  static const double _pullRefreshThreshold = 55;

  List<KlayKVideo> _videos = [];
  bool _loading = true;
  double _feedLoadingProgress = 0;
  bool _feedError = false;

  /// Marca que uma carga do feed está em voo (guarda de reentrância por
  /// execução — NÃO é o mesmo que a flag de UI `_loading`, que se inicia true
  /// para exibir o spinner). Isso impede que a PRIMEIRA carga seja pulada.
  bool _feedLoadInFlight = false;

  static const int _feedPageSize = 50;

  /// Teto duro para a carga completa do feed (autenticação + posts +
  /// likes/saves/follows). Garante que qualquer lentidão do Supabase termina
  /// em estado de erro com "Tentar novamente" — nunca em loading infinito.
  static const Duration feedLoadHardTimeout = Duration(seconds: 45);

  /// Teto do feed na memória: evita acumular centenas de vídeos ao rolar;
  /// páginas antigas saem da PageView (cache) e a paginação simplesmente para.
  static const int _maxFeedVideos = 200;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loadMoreFailed = false;

  List<AdCreative> _feedAds = [];
  final List<String> _countedAdImpressions = [];

  // Lives reais ativas (status='live') intercaladas no feed "Para você".
  // Somente dados reais do Supabase; quando uma live encerra, o realtime a
  // remove — nunca aparece uma live encerrada no feed.
  List<RealLive> _feedLives = const [];
  RealtimeChannel? _livesChannel;
  Timer? _livesRefreshDebounce;

  StreamSubscription<AuthState>? _authSub;

  String _myAvatarUrl = '';

  List<KlayKVideo> get videos => _videos;

  /// Feed combinado: vídeos intercalados com anúncios aprovados e, na aba
  /// "Para você", com lives reais ativas (status='live').
  /// Um anúncio entra a cada [kAdsFeedEveryN] vídeos. Só entram itens
  /// APPROVED vindos da RPC pública (nunca decididos pelo cliente).
  /// As lives vêm do Supabase (nunca do catálogo de demonstração).
  /// Cache do getter [feedItems] para a duração de um frame.
  ///
  /// O getter é lido em 7 pontos (`:2049`, `:2075`, `:2111`, `:2162`, `:2171`,
  /// `:2216`, `:2238`) e cada leitura percorria todos os vídeos remontando a
  /// lista — inclusive de dentro do `itemBuilder`, ou seja, uma vez por item
  /// construído. Aqui a lista é montada uma vez por frame de build.
  List<Object>? _feedItemsCache;
  Object? _feedItemsCacheStamp;

  /// Identidade das entradas que afetam a composição da lista.
  Object get _feedItemsStamp =>
      '${videos.length}|${_feedAds.length}|${_feedLives.length}|$_feedTab';

  List<Object> get feedItems {
    final stamp = _feedItemsStamp;
    final cached = _feedItemsCache;
    if (cached != null && _feedItemsCacheStamp == stamp) return cached;
    final built = _buildFeedItems();
    _feedItemsCache = built;
    _feedItemsCacheStamp = stamp;
    return built;
  }

  List<Object> _buildFeedItems() {
    final withAds = _feedAds.isNotEmpty;
    final withLives =
        _feedTab == _FeedTopBar.forYouIndex && _feedLives.isNotEmpty;
    if (!withAds && !withLives) return List<Object>.of(videos);

    final items = <Object>[];
    for (var i = 0; i < videos.length; i++) {
      items.add(videos[i]);
      // Live reais intercaladas (circular pelas ativas, sem duplicar num slot).
      if (withLives) {
        final liveSlot = (i + 1) % kFeedLiveEveryN == 0;
        if (liveSlot) {
          final live =
              _feedLives[(i + 1) ~/ kFeedLiveEveryN % _feedLives.length];
          items.add(live);
        }
      }
      final adSlot = withAds && i % kAdsFeedEveryN == kAdsFeedEveryN - 1;
      if (adSlot) {
        final ad = _feedAds[i ~/ kAdsFeedEveryN % _feedAds.length];
        items.add(ad);
      }
    }
    return items;
  }

  /// Carrega as lives reais ativas para intercalar no feed (status='live').
  Future<void> _loadFeedLives() async {
    if (!SupabaseService.instance.isConfigured) return;
    try {
      final lives = await SupabaseService.instance.fetchActiveLives().timeout(
        SupabaseService.networkTimeout,
      );
      if (!mounted) return;
      setState(() {
        _feedLives = lives;
      });
    } catch (_) {
      // Falha de rede: mantém o último snapshot válido de lives.
    }
    if (mounted) _subscribeFeedLives();
  }

  /// Realtime em `lives`: nova live entra e live encerrada sai sozinha do
  /// feed (nunca dependemos de reload manual). Debounce evita refetch em
  /// rajadas (ex.: viewer_count mudando).
  void _subscribeFeedLives() {
    if (!SupabaseService.instance.isConfigured) return;
    final me = SupabaseService.instance.client.auth.currentUser?.id;
    if (me == null) return;
    if (_livesChannel != null) return;
    try {
      _livesChannel = SupabaseService.instance.client
          .channel('feed-lives-$me')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'lives',
            callback: (_) => _scheduleFeedLivesRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'lives',
            callback: (_) => _scheduleFeedLivesRefresh(),
          )
          .subscribe();
    } catch (_) {
      // Realtime indisponível: o feed segue com o último snapshot válido.
    }
  }

  void _scheduleFeedLivesRefresh() {
    _livesRefreshDebounce?.cancel();
    _livesRefreshDebounce = Timer(
      const Duration(milliseconds: 500),
      _loadFeedLives,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _loadFeed();
    _loadFeedAds();
    _loadFeedLives();
    _initAuthAndLives();
    _loadAvatar();
    _updateRewardPause();
  }

  /// App volta ao primeiro plano → retoma; foi para background → pausa o vídeo
  /// ativo e interrompe preloads (nenhum controller toca sem necessidade).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active != _appActive && mounted) {
      setState(() {
        _appActive = active;
      });
    }
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabActive != widget.tabActive && mounted) {
      // Rebuild força o VideoItem ativo a pausar (ou retomar) o playback.
      setState(() {});
    }
    if (oldWidget.tabActive != widget.tabActive) {
      // NÃO pode sincronizar aqui: `didUpdateWidget` roda dentro da fase de
      // build, e o `ValueNotifier` notifica de forma síncrona. A notificação
      // chegava no `RewardTimerController.setActive()` -> `notifyListeners()`
      // -> `AnimatedBuilder.markNeedsBuild()` com a árvore em construção
      // ("setState() or markNeedsBuild() called during build").
      _scheduleRewardPauseSync();
    }
  }

  bool _rewardPauseSyncScheduled = false;

  /// Agenda a sincronização do sinal de pausa do RewardTimer para depois do
  /// frame, sem duplicar callbacks e sem notificar se nada mudou.
  void _scheduleRewardPauseSync() {
    if (_rewardPauseSyncScheduled) return;
    _rewardPauseSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rewardPauseSyncScheduled = false;
      if (!mounted) return;
      _updateRewardPause();
    });
  }

  // Assina as mudanças de sessão para recarregar avatar e lives do cabeçalho.
//
// A Central de Notificações NÃO é aberta por aqui: ela vive como aba dentro
// do hub de Mensagens (`messages_hub_screen.dart`), que tem realtime próprio.
// Antes este bloco também mantinha um canal só para atualizar o contador do
// sino do feed — que foi removido, junto com o polling que o alimentava.
void _initAuthAndLives() {
    if (!SupabaseService.instance.isConfigured) return;
    _authSub = SupabaseService.instance.client.auth.onAuthStateChange.listen((
      authState,
    ) {
      final event = authState.event;
      final session = authState.session;
      if (event == AuthChangeEvent.signedIn && session != null) {
        _loadAvatar();
        _loadFeedLives();
      } else if (event == AuthChangeEvent.signedOut) {
        final lc = _livesChannel;
        _livesChannel = null;
        if (lc != null) SupabaseService.instance.removeChannel(lc);
        if (mounted) {
          setState(() {
            _myAvatarUrl = '';
            _feedLives = const [];
          });
        }
      }
    });
  }

  /// Avatar real do usuário logado para o topo da Home.
  Future<void> _loadAvatar() async {
    if (!SupabaseService.instance.isConfigured) return;
    try {
      final me = await ProfileService.instance.fetchMyProfile();
      if (!mounted) return;
      final url = me?.avatarUrl ?? '';
      if (url != _myAvatarUrl) {
        setState(() => _myAvatarUrl = url);
      }
    } catch (_) {
      // Sem sessão ainda: mantém o avatar neutro no topo.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _livesRefreshDebounce?.cancel();
    final lc = _livesChannel;
    if (lc != null) {
      SupabaseService.instance.removeChannel(lc);
      _livesChannel = null;
    }
    _authSub?.cancel();
    _pageController.dispose();
    _pullExtent.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    if (!SupabaseService.instance.isConfigured) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }
    // Guarda de reentrância por execução (e não por _loading, que se inicia
    // true de propósito para exibir o spinner): chamadas duplicadas (troca de
    // aba, retry, refresh) não recarregam enquanto uma carga está em voo — mas
    // a PRIMEIRA carga SEMPRE entra. Sem isso o feed ficava "Carregando..."
    // para sempre (bug real).
    if (_feedLoadInFlight || _resolvingInitial) return;
    _feedLoadInFlight = true;
    debugPrint('[FEED] início (tab $_feedTab)');

    setState(() {
      _loading = true;
      _feedLoadingProgress = 0;
      _feedError = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _hasMore = true;
    });

    var done = false;
    try {
      final posts = await ContentService.instance
          .fetchFeed(limit: _feedPageSize)
          .timeout(feedLoadHardTimeout);
      debugPrint('[FEED] posts consultados: ${posts.length}');
      if (!mounted) {
        _resolvingInitial = false;
        return;
      }
      if (posts.isEmpty) {
        setState(() {
          _videos = const [];
          _feedLoadingProgress = 1;
          _loading = false;
          _feedError = false;
          _hasMore = false;
        });
        done = true;
        debugPrint('[FEED] estado atualizado (vazio)');
        _loadFeedAds();
        return;
      }
      _resolvingInitial = true;
      // Resolve em ondas: após a 1ª onda o feed já é pintado com os primeiros
      // vídeos (o 1º toca imediatamente); o restante entra em background sem
      // esperar a página inteira. NUNCA bloqueia a saída do loading na página
      // toda: cada onda pinta o que já tem.
      await _resolvePostUrls(
        posts,
        onWave: (partial) {
          if (!mounted) return;
          final progress = (partial.length / posts.length)
              .clamp(0.0, 1.0)
              .toDouble();
          setState(() {
            _videos = partial;
            _feedLoadingProgress = progress;
            _loading = false;
            _feedError = false;
          });
          debugPrint('[FEED] URLs resolvidas (onda): ${partial.length}');
        },
      );
      _resolvingInitial = false;
      if (mounted) {
        setState(() {
          _feedLoadingProgress = 1;
          if (posts.length < _feedPageSize) _hasMore = false;
        });
      }
      done = true;
      debugPrint('[FEED] estado atualizado; fim');
      _loadFeedAds();
    } catch (e) {
      debugPrint('[FEED] erro: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _feedError = true;
        });
      }
      done = true;
    } finally {
      _feedLoadInFlight = false;
      _resolvingInitial = false;
      // Saída de segurança: independentemente do que aconteceu, o loading
      // nunca permanece ativo — ou há conteúdo ou há estado de erro com o
      // botão "Tentar novamente".
      if (mounted && !done && _videos.isEmpty) {
        setState(() {
          _loading = false;
          _feedError = true;
        });
        debugPrint('[FEED] fim (saída de segurança)');
      }
    }
  }

  /// Aproximando do fim da PageView com vídeos congelados, busca a próxima
  /// página (offset = total já carregado). Relatório honesto: a RPC de
  /// resolução de URLs é chamada em lotes e cada falha mantém a URL crua.
  Future<void> _loadMoreFeed() async {
    if (!SupabaseService.instance.isConfigured) return;
    if (_loading || _loadingMore || !_hasMore) return;
    if (_resolvingInitial) return;
    if (_videos.isEmpty) return;
    if (_videos.length >= _maxFeedVideos) {
      setState(() => _hasMore = false);
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final posts = await ContentService.instance
          .fetchFeed(limit: _feedPageSize, offset: _videos.length)
          .timeout(feedLoadHardTimeout);
      final loaded = await _resolvePostUrls(posts);
      if (!mounted) return;
      setState(() {
        _videos = [..._videos, ...loaded];
        if (loaded.length < _feedPageSize) _hasMore = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  /// Gatilho de paginação: quando a página ativa chega perto do fim, carrega
  /// o próximo lote (offset estável → sem duplicatas na reversão).
  void _maybeLoadMore(int index) {
    if (index >= feedItems.length - 3) {
      _loadMoreFeed();
    }
  }

  /// Remove um post do feed local (após o dono apagá-lo), mantendo a
  /// PageView consistente sem recarregar tudo.
  void _removePost(String postId) {
    setState(() {
      _videos = List.of(_videos.where((v) => v.id != postId));
    });
  }

  /// Remove um anúncio oculto do feed imediatamente (sem esperar reload).
  void _removeFeedAd(String adId) {
    setState(() {
      _feedAds = List.of(_feedAds.where((a) => a.id != adId));
    });
  }

  /// Autoplay contínuo: quando o vídeo termina, avança para a página seguinte
  /// (ordem real do feed — incluindo anúncios aprovados). O PageView desliza
  /// uma página e o novo vídeo já pré-carregado assume a reprodução após o
  /// `onPageChanged`. Sem loop do vídeo atual quando existe próximo (§7).
  void _autoAdvance(int fromIndex) {
    final target = fromIndex + 1;
    if (target >= feedItems.length) return;
    if (!mounted || !_pageController.hasClients) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Carrega anúncios aprovados para intercalar no feed. Nunca decide status
  /// no cliente: usa a RPC pública (security definer) que só retorna APPROVED.
  /// O conjunto é fixado para a sessão (cap local anti-spam §33) — a PageView
  /// preserva o mesmo itemCount, sem encolher em runtime.
  Future<void> _loadFeedAds() async {
    if (!SupabaseService.instance.isConfigured) return;
    if (_adsLoading) return;
    _adsLoading = true;
    try {
      final ads = await AdsService.instance
          .fetchApprovedAds(limit: 15)
          .timeout(SupabaseService.networkTimeout);
      if (!mounted) return;
      setState(() {
        _feedAds = List.of(
          ads.where((a) => a.isApproved).take(kAdMaxPerSession),
        );
      });
    } catch (_) {
      // Anúncios são opcionais no feed; falha silenciosa mantém o feed vídeo.
    } finally {
      _adsLoading = false;
    }
  }

  /// Registra uma impressão quando um anúncio vira a página ativa (uma vez por
  /// visualização sessional). A RPC conta só quando o backend aceita.
  void _trackAdImpression(int combinedIndex) {
    final item = feedItems[combinedIndex];
    if (item is! AdCreative) return;
    if (_countedAdImpressions.contains(item.id)) return;
    _countedAdImpressions.add(item.id);
    AdsService.instance.trackEvent(item.id, 'impression');
  }

  /// Grava a visualização do vídeo que entrou na tela.
  ///
  /// Antes disso `posts.views_count` nunca era escrito: a coluna existia, o
  /// Creator Dashboard lia, e o número ficava sempre zerado. A RPC
  /// `record_post_view` só conta a primeira vez por usuário e vídeo, então
  /// deslizar para frente e voltar não infla o contador.
  ///
  /// Só conta vídeo de criador — anúncio tem métrica própria (`impression`)
  /// e LIVE não é `posts`.
  void _recordFeedView(int combinedIndex) {
    if (_feedTab != _FeedTopBar.forYouIndex &&
        _feedTab != _FeedTopBar.followingIndex &&
        _feedTab != _FeedTopBar.storeIndex) {
      return;
    }
    final items = feedItems;
    if (combinedIndex < 0 || combinedIndex >= items.length) return;
    final item = items[combinedIndex];
    if (item is! KlayKVideo) return;
    if (_viewedPostIds.contains(item.id)) return;
    _viewedPostIds.add(item.id);
    unawaited(ContentService.instance.recordPostView(item.id));
  }

  /// Ids já contabilizados nesta sessão, para não repetir a chamada quando o
  /// usuário desliza para trás e para frente no mesmo vídeo.
  final Set<String> _viewedPostIds = <String>{};

  /// Mantém o sinal de pausa da recompensa sincronizado: o ciclo só conta
  /// tempo quando o Feed (aba ativa) está na sub-aba que reproduz vídeos.
  void _updateRewardPause() {
    final notifier = widget.rewardPaused;
    if (notifier == null) return;
    final watching =
        widget.tabActive &&
        (_feedTab == _FeedTopBar.followingIndex ||
            _feedTab == _FeedTopBar.forYouIndex ||
            _feedTab == _FeedTopBar.storeIndex);
    if (notifier.value != !watching) {
      notifier.value = !watching;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isMarketplace = _feedTab == _FeedTopBar.storeIndex;
    final showFeed =
        !isMarketplace &&
        (_feedTab == _FeedTopBar.followingIndex ||
            _feedTab == _FeedTopBar.forYouIndex);

    return Scaffold(
      backgroundColor: kc(context).bg,
      body: Stack(
        children: [
          // A aba Loja é o Marketplace: tela cheia com busca, filtros, grade
          // e "Minha loja". Substitui o PageView de vídeos — o conteúdo de
          // vídeo da Loja nunca foi próprio, era o mesmo feed com chip marcado.
          if (isMarketplace)
            Positioned.fill(
              child: StoreMarketScreen(topPadding: topPadding),
            ),
          if (showFeed)
            NotificationListener<ScrollNotification>(
              onNotification: _onFeedScrollNotification,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                // Overscroll elástico: permite puxar o primeiro vídeo para
                // baixo (índice 0) com o conteúdo acompanhando o dedo em
                // qualquer plataforma. Nos demais vídeos o swipe normal segue
                // intacto (apenas bounce nas bordas, sem refresh).
                physics: const BouncingScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                // Pré-constrói a página vizinha (pré-carga do vídeo seguinte
                // para o autoplay/swipe sem stutter) — com cache implícito
                // limitado, sem instanciar todas as páginas do feed.
                allowImplicitScrolling: true,
                itemCount: feedItems.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  _trackAdImpression(index);
                  _maybeLoadMore(index);
                  _recordFeedView(index);
                },
                itemBuilder: (context, index) {
                  final item = feedItems[index];
                  if (item is RealLive) {
                    return RepaintBoundary(
                      key: ValueKey('rp-live-${item.id}'),
                      child: _FeedLiveItem(
                        key: ValueKey('live-${item.id}'),
                        live: item,
                        isActive:
                            index == _currentPage &&
                            widget.tabActive &&
                            _appActive,
                        onWatch: () => _openRealLiveInFeed(item),
                      ),
                    );
                  }
                  if (item is AdCreative) {
                    return RepaintBoundary(
                      key: ValueKey('rp-ad-${item.id}'),
                      child: _FeedAdItem(
                        key: ValueKey('ad-${item.id}'),
                        ad: item,
                        isActive:
                            index == _currentPage &&
                            widget.tabActive &&
                            _appActive,
                        onHidden: () => _removeFeedAd(item.id),
                      ),
                    );
                  }
                  final video = item as KlayKVideo;
                  return RepaintBoundary(
                    key: ValueKey('rp-${video.id}'),
                    child: VideoItem(
                      key: ValueKey(video.id),
                      video: video,
                      videoIndex: index,
                      isActive:
                          index == _currentPage &&
                          widget.tabActive &&
                          _appActive,
                      shouldPreload:
                          widget.tabActive &&
                          _appActive &&
                          (index == _currentPage || index == _currentPage + 1),
                      onDeleted: () => _removePost(video.id),
                      onEnded: index < feedItems.length - 1
                          ? () => _autoAdvance(index)
                          : null,
                    ),
                  );
                },
              ),
            ),
          if (showFeed && _loading && videos.isEmpty)
            Positioned.fill(
              child: _FeedLoadingState(progress: _feedLoadingProgress),
            ),
          if (showFeed && _feedError && videos.isEmpty)
            KlaykErrorState(
              onRetry: _loadFeed,
              title: AppLocalizations.of(context)!.loadVideosFailTitle,
              message: AppLocalizations.of(context)!.loadVideosFailBody,
            ),
          if (showFeed &&
              !_loading &&
              !_feedError &&
              videos.isEmpty &&
              feedItems.isEmpty)
            _FeedEmptyState(onRetry: _loadFeed),
          if (showFeed && _loadingMore)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 96,
              child: Center(child: _FeedLoadMoreIndicator()),
            ),
          if (showFeed && _loadMoreFailed && _hasMore)
            Positioned(
              left: 0,
              right: 0,
              bottom: 96,
              child: Center(child: _FeedLoadMoreRetry(onRetry: _loadMoreFeed)),
            ),
          if (_feedTab == _FeedTopBar.liveIndex)
            Positioned.fill(
              child: _LiveArea(topPadding: topPadding, onWatch: _openLive),
            ),
          if (_feedTab == _FeedTopBar.gamesIndex)
            Positioned.fill(child: _GamesArea(topPadding: topPadding)),
          if (_feedTab == _FeedTopBar.destaquesIndex)
            Positioned.fill(
              child: _DestaquesArea(
                topPadding: topPadding,
                onWatchLive: _openLive,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FeedTopBar(
              topPadding: topPadding,
              feedTab: _feedTab,
              onTabChanged: (tab) {
                if (tab == _FeedTopBar.discoverIndex) {
                  _openDiscover();
                  return;
                }
                if (tab == _FeedTopBar.communitiesIndex) {
                  _openCommunities();
                  return;
                }
                if (tab == _FeedTopBar.friendsIndex) {
                  _openFriends();
                  return;
                }
                if (tab == _FeedTopBar.eventsIndex) {
                  _openEvents();
                  return;
                }
                if (tab == _FeedTopBar.audioIndex) {
                  _openAudioRooms();
                  return;
                }
                if (tab == _FeedTopBar.momentsIndex) {
                  _openMoments();
                  return;
                }
                if (tab == _FeedTopBar.risingIndex) {
                  _openRisingCreators();
                  return;
                }
                setState(() {
                  _feedTab = tab;
                });
                _updateRewardPause();
              },
              onSearch: () {
                showSearch(context: context, delegate: KlayKSearchDelegate());
              },
              avatarUrl: _myAvatarUrl,
              onProfile: () => kNavIndex.value = 5,
            ),
          ),
          // Pull-to-refresh (índice 0): indicador compacto estilo KLAY K que
          // acompanha o dedo e gira enquanto atualiza. Sem botão fixo na tela.
          if (showFeed)
            Positioned(
              top: topPadding + 64,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pullExtent,
                    builder: (context, _) => _FeedPullIndicator(
                      pull: _pullExtent.value,
                      refreshing: _refreshingPull,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Detector de pull-to-refresh: verifica o arrasto além do limite superior
  /// do feed (extentBefore == 0 ⇔ primeiro vídeo). Nunca ativa em outro índice;
  /// o swipe vertical normal e o autoplay continuam intactos.
  bool _onFeedScrollNotification(ScrollNotification n) {
    if (_refreshingPull) return false;
    final atTop = n.metrics.extentBefore <= 0.0001;
    if (n is ScrollUpdateNotification) {
      final px = n.metrics.pixels;
      if (atTop && px < 0) {
        _pullExtent.value = (-px).clamp(0.0, 100.0);
      } else if (_pullExtent.value > 0) {
        _pullExtent.value = 0;
      }
    } else if (n is ScrollEndNotification) {
      if (atTop && _pullExtent.value >= _pullRefreshThreshold) {
        _handleRefresh();
      } else if (_pullExtent.value > 0) {
        _pullExtent.value = 0;
      }
    }
    return false;
  }

  /// Refresh do feed preservando a posição: reutiliza as mesmas funções de
  /// carga reais (vídeos, anúncios e lives), sem duplicar posts e sem resetar
  /// o PageController/controllers de vídeo. Ao terminar, o indicador some.
  Future<void> _handleRefresh() async {
    if (_refreshingPull) return;
    setState(() {
      _refreshingPull = true;
    });
    try {
      await Future.wait([_loadFeed(), _loadFeedAds(), _loadFeedLives()]);
    } finally {
      if (mounted) {
        setState(() {
          _refreshingPull = false;
        });
        _pullExtent.value = 0;
      }
    }
  }

  /// Abre uma live real pelo card do feed (mesmo fluxo da Central de Lives):
  /// o dono entra como streamer; qualquer outro como espectador. Game Live
  /// mantém o flag isGameLive (MediaProjection/screen share).
  Future<void> _openRealLiveInFeed(RealLive live) async {
    final isOwner =
        SupabaseService.instance.client.auth.currentUser?.id == live.streamerId;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LiveRoomScreen(
          live: live,
          role: isOwner ? LiveRole.streamer : LiveRole.viewer,
          isGameLive: _isGameLiveFeed(live),
        ),
      ),
    );
    _loadFeedLives();
  }

  bool _isGameLiveFeed(RealLive live) =>
      live.category.toLowerCase().contains('jogo') ||
      (live.gameName != null && live.gameName!.isNotEmpty);

  Future<void> _openCommunities() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CommunitiesScreen()));
  }

  Future<void> _openDiscover() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DiscoverScreen()));
  }

  Future<void> _openFriends() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
  }

  Future<void> _openEvents() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EventsScreen()));
  }

  Future<void> _openAudioRooms() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AudioRoomsScreen()));
  }

  Future<void> _openMoments() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MomentsScreen()));
  }

  Future<void> _openRisingCreators() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RisingCreatorsScreen()));
  }

  Future<bool> _openLive(KlayKLive live) async {
    // Lives reais são abertas via `_openRealLive` (LiveRoomScreen/LiveKit).
    // `onWatch` cobre apenas o catálogo de demonstração (`kAllLives`).
    final ended = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _LiveViewerScreen(live: live)),
    );
    return ended ?? false;
  }
}

// ============================================================
// ESTADOS DO FEED (loading / vazio) — visual preto/grafite + roxo neon
// ============================================================

class _FeedLoadingState extends StatelessWidget {
  const _FeedLoadingState({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return FeedLoadingHud(progress: progress);
  }
}

/// Feed vazio (backend sem posts / modo sem conexão): nunca inventa vídeo.
/// Mostra somente estados reais com ação de atualizar (§4/§9).
class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = !SupabaseService.instance.isConfigured;
    return KlaykEmptyState(
      icon: Icons.videocam_off_rounded,
      title: AppLocalizations.of(context)!.noVideosAvailable,
      message: offline
          ? AppLocalizations.of(context)!.noVideosLogin
          : AppLocalizations.of(context)!.noVideosFollowHint,
      actionLabel: AppLocalizations.of(context)!.refresh,
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
    );
  }
}

/// Indicador discreto de carregamento da próxima página (feed infinito).
class _FeedLoadMoreIndicator extends StatelessWidget {
  const _FeedLoadMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: kc(context).surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            AppLocalizations.of(context)!.loadingMoreVideos,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Falha ao carregar a próxima página: pílula retry (não bloqueia o feed).
class _FeedLoadMoreRetry extends StatelessWidget {
  const _FeedLoadMoreRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('feed_load_more_retry'),
      onTap: onRetry,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: kc(context).surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 18),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.loadMoreRetry,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TOPO
// ============================================================

class _FeedTopBar extends StatelessWidget {
  final double topPadding;
  final int feedTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onSearch;
  final String avatarUrl;
  final VoidCallback onProfile;

  const _FeedTopBar({
    required this.topPadding,
    required this.feedTab,
    required this.onTabChanged,
    required this.onSearch,
    required this.onProfile,
    this.avatarUrl = '',
  });

  /// Ordem dos chips no topo do feed.
  ///
  /// A ordem segue a [_tabTitles] e o índice é a posição na lista, então os
  /// dois precisam andar juntos. Loja (antigo `storeIndex`) e Jogos
  /// (`gamesIndex`) tinham índices invertidos em relação ao desejado, e como
  /// todo o código compara com estas constantes, trocar os valores aqui realoca
  /// as abas sem quebrar nenhum `if`.
  static const int liveIndex = 0;
  static const int forYouIndex = 1;
  static const int followingIndex = 2;

  /// Índice da aba Loja (mostra o mesmo feed de vídeos, com o chip destacado).
  static const int storeIndex = 3;

  /// Índice da aba Jogos.
  static const int gamesIndex = 4;

  /// Índice da aba que abre a vitrine de Destaques. Sem chip que a alcance —
  /// ver [_tabTitles].
  static const int destaquesIndex = 5;

  /// Títulos dos chips, na MESMA ordem dos índices acima.
  ///
  /// Antes esta lista tinha só 4 entradas enquanto existiam 13 índices, o que
  /// tornava Loja e Destaques inalcançáveis por toque: `_DestaquesArea` e o
  /// chip de Loja eram código morto.
  static List<String> tabTitles(AppLocalizations l10n) => [
    l10n.liveTab,
    l10n.forYouTab,
    l10n.followingFeedsTab,
    l10n.store,
    l10n.gamesTab,
  ];

  /// Índice da aba que abre a exploração de Descobrir/Tendências em tela cheia.
  static const int discoverIndex = 6;

  /// Índice da aba que abre a exploração de Comunidades em tela cheia.
  static const int communitiesIndex = 7;

  /// Índice da aba que abre o hub de Amizades em tela cheia.
  static const int friendsIndex = 8;

  /// Índice da aba que abre a agenda/descoberta de Eventos em tela cheia.
  static const int eventsIndex = 9;

  /// Índice da aba que abre as Salas de Voz (Áudio) em tela cheia.
  static const int audioIndex = 10;

  /// Índice da aba que abre os Momentos (efémeros) em tela cheia.
  static const int momentsIndex = 11;

  /// Índice da aba que abre os Criadores em Ascensão em tela cheia.
  static const int risingIndex = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visibleTabs = tabTitles(l10n);
    return Container(
      padding: EdgeInsets.only(top: topPadding + 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Categorias do feed + pesquisa na mesma linha, junta do topo,
              // horizontalmente rolável. A lupa compacta fica logo após
              // "Jogos" e usa o mesmo detector real de pesquisa.
              SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      ...List.generate(visibleTabs.length, (index) {
                        final selected = feedTab == index;
                        return GestureDetector(
                          onTap: () => onTabChanged(index),
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: selected ? 1.0 : 0.72,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    visibleTabs[index],
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFFB7B7C0),
                                      fontSize: 15,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    height: 3,
                                    width: selected ? 20 : 0,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFF8B5CF6)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 6),
                      // Lupa compacta (toque confortável ≥ 44px) após "Jogos".
                      Semantics(
                        label: 'Pesquisar',
                        button: true,
                        child: GestureDetector(
                          onTap: onSearch,
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.search_rounded,
                              color: Colors.white,
                              size: 24,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ============================================================
// LIVE NO FEED + PULL-TO-REFRESH
// ============================================================

/// Indicador compacto de refresh do feed (identidade KLAY K): pequeno,
/// discreto e sem botão fixo. Aparece apenas durante o gesto pull-to-refresh
/// no primeiro vídeo, acompanha o arrasto e gira enquanto atualiza.
class _FeedPullIndicator extends StatefulWidget {
  const _FeedPullIndicator({required this.pull, required this.refreshing});

  final double pull;
  final bool refreshing;

  @override
  State<_FeedPullIndicator> createState() => _FeedPullIndicatorState();
}

class _FeedPullIndicatorState extends State<_FeedPullIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void didUpdateWidget(_FeedPullIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshing && !oldWidget.refreshing) {
      _spin.repeat();
    } else if (!widget.refreshing && oldWidget.refreshing) {
      _spin.stop();
      _spin.reset();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = widget.refreshing;
    final pull = widget.pull.clamp(0.0, 100.0);
    if (!refreshing && pull <= 0.5) return const SizedBox.shrink();

    final size = refreshing ? 44.0 : (30.0 + pull * 0.24).clamp(30.0, 52.0);
    final opacity = refreshing
        ? 1.0
        : (pull / _kPullIndicatorFade).clamp(0.0, 1.0);
    const neon = Color(0xFF8B5CF6);

    Widget icon;
    if (refreshing) {
      icon = RotationTransition(
        turns: _spin,
        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
      );
    } else {
      icon = Transform.rotate(
        angle: pull * 0.035,
        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
      );
    }

    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xE6161616),
          border: Border.all(color: neon.withValues(alpha: 0.55), width: 1.2),
          boxShadow: [
            BoxShadow(color: neon.withValues(alpha: 0.15), blurRadius: 12),
          ],
        ),
        child: Center(child: icon),
      ),
    );
  }
}

/// Ponto máximo de opacidade do indicador (fade proporcional ao arrasto).
const double _kPullIndicatorFade = 70.0;

/// Altura das abas do feed (topo) que ficam por cima das páginas: 6 (gap do
/// topo) + 44 (fileira das abas) + 10 (espaço abaixo) — usado pelo card de
/// live para o badge AO VIVO nunca ficar escondido atrás das abas.
const double _kFeedTopBarClear = 66.0;

/// Página fullscreen de LIVE REAL no feed "Para você" (status='live').
/// Mostra apenas dados reais: título, streamer (avatar/nome), categoria/jogo,
/// espectadores reais e CTA para entrar na Live. O preview usa o cover real
/// quando existe; senão um gradiente — nunca imagem aleatória/placeholder fake.
class _FeedLiveItem extends StatelessWidget {
  const _FeedLiveItem({
    super.key,
    required this.live,
    required this.isActive,
    required this.onWatch,
  });

  final RealLive live;

  /// Se o slot é a página ativa (para destaque visual, sem autoplay da live).
  final bool isActive;

  final VoidCallback onWatch;

  bool get _isGame =>
      live.category.toLowerCase().contains('jogo') ||
      (live.gameName != null && live.gameName!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final game = _isGame;
    final format = game
        ? (live.gameName != null && live.gameName!.isNotEmpty
              ? live.gameName!
              : live.category)
        : live.category.isEmpty
        ? 'Bate-papo'
        : live.category;

    final bottom = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.remove_red_eye_rounded,
                    color: Colors.white70,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${live.viewerCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (game) ...[
              const Icon(
                Icons.sports_esports_rounded,
                color: Color(0xFFB794FF),
                size: 16,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  format,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          live.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: _kPurple.withValues(alpha: 0.4),
              backgroundImage: live.streamerAvatar != null
                  ? NetworkImage(live.streamerAvatar!)
                  : null,
              child: const Icon(Icons.person, color: Colors.white70, size: 11),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                live.streamerDisplayName ?? live.streamerUsername ?? 'Streamer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (live.description.isNotEmpty) ...[
          Text(
            live.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF3A3A3A), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded, color: _kPurple, size: 18),
                const SizedBox(width: 5),
                Text(
                  l10n.enterLive,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      label:
          'Live ao vivo de ${live.streamerDisplayName ?? live.streamerUsername ?? ''}',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onWatch,
        child: Container(
          color: const Color(0xFF14101A),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (live.coverUrl != null && live.coverUrl!.isNotEmpty)
                Image.network(
                  cacheWidth: imageDecodeWidth(context, 180),
                  live.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _FeedLiveFallback(avatarUrl: live.streamerAvatar),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : _FeedLiveFallback(avatarUrl: live.streamerAvatar),
                )
              else
                _FeedLiveFallback(avatarUrl: live.streamerAvatar),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x33000000),
                      Colors.transparent,
                      Color(0xCC000000),
                      Color(0xF014101A),
                    ],
                    stops: [0.0, 0.3, 0.65, 1.0],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    _kFeedTopBarClear,
                    16,
                    18,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _kLiveRed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.circle,
                                  color: Colors.white,
                                  size: 7,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  AppLocalizations.of(context)!.liveBadge,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            game
                                ? Icons.sports_esports_rounded
                                : Icons.videocam_rounded,
                            color: _kPurple,
                            size: 18,
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Conteúdo inferior rolável em telas muito baixas
                      // (nunca estoura: tela pequena + fontes grandes).
                      Flexible(child: SingleChildScrollView(child: bottom)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fundo gradiente para o card de live sem cover: avatar GRANDE do streamer
/// (com fallback KLAY K) sobre gradiente — nunca fake.
class _FeedLiveFallback extends StatelessWidget {
  final String? avatarUrl;

  const _FeedLiveFallback({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1B54), Color(0xFF0D0B14)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kPurple.withValues(alpha: 0.55),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kPurple.withValues(alpha: 0.4),
                    blurRadius: 26,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? Image.network(
                      avatarUrl!,
                      cacheWidth: imageDecodeWidth(context, 92),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _FallbackInitialAvatar(),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const _FallbackInitialAvatar(),
                    )
                  : const _FallbackInitialAvatar(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar de fallback com a inicial KLAY K ('.') sobre anel roxo — usado
/// quando não há avatar do streamer.
class _FallbackInitialAvatar extends StatelessWidget {
  const _FallbackInitialAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPurple.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: const Icon(Icons.sensors_rounded, color: Colors.white, size: 40),
    );
  }
}

// ============================================================
// VIDEO ITEM
// ============================================================

/// Página de ANÚNCIO fullscreen do feed. Rende um anúncio aprovado de forma
/// inconfundível: badge ANÚNCIO, selo oficial quando verificado, menu
/// "por que estou vendo?/ocultar/denunciar" e CTA explícito.
class _FeedAdItem extends StatelessWidget {
  final AdCreative ad;

  /// Se o slot é a página ativa (para efeitos visuais de destaque).
  final bool isActive;

  /// Remoção imediata do slot após o usuário ocultar o anúncio.
  final VoidCallback? onHidden;

  const _FeedAdItem({
    super.key,
    required this.ad,
    required this.isActive,
    this.onHidden,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final advertiser = ad.advertiserName.isNotEmpty
        ? ad.advertiserName
        : l10n.advertiser;
    return Semantics(
      container: true,
      label: l10n.adOf(advertiser, ad.title.isEmpty ? '' : ' · ${ad.title}'),
      child: Container(
        color: kc(context).bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ad.mediaUrl.isNotEmpty)
              Image.network(
                cacheWidth: imageDecodeWidth(context, 180),
                ad.mediaUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _AdFallbackBg(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : const _AdFallbackBg(),
              )
            else
              const _AdFallbackBg(),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Colors.transparent,
                    Color(0xCC000000),
                    Color(0xF014101A),
                  ],
                  stops: [0.0, 0.25, 0.65, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const AdBadge(),
                        const Spacer(),
                        AdOverflowMenu(ad: ad, onHidden: onHidden),
                      ],
                    ),
                    const Spacer(),
                    if (ad.verified) ...[
                      const VerifiedAdSeal(compact: true),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      ad.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        height: 1.25,
                      ),
                    ),
                    if (ad.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        ad.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        AdAvatar(ad: ad),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ad.advertiserName.isEmpty
                                ? AppLocalizations.of(context)!.advertiser
                                : ad.advertiserName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (ad.verified) ...[
                          Text(
                            AppLocalizations.of(context)!.adVerified,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ] else
                          Text(
                            AppLocalizations.of(context)!.adcompany,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    // CTA só aparece se a campanha tiver um destino real e
                    // aprovado; sem CTA válido, o botão NUNCA aparece (§35/§62).
                    if (ad.hasValidCta) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => _openCta(context, ad),
                          style: FilledButton.styleFrom(
                            backgroundColor: kAdPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(ad.ctaLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCta(BuildContext context, AdCreative ad) {
    openAdCta(context, ad);
  }
}

/// Fundo gradiente quando o anúncio não tem mídia ou ela falha ao carregar.
class _AdFallbackBg extends StatelessWidget {
  const _AdFallbackBg();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2350), Color(0xFF14101A)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.campaign_rounded, color: kAdPurple, size: 64),
      ),
    );
  }
}

class VideoItem extends StatefulWidget {
  final KlayKVideo video;
  final int videoIndex;
  final bool isActive;
  final bool shouldPreload;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;

  /// Chamado quando o vídeo chega ao fim (apenas se ainda for a página ativa)
  /// — o feed avança para o próximo item. Ausente no último item, que então
  /// repete em loop de forma discreta.
  final VoidCallback? onEnded;

  const VideoItem({
    super.key,
    required this.video,
    required this.videoIndex,
    required this.isActive,
    this.shouldPreload = false,
    this.onClose,
    this.onDeleted,
    this.onEnded,
  });

  @override
  State<VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<VideoItem>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;

  bool _loading = true;
  bool _error = false;
  bool _buffering = false;
  bool _showPlayIcon = false;
  bool _showHeart = false;
  bool _downloading = false;
  bool _hashtagsExpanded = false;
  bool _shouldPlayWhenReady = false;

  /// Trava anti-duplicação do avanço automático (evita pular 2 páginas no fim).
  bool _advancing = false;

  /// Quando o usuário retoma um vídeo que já acabou, rebobina para 0 e toca.
  bool _resumeFromEnd = false;

  Timer? _playIconTimer;
  Timer? _heartTimer;

  late AnimationController _heartController;
  late Animation<double> _heartAnimation;

  @override
  void initState() {
    super.initState();

    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _heartAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.elasticOut),
    );

    if (widget.isActive || widget.shouldPreload) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.video.videoUrl),
      );

      _controller = controller;

      await controller.initialize();

      // Loop apenas no ÚLTIMO item do feed (sem próximo). Com próximo, deixa
      // completar para disparar o autoplay contínuo via [_onVideoTick].
      await controller.setLooping(widget.onEnded == null);
      controller.addListener(_onVideoTick);

      if (widget.isActive || _shouldPlayWhenReady) {
        _shouldPlayWhenReady = false;
        await _playFromCurrentPosition();
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  /// Reproduz a partir da posição atual, rebobinando quando o vídeo já chegou
  /// ao fim (retomada manual ou paginação de volta ao item).
  Future<void> _playFromCurrentPosition() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isCompleted) {
      _resumeFromEnd = true;
      await controller.seekTo(Duration.zero);
      return;
    }
    await controller.play();
  }

  /// Escuta o fim do vídeo (loop desligado) para autoplay contínuo e cuida da
  /// retomada de vídeos que já terminaram. Também acende (só na virada) o
  /// indicador discreto de buffering — sem rebuild por tick.
  void _onVideoTick() {
    final controller = _controller;
    if (!mounted || controller == null) return;

    final buffering = controller.value.isBuffering;
    if (buffering != _buffering) {
      _buffering = buffering;
      setState(() {});
    }

    if (_resumeFromEnd) {
      if (controller.value.position.inMilliseconds <= 60 &&
          !controller.value.isPlaying) {
        _resumeFromEnd = false;
        controller.play();
      }
      return;
    }

    final onEnded = widget.onEnded;
    if (onEnded == null || !widget.isActive || _advancing) return;
    if (!controller.value.isCompleted) return;
    _advancing = true;
    onEnded();
  }

  @override
  void didUpdateWidget(covariant VideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nowShouldInit = widget.isActive || widget.shouldPreload;
    final wasShouldInit = oldWidget.isActive || oldWidget.shouldPreload;
    if (_controller == null && nowShouldInit && !wasShouldInit) {
      _initializeVideo();
      return;
    }

    if (widget.isActive && !oldWidget.isActive) {
      _advancing = false;
      if (_controller == null || !_controller!.value.isInitialized) {
        _shouldPlayWhenReady = true;
      } else {
        _playFromCurrentPosition();
      }
    }

    if (!widget.isActive && oldWidget.isActive) {
      _shouldPlayWhenReady = false;
      _resumeFromEnd = false;
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.pause();
      }
    }
  }

  @override
  void dispose() {
    _playIconTimer?.cancel();
    _heartTimer?.cancel();
    _heartController.dispose();
    try {
      _controller?.pause();
    } catch (_) {}
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _toggleVideo() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (_controller!.value.isPlaying) {
      _controller!.pause();

      setState(() {
        _showPlayIcon = true;
      });

      _playIconTimer?.cancel();

      _playIconTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _showPlayIcon = false;
          });
        }
      });
    } else {
      _playFromCurrentPosition();

      setState(() {
        _showPlayIcon = false;
      });
    }
  }

  void _likeVideo() {
    final wasLiked = widget.video.liked;
    setState(() {
      widget.video.liked = !widget.video.liked;

      if (widget.video.liked) {
        widget.video.likes++;
        if (!ExperienceSettings.instance.reduceAnimations) {
          _showHeart = true;
          _heartController.forward(from: 0);
        }
      } else {
        widget.video.likes--;
      }
    });

    if (widget.video.liked) {
      _heartTimer?.cancel();
      _heartTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _showHeart = false;
          });
        }
      });
    }

    _syncLike(wasLiked);
  }

  Future<void> _syncLike(bool wasLiked) async {
    if (!SupabaseService.instance.isConfigured) return;
    try {
      if (widget.video.liked) {
        await ContentService.instance.likePost(widget.video.id);
      } else {
        await ContentService.instance.unlikePost(widget.video.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        widget.video.liked = wasLiked;
        widget.video.likes += wasLiked ? 1 : -1;
      });
      if (wasLiked) _showHeart = false;
      _showSnack(AppLocalizations.of(context)!.likeUpdateFail);
    }
  }

  void _toggleHashtags() {
    setState(() {
      _hashtagsExpanded = !_hashtagsExpanded;
    });
  }

  Future<void> _toggleFollow() async {
    final authorId = widget.video.authorId;
    if (authorId == null || authorId.isEmpty) return;
    if (!SupabaseService.instance.isConfigured) return;

    final wasFollowing = widget.video.following;
    setState(() {
      widget.video.following = !wasFollowing;
    });

    try {
      final svc = ContentService.instance;
      if (wasFollowing) {
        await svc.unfollowUser(authorId);
      } else {
        await svc.followUser(authorId);
      }
      if (!mounted) return;
      _showSnack(
        wasFollowing
            ? AppLocalizations.of(context)!.unfollowed
            : '✓ ${AppLocalizations.of(context)!.nowFollowing}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        widget.video.following = wasFollowing;
      });
      _showSnack(AppLocalizations.of(context)!.followUpdateFail);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ---------------------------------------------------------------------------
  // Ações do dono do vídeo (Editar / Apagar). A posse é reforçada no backend
  // (RLS + RPCs security definer); aqui apenas o gating de UI + confirmação.
  // ---------------------------------------------------------------------------

  bool get _isOwner =>
      widget.video.authorId != null &&
      widget.video.authorId!.isNotEmpty &&
      widget.video.authorId ==
          SupabaseService.instance.client.auth.currentUser?.id;

  Future<void> _editVideo() async {
    final res = await editPostDialog(
      context,
      description: widget.video.description,
      hashtags: widget.video.hashtags,
    );
    if (res == null || !mounted) return;
    final ok = await ContentService.instance.updatePost(
      postId: widget.video.id,
      description: res.description,
      hashtags: res.hashtags,
    );
    if (!mounted) return;
    if (ok) {
      _showSnack(AppLocalizations.of(context)!.videoUpdated);
    } else {
      _showSnack(AppLocalizations.of(context)!.updateFail);
    }
  }

  Future<void> _deleteVideo() async {
    final l10n = AppLocalizations.of(context)!;
    final go = await confirmDeleteDialog(
      context,
      title: l10n.deleteVideoTitle,
      message: l10n.deleteVideoBody,
    );
    if (!go || !mounted) return;
    try {
      await ContentService.instance.deletePost(
        widget.video.id,
        videoPath: widget.video.videoUrl,
        coverUrl: widget.video.coverUrl,
      );
      if (!mounted) return;
      widget.onDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      _showSnack(ContentService.deletePostErrorMessage(e, l10n));
    }
  }

  Future<void> _openCreatorProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: widget.video.authorId ?? ''),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openAudioPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AudioScreen(video: widget.video)));
    if (mounted) setState(() {});
  }

  String get _shareLink => 'https://klayk.app/v/${widget.video.id}';

  Future<void> _showShareMenu() async {
    // Textos localizados capturados ANTES de qualquer await: usar BuildContext
    // depois de um gap assíncrono quebra se o widget já foi descartado, e
    // evita repetir a lookup em cada ramo do switch.
    final l10n = AppLocalizations.of(context)!;
    final shareText =
        '${l10n.lookAtThisVideo} 🎬\n$_shareLink\n${widget.video.videoUrl}';

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildShareSheet(),
    );

    if (action == null) return;
    if (!mounted) return;

    switch (action) {
      case 'friend':
        final friend = await _pickFriend();
        if (friend == null) return;
        if (!SupabaseService.instance.isConfigured) return;
        await _sendVideoToFriend(friend);
      case 'messages':
        final friend = await _pickFriend();
        if (friend == null) return;
        if (!SupabaseService.instance.isConfigured) return;
        await _sendVideoToFriend(friend);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _shareLink));
        if (!mounted) return;
        _showSnack(l10n.linkCopied);
        await _notifyShare();
      case 'whatsapp':
        await _launchShareUrl(
          'https://wa.me/?text=${Uri.encodeComponent('${l10n.lookAtThisVideo} $_shareLink')}',
          'WhatsApp',
        );
      case 'instagram':
        await Share.share(shareText);
        if (!mounted) return;
        await _countShare();
        await _notifyShare();
      case 'facebook':
        await _launchShareUrl(
          'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_shareLink)}',
          'Facebook',
        );
      case 'system':
        await Share.share(shareText);
        if (!mounted) return;
        await _countShare();
        await _notifyShare();
      case 'report':
        await showReportDialog(
          context,
          targetId: widget.video.id,
          targetType: 'post',
          targetLabel: l10n.reportTargetPost,
        );
    }
  }

  /// Notifica o dono do vídeo quando alguém compartilha de verdade (evento
  /// real de compartilhamento — nunca gera aviso para o próprio autor).
  /// Conta o compartilhamento de verdade.
  ///
  /// Antes os quatro caminhos de compartilhamento faziam
  /// `setState(() => widget.video.shares++)`: o número subia na tela e sumia ao
  /// sair, porque `posts.shares_count` não tinha trigger nem gravação. Agora a
/// RPC `increment_post_share` persiste e devolve o total do banco, que é o que
  /// aparece. Se a gravação falhar, mantemos o incremento local para a
  /// experiência não parecer quebrada — e o próximo compartilhamento tenta de novo.
  ///
  /// O total do servidor só é aplicado quando é >= o valor local. Sem essa
  /// guarda, um servidor desatualizado (réplica, RPC que devolveu o valor
  /// corrente para anônimo) fazia o contador VOLTAR: o usuário compartilhava,
  /// o número subia para 1 na hora e no `setState` seguinte caía para 0.
  /// Com o teto de 1/hora, um segundo compartilhamento legítimo já devolve
  /// exatamente o valor anterior — também nesse caso o local é a verdade melhor.
  Future<void> _countShare() async {
    if (!mounted) return;
    setState(() => widget.video.shares++);
    if (!SupabaseService.instance.isConfigured) return;
    final total = await ContentService.instance.incrementShare(widget.video.id);
    if (!mounted || total == null || total < widget.video.shares) return;
    setState(() => widget.video.shares = total);
  }

  Future<void> _notifyShare() async {
    if (!SupabaseService.instance.isConfigured) return;
    final me = SupabaseService.instance.client.auth.currentUser?.id;
    final owner = widget.video.authorId ?? '';
    if (me == null || owner.isEmpty || me == owner) return;
    try {
      await ContentService.instance.notify(
        toUserId: owner,
        actorId: me,
        type: 'share',
        refId: widget.video.id,
        message: '',
      );
    } catch (_) {}
  }

  Future<void> _launchShareUrl(String url, String label) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri.parse(url);
    final available = await canLaunchUrl(uri);
    if (!available) {
      _showSnack(l10n.unavailableOnDevice(label));
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      await _countShare();
      await _notifyShare();
    } else {
      _showSnack(l10n.couldNotOpen(label));
    }
  }

  /// Seleciona um amigo real (backend) para receber o vídeo. Nunca usa lista
  /// falsa: sem amigos ou sem backend, mostra estado honesto (vazio/erro).
  Future<UserProfile?> _pickFriend() async {
    final l10n = AppLocalizations.of(context)!;
    if (!SupabaseService.instance.isConfigured) {
      _showSnack(l10n.loginToSendVideos);
      return null;
    }
    List<UserProfile> friends;
    try {
      friends = await ProfileService.instance.fetchMutualFriends();
    } catch (_) {
      _showSnack(l10n.loadFriendsFail);
      return null;
    }
    if (!mounted) return null;
    if (friends.isEmpty) {
      _showSnack(l10n.noFriendsToReceive);
      return null;
    }
    return showDialog<UserProfile>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        title: Text(
          AppLocalizations.of(context)!.shareToFriend,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: friends.length,
            itemBuilder: (context, i) {
              final f = friends[i];
              final name =
                  f.displayName ??
                  f.username ??
                  AppLocalizations.of(context)!.friend;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(
                    0xFF8B5CF6,
                  ).withValues(alpha: 0.35),
                  backgroundImage:
                      (f.avatarUrl != null && f.avatarUrl!.isNotEmpty)
                      ? NetworkImage(f.avatarUrl!)
                      : null,
                  child: (f.avatarUrl == null || f.avatarUrl!.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white, size: 20)
                      : null,
                ),
                title: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: f.username != null && f.username!.isNotEmpty
                    ? Text(
                        '@${f.username}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      )
                    : null,
                onTap: () => Navigator.pop(context, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  /// Envia o vídeo para um amigo real via DM (conversa real no backend).
  Future<void> _sendVideoToFriend(UserProfile friend) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final conv = await MessageService.instance.getOrCreateConversation(
        friend.id,
      );
      final link =
          '🎬 ${widget.video.displayName}\n$_shareLink\n'
          '${widget.video.videoUrl}';
      await MessageService.instance.sendMessage(conv.id, link);
      if (!mounted) return;
      kNavIndex.value = 4;
      _showSnack(
        l10n.videoSentTo(friend.displayName ?? friend.username ?? l10n.friend),
      );
      await _countShare();
    } catch (_) {
      _showSnack(l10n.sendVideoFail);
    }
  }

  Widget _buildShareSheet() {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text(
                l10n.share,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _ShareOption(
              icon: Icons.person_add_alt_1_rounded,
              color: const Color(0xFF8B5CF6),
              label: l10n.shareToFriend,
              value: 'friend',
            ),
            _ShareOption(
              icon: Icons.chat_bubble_rounded,
              color: const Color(0xFFFF4D6A),
              label: l10n.messagesTab,
              value: 'messages',
            ),
            _ShareOption(
              icon: Icons.link_rounded,
              color: const Color(0xFFFFA53D),
              label: l10n.copyLink,
              value: 'copy',
            ),
            _ShareOption(
              icon: Icons.ios_share_rounded,
              color: const Color(0xFF22C55E),
              label: l10n.shareSystemOthers,
              value: 'system',
            ),
            const _ShareOption(
              icon: Icons.chat_rounded,
              color: Color(0xFF25D366),
              label: 'WhatsApp',
              value: 'whatsapp',
            ),
            const _ShareOption(
              icon: Icons.camera_alt_rounded,
              color: Color(0xFFE1306C),
              label: 'Instagram',
              value: 'instagram',
            ),
            const _ShareOption(
              icon: Icons.thumb_up_alt_rounded,
              color: Color(0xFF1877F2),
              label: 'Facebook',
              value: 'facebook',
            ),
            _ShareOption(
              icon: Icons.more_horiz_rounded,
              color: Colors.white,
              label: l10n.moreAndroidOptions,
              value: 'system',
            ),
            const SizedBox(height: 4),
            const Divider(color: Color(0xFF2A2A2A), height: 20),
            _ShareOption(
              icon: Icons.flag_rounded,
              color: const Color(0xFFE4183C),
              label: l10n.reportPost,
              value: 'report',
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _showSaveMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text(
                AppLocalizations.of(context)!.savePost,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _ShareOption(
              icon: widget.video.saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: const Color(0xFF8B5CF6),
              label: widget.video.saved
                  ? AppLocalizations.of(context)!.removeFromSaved
                  : AppLocalizations.of(context)!.addToSaved,
              value: 'favorite',
            ),
            _ShareOption(
              icon: Icons.download_rounded,
              color: const Color(0xFF22C55E),
              label: AppLocalizations.of(context)!.downloadToDevice,
              value: 'download',
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case 'favorite':
        final wasSaved = widget.video.saved;
        setState(() => widget.video.saved = !widget.video.saved);
        _showSnack(
          widget.video.saved
              ? AppLocalizations.of(context)!.savedUpdated
              : AppLocalizations.of(context)!.unsavedUpdated,
        );
        await _syncSave(wasSaved);
      case 'download':
        await _downloadToDevice();
    }
  }

  Future<void> _syncSave(bool wasSaved) async {
    if (!SupabaseService.instance.isConfigured) return;
    try {
      if (widget.video.saved) {
        await ContentService.instance.savePost(widget.video.id);
      } else {
        await ContentService.instance.unsavePost(widget.video.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => widget.video.saved = wasSaved);
      _showSnack(AppLocalizations.of(context)!.saveSyncError);
    }
  }

  Future<void> _downloadToDevice() async {
    if (_downloading) return;

    setState(() => _downloading = true);

    try {
      final response = await http.get(Uri.parse(widget.video.videoUrl));

      if (!mounted) return;

      if (response.statusCode != 200) {
        _showSnack(AppLocalizations.of(context)!.downloadFail);
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.video.id}.mp4');
      await file.writeAsBytes(response.bodyBytes, flush: true);

      if (!mounted) return;

      _showSnack(AppLocalizations.of(context)!.videoDownloaded);
    } catch (_) {
      if (!mounted) return;
      _showSnack(AppLocalizations.of(context)!.downloadFail);
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  void _showComments() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // Altura razoável do painel; o teclado desloca o sheet inteiro para
        // cima via AnimatedPadding(bottom: viewInsets), mantendo o campo de
        // comentário e o botão Enviar sempre visíveis (sem overflow).
        final screenH = MediaQuery.of(context).size.height;
        final insets = MediaQuery.of(context).viewInsets.bottom;
        final sheetH = (screenH * 0.72).clamp(260.0, screenH * 0.8);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: insets),
          child: SizedBox(
            height: sheetH,
            child: SafeArea(
              top: false,
              child: CommentsSheet(video: widget.video),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Detector de toque de TODO o vídeo: apenas um único toque faz pausar/
    // retomar. Um único tap não compete com o drag vertical do PageView, então
    // o swipe é reconhecido de primeira. Duplo toque (curtir) fica numa região
    // central dedicada (ver _TapZones) para não atrasar o reconhecimento do
    // deslize — corrige a rolagem lenta/travada na primeira tentativa.
    return GestureDetector(
      onTap: _toggleVideo,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: _controller != null && _controller!.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : _buildPlaceholder(),
          ),
          // Região central de duplo-toque para curtir. `translucent` deixa o
          // drag vertical seguir para o PageView (duplo-toque é derrotado por
          // qualquer movimento de deslize), então o swipe continua instantâneo,
          // sem bloquear os botões laterais.
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _likeVideo,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          if (_buffering && !_loading)
            const Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white70,
                ),
              ),
            ),
          if (_error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white54,
                    size: 48,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context)!.videoLoadFail,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          if (_showPlayIcon)
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          if (_showHeart)
            Center(
              child: AnimatedBuilder(
                animation: _heartAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.4 + _heartAnimation.value,
                    child: child,
                  );
                },
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFF4D6A),
                  size: 130,
                  shadows: [
                    Shadow(color: Colors.black45, blurRadius: 16),
                    Shadow(
                      color: Colors.black38,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          // Gradiente escuro discreto na base para legibilidade do texto
          // (sem card gigante cobrindo o vídeo) — identidade preto/grafite.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 240,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Bloco do criador: nome, @usuário e (abaixo) descrição + hashtags no mesmo
          // bloco de texto. É o ÚNICO lugar do feed com esses dados.
          //
          // `bottom` menor = mais baixo na tela, longe do centro do vídeo.
          // O deslocamento é relativo ao `bottomPadding`, que já embute a
          // altura da navegação inferior — então continua responsivo: em
          // telas com navegação maior, o bloco sobe junto, sem cobrir vídeo.
          Positioned(
            left: 12,
            right: 92,
            bottom: bottomPadding + 10,
            child: _CreatorStrip(
              video: widget.video,
              onTap: _openCreatorProfile,
              hashtagsExpanded: _hashtagsExpanded,
              onToggleHashtags: _toggleHashtags,
            ),
          ),
          Positioned(
            right: 10,
            bottom: bottomPadding + 64,
            child: _SideActions(
              video: widget.video,
              controller: _controller,
              isOwner: _isOwner,
              onEditPost: _editVideo,
              onDeletePost: _deleteVideo,
              onLike: _likeVideo,
              onComment: _showComments,
              onShare: _showShareMenu,
              onSave: _showSaveMenu,
              onProfile: _openCreatorProfile,
              onAudio: _openAudioPage,
              onFollow: _toggleFollow,
              downloading: _downloading,
            ),
          ),
          if (widget.onClose != null)
            Positioned(
              left: 12,
              top: MediaQuery.of(context).padding.top + 8,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    final cover = widget.video.coverUrl ?? '';
    return Container(
      color: const Color(0xFF181820),
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover.isNotEmpty)
            Image.network(
              cover,
              fit: BoxFit.cover,
              cacheWidth: imageDecodeWidth(context, 220),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Velatura dark com identidade KLAY K: mantém legíveis os overlays
          // enquanto o vídeo carrega (nunca tela cinza vazia).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0x77000000)],
              ),
            ),
          ),
          const Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FOLHA DE COMENTÁRIOS
// ============================================================

class CommentsSheet extends StatefulWidget {
  final KlayKVideo video;

  const CommentsSheet({super.key, required this.video});

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// ID do comentário sendo respondido. Sem isto a resposta era criada como
  /// comentário solto: a coluna `parent_id` existe no banco mas nunca era
  /// enviada, então "responder" não formava thread nenhuma.
  /// Nome do autor do comentário respondido (só para o rótulo na UI).
  String? _replyToName;
  String? _replyToId;

  Comment? _editingComment;

  List<Comment> _comments = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _totalComments = 0;
  final ScrollController _listScroll = ScrollController();

  bool get _real =>
      SupabaseService.instance.isConfigured && widget.video.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.video.commentList);
    _listScroll.addListener(_onListScroll);
    if (_real) _loadComments();
  }

  /// Traz a próxima página quando chega perto do fim da lista.
  void _onListScroll() {
    if (!_listScroll.hasClients) return;
    final nearEnd =
        _listScroll.position.pixels >=
        _listScroll.position.maxScrollExtent - 320;
    if (nearEnd && _real && _hasMore && !_loading && !_loadingMore) {
      _loadMoreComments();
    }
  }

  @override
  void dispose() {
    _listScroll
      ..removeListener(_onListScroll)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Converte um [PostComment] do banco no modelo de exibição, preservando o
  /// vínculo de resposta e as curtidas.
  Comment _toView(PostComment c) => Comment(
    id: c.id,
    username: c.author?.username != null
        ? '@${c.author!.username}'
        : AppLocalizations.of(context)!.user,
    text: c.text,
    timestamp: c.createdAt,
    // O rótulo mostra QUEM foi respondido (o autor do pai), não a palavra
    // fixa "resposta" que não dizia nada.
    replyTo: c.parentId != null ? _parentAuthorLabel(c.parentId!) : null,
    parentCommentId: c.parentId,
    authorId: c.author?.id,
    avatarUrl: c.author?.avatarUrl,
    likes: c.likesCount,
    liked: c.likedByMe,
    edited: c.editedAt != null,
    isVerified: c.author?.isVerified ?? false,
    mine:
        c.userId != null &&
        c.userId == SupabaseService.instance.client.auth.currentUser?.id,
  );

  /// Nome de quem recebeu a resposta, resolvido na lista já carregada.
  String _parentAuthorLabel(String parentId) {
    for (final c in _comments) {
      if (c.id == parentId) return c.username;
    }
    for (final c in _rawComments) {
      if (c.id == parentId) {
        return c.author?.username != null
            ? '@${c.author!.username}'
            : AppLocalizations.of(context)!.user;
      }
    }
    return AppLocalizations.of(context)!.user;
  }

  ///_BR_: última página bruta do banco, usada só para resolver o nome do pai.
  List<PostComment> _rawComments = const <PostComment>[];

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        ContentService.instance.fetchComments(
          widget.video.id,
          limit: kCommentPageSize,
        ),
        ContentService.instance.countComments(widget.video.id),
      ]);
      final raw = (results[0] as List<PostComment>);
      _rawComments = raw;
      final mapped = raw.map(_toView).toList();
      _totalComments = (results[1] as int);
      _hasMore = mapped.length < _totalComments;
      if (mounted) {
        setState(() {
          _comments = mapped;
          widget.video.commentList = mapped;
          widget.video.comments = _totalComments;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Paginação: busca o próximo bloco a partir do que já foi carregado.
  Future<void> _loadMoreComments() async {
    setState(() => _loadingMore = true);
    try {
      final more = await ContentService.instance.fetchComments(
        widget.video.id,
        limit: kCommentPageSize,
        offset: _rawComments.length,
      );
      if (!mounted) return;
      if (more.isEmpty) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }
      _rawComments = <PostComment>[..._rawComments, ...more];
      final mapped = _rawComments.map(_toView).toList();
      setState(() {
        _comments = mapped;
        _hasMore = mapped.length < _totalComments;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Curte/descurte persistindo de verdade. Antes isto só mudava o objeto em
  /// memória e sumia ao fechar a sheet.
  Future<void> _toggleLike(Comment c) async {
    if (!_real) {
      setState(() {
        final i = _comments.indexWhere((x) => x.id == c.id);
        if (i < 0) return;
        _comments[i] = _comments[i].copyWith(
          liked: !_comments[i].liked,
          likes: _comments[i].likes + (_comments[i].liked ? -1 : 1),
        );
      });
      return;
    }
    // Otimista: a UI responde na hora e reverte se o banco recusar.
    final prevLiked = c.liked;
    final prevLikes = c.likes;
    setState(() {
      final i = _comments.indexWhere((x) => x.id == c.id);
      if (i < 0) return;
      _comments[i] = _comments[i].copyWith(
        liked: !prevLiked,
        likes: prevLikes + (prevLiked ? -1 : 1),
      );
    });
    try {
      final r = await ContentService.instance.toggleCommentLike(c.id);
      if (!mounted) return;
      setState(() {
        final i = _comments.indexWhere((x) => x.id == c.id);
        if (i < 0) return;
        _comments[i] = _comments[i].copyWith(liked: r.liked, likes: r.count);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final i = _comments.indexWhere((x) => x.id == c.id);
        if (i < 0) return;
        _comments[i] = _comments[i].copyWith(
          liked: prevLiked,
          likes: prevLikes,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível curtir agora.')),
      );
    }
  }

  Future<void> _addComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final parentId = _replyToId;
    setState(() {
      _replyToName = null;
      _replyToId = null;
    });
    _focusNode.unfocus();

    if (_real) {
      try {
        // Enviando o parentId é o que cria a thread de verdade. Antes o
        // argumento era omitido, então toda "resposta" era salva como
        // comentário solto mesmo existindo a coluna no banco.
        await ContentService.instance.addComment(
          widget.video.id,
          text,
          parentId: parentId,
        );
        await _loadComments();
        if (mounted) {
          setState(() {
            widget.video.comments = _totalComments;
          });
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.commentSendError),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    setState(() {
      _comments = [
        ..._comments,
        Comment(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          username: 'KLAY K OFICIAL',
          text: text,
          timestamp: DateTime.now(),
          replyTo: _replyToName,
          mine: true,
        ),
      ];
      widget.video.commentList = _comments;
      widget.video.comments++;
    });
  }

  void _deleteComment(Comment comment, {required bool real}) {
    if (real) {
      ContentService.instance
          .deleteComment(comment.id)
          .then((_) {
            _loadComments();
          })
          .catchError((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.commentDeleteError,
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
      return;
    }
    setState(() {
      _comments = _comments.where((c) => c.id != comment.id).toList();
      widget.video.commentList = _comments;
      if (widget.video.comments > 0) widget.video.comments--;
    });
  }

  void _startReply(Comment comment) {
    setState(() {
      _replyToName = comment.username;
      _replyToId = comment.id;
    });
    _focusNode.requestFocus();
  }

  void _startEditComment(Comment comment) {
    setState(() {
      _editingComment = comment;
      _replyToName = null;
      _controller.text = comment.text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelCommentEdit() {
    setState(() {
      _editingComment = null;
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  void _copyComment(Comment comment) {
    Clipboard.setData(ClipboardData(text: comment.text)).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.commentCopied),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Future<void> _applyCommentEdit() async {
    final target = _editingComment;
    if (target == null) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _cancelCommentEdit();
      return;
    }
    if (_real) {
      final applied = await ContentService.instance.editComment(
        target.id,
        text,
      );
      if (!mounted) return;
      if (!applied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.commentEditUnavailable),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _loadComments();
      return;
    }
    setState(() {
      _comments = _comments.map((c) {
        if (c.id != target.id) return c;
        return Comment(
          id: c.id,
          username: c.username,
          text: text,
          timestamp: c.timestamp,
          replyTo: c.replyTo,
          authorId: c.authorId,
          avatarUrl: c.avatarUrl,
          likes: c.likes,
          liked: c.liked,
          mine: c.mine,
          edited: true,
        );
      }).toList();
      widget.video.commentList = _comments;
      _editingComment = null;
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  Future<void> _reportComment(Comment comment) async {
    if (!mounted) return;
    await showReportDialog(
      context,
      targetId: comment.id,
      targetType: 'comment',
      targetLabel: AppLocalizations.of(context)!.commentOf(comment.username),
    );
  }

  void _openCommentProfile(Comment comment) {
    final id = comment.authorId;
    if (id == null || id.isEmpty || !mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white30,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context)!.commentsTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${widget.video.comments}',
                  style: const TextStyle(
                    color: Color(0xFFB28DFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white54, size: 22),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading && _comments.isEmpty
              ? const KlaykLoader()
              : _comments.isEmpty
              ? KlaykEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: AppLocalizations.of(context)!.beFirstToComment,
                  message: AppLocalizations.of(context)!.shareYourOpinion,
                )
              : ListView.builder(
                  controller: _listScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _comments.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _comments.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final c = _comments[index];
                    // Resposta fica recuada e com linha de ligação, para
                    // leitura de thread ficar óbvia.
                    final isReply = c.parentCommentId != null;
                    return Padding(
                      padding: EdgeInsets.only(left: isReply ? 26 : 0),
                      child: isReply
                          // Resposta recuada, com linha de ligação roxa para
                          // a leitura de thread ficar óbvia.
                          ? Container(
                              padding: const EdgeInsets.only(left: 10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: Color(0xFF8B5CF6),
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: _CommentTile(
                                comment: c,
                                onReply: () => _startReply(c),
                                onEdit: () => _startEditComment(c),
                                onCopy: () => _copyComment(c),
                                onDelete: () => _deleteComment(c, real: _real),
                                // Persiste no banco de verdade. Antes só
                                // mudava o objeto em memória.
                                onToggle: () => _toggleLike(c),
                                onReport: () => _reportComment(c),
                                onProfile: () => _openCommentProfile(c),
                              ),
                            )
                          : _CommentTile(
                              comment: c,
                              onReply: () => _startReply(c),
                              onEdit: () => _startEditComment(c),
                              onCopy: () => _copyComment(c),
                              onDelete: () => _deleteComment(c, real: _real),
                              onToggle: () => _toggleLike(c),
                              onReport: () => _reportComment(c),
                              onProfile: () => _openCommentProfile(c),
                            ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
          ),
          child: Row(
            children: [
              const Icon(Icons.sentiment_satisfied_alt, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_replyToName != null) ...[
                      InkWell(
                        onTap: () => setState(() => _replyToName = null),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${AppLocalizations.of(context)!.replyToLabel(_replyToName!)} ✕',
                            style: const TextStyle(
                              color: Color(0xFFB28DFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_editingComment != null) ...[
                      InkWell(
                        onTap: _cancelCommentEdit,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${AppLocalizations.of(context)!.editingCommentLabel} ✕',
                            style: const TextStyle(
                              color: Color(0xFF8B5CF6),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: const Color(0xFF8B5CF6),
                      decoration: InputDecoration(
                        hintText: _editingComment != null
                            ? AppLocalizations.of(context)!.editCommentHint
                            : AppLocalizations.of(context)!.addCommentHint,
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _editingComment != null
                          ? _applyCommentEdit()
                          : _addComment(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _editingComment != null
                    ? _applyCommentEdit
                    : _addComment,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _editingComment != null ? 'Salvar' : 'Enviar',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onReport;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onProfile;

  const _CommentTile({
    required this.comment,
    required this.onReply,
    required this.onDelete,
    required this.onToggle,
    required this.onReport,
    this.onEdit,
    this.onCopy,
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final canOpenProfile =
        onProfile != null && (comment.authorId?.isNotEmpty ?? false);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: canOpenProfile ? onProfile : null,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
              backgroundImage:
                  (comment.avatarUrl != null && comment.avatarUrl!.isNotEmpty)
                  ? NetworkImage(comment.avatarUrl!)
                  : null,
              child: (comment.avatarUrl == null || comment.avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white, size: 20)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: canOpenProfile ? onProfile : null,
                      child: Flexible(
                        child: Text(
                          comment.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: canOpenProfile
                                ? TextDecoration.underline
                                : null,
                            decorationColor: Colors.white38,
                          ),
                        ),
                      ),
                    ),
                    if (comment.isVerified) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(size: 15),
                    ],
                    if (comment.mine) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.you,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (comment.replyTo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!.replyToLabel(comment.replyTo!),
                      style: TextStyle(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (comment.edited)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      AppLocalizations.of(context)!.editedLabel,
                      style: TextStyle(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GestureDetector(
                      onTap: onToggle,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            comment.liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: comment.liked
                                ? const Color(0xFFFF4D6A)
                                : Colors.white38,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${comment.likes}',
                            style: TextStyle(
                              color: comment.liked
                                  ? const Color(0xFFFF4D6A)
                                  : Colors.white38,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    GestureDetector(
                      onTap: onReply,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        AppLocalizations.of(context)!.reply,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (comment.mine) ...[
                      const SizedBox(width: 18),
                      GestureDetector(
                        onTap: onCopy,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          AppLocalizations.of(context)!.copy,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      GestureDetector(
                        onTap: onEdit,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          AppLocalizations.of(context)!.edit,
                          style: const TextStyle(
                            color: Color(0xFFB28DFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      GestureDetector(
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1C1C26),
                              title: Text(
                                AppLocalizations.of(
                                  context,
                                )!.deleteCommentTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              content: Text(
                                AppLocalizations.of(context)!.deleteCommentBody,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(
                                    AppLocalizations.of(context)!.cancel,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    AppLocalizations.of(context)!.delete,
                                    style: const TextStyle(
                                      color: Color(0xFFFF4D6A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) onDelete();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          AppLocalizations.of(context)!.delete,
                          style: const TextStyle(
                            color: Color(0xFFFF4D6A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (!comment.mine) ...[
                      const SizedBox(width: 18),
                      GestureDetector(
                        onTap: onReport,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          AppLocalizations.of(context)!.report,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ESTILOS COMPARTILHADOS
// ============================================================

const _kIconShadow = [
  Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
  Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 0)),
];

const _kLabelShadow = [
  Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
];

// ============================================================
// ÍCONE DE ASSET (PNG)
// ============================================================

class _StyledAssetIcon extends StatelessWidget {
  final String asset;
  final double size;
  final Color? tint;
  final bool shadow;

  const _StyledAssetIcon({
    required this.asset,
    required this.size,
    this.tint,
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (shadow)
          Transform.translate(
            offset: const Offset(0, 1.5),
            child: Opacity(
              opacity: 0.4,
              child: Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.contain,
                color: Colors.black,
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
          ),
        Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          color: tint,
          colorBlendMode: tint == null ? null : BlendMode.srcIn,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: size * 0.6,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// DISCO DE MÚSICA GIRATÓRIO
// ============================================================

class _RotatingDisc extends StatefulWidget {
  final VideoPlayerController? controller;
  final double size;

  const _RotatingDisc({required this.controller, required this.size});

  @override
  State<_RotatingDisc> createState() => _RotatingDiscState();
}

class _RotatingDiscState extends State<_RotatingDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    widget.controller?.addListener(_syncWithPlayer);
    _syncWithPlayer();
  }

  @override
  void didUpdateWidget(covariant _RotatingDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncWithPlayer);
      widget.controller?.addListener(_syncWithPlayer);
    }
    _syncWithPlayer();
  }

  void _syncWithPlayer() {
    final isPlaying = widget.controller?.value.isPlaying ?? false;
    if (isPlaying == _playing) return;
    _playing = isPlaying;
    if (!mounted) return;
    if (isPlaying) {
      _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_syncWithPlayer);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotation,
      child: _StyledAssetIcon(
        asset: 'assets/ic_disco.png',
        size: widget.size,
        shadow: true,
      ),
    );
  }
}

// ============================================================
// AÇÕES LATERAIS
// ============================================================

class _SideActions extends StatelessWidget {
  final KlayKVideo video;
  final VideoPlayerController? controller;
  final bool isOwner;
  final VoidCallback? onEditPost;
  final VoidCallback? onDeletePost;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onProfile;
  final VoidCallback onAudio;
  final VoidCallback onFollow;
  final bool downloading;

  const _SideActions({
    required this.video,
    required this.isOwner,
    this.onEditPost,
    this.onDeletePost,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onProfile,
    required this.onAudio,
    required this.onFollow,
    required this.downloading,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ContentOverflowMenu(
          isOwner: isOwner,
          onEdit: onEditPost ?? () {},
          onDelete: onDeletePost ?? () {},
        ),
        _CreatorAvatar(
          avatarUrl: video.avatarUrl,
          following: video.following,
          onTap: onProfile,
          onFollow: onFollow,
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: video.liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconWidget: _StyledAssetIcon(
            asset: 'assets/ic_curtir.png',
            size: 40,
            tint: video.liked ? const Color(0xFFFF4D6A) : Colors.white,
            shadow: true,
          ),
          label: _formatNumber(video.likes),
          active: video.liked,
          activeColor: const Color(0xFFFF4D6A),
          semanticLabel: AppLocalizations.of(context)!.likeLabel,
          onTap: onLike,
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: Icons.chat_bubble_rounded,
          iconWidget: const _StyledAssetIcon(
            asset: 'assets/ic_comentario.png',
            size: 42,
            shadow: true,
          ),
          label: _formatNumber(video.comments),
          semanticLabel: AppLocalizations.of(context)!.commentsTitle,
          onTap: onComment,
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: Icons.reply_rounded,
          iconWidget: const _StyledAssetIcon(
            asset: 'assets/ic_compartilhar.png',
            size: 40,
            shadow: true,
          ),
          label: _formatNumber(video.shares),
          semanticLabel: AppLocalizations.of(context)!.share,
          onTap: onShare,
        ),
        const SizedBox(height: 14),
        _ActionIcon(
          icon: video.saved
              ? Icons.verified_rounded
              : Icons.file_download_rounded,
          iconWidget: downloading
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                )
              : _StyledAssetIcon(
                  asset: 'assets/ic_download.png',
                  size: 40,
                  tint: video.saved ? const Color(0xFF8B5CF6) : Colors.white,
                  shadow: true,
                ),
          label: video.saved ? AppLocalizations.of(context)!.saveShort : '',
          semanticLabel: AppLocalizations.of(context)!.savePost,
          onTap: onSave,
        ),
        const SizedBox(height: 14),
        Semantics(
          label: AppLocalizations.of(context)!.music,
          button: true,
          child: GestureDetector(
            onTap: onAudio,
            child: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.25),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _RotatingDisc(controller: controller, size: 28),
            ),
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ============================================================
// AVATAR DO CRIADOR
// ============================================================

class _CreatorAvatar extends StatelessWidget {
  final String avatarUrl;
  final bool following;
  final VoidCallback onTap;
  final VoidCallback onFollow;

  const _CreatorAvatar({
    required this.avatarUrl,
    required this.following,
    required this.onTap,
    required this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Perfil',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: following ? const Color(0xFF8B5CF6) : Colors.white,
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF8B5CF6,
                    ).withValues(alpha: following ? 0.25 : 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  // Avatar de 52px: sem cacheWidth o Flutter decodifica a
                  // imagem no tamanho original e segura os pixels em memória.
                  // O helper já existia e era usado em outros pontos.
                  cacheWidth: imageDecodeWidth(context, 52),
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -4,
              right: -4,
              // Badge "+" / "✓": toque curto segue (ou deixa de seguir) o
              // criador usando o sistema real de follows, sem abrir tela nova.
              child: Semantics(
                label: following
                    ? AppLocalizations.of(context)!.following
                    : AppLocalizations.of(context)!.follow,
                button: true,
                child: GestureDetector(
                  onTap: onFollow,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        following ? Icons.check_rounded : Icons.add_rounded,
                        color: following
                            ? const Color(0xFF8B5CF6)
                            : Colors.black,
                        size: 15,
                        weight: 800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BOTÃO DE AÇÃO LATERAL
// ============================================================

class _ActionIcon extends StatefulWidget {
  final IconData icon;
  final Widget? iconWidget;
  final String label;
  final bool active;
  final Color activeColor;
  final String semanticLabel;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.semanticLabel,
    this.iconWidget,
    this.active = false,
    this.activeColor = const Color(0xFFFF4D6A),
  });

  @override
  State<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends State<_ActionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        // Padding extra dá área de toque confortável sem aumentar o ícone.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _scale,
                builder: (_, child) =>
                    Transform.scale(scale: _scale.value, child: child),
                child:
                    widget.iconWidget ??
                    Icon(
                      widget.icon,
                      color: widget.active ? widget.activeColor : Colors.white,
                      size: 40,
                      shadows: _kIconShadow,
                    ),
              ),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: _kLabelShadow,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BLOCO DO CRIADOR (substitui a faixa de "Áudio original")
// ============================================================

/// Tipos de selo suportados pelo bloco do criador.
///
/// Hoje só [verified] existe de verdade (o selo oficial do projeto). Os
/// demais ficam declarados como ponto de extensão para Creator, Pro, Elite,
/// Legend e Founder — mas **não** são exibidos: enquanto o backend não mandar
/// um papel, nenhum selo além de verificado aparece.
enum KlaykBadgeKind {
  verified,
  creator,
  pro,
  elite,
  legend,
  founder;

  /// Só verificação é aplicada ao bloco do criador nesta etapa.
  static bool isActive(KlaykBadgeKind kind) => kind == KlaykBadgeKind.verified;
}

/// Os selos ativos para este criador.
///
/// Ponto único de decisão: é aqui que Creator/Pro/Elite/Legend/Founder vão
/// entrar quando o backend passar a informar o papel do autor. Por enquanto
/// devolve no máximo um selo (verificado), então nunca duplica ícone na linha.
List<KlaykBadgeKind> _creatorBadgesFor(KlayKVideo video) {
  final out = <KlaykBadgeKind>[];
  if (video.isVerified) out.add(KlaykBadgeKind.verified);
  return out.where(KlaykBadgeKind.isActive).toList();
}

/// Informação do criador na parte inferior esquerda do vídeo.
///
/// Ocupa exatamente o espaço que era da faixa de áudio, sem criar área nova:
/// nome + selo na mesma linha, @username abaixo e #klayk em roxo/neon.
///
/// Dados vem do próprio [KlayKVideo] (displayName / username / isVerified) —
/// nada é fixo no código e nenhuma consulta extra é feita ao Supabase.
///
/// A estrutura já aceita outros tipos de selo no futuro: [KlaykBadgeKind]
/// hoje só produz [KlaykBadgeKind.verified], mas o ponto de extensão está
/// aqui para Creator/Pro/Elite/Legend/Founder.
class _CreatorStrip extends StatelessWidget {
  final KlayKVideo video;
  final VoidCallback onTap;

  /// Estado do "mais/menos". Controla **apenas** a descrição + hashtags: nome e
  /// @usuário nunca são afetados.
  final bool hashtagsExpanded;
  final VoidCallback onToggleHashtags;

  const _CreatorStrip({
    required this.video,
    required this.onTap,
    required this.hashtagsExpanded,
    required this.onToggleHashtags,
  });

  /// Linhas do texto antes de cortar. Curto aparece inteiro, sem "mais".
  static const int _collapsedLines = kCaptionCollapsedLines;

  /// Descrição + hashtags como UM único bloco de texto.
  ///
  /// O KLAY K injeta `klayk` em todo post, então a lista de hashtags já vem
  /// com ele — aqui entra junto da descrição, sem bloco separado e sem
  /// duplicar a #klayk.
  String get _caption {
    final desc = video.description.trim();
    final tags = video.hashtags
        .map((t) => t.trim().replaceFirst(RegExp(r'^#'), ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '#$t')
        .toList();
    if (desc.isEmpty) return tags.join(' ');
    if (tags.isEmpty) return desc;
    return '$desc ${tags.join(' ')}';
  }

  /// Mesmo texto da [_caption], mas como spans: hashtags mantêm a cor de
  /// destaque do KLAY K e continuam no MESMO bloco (quebra junto com a
  /// descrição, respeita as mesmas linhas e o mesmo corte).
  TextSpan _captionSpan(Color accent) {
    final desc = video.description.trim();
    final tags = video.hashtags
        .map((t) => t.trim().replaceFirst(RegExp(r'^#'), ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '#$t')
        .toList();
    final children = <InlineSpan>[];
    if (desc.isNotEmpty) {
      children.add(
        TextSpan(
          text: desc,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    for (final tag in tags) {
      children.add(
        TextSpan(
          text: ' $tag',
          style: TextStyle(color: accent, fontWeight: FontWeight.w600),
        ),
      );
    }
    return TextSpan(
      children: children,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        height: 1.3,
        shadows: _kLabelShadow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final name = video.displayName.trim();
    final handle = video.username.trim();
    final hasName = name.isNotEmpty && name != 'Usuário';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Linha 1: nome + selo, com truncamento elegante. O selo fica
          // dentro do Flexible para nunca estourar a largura disponível.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  hasName ? name : handle.replaceFirst('@', ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    shadows: _kLabelShadow,
                  ),
                ),
              ),
              for (final badge in _creatorBadgesFor(video)) ...[
                const SizedBox(width: 5),
                if (badge == KlaykBadgeKind.verified)
                  const VerifiedBadge(size: 15),
              ],
            ],
          ),
          if (handle.isNotEmpty && handle != '@usuario') ...[
            const SizedBox(height: 2),
            Text(
              handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: _kLabelShadow,
              ),
            ),
          ],
          const SizedBox(height: 3),
          // Descrição + hashtags como UM bloco de texto, logo ABAIXO do
          // @usuário. Nunca na mesma linha do @usuário, nunca em bloco
          // separado: é o mesmo `Text.rich`, quebrando junto.
          LayoutBuilder(
            builder: (context, constraints) {
              if (_caption.isEmpty) return const SizedBox.shrink();
              final span = _captionSpan(colors.primarySoft);
              // Mede o texto real para só mostrar "mais" quando existe
              // conteúdo escondido de fato (e não por um chute de tamanho).
              //
              // A medição é cacheada por (texto, largura, direção): o
              // `PageView` mantém 3 páginas vivas e esta medição rodava em
              // todas elas a cada rebuild, não só na página ativa. A largura
              // só muda em rotação ou split-screen, então o cache erra pouco.
              final hidden = captionOverflows(
                span: span,
                maxWidth: constraints.maxWidth,
                textDirection: Directionality.of(context),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    span,
                    maxLines: hashtagsExpanded ? null : _collapsedLines,
                    overflow: hashtagsExpanded
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                  ),
                  if (hidden)
                    GestureDetector(
                      onTap: onToggleHashtags,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              hashtagsExpanded ? 'menos' : 'mais',
                              style: TextStyle(
                                color: colors.primarySoft,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                shadows: _kLabelShadow,
                              ),
                            ),
                            Icon(
                              hashtagsExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: colors.primarySoft,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FAIXA DE ÁUDIO
// ============================================================

class _AudioStrip extends StatelessWidget {
  final String audioName;
  final VoidCallback onTap;

  /// Tamanho do texto. A tela de áudio usa 16 (é o conteúdo principal de lá);
  /// no feed usava 12 como rótulo discreto.
  final double fontSize;

  const _AudioStrip({
    required this.audioName,
    required this.onTap,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_rounded,
            color: Colors.white,
            size: fontSize + 4,
            shadows: _kLabelShadow,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              audioName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: fontSize >= 16 ? FontWeight.w800 : FontWeight.w500,
                shadows: _kLabelShadow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// OPÇÃO DE MENU (COMPARTILHAR / SALVAR)
// ============================================================

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _ShareOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PÁGINA DO ÁUDIO
// ============================================================

class AudioScreen extends StatefulWidget {
  final KlayKVideo video;

  const AudioScreen({super.key, required this.video});

  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  int _totalUses = 0;
  bool _audioLoading = true;
  List<FeedPost> _related = const [];
  bool _relatedLoading = true;

  /// Modo de gerenciamento: seleção múltipla de vídeos deste som.
  bool _manageMode = false;
  final Set<String> _selected = {};
  bool _deleting = false;

  /// True quando o usuário tem capability 'moderation' (apagar vídeos de
  /// outros). O cliente apenas decide o atalho — o backend revalida.
  bool _isMod = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadModCap();
  }

  Future<void> _loadModCap() async {
    if (!SupabaseService.instance.isConfigured) return;
    try {
      final caps = await AdminService.instance.myCaps();
      if (mounted) setState(() => _isMod = caps.contains('moderation'));
    } catch (_) {}
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _deleting) return;
    final n = _selected.length;
    final go = await confirmDeleteDialog(
      context,
      title: AppLocalizations.of(context)!.deleteVideosTitle(n),
      message: AppLocalizations.of(context)!.deleteVideosBody,
      confirmLabel: AppLocalizations.of(context)!.deleteConfirmDialog(n),
    );
    if (!go || !mounted) return;
    await _performDelete(_selected);
  }

  Future<void> _deleteAllAudioVideos() async {
    if (_related.isEmpty || _deleting) return;
    final go = await confirmDeleteDialog(
      context,
      title: AppLocalizations.of(context)!.deleteAllAudioVideosTitle,
      message: AppLocalizations.of(context)!.deleteAllAudioVideosBody,
      confirmLabel: AppLocalizations.of(context)!.deleteAllConfirm,
    );
    if (!go || !mounted) return;
    await _performDelete(_related.map((p) => p.id).toSet());
  }

  Future<void> _performDelete(Set<String> ids) async {
    final myId = SupabaseService.instance.client.auth.currentUser?.id;
    setState(() => _deleting = true);
    var removed = 0;
    var denied = 0;
    for (final p in _related) {
      if (!ids.contains(p.id)) continue;
      final mine = myId != null && p.userId == myId;
      try {
        if (mine) {
          await ContentService.instance.deletePost(
            p.id,
            videoPath: p.videoUrl,
            coverUrl: p.coverUrl,
          );
        } else if (_isMod) {
          final res = await AdminService.instance.adminDeletePost(p.id);
          if (res['ok'] != true && res['id'] == null) {
            denied++;
            continue;
          }
        } else {
          denied++;
          continue;
        }
        removed++;
      } catch (_) {
        denied++;
      }
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _selected.clear();
      _manageMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed > 0
              ? AppLocalizations.of(context)!.audioVideosDeleted(removed)
              : AppLocalizations.of(context)!.audioVideosDeleted(0),
        ),
      ),
    );
    if (denied > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.deleteDeniedPermission),
        ),
      );
    }
    _load();
  }

  /// Dados reais de posts que usam o mesmo áudio (Supabase). Sem modo demo:
  /// sem backend, os valores ficam em 0/vazio (nunca inventa números).
  Future<void> _load() async {
    final audioName = widget.video.audioName;
    if (audioName.isNotEmpty && SupabaseService.instance.isConfigured) {
      try {
        final count = await ContentService.instance.countPostsByAudio(
          audioName,
        );
        final feed = await ContentService.instance.fetchFeed();
        final related = feed
            .where((p) => p.audioName == audioName)
            .take(50)
            .toList();
        if (mounted) {
          setState(() {
            _totalUses = count;
            _related = related;
            _audioLoading = false;
            _relatedLoading = false;
          });
        }
        return;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _audioLoading = false;
        _relatedLoading = false;
      });
    }
  }

  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final totalUses = _totalUses;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F16),
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          AppLocalizations.of(context)!.audio,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (_manageMode)
            TextButton(
              onPressed: _deleting
                  ? null
                  : () => setState(() {
                      _manageMode = false;
                      _selected.clear();
                    }),
              child: Text(
                AppLocalizations.of(context)!.doneAction,
                style: const TextStyle(color: Color(0xFFB28DFF)),
              ),
            )
          else if (_related.isNotEmpty)
            IconButton(
              tooltip: AppLocalizations.of(context)!.manageSoundVideos,
              onPressed: _deleting
                  ? null
                  : () => setState(() => _manageMode = true),
              icon: const Icon(Icons.select_all_rounded, color: Colors.white70),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4C1D95), Color(0xFF8B5CF6)],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nome do áudio com ícone de nota: o mesmo componente
                      // que antes aparecia no feed, agora onde o áudio é o
                      // conteúdo real da tela.
                      _AudioStrip(
                        audioName: widget.video.audioName,
                        onTap: () {},
                        fontSize: 16,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.video.displayName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _audioLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFB28DFF),
                              ),
                            )
                          : Text(
                              AppLocalizations.of(
                                context,
                              )!.soundUses(totalUses),
                              style: const TextStyle(
                                color: Color(0xFFB28DFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: GestureDetector(
              onTap: () {
                kNavIndex.value = 3;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.createVideoWithSound,
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  AppLocalizations.of(context)!.useThisSound,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Text(
              AppLocalizations.of(context)!.videosUsingAudio,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_manageMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                AppLocalizations.of(context)!.tapVideosToSelect,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          Expanded(
            child: _relatedLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  )
                : _related.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.noVideosUsingAudio,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _related.length,
                    itemBuilder: (context, index) {
                      final p = _related[index];
                      final selected = _selected.contains(p.id);
                      final name =
                          p.author?.name ?? AppLocalizations.of(context)!.user;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: _manageMode
                              ? () => setState(() {
                                  if (!_selected.add(p.id)) {
                                    _selected.remove(p.id);
                                  }
                                })
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => VideoPreviewScreen(post: p),
                                  ),
                                ),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF2A2440)
                                  : const Color(0xFF1C1C26),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF8B5CF6)
                                    : Colors.white10,
                                width: selected ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                if (_manageMode) ...[
                                  Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: selected
                                        ? const Color(0xFF8B5CF6)
                                        : Colors.white38,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child:
                                      p.coverUrl == null || p.coverUrl!.isEmpty
                                      ? Container(
                                          width: 56,
                                          height: 76,
                                          color: const Color(0xFF2A2A38),
                                          child: const Icon(
                                            Icons.play_circle_outline,
                                            color: Colors.white38,
                                          ),
                                        )
                                      : Image.network(
                                          p.coverUrl!,
                                          width: 56,
                                          height: 76,
                                          cacheWidth: imageDecodeWidth(
                                            context,
                                            56,
                                          ),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                width: 56,
                                                height: 76,
                                                color: const Color(0xFF2A2A38),
                                                child: const Icon(
                                                  Icons.play_circle_outline,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (p.author?.isVerified ??
                                              false) ...[
                                            const SizedBox(width: 5),
                                            const VerifiedBadge(size: 15),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.likesText(_format(p.likesCount)),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Color(0xFF8B5CF6),
                                  size: 30,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _manageMode
          ? SafeArea(
              child: Container(
                color: const Color(0xFF14141E),
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deleting
                            ? AppLocalizations.of(context)!.deleting
                            : _selected.isEmpty
                            ? AppLocalizations.of(context)!.noneSelected
                            : AppLocalizations.of(
                                context,
                              )!.selectedCount(_selected.length),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _deleting ? null : _deleteAllAudioVideos,
                      child: Text(
                        AppLocalizations.of(context)!.deleteAll,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: (_selected.isEmpty || _deleting)
                          ? null
                          : _deleteSelected,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                      ),
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.deleteCount(_selected.length),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

// ============================================================
// ÁREA DE LIVES (ABA LIVE)
// ============================================================

const _kPurple = Color(0xFF8B5CF6);
const _kLiveRed = Color(0xFFFF2E4D);

class _LiveArea extends StatefulWidget {
  final double topPadding;
  final bool showHeader;
  final Future<bool> Function(KlayKLive live) onWatch;

  const _LiveArea({
    required this.topPadding,
    required this.onWatch,
    this.showHeader = true,
  });

  @override
  State<_LiveArea> createState() => _LiveAreaState();
}

class _LiveAreaState extends State<_LiveArea> {
  int _categoryFilter = 0;

  /// Anúncio institucional do hub de Live (exibido entre seções, sem tocar
  /// na transmissão). Reutiliza [AdCard] com a identidade oficial KLAY K.
  final AdSpot _hubAds = AdSpot();

  /// Em flutter_test não há rede real nem timers controláveis; o carregamento
  /// das lives reais fica desativado e a aba usa o conteúdo demo determinístico.
  static final bool _inTests = Platform.environment['FLUTTER_TEST'] == 'true';

  /// Lives reais (Supabase). Quando o Supabase está configurado e esse fluxo
  /// é usado, a aba Live mostra as transmissões reais; senão o modo demo
  /// (simulado) continua como era.
  List<RealLive>? _activeLives;

  bool get _useReal =>
      SupabaseService.instance.isConfigured && _activeLives != null;

  /// Verdadeiro enquanto ainda não terminamos de cargar as lives reais.
  bool get _liveLoading =>
      SupabaseService.instance.isConfigured && _activeLives == null;

  /// Habilita a ação "Apagar todas as lives" no cabeçalho. O backend sempre
  /// restringe o escopo (próprias; TODAS apenas com capability 'moderation'),
  /// então o botão é apenas um atalho — nunca decide permissão no cliente.
  bool _canManageLives = false;

  @override
  void initState() {
    super.initState();
    _hubAds.load(limit: 3);
    if (SupabaseService.instance.isConfigured && !_inTests) {
      _loadRealLives();
    }
  }

  Future<void> _loadRealLives() async {
    try {
      final lives = await SupabaseService.instance.fetchActiveLives().timeout(
        SupabaseService.networkTimeout,
      );
      if (!mounted) return;
      setState(() => _activeLives = lives);
      _refreshManageLiveScope(lives);
    } catch (_) {
      // Em caso de falha (sem rede, backend desligado), permanece no demo.
    }
  }

  Future<void> _refreshManageLiveScope(List<RealLive> lives) async {
    final uid = SupabaseService.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final anyOwn = lives.any((l) => l.streamerId == uid);
    if (anyOwn) {
      if (mounted) setState(() => _canManageLives = true);
      return;
    }
    final caps = await AdminService.instance.myCaps();
    if (mounted && caps.contains('moderation')) {
      setState(() => _canManageLives = true);
    }
  }

  Future<void> _deleteAllLives() async {
    final go = await confirmDeleteDialog(
      context,
      title: 'Apagar todas as lives?',
      message:
          'Esta ação excluirá permanentemente as lives permitidas e '
          'seus arquivos relacionados.',
      confirmLabel: 'Apagar todas',
    );
    if (!go || !mounted) return;
    final uid = SupabaseService.instance.client.auth.currentUser?.id;
    final lives = _activeLives ?? const <RealLive>[];
    final activeIds = lives
        .where(
          (l) => l.status == 'live' && (l.streamerId == uid || _canManageLives),
        )
        .map((l) => l.id)
        .toList();
    try {
      final deleted = await ContentService.instance.deleteAllLives(
        activeIds: activeIds,
      );
      if (!mounted) return;
      if (deleted >= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todas as lives foram apagadas.')),
        );
        _loadRealLives();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível apagar as lives agora. Tente de novo.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível apagar as lives agora. Tente de novo.',
          ),
        ),
      );
    }
  }

  bool _isGameLive(RealLive live) =>
      live.category.toLowerCase().contains('jogo') ||
      (live.gameName != null && live.gameName!.isNotEmpty);

  Future<void> _editLive(RealLive live) async {
    final res = await editLiveDialog(
      context,
      title: live.title,
      description: live.description,
      category: live.category,
      privacy: live.privacy,
    );
    if (res == null || !mounted) return;
    final ok = await ContentService.instance.updateLive(
      liveId: live.id,
      title: res.title,
      description: res.description,
      category: res.category,
      privacy: res.privacy,
      coverUrl: live.coverUrl,
    );
    if (!mounted) return;
    if (ok) {
      _loadRealLives();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Live atualizada.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar agora. Tente de novo.'),
        ),
      );
    }
  }

  Future<void> _deleteLive(RealLive live) async {
    final go = await confirmDeleteDialog(
      context,
      title: 'Apagar live?',
      message:
          'A live e seu histórico (chat, presentes e eventos) serão removidos '
          'permanentemente. Essa ação não pode ser desfeita.',
    );
    if (!go || !mounted) return;
    try {
      await ContentService.instance.deleteLive(
        live.id,
        coverUrl: live.coverUrl,
      );
      if (!mounted) return;
      _loadRealLives();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível apagar a live.')),
      );
    }
  }

  Future<void> _openRealLive(RealLive live) async {
    // Papel REAL: o dono da live entra como streamer (consegue encerrar e vê o
    // próprio vídeo/áudio); qualquer outra pessoa entra como espectador.
    final isOwner =
        SupabaseService.instance.client.auth.currentUser?.id == live.streamerId;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LiveRoomScreen(
          live: live,
          role: isOwner ? LiveRole.streamer : LiveRole.viewer,
          isGameLive: _isGameLive(live),
        ),
      ),
    );
    _loadRealLives();
  }

  // ---------------------------------------------------------------------------
  // CENTRAL DE LIVES — navegação dos cinco formatos direto para os fluxos reais
  // existentes (nunca para dados falsos).
  // ---------------------------------------------------------------------------

  static const List<LiveFormat> _formats = [
    LiveFormat(
      id: 'video',
      title: '',
      description: '',
      icon: Icons.videocam_rounded,
      accent: kkLivePurple,
    ),
    LiveFormat(
      id: 'audio',
      title: '',
      description: '',
      icon: Icons.mic_rounded,
      accent: kkLiveMagenta,
    ),
    LiveFormat(
      id: 'friends',
      title: '',
      description: '',
      icon: Icons.people_rounded,
      accent: Color(0xFF22C55E),
    ),
    LiveFormat(
      id: 'filmes',
      title: '',
      description: '',
      icon: Icons.movie_rounded,
      accent: Color(0xFFF59E0B),
    ),
    LiveFormat(
      id: 'jogos',
      title: '',
      description: '',
      icon: Icons.sports_esports_rounded,
      accent: kkLivePurple,
    ),
  ];

  static const List<String> _exploreCategories = [
    'Todos',
    'Jogos',
    'Filmes',
    'Música',
    'Bate-papo',
    'Comédia',
    'Educativo',
  ];

  String _formatTitle(AppLocalizations l10n, String id) {
    switch (id) {
      case 'audio':
        return l10n.liveFormatAudio;
      case 'friends':
        return l10n.liveFormatFriends;
      case 'filmes':
        return l10n.liveFormatFilms;
      case 'jogos':
        return l10n.liveFormatGames;
      default:
        return l10n.liveFormatVideo;
    }
  }

  String _formatDescription(AppLocalizations l10n, String id) {
    switch (id) {
      case 'audio':
        return l10n.liveFormatAudioDesc;
      case 'friends':
        return l10n.liveFormatFriendsDesc;
      case 'filmes':
        return l10n.liveFormatFilmsDesc;
      case 'jogos':
        return l10n.liveFormatGamesDesc;
      default:
        return l10n.liveFormatVideoDesc;
    }
  }

  List<LiveFormat> _localizedFormats(AppLocalizations l10n) {
    return _formats
        .map(
          (f) => LiveFormat(
            id: f.id,
            title: _formatTitle(l10n, f.id),
            description: _formatDescription(l10n, f.id),
            icon: f.icon,
            accent: f.accent,
          ),
        )
        .toList();
  }

  String _categoryLabel(AppLocalizations l10n, String category) {
    switch (category.toLowerCase()) {
      case 'jogos':
        return l10n.gamesTab;
      case 'filmes':
        return l10n.liveFormatFilms;
      case 'música':
      case 'musica':
        return l10n.music;
      case 'bate-papo':
        return l10n.exploreChat;
      case 'comédia':
      case 'comedia':
        return l10n.exploreComedy;
      case 'educativo':
        return l10n.exploreEducational;
      default:
        return l10n.exploreAll;
    }
  }

  Future<void> _openVideoLive() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StartLiveScreen()));
    _loadRealLives();
  }

  Future<void> _openAudioLive() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AudioRoomsScreen()));
    _loadRealLives();
  }

  Future<void> _openFriendsLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const AudioRoomsScreen(autoCreate: true, friendsMode: true),
      ),
    );
    _loadRealLives();
  }

  Future<void> _openFilmsLive() async {
    final l10n = AppLocalizations.of(context)!;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StartLiveScreen(
          initialCategory: 'Filmes',
          title: l10n.liveFilmsTitle,
        ),
      ),
    );
    _loadRealLives();
  }

  Future<void> _openGamesLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const StartLiveScreen(forceGame: true),
      ),
    );
    _loadRealLives();
  }

  /// Lives reais de uma categoria (label de [_exploreCategories]) e ordenação
  /// para as seções da Central.
  List<RealLive> _realLivesByCategory(String category) {
    final lives = _activeLives ?? const <RealLive>[];
    if (category != 'Todos') {
      return lives
          .where((l) => l.category.toLowerCase() == category.toLowerCase())
          .toList()
        ..sort((a, b) => b.viewerCount.compareTo(a.viewerCount));
    }
    final sorted = List.of(lives)
      ..sort((a, b) => b.viewerCount.compareTo(a.viewerCount));
    return sorted;
  }

  void _openFormat(LiveFormat format) {
    switch (format.id) {
      case 'video':
        _openVideoLive();
      case 'audio':
        _openAudioLive();
      case 'friends':
        _openFriendsLive();
      case 'filmes':
        _openFilmsLive();
      case 'jogos':
        _openGamesLive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    if (!widget.showHeader) {
      return Container(color: Colors.black, child: _buildCentral(topInset));
    }

    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: widget.topPadding + 96),
            Expanded(child: _buildCentral(topInset)),
          ],
        ),
      ),
    );
  }

  /// Corpo da Central de Lives: cabeçalho + formatos + ao vivo agora + em alta
  /// + explorar por categoria. Seções com dados reais do backend ou estados de
  /// carregamento/vazio/erro (nunca dados falsos permanentes).
  Widget _buildCentral(double topInset) {
    final l10n = AppLocalizations.of(context)!;
    final liveFormats = _localizedFormats(l10n);
    final liveNow = _realLivesByCategory(_exploreCategories[_categoryFilter]);
    final trending = _realLivesByCategory('Todos');

    return ListView(
      key: const PageStorageKey('live-central'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        // ---- Cabeçalho ----
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.live,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (_canManageLives)
              IconButton(
                tooltip: l10n.deleteAllLives,
                onPressed: _deleteAllLives,
                icon: const Icon(
                  Icons.delete_sweep_rounded,
                  color: Color(0xFFEF4444),
                  size: 22,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          l10n.whatDoYouWantToDoToday,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 18),

        // ---- Formatos (5 cards) ----
        LayoutBuilder(
          builder: (context, constraints) {
            final twoPerLine = constraints.maxWidth >= 420;
            final cards = liveFormats.map(
              (f) => LiveTypeCard(
                key: ValueKey('live-${f.id}'),
                format: f,
                onTap: () => _openFormat(f),
              ),
            );
            if (twoPerLine) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in cards)
                    SizedBox(width: (constraints.maxWidth - 12) / 2, child: c),
                ],
              );
            }
            // Celulares menores: 2 colunas com o último card ocupando a linha.
            return _FormatMobileGrid(formats: liveFormats, onOpen: _openFormat);
          },
        ),
        const SizedBox(height: 26),

        // ---- Ao vivo agora ----
        _SectionHeader(
          title: l10n.liveNowTitle,
          subtitle: l10n.liveNowSubtitle,
          icon: Icons.circle,
          liveBadge: true,
        ),
        const SizedBox(height: 12),
        if (_liveLoading)
          const LiveNowSkeleton()
        else if (!SupabaseService.instance.isConfigured)
          _DemoHint(onStart: _openVideoLive)
        else if (liveNow.isEmpty)
          _EmptyLiveState(onStart: _openVideoLive)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.62,
            ),
            itemCount: liveNow.length,
            itemBuilder: (context, index) {
              final live = liveNow[index];
              return _RealLiveCard(
                live: live,
                onTap: () => _openRealLive(live),
                onEditLive: () => _editLive(live),
                onDeleteLive: () => _deleteLive(live),
              );
            },
          ),
        if (_hubAds.ads.isNotEmpty) ...[
          const SizedBox(height: 22),
          AdCard(
            ad: _hubAds.ads.first,
            onHidden: () =>
                setState(() => _hubAds.remove(_hubAds.ads.first.id)),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 26),

        // ---- Em alta ----
        _SectionHeader(
          title: l10n.trendingTitle,
          subtitle: l10n.trendingSubtitle,
          icon: Icons.local_fire_department_rounded,
          accent: kkLiveMagenta,
        ),
        const SizedBox(height: 12),
        if (_liveLoading)
          const LiveNowSkeleton(rows: 1, rail: true)
        else if (trending.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.trendingLivesEmpty,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: trending.take(8).length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final live = trending[index];
                return TrendingLiveCard(
                  title: live.title,
                  meta: live.streamerDisplayName ?? l10n.transmission,
                  viewers: live.viewerCount,
                  onTap: () => _openRealLive(live),
                );
              },
            ),
          ),
        const SizedBox(height: 26),

        // ---- Explorar Lives ----
        _SectionHeader(
          title: l10n.exploreLivesTitle,
          subtitle: l10n.exploreLivesSubtitle,
          icon: Icons.explore_rounded,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _exploreCategories.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                LiveCategoryChip(
                  label: _categoryLabel(l10n, _exploreCategories[i]),
                  selected: _categoryFilter == i,
                  onTap: () => setState(() => _categoryFilter = i),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ---- Jogos ao vivo (rail preservado) ----
        _livestreamGamesRail(),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // LIVE JOGANDO — modo games reutilizando o MESMO sistema de lives (mesma
  // tabela/navegação; apenas uma vitrine destacada + filtro 'Jogos').
  // ---------------------------------------------------------------------------

  Widget _livestreamGamesRail() {
    final realGames = _useReal
        ? (_activeLives ?? const []).where(_isGameLive).toList()
        : const <RealLive>[];
    final demoGames = !_useReal
        ? kAllLives.where((l) => l.isGame).toList()
        : const <KlayKLive>[];
    if (realGames.isEmpty && demoGames.isEmpty) {
      return const SizedBox.shrink();
    }
    final games = _useReal ? realGames.length : demoGames.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Flexible(
                child: Text(
                  '🎮 LIVE JOGANDO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LiveGamesScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: _kPurple,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(AppLocalizations.of(context)!.seeAll),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: games,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (_useReal) {
                final live = realGames[index];
                return _GameLiveRailCard(
                  title: live.title,
                  gameName: live.gameName ?? 'Games',
                  meta: live.streamerDisplayName ?? 'Transmissão',
                  viewers: live.viewerCount,
                  coverUrl: live.coverUrl,
                  onTap: () => _openRealLive(live),
                );
              }
              final live = demoGames[index];
              return _GameLiveRailCard(
                title: live.title,
                gameName: live.gameName,
                meta: live.displayName,
                viewers: live.viewers,
                onTap: () async {
                  final ended = await widget.onWatch(live);
                  if (ended && mounted) {
                    setState(() {
                      kAllLives.removeWhere((l) => l.id == live.id);
                    });
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool liveBadge;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accent = kkLivePurple,
    this.liveBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (liveBadge) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kkLiveRed,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: kkLiveRed.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.circle, color: Colors.white, size: 7),
              ),
              const SizedBox(width: 8),
            ] else ...[
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                shadows: [
                  Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 12),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}

/// Grid responsivo dos 5 cards de formato para telas pequenas: 2 colunas e o
/// último card ocupando a linha inteira.
class _FormatMobileGrid extends StatelessWidget {
  final List<LiveFormat> formats;
  final ValueChanged<LiveFormat> onOpen;

  const _FormatMobileGrid({required this.formats, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < formats.length; i += 2) {
      final isLastOdd = formats.length.isOdd && i == formats.length - 1;
      final first = formats[i];
      final second = i + 1 < formats.length ? formats[i + 1] : null;
      final firstWidget = SizedBox(
        width: isLastOdd ? double.infinity : null,
        child: LiveTypeCard(format: first, onTap: () => onOpen(first)),
      );
      if (second == null) {
        rows.add(firstWidget);
        rows.add(const SizedBox(height: 12));
        break;
      }
      rows.add(
        Row(
          children: [
            Expanded(
              child: LiveTypeCard(format: first, onTap: () => onOpen(first)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LiveTypeCard(format: second, onTap: () => onOpen(second)),
            ),
          ],
        ),
      );
      rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

/// Skeleton de carregamento das seções de live (sem dados falsos).
class LiveNowSkeleton extends StatelessWidget {
  final int rows;
  final bool rail;

  const LiveNowSkeleton({super.key, this.rows = 2, this.rail = false});

  @override
  Widget build(BuildContext context) {
    if (rail) {
      return SizedBox(
        height: 128,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: List.generate(3, (_) {
            return Container(
              width: 200,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: kkLiveCard,
                borderRadius: BorderRadius.circular(16),
              ),
            );
          }),
        ),
      );
    }
    final items = <Widget>[];
    for (var r = 0; r < rows; r++) {
      items
        ..add(
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: kkLiveCard,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: kkLiveCard,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: 10));
    }
    return Column(children: items);
  }
}

class _DemoHint extends StatelessWidget {
  final VoidCallback onStart;

  const _DemoHint({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return _EmptyLiveState(
      onStart: onStart,
      title: AppLocalizations.of(context)!.configureSupabaseForLives,
    );
  }
}

class _EmptyLiveState extends StatelessWidget {
  final VoidCallback onStart;
  final String? title;

  const _EmptyLiveState({required this.onStart, this.title});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kkLiveBorder),
        color: kkLiveSurface.withValues(alpha: 0.5),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.radio_button_checked_rounded,
            color: kkLiveRed,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            title ?? l10n.noLivesNow,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.startOne,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: kkLivePurple,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.sensors_rounded, color: Colors.white),
            label: Text(
              l10n.startLive,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RealLiveCard extends StatelessWidget {
  final RealLive live;
  final VoidCallback onTap;
  final VoidCallback? onEditLive;
  final VoidCallback? onDeleteLive;

  const _RealLiveCard({
    required this.live,
    required this.onTap,
    this.onEditLive,
    this.onDeleteLive,
  });

  bool get _isOwner =>
      SupabaseService.instance.client.auth.currentUser?.id == live.streamerId;

  @override
  Widget build(BuildContext context) {
    return KlayLiveFeedCard(
      live: live,
      onTap: onTap,
      headerTrailing: _isOwner
          ? ContentOverflowMenu(
              isOwner: true,
              onEdit: onEditLive ?? () {},
              onDelete: onDeleteLive ?? () {},
            )
          : null,
    );
  }
}

class _GameLiveRailCard extends StatelessWidget {
  final String title;
  final String gameName;
  final String meta;
  final int viewers;
  final String? coverUrl;
  final VoidCallback onTap;

  const _GameLiveRailCard({
    required this.title,
    required this.gameName,
    required this.meta,
    required this.viewers,
    this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cUrl = coverUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1B4D), Color(0xFF13112B)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
              blurRadius: 16,
            ),
          ],
        ),
        child: Stack(
          children: [
            if (cUrl != null && cUrl.isNotEmpty) ...[
              Positioned.fill(
                child: Image.network(
                  cUrl,
                  cacheWidth: imageDecodeWidth(context, 180),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              right: 10,
              top: 10,
              child: _liveBadge(AppLocalizations.of(context)!.liveBadge),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  const Icon(
                    Icons.sports_esports_rounded,
                    color: Color(0xFFB794FF),
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gameName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB794FF),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFF2E4D).withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, color: Colors.white, size: 6),
        const SizedBox(width: 4),
        Text(
          viewers > 0 ? '$label • $viewers' : label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

// REPRODUÇÃO DE LIVE (FULLSCREEN)
// ============================================================

class _LiveViewerScreen extends StatefulWidget {
  final KlayKLive live;

  const _LiveViewerScreen({required this.live});

  @override
  State<_LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<_LiveViewerScreen> {
  VideoPlayerController? _controller;

  late int _likes;
  late int _giftCount;
  late int _viewers;
  late bool _liked = false;
  late bool _following = false;
  late List<String> _comments;
  bool _showComments = false;
  bool _loading = true;
  final TextEditingController _commentField = TextEditingController();

  @override
  void initState() {
    super.initState();
    _likes = widget.live.likes;
    _giftCount = widget.live.giftCount;
    _viewers = widget.live.viewers;
    _comments = widget.live.comments.toList();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.live.videoUrl),
      );
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _commentField.dispose();
    super.dispose();
  }

  void _sendComment() {
    final text = _commentField.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _comments.insert(0, text);
      _commentField.clear();
    });
  }

  void _showGiftNotice() {
    // Catálogo de demonstração (kAllLives) não é sala real: NUNCA gera
    // transação. Mostra um aviso honesto em vez de um presente falso.
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.demoGiftsTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppLocalizations.of(context)!.demoGiftsBody,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.gotIt),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3B0764), Color(0xFF8B5CF6)],
                ),
              ),
            ),
          if (widget.live.isGame)
            Center(
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: const Icon(
                  Icons.sports_esports_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: topPadding + 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
            ),
          ),
          if (widget.live.own)
            Positioned(
              right: 12,
              top: topPadding + 8,
              child: PopupMenuButton<String>(
                color: const Color(0xFF1C1C26),
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                onSelected: (value) {
                  if (value == 'end') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.liveEnded),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    Navigator.pop(context, true);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'end',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.stop_circle_outlined,
                          color: Color(0xFFFF4D6A),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AppLocalizations.of(context)!.endLive,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            left: 60,
            right: 60,
            top: topPadding + 8,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _kLiveRed,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color: _kLiveRed.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.circle, color: Colors.white, size: 7),
                      const SizedBox(width: 5),
                      Text(
                        AppLocalizations.of(context)!.liveBadge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.live.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: _kLabelShadow,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 10,
            bottom: bottomPadding + 90,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _following = !_following),
                  child: SizedBox(
                    width: 54,
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipOval(
                              child: Image.network(
                                cacheWidth: imageDecodeWidth(context, 52),
                                widget.live.avatarUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 52,
                                  height: 52,
                                  color: Colors.grey[800],
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ),
                            if (!_following)
                              Positioned(
                                bottom: -8,
                                left: 14,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: _kLiveRed,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _following
                              ? AppLocalizations.of(context)!.following
                              : AppLocalizations.of(context)!.follow,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            shadows: _kLabelShadow,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _LiveAction(
                  icon: _liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _liked ? const Color(0xFFFF4D6A) : Colors.white,
                  label: _likes >= 1000
                      ? '${(_likes / 1000).toStringAsFixed(1)}k'
                      : '$_likes',
                  onTap: () {
                    setState(() {
                      _liked = !_liked;
                      _likes += _liked ? 1 : -1;
                    });
                  },
                ),
                const SizedBox(height: 18),
                _LiveAction(
                  icon: Icons.chat_bubble_rounded,
                  color: Colors.white,
                  label: '${_comments.length}',
                  onTap: () => setState(() => _showComments = !_showComments),
                ),
                const SizedBox(height: 18),
                _LiveAction(
                  icon: Icons.card_giftcard_rounded,
                  color: _kPurple,
                  label: '$_giftCount',
                  onTap: _showGiftNotice,
                ),
                const SizedBox(height: 18),
                _LiveAction(
                  icon: Icons.share_rounded,
                  color: Colors.white,
                  label: AppLocalizations.of(context)!.share,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)!.liveLinkCopied,
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 84,
            bottom: bottomPadding + 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kPurple.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.remove_red_eye_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _viewers >= 1000
                                ? '${(_viewers / 1000).toStringAsFixed(1)}k'
                                : '$_viewers',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (widget.live.isGame) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Text(
                          widget.live.gameName,
                          style: const TextStyle(
                            color: _kPurple,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.live.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          shadows: _kLabelShadow,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    if (widget.live.isVerified) const VerifiedBadge(size: 16),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.live.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    shadows: _kLabelShadow,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        color: _kPurple,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _commentField,
                          onSubmitted: (_) => _sendComment(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          cursorColor: _kPurple,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(
                              context,
                            )!.writeCommentHint,
                            hintStyle: const TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _sendComment,
                        child: const Icon(
                          Icons.send_rounded,
                          color: _kPurple,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_showComments)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: topPadding + 66,
              child: GestureDetector(
                onTap: () => setState(() => _showComments = false),
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      height: 320,
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C26),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.commentsCount(_comments.length),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _comments.length,
                              itemBuilder: (context, index) {
                                String name = AppLocalizations.of(
                                  context,
                                )!.viewerFallback;
                                if (index == 0) name = widget.live.displayName;
                                if (index == 1) name = 'Clarice';
                                if (index == 2) name = 'Daniel';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.circle,
                                        color: _kPurple,
                                        size: 8,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '$name  ',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              TextSpan(
                                                text: _comments[index],
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _LiveAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              shadows: _kLabelShadow,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ÁREA JOGOS DA HOME
// ============================================================

/// Prévia da aba Jogos dentro da Home: catálogo real do backend (`games`) com
/// os mesmos cards da aba Jogos ([KlaykGameCard]). Abre os jogos/rankings
/// reais; "Ver todos" leva à aba Jogos completa.
class _GamesArea extends StatefulWidget {
  final double topPadding;

  const _GamesArea({required this.topPadding});

  @override
  State<_GamesArea> createState() => _GamesAreaState();
}

class _GamesAreaState extends State<_GamesArea> {
  final _svc = GameService.instance;
  List<GameInfo> _games = const [];
  Map<String, int> _records = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final games = await _svc.catalog();
    final records = await _svc.myRecords();
    if (!mounted) return;
    setState(() {
      _games = games;
      _records = records;
      _loading = false;
    });
  }

  void _openGame(GameInfo g) {
    openGame(context, g).then((_) {
      if (mounted) _load();
    });
  }

  void _openLeaderboard(GameInfo g) {
    KlaykNav.push(context, GameLeaderboardScreen(game: g));
  }

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return Container(
      color: colors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: widget.topPadding + 96),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.sports_esports_rounded,
                    color: colors.primarySoft,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Jogos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => kNavIndex.value = 2,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primarySoft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(20, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                  label: const Text(
                    'Ver todos',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: KlaykLoader())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _games.isEmpty
                        ? const KlaykEmptyState(
                            icon: Icons.sports_esports_rounded,
                            title: 'Sem jogos no momento',
                            message: 'Novos jogos chegam em breve no KLAY K.',
                          )
                        // `builder` em vez de `children`: antes os cards eram
                        // todos construídos de uma vez, e o catálogo já tem 31
                        // jogos e cresce. Agora só o que está visível é criado.
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                            itemCount: _games.length,
                            itemBuilder: (context, i) {
                              final g = _games[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: KlaykGameCard(
                                  game: g,
                                  best: _records[g.id] ?? 0,
                                  onPlay: g.isActive
                                      ? () => _openGame(g)
                                      : null,
                                  onRanking: g.isActive
                                      ? () => _openLeaderboard(g)
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ABA DESTAQUES
// ============================================================

class _DestaquesArea extends StatefulWidget {
  final double topPadding;
  final Future<bool> Function(KlayKLive live) onWatchLive;

  const _DestaquesArea({required this.topPadding, required this.onWatchLive});

  @override
  State<_DestaquesArea> createState() => _DestaquesAreaState();
}

class _DestaquesAreaState extends State<_DestaquesArea> {
  final List<Map<String, String>> _trending = const [
    {
      'displayName': 'SEM NOÇÃO TV',
      'avatarUrl': 'https://i.pravatar.cc/150?img=12',
      'views': '12,4M',
      'tag': '#sucesso',
    },
    {
      'displayName': 'KLAY K BRASIL',
      'avatarUrl': 'https://i.pravatar.cc/150?img=32',
      'views': '9,1M',
      'tag': '#brasil',
    },
    {
      'displayName': 'CRIADORES KLAY K',
      'avatarUrl': 'https://i.pravatar.cc/150?img=45',
      'views': '7,6M',
      'tag': '#viral',
    },
    {
      'displayName': 'Maria K',
      'avatarUrl': 'https://i.pravatar.cc/150?img=47',
      'views': '5,2M',
      'tag': '#klayk',
    },
  ];

  final List<Map<String, String>> _creators = const [
    {'name': 'SEM NOÇÃO TV', 'avatarUrl': 'https://i.pravatar.cc/150?img=12'},
    {'name': 'KLAY K BRASIL', 'avatarUrl': 'https://i.pravatar.cc/150?img=32'},
    {'name': 'Maria K', 'avatarUrl': 'https://i.pravatar.cc/150?img=47'},
    {'name': 'Pedro L', 'avatarUrl': 'https://i.pravatar.cc/150?img=59'},
    {'name': 'CRIADORES', 'avatarUrl': 'https://i.pravatar.cc/150?img=45'},
  ];

  final List<Map<String, String>> _games = const [
    {'name': 'FreeFire', 'icon': '🔥', 'viewers': '58,3k'},
    {'name': 'Valorant', 'icon': '🎯', 'viewers': '41,9k'},
    {'name': 'LOL', 'icon': '⚔️', 'viewers': '36,2k'},
    {'name': 'Minecraft', 'icon': '⛏️', 'viewers': '21,7k'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: widget.topPadding + 96),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          color: _kPurple,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppLocalizations.of(context)!.highlights,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionTitle(
                    title: AppLocalizations.of(context)!.trendingVideos,
                    trailing: AppLocalizations.of(context)!.seeAll,
                    onTrailing: () =>
                        _showSnack(AppLocalizations.of(context)!.allTrending),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 96,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _trending.length,
                      itemBuilder: (context, index) {
                        return _TrendingVideoCard(
                          rank: index + 1,
                          displayName: _trending[index]['displayName']!,
                          avatarUrl: _trending[index]['avatarUrl']!,
                          views: _trending[index]['views']!,
                          tag: _trending[index]['tag']!,
                          onTap: () => _showSnack(
                            'Abrindo ${_trending[index]['displayName']}',
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: AppLocalizations.of(context)!.trendingCreators,
                    trailing: AppLocalizations.of(context)!.seeAll,
                    onTrailing: () => _showSnack(
                      AppLocalizations.of(context)!.trendingCreators,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 96,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _creators.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () => _showSnack(
                            AppLocalizations.of(
                              context,
                            )!.profileOf(_creators[index]['name']!),
                          ),
                          child: Container(
                            width: 78,
                            margin: const EdgeInsets.only(right: 8),
                            child: Column(
                              children: [
                                ClipOval(
                                  child: Image.network(
                                    _creators[index]['avatarUrl']!,
                                    cacheWidth: imageDecodeWidth(context, 64),
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 64,
                                      height: 64,
                                      color: Colors.grey[800],
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _creators[index]['name']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: AppLocalizations.of(context)!.gamesTab,
                    trailing: AppLocalizations.of(context)!.seeAll,
                    onTrailing: () =>
                        _showSnack(AppLocalizations.of(context)!.allGames),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _games.length,
                      itemBuilder: (context, index) {
                        final game = _games[index];
                        return GestureDetector(
                          onTap: () => _showSnack(
                            AppLocalizations.of(
                              context,
                            )!.openGame(game['name']!),
                          ),
                          child: Container(
                            width: 132,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _kPurple.withValues(alpha: 0.35),
                                width: 1,
                              ),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF251A3D), Color(0xFF181820)],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  game['icon']!,
                                  style: const TextStyle(fontSize: 30),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  game['name']!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.circle,
                                      color: _kLiveRed,
                                      size: 7,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.watchingCount(game['viewers']!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: AppLocalizations.of(context)!.liveBroadcasts,
                    trailing: AppLocalizations.of(context)!.seeAll,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 480,
                child: _LiveArea(
                  topPadding: 0,
                  showHeader: false,
                  onWatch: widget.onWatchLive,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String trailing;
  final VoidCallback? onTrailing;

  const _SectionTitle({
    required this.title,
    this.trailing = '',
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing.isNotEmpty)
            GestureDetector(
              onTap: onTrailing,
              child: Row(
                children: [
                  Text(
                    trailing,
                    style: const TextStyle(
                      color: _kPurple,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _kPurple,
                    size: 16,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendingVideoCard extends StatelessWidget {
  final int rank;
  final String displayName;
  final String avatarUrl;
  final String views;
  final String tag;
  final VoidCallback onTap;

  const _TrendingVideoCard({
    required this.rank,
    required this.displayName,
    required this.avatarUrl,
    required this.views,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 86,
        margin: const EdgeInsets.only(right: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF181820),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              avatarUrl,
              cacheWidth: imageDecodeWidth(context, 86),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF23232E),
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  color: _kPurple,
                  size: 34,
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xE6000000)],
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kPurple,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    views,
                    style: const TextStyle(
                      color: _kPurple,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TELA DE ENVIO
// ============================================================

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, this.draftsStore, this.preselectedVideo});

  /// Armazenamento de rascunhos injetável (mesmo padrão que o `DraftsScreen`).
  /// Quando omitido, usa o `DraftsService.instance` real.
  final DraftStore? draftsStore;

  /// Caminho local de um vídeo já gravado/capturado.
  ///
  /// Quando informado, a tela entra direto na revisão: não pede arquivo e já
  /// inicia o upload, reusando exatamente o mesmo caminho do `_pickVideo`.
  /// É o que liga a tela de criação de vídeo (gravação) à publicação.
  final String? preselectedVideo;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController _descriptionController = TextEditingController();

  File? _selectedVideo;
  bool _picking = false;
  bool _publishing = false;
  bool _savingDraft = false;

  /// Upload do vídeo: inicia no momento em que o usuário escolhe o arquivo
  /// (não espera o tap em "Publicar"). Reaproveitado pelo publish — nunca
  /// envia o mesmo vídeo duas vezes.
  _VideoUploadTask? _videoTask;
  String? _uploadedVideoPath;

  @override
  void initState() {
    super.initState();
    // Vídeo já gravado na tela de criação: entra direto na revisão, sem pedir
    // arquivo de novo. O arquivo tem de existir de fato — uma gravação que o
    // usuário apagou não pode chegar aqui.
    final pre = widget.preselectedVideo;
    if (pre != null && pre.isNotEmpty && File(pre).existsSync()) {
      // Adiado para o primeiro frame: `setState`/upload aqui ainda não podem
      // tocar no contexto de mounted nem disparar build durante o build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _adoptVideo(File(pre));
      });
    }
  }

  /// Adota um vídeo já escolhido: cancela upload anterior, limpa o objeto
  /// antigo no servidor e inicia o novo upload.
  ///
  /// Compartilhado por [initState] (vídeo pré-selecionado) e [_pickVideo]
  /// (galeria) para que os dois caminhos sejam idênticos.
  void _adoptVideo(File file) {
    if (!mounted) return;
    _cancelPendingUpload();
    final uploaded = _uploadedVideoPath;
    setState(() {
      _selectedVideo = file;
      _uploadedVideoPath = null;
      _uploadProgress = null;
    });
    if (uploaded != null) {
      ContentService.instance.removeVideoObject(uploaded);
    }
    _startUploadIfConfigured();
  }

  double? _uploadProgress;

  @override
  void dispose() {
    _cancelPendingUpload();
    // Deixou a tela sem publicar: remove o objeto enviado (nunca publicado).
    if (_uploadedVideoPath != null && !_publishing) {
      ContentService.instance.removeVideoObject(_uploadedVideoPath!);
    }
    _descriptionController.dispose();
    super.dispose();
  }

  /// Extrai as hashtags (#tokens) de uma descrição, no mesmo formato que o
  /// publish usa — [String] sem o `#`.
  List<String> _parseHashtags(String description) => <String>[
    'klayk',
    for (final tag in description.split(RegExp(r'\s+')))
      if (tag.startsWith('#')) tag.substring(1),
  ];

  String _coverMimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  String _videoMimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.mp4')) return 'video/mp4';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.webm')) return 'video/webm';
    if (p.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  void _cancelPendingUpload() {
    final task = _videoTask;
    if (task != null) task.cancelled = true;
    _videoTask = null;
    _uploadProgress = null;
  }

  /// Começa o upload assim que o vídeo é selecionado (configurado), antes de
  /// qualquer interação. Em modo demo (`!isConfigured`) nada é enviado.
  Future<void> _pickVideo() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked != null && mounted) {
        _adoptVideo(File(picked.path));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.videoPickError),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _startUploadIfConfigured() {
    if (!SupabaseService.instance.isConfigured) return;
    final video = _selectedVideo;
    if (video == null || _videoTask != null || _uploadedVideoPath != null) {
      return;
    }
    final task = _VideoUploadTask(_uploadVideo(video));
    _videoTask = task;
  }

  Future<String> _uploadVideo(File video) async {
    final content = ContentService.instance;
    final path = await content.uploadVideo(
      video,
      mime: _videoMimeFor(video.path),
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _uploadProgress = p;
          _videoTask?.progress = p;
        });
      },
      isCancelled: () => _videoTask?.cancelled ?? true,
    );
    if (mounted) setState(() => _uploadProgress = 1);
    return path;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context)!;

    if (_publishing) return;

    if (!SupabaseService.instance.isConfigured) {
      _showMessage(l10n.videoSentSuccessfully);
      _descriptionController.clear();
      return;
    }

    final video = _selectedVideo;
    if (video == null) {
      _showMessage(l10n.selectVideoFirst);
      return;
    }

    setState(() => _publishing = true);
    try {
      // Vídeo: usa o upload já iniciado na seleção (ou concluído). Nunca
      // reenvia o mesmo arquivo.
      final Future<String> videoFuture;
      if (_uploadedVideoPath != null) {
        videoFuture = Future<String>.value(_uploadedVideoPath!);
      } else if (_videoTask != null) {
        videoFuture = _videoTask!.done;
      } else {
        final task = _VideoUploadTask(_uploadVideo(video));
        _videoTask = task;
        videoFuture = task.done;
      }

      // Capa em PARALELO com o fim do vídeo (antes era sequencial, depois do
      // upload completo — o gargalo do "app travado" durante k grande).
      final coverFuture = _pickAndUploadCover();

      final videoPath = await videoFuture;
      String? coverUrl;
      try {
        coverUrl = await coverFuture;
      } catch (_) {
        coverUrl = null;
      }

      final description = _descriptionController.text.trim();
      final hashtags = _parseHashtags(description);

      await ContentService.instance.createPost(
        videoPath: videoPath,
        coverUrl: coverUrl,
        description: description,
        audioName: l10n.originalAudio,
        hashtags: hashtags,
      );

      if (mounted) {
        setState(() {
          _selectedVideo = null;
          _descriptionController.clear();
          _uploadedVideoPath = null;
          _videoTask = null;
          _uploadProgress = null;
        });
      }
      _showMessage(l10n.videoSentSuccessfully);
    } on UploadCancelledException {
      if (mounted) _showMessage(l10n.uploadCancelled);
    } catch (_) {
      if (mounted) {
        _showMessage(l10n.publishVideoFail);
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<String?> _pickAndUploadCover() async {
    try {
      final cover = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
      );
      if (cover == null) return null;
      return ContentService.instance.uploadCover(File(cover.path));
    } catch (_) {
      return null;
    }
  }

  /// Salva o vídeo/capa no bucket privado `drafts` e cria o rascunho
  /// (aparece em "Rascunhos"; nunca no feed até publicar).
  Future<void> _saveDraft() async {
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context)!;

    if (_savingDraft) return;

    final store = widget.draftsStore ?? DraftsService.instance;
    final backend =
        widget.draftsStore != null || SupabaseService.instance.isConfigured;
    if (!backend) {
      _showMessage(l10n.draftSavedShort);
      _descriptionController.clear();
      return;
    }

    final video = _selectedVideo;
    if (video == null) {
      _showMessage(l10n.selectVideoFirst);
      return;
    }

    setState(() => _savingDraft = true);
    try {
      // Upload por STREAM (sem ler o vídeo inteiro na memória).
      final videoPath = await store.uploadVideoFile(
        video,
        contentType: _videoMimeFor(video.path),
      );

      String? coverPath;
      try {
        final cover = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 720,
        );
        if (cover != null) {
          final coverBytes = await File(cover.path).readAsBytes();
          final cName =
              '${DateTime.now().millisecondsSinceEpoch}_${cover.path.split('/').last}';
          coverPath = await store.uploadCoverBytes(
            cName,
            coverBytes,
            contentType: _coverMimeFor(cover.path),
          );
        }
      } catch (_) {
        coverPath = null;
      }

      final description = _descriptionController.text.trim();
      await store.create(
        videoPath: videoPath,
        coverPath: coverPath ?? '',
        description: description,
        audioName: l10n.originalAudio,
        hashtags: _parseHashtags(description),
      );

      if (mounted) {
        setState(() {
          _selectedVideo = null;
          _descriptionController.clear();
        });
      }
      _showMessage(l10n.draftSaved);
    } catch (_) {
      _showMessage(l10n.draftSaveFail);
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedVideo;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.sendVideoButton,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected != null
                      ? const Color(0xFF8B5CF6)
                      : const Color(0xFF2E2A45),
                  width: 1.5,
                ),
              ),
              child: selected != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: VideoPlaybackPreview(file: selected),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: _publishing
                                ? null
                                : () {
                                    _cancelPendingUpload();
                                    final uploaded = _uploadedVideoPath;
                                    setState(() {
                                      _selectedVideo = null;
                                      _uploadedVideoPath = null;
                                      _uploadProgress = null;
                                    });
                                    if (uploaded != null) {
                                      ContentService.instance.removeVideoObject(
                                        uploaded,
                                      );
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.video_call_rounded,
                          color: Colors.white38,
                          size: 64,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)!.selectVideoPlaceholder,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _pickVideo,
                          icon: _picking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.photo_library_outlined),
                          label: Text(
                            AppLocalizations.of(context)!.galleryPick,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF8A2BE2)),
                          ),
                        ),
                      ],
                    ),
            ),
            if (SupabaseService.instance.isConfigured &&
                _videoTask != null) ...[
              const SizedBox(height: 12),
              _UploadProgressBar(
                progress: _uploadProgress ?? _videoTask!.progress,
                done: _uploadedVideoPath != null,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.descriptionLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              cursorColor: const Color(0xFF8A2BE2),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.whatsHappening,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E1B2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _publishing ? null : _publish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A2BE2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _publishing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                            value:
                                _uploadProgress != null && _uploadProgress! < 1
                                ? _uploadProgress
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _uploadProgress != null && _uploadProgress! < 1
                              ? AppLocalizations.of(context)!.publishingPercent(
                                  (_uploadProgress! * 100).round(),
                                )
                              : AppLocalizations.of(context)!.finalizing,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      AppLocalizations.of(context)!.publishAction,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _savingDraft ? null : _saveDraft,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF8A2BE2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _savingDraft
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.note_add_outlined, size: 20),
              label: Text(
                _savingDraft
                    ? AppLocalizations.of(context)!.savingDraft
                    : AppLocalizations.of(context)!.saveDraft,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoUploadTask {
  _VideoUploadTask(this.done);

  /// Completa com o caminho do objeto quando o upload termina.
  final Future<String> done;

  /// Abortar o envio (fluxo de bytes é interrompido).
  bool cancelled = false;
  double progress = 0;
}

/// Barra discreta de progresso real do envio do vídeo (aparece assim que o
/// usuário seleciona o arquivo, antes mesmo de tocar em "Publicar").
class _UploadProgressBar extends StatelessWidget {
  final double progress;
  final bool done;

  const _UploadProgressBar({required this.progress, required this.done});

  @override
  Widget build(BuildContext context) {
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: done ? 1 : progress.clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: const Color(0xFF2E2A45),
          color: const Color(0xFF8A2BE2),
        ),
        const SizedBox(height: 6),
        Text(
          done
              ? AppLocalizations.of(context)!.videoReadyToPublish
              : AppLocalizations.of(context)!.uploadingVideo(pct),
          style: TextStyle(
            color: done ? const Color(0xFF8B5CF6) : Colors.white70,
            fontSize: 12.5,
            fontWeight: done ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class VideoPlaybackPreview extends StatefulWidget {
  final File file;

  const VideoPlaybackPreview({super.key, required this.file});

  @override
  State<VideoPlaybackPreview> createState() => _VideoPlaybackPreviewState();
}

class _VideoPlaybackPreviewState extends State<VideoPlaybackPreview> {
  VideoPlayerController? _controller;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(widget.file);
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Icon(
          Icons.videocam_off_rounded,
          color: Colors.white38,
          size: 48,
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}

// ============================================================
// TELA DE MENSAGENS
// ============================================================

// ============================================================
// PESQUISA
// ============================================================

class KlayKSearchDelegate extends SearchDelegate {
  static const List<String> _categories = [
    'Tudo',
    'Música',
    'Jogos',
    'Esportes',
    'Comédia',
    'Virais',
  ];

  static const List<String> _trending = [
    '#klayk',
    'dança viral',
    'desafio do klay',
    'música nova',
    'como ser criador',
  ];

  static const List<Map<String, String>> _scopes = [
    {'label': 'Tudo', 'value': 'all'},
    {'label': 'Pessoas', 'value': 'user'},
    {'label': 'Vídeos', 'value': 'post'},
    {'label': 'Hashtags', 'value': 'hashtag'},
    {'label': 'Lives', 'value': 'live'},
  ];

  /// Busca inicial pré-preenchida (ex.: pílula de hashtag do vídeo).
  final String? queryHint;

  KlayKSearchDelegate({this.queryHint});

  bool _seedApplied = false;

  /// Aplica a busca inicial uma única vez, preenchendo o campo de pesquisa.
  /// Usa o setter público `query` (que atualiza o TextField do SearchDelegate).
  void _applyQueryHint() {
    final seed = queryHint;
    if (_seedApplied || seed == null || seed.trim().isEmpty) return;
    _seedApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (query.trim().isEmpty) query = seed;
    });
  }

  final ValueNotifier<String> _scope = ValueNotifier<String>('all');
  final ValueNotifier<int> _homeTick = ValueNotifier<int>(0);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          if (query.isEmpty) {
            close(context, null);
          } else {
            query = '';
          }
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildRealResults(context, tabs: true);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    _applyQueryHint();
    if (query.isEmpty) {
      return _buildHome(context);
    }
    return _buildRealResults(context, tabs: true);
  }

  Widget _buildRealResults(BuildContext context, {bool tabs = false}) {
    if (!SupabaseService.instance.isConfigured) {
      final items = _trending
          .where((t) => t.toLowerCase().contains(query.toLowerCase()))
          .toList();
      return _buildResultList(context, items);
    }
    return ValueListenableBuilder<String>(
      valueListenable: _scope,
      builder: (context, scope, _) {
        return Column(
          children: [
            if (tabs)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  children: _scopes.map((s) {
                    final sel = scope == s['value'];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(
                          s['label']!,
                          style: TextStyle(
                            color: sel ? Colors.white : Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        selected: sel,
                        selectedColor: const Color(0xFF8A2BE2),
                        backgroundColor: const Color(0xFF1B1A26),
                        onSelected: (_) {
                          _scope.value = s['value']!;
                          _record();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            Expanded(
              child: FutureBuilder<List<SearchResult>>(
                future: SocialService.instance.search(query, scope: scope),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6),
                      ),
                    );
                  }
                  final results = snapshot.data ?? const <SearchResult>[];
                  if (results.isEmpty) {
                    return const Center(
                      child: Text(
                        'Nada encontrado',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final r = results[i];
                      final IconData typeIcon = switch (r.type) {
                        'user' => Icons.person_rounded,
                        'post' => Icons.play_circle_outline_rounded,
                        'hashtag' => Icons.tag_rounded,
                        'live' => Icons.sensors_rounded,
                        _ => Icons.search,
                      };
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1E1B2E),
                          backgroundImage:
                              r.avatarUrl != null && r.avatarUrl!.isNotEmpty
                              ? NetworkImage(r.avatarUrl!)
                              : null,
                          child: r.type == 'user'
                              ? (r.avatarUrl == null || r.avatarUrl!.isEmpty
                                    ? Icon(
                                        typeIcon,
                                        color: const Color(0xFFB28DFF),
                                        size: 20,
                                      )
                                    : null)
                              : Icon(
                                  typeIcon,
                                  color: const Color(0xFFB28DFF),
                                  size: 20,
                                ),
                        ),
                        title: r.type == 'user'
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      r.title,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (r.isVerified) ...[
                                    const SizedBox(width: 4),
                                    const VerifiedBadge(size: 14),
                                  ],
                                ],
                              )
                            : Text(
                                r.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        subtitle: Text(
                          r.subtitle.isEmpty
                              ? r.type.toUpperCase()
                              : (r.type == 'user' ? '@${r.subtitle}' : r.title),
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: r.type == 'user'
                            ? const Icon(
                                Icons.chevron_right,
                                color: Colors.white24,
                              )
                            : null,
                        onTap: () {
                          _record();
                          switch (r.type) {
                            case 'user':
                              close(context, null);
                              _openAuthor(context, r.id);
                              break;
                            case 'hashtag':
                              // Antes só trocava a query para "#tag" e
                              // refazia a busca. Agora abre a página da
                              // hashtag, que é o que a pessoa esperava ao
                              // tocar no resultado.
                              close(context, null);
                              openHashtag(
                                context,
                                r.subtitle.isNotEmpty ? r.subtitle : r.title,
                              );
                              break;
                            default:
                              // `post` e `live`: abrem o conteúdo. Fechar o
                              // delegate primeiro mantém a busca fora da
                              // pilha, então voltar volta para o feed.
                              close(context, null);
                              openSearchResult(context, r);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _record() {
    if (query.trim().isEmpty) return;
    SocialService.instance.recordSearch(query, resultType: _scope.value);
  }

  void _openAuthor(BuildContext context, String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
    );
  }

  Widget _buildHome(BuildContext context) {
    if (!SupabaseService.instance.isConfigured) {
      return _buildLegacyHome(context);
    }
    return ValueListenableBuilder<int>(
      valueListenable: _homeTick,
      builder: (context, tick, _) {
        return FutureBuilder<
          ({List<String> recents, List<HashtagTrend> trends})
        >(
          future: () async {
            final results = await Future.wait<Object>([
              SocialService.instance.fetchSearchHistory(limit: 10),
              SocialService.instance.trendingHashtags(limit: 15),
            ]);
            return (
              recents: (results[0] as List).cast<String>(),
              trends: (results[1] as List).cast<HashtagTrend>(),
            );
          }(),
          builder: (context, snapshot) {
            final recents = snapshot.data?.recents ?? const <String>[];
            final trends = snapshot.data?.trends ?? const <HashtagTrend>[];
            return ListView(
              children: [
                if (recents.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recentes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_sweep_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                          tooltip: 'Limpar recentes',
                          onPressed: () {
                            SocialService.instance.clearSearchHistory();
                            _homeTick.value++;
                          },
                        ),
                      ],
                    ),
                  ),
                  ...recents.map(
                    (term) => ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.history_rounded,
                        color: Color(0xFFB28DFF),
                      ),
                      title: Text(
                        term,
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        query = term;
                        _record();
                      },
                    ),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    'Categorias',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((category) {
                      return ChoiceChip(
                        label: Text(category),
                        selected: false,
                        onSelected: (_) {
                          query = category;
                          _record();
                        },
                        backgroundColor: const Color(0xFF1E1B2E),
                        selectedColor: const Color(0xFF8A2BE2),
                        labelStyle: const TextStyle(color: Colors.white),
                      );
                    }).toList(),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Em alta',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trends.isNotEmpty)
                  ...trends.map(
                    (t) => ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.trending_up,
                        color: Color(0xFFB28DFF),
                      ),
                      title: Text(
                        '#${t.tag}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: Text(
                        '${t.count}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        query = '#${t.tag}';
                        _scope.value = 'post';
                        _record();
                      },
                    ),
                  )
                else
                  ..._trending.map(
                    (term) => ListTile(
                      leading: const Icon(
                        Icons.trending_up,
                        color: Color(0xFFB28DFF),
                      ),
                      title: Text(
                        term,
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        query = term;
                        _record();
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLegacyHome(BuildContext context) {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Categorias',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((category) {
              return ChoiceChip(
                label: Text(category),
                selected: false,
                onSelected: (_) => query = category,
                backgroundColor: const Color(0xFF1E1B2E),
                selectedColor: const Color(0xFF8A2BE2),
                labelStyle: const TextStyle(color: Colors.white),
              );
            }).toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'Em alta',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ..._trending.map(
          (term) => ListTile(
            leading: const Icon(Icons.trending_up, color: Color(0xFFB28DFF)),
            title: Text(term, style: const TextStyle(color: Colors.white)),
            onTap: () => close(context, term),
          ),
        ),
      ],
    );
  }

  Widget _buildResultList(BuildContext context, List<String> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text('Nada encontrado', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView(
      children: items
          .map(
            (term) => ListTile(
              leading: const Icon(Icons.search, color: Colors.white38),
              title: Text(term, style: const TextStyle(color: Colors.white)),
              onTap: () => close(context, term),
            ),
          )
          .toList(),
    );
  }
}

/// Cache da medição de overflow da legenda do criador.
///
/// Chave: texto + largura arredondada + direção. Costuma existir um único par
/// (texto, largura) por vídeo, então o custo é desprezível.
final Map<String, bool> _captionOverflowCache = <String, bool>{};

/// Quantas linhas a legenda do criador mostra antes de cortar.
const int kCaptionCollapsedLines = 2;

/// Diz se a legenda estoura as [kCaptionCollapsedLines] na largura dada.
///
/// Substitui o `TextPainter` montado a cada build: o `PageView` do feed mantém
/// três páginas vivas e a medição rodava em todas elas a cada reconstrução,
/// mesmo nas páginas que não estavam visíveis.
bool captionOverflows({
  required TextSpan span,
  required double maxWidth,
  required TextDirection textDirection,
}) {
  if (maxWidth <= 0) return false;
  final key =
      '${span.toPlainText()}|$maxWidth.toStringAsFixed(0)|${textDirection.index}';
  final cached = _captionOverflowCache[key];
  if (cached != null) return cached;

  final painter = TextPainter(
    text: span,
    maxLines: kCaptionCollapsedLines,
    textDirection: textDirection,
  )..layout(maxWidth: maxWidth);
  final hidden = painter.didExceedMaxLines;
  painter.dispose();

  // Teto curto: com rolagem infinita o texto muda sempre, e o cache não pode
  // crescer sem limite.
  if (_captionOverflowCache.length > 128) _captionOverflowCache.clear();
  _captionOverflowCache[key] = hidden;
  return hidden;
}
