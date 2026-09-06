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

import 'models/ad_models.dart';
import 'models/klayk_live_models.dart';
import 'models/post_models.dart';
import 'models/user_profile.dart';
import 'services/account_service.dart';
import 'services/ads_service.dart';
import 'services/experience_settings.dart';
import 'screens/app_gate.dart';
import 'screens/auth_screen.dart';
import 'screens/live_room_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/games/game_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/user_profile_screen.dart';
import 'screens/profile/video_preview_screen.dart';
import 'screens/live_games_screen.dart';
import 'screens/start_live_screen.dart';
import 'screens/communities/communities_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/audio_rooms_screen.dart';
import 'screens/events_screen.dart';
import 'screens/moments_screen.dart';
import 'screens/rising_creators_screen.dart';import 'widgets/live_premium_bubble.dart';
import 'widgets/reward_floating_button.dart';
import 'widgets/verified_badge.dart';
import 'widgets/content_actions.dart';
import 'widgets/live_hub_components.dart';
import 'services/app_config.dart';
import 'services/content_service.dart';
import 'services/drafts_service.dart';
import 'services/message_service.dart';
import 'services/profile_service.dart';
import 'services/social_service.dart';
import 'services/storage_upload.dart';
import 'services/supabase_service.dart';
import 'services/guardian_service.dart';
import 'services/live_kit_service.dart';
import 'theme/klayk_theme.dart';
import 'design/klayk_design.dart';
import 'widgets/klayk_ux.dart';
import 'widgets/ad_widgets.dart';
import 'widgets/ad_spot.dart';

/// A cada N vídeos, um anúncio aprovado entra no feed (intercalação
/// transparente com badge ANÚNCIO). Não afeta a lógica de vídeo existente.
const int kAdsFeedEveryN = 5;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  try {
    await SupabaseService.instance.ensureReady();
  } catch (_) {
    // Sem Supabase configurado (--dart-define ausente), o app segue em modo
    // demo — nada aqui deve impedir a execução normal.
  }

  runApp(const KlayKApp());
}

// ============================================================
// APP
// ============================================================

class KlayKApp extends StatelessWidget {
  const KlayKApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ExperienceSettings.instance.prefs,
      builder: (context, child) {
        final reduceMotion =
            ExperienceSettings.instance.reduceAnimations;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'KLAY K',
          theme: KlaykTheme.dark(reduceMotion: reduceMotion),
          routes: {
            '/login': (_) => const AuthScreen(),
            '/live/start': (_) => const StartLiveScreen(),
          },
          home: AppGate(homeBuilder: () => const MainScreen()),
        );
      },
    );
  }
}

// ============================================================
// CONTROLE DE ABA GLOBAL
// ============================================================

final ValueNotifier<int> kNavIndex = ValueNotifier<int>(0);

// ============================================================
// MODELOS
// ============================================================

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
  });
}

class KlayKVideo {
  final String id;
  final String? authorId;
  final String videoUrl;
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
Future<List<KlayKVideo>> _resolvePostUrls(List<FeedPost> posts) async {
  final out = <KlayKVideo>[];
  if (posts.isEmpty) return out;
  const batch = 5;
  for (var i = 0; i < posts.length; i += batch) {
    final end = i + batch > posts.length ? posts.length : i + batch;
    final chunk = posts.sublist(i, end);
    final urls = await Future.wait(chunk.map((post) async {
      try {
        return await ContentService.instance.resolveVideoUrl(post);
      } catch (_) {
        return post.videoUrl;
      }
    }));
    for (var j = 0; j < urls.length; j++) {
      out.add(_videoFromPostResolved(chunk[j], urls[j]));
    }
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
  const reasons = [
    'Conteúdo inadequado ou ofensivo',
    'Assédio ou bullying',
    'Spam ou publicidade enganosa',
    'Desinformação ou fake news',
    'Violência ou discurso de ódio',
    'Viola meus direitos (autoral, privacidade)',
    'Outro',
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
            'Denunciar $targetLabel',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Escolha um motivo. A moderação do KLAY K vai analisar sua denúncia.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
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
      title: Text('Denunciar $targetLabel',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Motivo: $reason',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: detailsCtrl,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Conte mais detalhes (opcional)',
              hintStyle: TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Color(0xFF17151F),
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, detailsCtrl.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE4183C)),
          child: const Text('Enviar denúncia'),
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
    messenger.showSnackBar(const SnackBar(
      content: Text('Denúncia enviada. Obrigado por ajudar o KLAY K!'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('Erro ao enviar denúncia: $e'),
    ));
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
  late List<Widget> _screens; // setado em initState (estável) com tabActive atual.

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
      final settings =
          await AccountService.instance.fetchSettings().catchError((_) => const AccountSettings());
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
        const GameScreen(),
        const UploadScreen(),
        const RealMessagesScreen(),
        const ProfileScreen(),
      ];

  Future<void> _refreshUnread() async {
    if (!SupabaseService.instance.isConfigured) return;
    final c = await MessageService.instance.unreadCount().catchError((_) => 0);
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
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          RewardFloatingButton(visibleTab: _currentIndex, paused: _rewardPaused),
          const LivePremiumBubble(),
          const MaintenanceLayer(),
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
                    emergency ? 'KLAY K em emergência' : 'KLAY K em manutenção',
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
                        ? 'Estamos por aqui em breve. Obrigado pela paciência.'
                        : w.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'modo ${w.mode}${w.isGlobal ? ' · escopo global' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _tick,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
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
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.construction_rounded,
                  color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${w.isGlobal ? 'KLAY K' : w.feature} em manutenção'
                  '${w.message.isEmpty ? '.' : ': ${w.message}'}',
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
      backgroundColor: const Color(0xFF1C1C26),
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
              const Text(
                'Criar no KLAY K',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              _publishTile(ctx, Icons.video_library_rounded, 'Vídeo curto',
                  onTap: () {
                Navigator.of(ctx).pop();
                onTap(2);
              }),
              _publishTile(ctx, Icons.sensors_rounded, 'Live ao vivo',
                  iconColor: const Color(0xFFFF2E4D), onTap: () {
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
              }),
              _publishTile(ctx, Icons.mic_rounded, 'Áudio',
                  iconColor: const Color(0xFFAB47BC), onTap: () {
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
              }),
              _publishTile(ctx, Icons.group_rounded, 'Amigos',
                  iconColor: const Color(0xFF00BFA5), onTap: () {
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
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _liveNotConfigured(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Lives reais exigem Supabase + LiveKit configurados (--dart-define).',
        ),
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(
            color: Color(0xFF252525),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_home.png',
                  label: 'Início',
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_jogo.png',
                  label: 'Jogo',
                  selected: currentIndex == 1,
                  onTap: () => onTap(1),
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
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFA955FF),
                              Color(0xFF7C3AED),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.32),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6)
                                  .withValues(
                                    alpha: currentIndex == 2 ? 0.95 : 0.6,
                                  ),
                              blurRadius: currentIndex == 2 ? 22 : 14,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: const Color(0xFF5B21B6)
                                  .withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 28,
                          shadows: [
                            Shadow(
                              color: Colors.black38,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      const SizedBox(height: 11),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_mensagens.png',
                  label: 'Mensagens',
                  selected: currentIndex == 3,
                  badge: messageUnread,
                  onTap: () => onTap(3),
                ),
              ),
              Expanded(
                child: _NavigationItem(
                  asset: 'assets/ic_perfil_aba.png',
                  label: 'Perfil',
                  selected: currentIndex == 4,
                  onTap: () => onTap(4),
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
  final String asset;
  final String label;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
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
                asset: asset,
                size: 24,
                tint: selected ? Colors.white : const Color(0xFF8E8E8E),
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
              if (selected)
                Positioned(
                  right: -8,
                  top: -4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF8B5CF6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.6),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.normal,
                shadows: selected
                    ? [
                        Shadow(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.45),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
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

  /// Notifica o [RewardFloatingButton] quando nenhum vídeo do feed está de
  /// fato sendo assistido (o ciclo de recompensa pausa nesses casos).
  final ValueNotifier<bool>? rewardPaused;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final PageController _pageController;

  int _currentPage = 0;
  int _feedTab = 0;

  List<KlayKVideo> _videos = [];
  bool _loading = true;
  bool _feedError = false;

  List<AdCreative> _feedAds = [];
  final List<String> _countedAdImpressions = [];

  int _notifUnread = 0;
  RealtimeChannel? _notifChannel;
  StreamSubscription<AuthState>? _authSub;

  List<KlayKVideo> get videos => _videos;

  /// Feed combinado: vídeos intercalados com anúncios aprovados.
  /// Um anúncio entra a cada [kAdsFeedEveryN] vídeos. Só entram itens
  /// APPROVED vindos da RPC pública (nunca decididos pelo cliente).
  List<Object> get feedItems {
    if (_feedAds.isEmpty) return List<Object>.of(videos);
    final items = <Object>[];
    for (var i = 0; i < videos.length; i++) {
      items.add(videos[i]);
      final adSlot = i % kAdsFeedEveryN == kAdsFeedEveryN - 1;
      if (adSlot) {
        final ad = _feedAds[i ~/ kAdsFeedEveryN % _feedAds.length];
        items.add(ad);
      }
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadFeed();
    _loadFeedAds();
    _initNotifications();
    _updateRewardPause();
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabActive != widget.tabActive && mounted) {
      // Rebuild força o VideoItem ativo a pausar (ou retomar) o playback.
      setState(() {});
    }
    if (oldWidget.tabActive != widget.tabActive) {
      _updateRewardPause();
    }
  }

  void _initNotifications() {
    if (!SupabaseService.instance.isConfigured) return;
    _notifBadgeRefresh();
    try {
      _notifChannel ??=
          SupabaseService.instance.subscribeToNotifications((_) {
        _notifBadgeRefresh();
      });
    } catch (_) {
      // Sem sessão ainda: entra quando o usuário fizer login.
    }
    _authSub = SupabaseService.instance.client.auth.onAuthStateChange.listen(
      (authState) {
        final event = authState.event;
        final session = authState.session;
        if (event == AuthChangeEvent.signedIn && session != null) {
          _notifBadgeRefresh();
          try {
            _notifChannel ??=
                SupabaseService.instance.subscribeToNotifications((_) {
              _notifBadgeRefresh();
            });
          } catch (_) {}
        } else if (event == AuthChangeEvent.signedOut) {
          final ch = _notifChannel;
          _notifChannel = null;
          if (ch != null) SupabaseService.instance.removeChannel(ch);
          if (mounted) setState(() => _notifUnread = 0);
        }
      },
    );
  }

  Future<void> _notifBadgeRefresh() async {
    final c = await ContentService.instance.unreadNotificationCount();
    if (mounted && c != _notifUnread) {
      setState(() => _notifUnread = c);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    final ch = _notifChannel;
    if (ch != null) {
      SupabaseService.instance.removeChannel(ch);
    }
    _pageController.dispose();
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

    setState(() {
      _loading = true;
      _feedError = false;
    });

    try {
      final posts = await ContentService.instance.fetchFeed();
      final loaded = await _resolvePostUrls(posts);
      if (mounted) {
        setState(() {
          _videos = loaded;
          _loading = false;
          _feedError = false;
        });
      }
      _loadFeedAds();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _feedError = true;
        });
      }
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
    try {
      final ads = await AdsService.instance.fetchApprovedAds(limit: 15);
      if (!mounted) return;
      setState(() {
        _feedAds = List.of(
          ads.where((a) => a.isApproved).take(kAdMaxPerSession),
        );
      });
    } catch (_) {
      // Anúncios são opcionais no feed; falha silenciosa mantém o feed vídeo.
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

  /// Mantém o sinal de pausa da recompensa sincronizado: o ciclo só conta
  /// tempo quando o Feed (aba ativa) está na sub-aba que reproduz vídeos.
  void _updateRewardPause() {
    final notifier = widget.rewardPaused;
    if (notifier == null) return;
    final watching = widget.tabActive &&
        (_feedTab == 0 || _feedTab == 1 || _feedTab == 3);
    if (notifier.value != !watching) {
      notifier.value = !watching;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final showFeed = _feedTab == 0 || _feedTab == 1 || _feedTab == 3;

    return Scaffold(
      backgroundColor: kc(context).bg,
      body: Stack(
        children: [
          if (showFeed)
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: feedItems.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
                _trackAdImpression(index);
              },
              itemBuilder: (context, index) {
                final item = feedItems[index];
                if (item is AdCreative) {
                  return RepaintBoundary(
                    key: ValueKey('rp-ad-${item.id}'),
                    child: _FeedAdItem(
                      key: ValueKey('ad-${item.id}'),
                      ad: item,
                      isActive:
                          index == _currentPage && widget.tabActive,
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
                    isActive: index == _currentPage && widget.tabActive,
                    shouldPreload: index == _currentPage ||
                        index == _currentPage + 1,
                    onDeleted: () => _removePost(video.id),
                    onEnded:
                        index < feedItems.length - 1
                            ? () => _autoAdvance(index)
                            : null,
                  ),
                );
              },
            ),
          if (showFeed && _loading && videos.isEmpty)
            const _FeedLoadingState(),
          if (showFeed && _feedError && videos.isEmpty)
            KlaykErrorState(
              onRetry: _loadFeed,
              title: 'Não foi possível carregar os vídeos.',
              message: 'Verifique sua conexão e tente novamente.',
            ),
          if (showFeed &&
              !_loading &&
              !_feedError &&
              videos.isEmpty &&
              feedItems.isEmpty)
            _FeedEmptyState(onRetry: _loadFeed),
          if (_feedTab == _FeedTopBar.liveIndex)
            Positioned.fill(
              child: _LiveArea(
                topPadding: topPadding,
                onWatch: _openLive,
              ),
            ),
          if (_feedTab == 4)
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
                showSearch(
                  context: context,
                  delegate: KlayKSearchDelegate(),
                );
              },
              onNotifications: _openNotifications,
              notificationUnread: _notifUnread,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _notifBadgeRefresh();
  }

  Future<void> _openCommunities() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CommunitiesScreen()),
    );
  }

  Future<void> _openDiscover() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DiscoverScreen()),
    );
  }

  Future<void> _openFriends() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  Future<void> _openEvents() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EventsScreen()),
    );
  }

  Future<void> _openAudioRooms() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AudioRoomsScreen()),
    );
  }

  Future<void> _openMoments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MomentsScreen()),
    );
  }

  Future<void> _openRisingCreators() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RisingCreatorsScreen()),
    );
  }

  Future<bool> _openLive(KlayKLive live) async {
    // Lives reais são abertas via `_openRealLive` (LiveRoomScreen/LiveKit).
    // `onWatch` cobre apenas o catálogo de demonstração (`kAllLives`).
    final ended = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _LiveViewerScreen(live: live),
      ),
    );
    return ended ?? false;
  }
}

// ============================================================
// ESTADOS DO FEED (loading / vazio) — visual preto/grafite + roxo neon
// ============================================================

/// Tela de carregamento do feed: fundo preto/grafite, monograma KLAY K com
/// brilho roxo neon discreto e indicador leve. NUNCA mostra vídeo fake (§3).
class _FeedLoadingState extends StatelessWidget {
  const _FeedLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0B11),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF14101E),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/klay_k_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        'k',
                        style: TextStyle(
                          fontSize: 40,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'KLAY K',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(color: Color(0xFFA78BFA), blurRadius: 20),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const KlaykLoader(label: 'Carregando seu feed…'),
            ],
          ),
        ),
      ),
    );
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
      title: 'Nenhum vídeo disponível',
      message: offline
          ? 'Conecte-se com sua conta para ver os vídeos do KLAY K.'
          : 'Os vídeos de quem você acompanha aparecerão aqui.',
      actionLabel: 'Atualizar',
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
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
  final VoidCallback onNotifications;
  final int notificationUnread;

  const _FeedTopBar({
    required this.topPadding,
    required this.feedTab,
    required this.onTabChanged,
    required this.onSearch,
    required this.onNotifications,
    this.notificationUnread = 0,
  });

  static const int liveIndex = 2;

  static const List<String> _tabs = [
    'Para você',
    'Seguindo',
    'Live',
    'Loja',
    'Destaques',
    'Descobrir',
    'Comunidades',
    'Amizades',
    'Eventos',
    'Áudio',
    'Momentos',
    'Em ascensão',
  ];

  /// Índice da aba que abre a exploração de Descobrir/Tendências em tela cheia.
  static const int discoverIndex = 5;

  /// Índice da aba que abre a exploração de Comunidades em tela cheia.
  static const int communitiesIndex = 6;

  /// Índice da aba que abre o hub de Amizades em tela cheia.
  static const int friendsIndex = 7;

  /// Índice da aba que abre a agenda/descoberta de Eventos em tela cheia.
  static const int eventsIndex = 8;

  /// Índice da aba que abre as Salas de Voz (Áudio) em tela cheia.
  static const int audioIndex = 9;

  /// Índice da aba que abre os Momentos (efémeros) em tela cheia.
  static const int momentsIndex = 10;

  /// Índice da aba que abre os Criadores em Ascensão em tela cheia.
  static const int risingIndex = 11;

  @override
  Widget build(BuildContext context) {
    final isLive = feedTab == liveIndex;
    final colors = kc(context);

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
          // ---- Linha do topo: identidade + LIVE + perfil + notificações + pesquisa ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Logo / nome KLAY K (flexível para não estourar em telas pequenas)
                Flexible(
                  child: _buildLogo(feedTab, onTabChanged, isLive),
                ),
                const SizedBox(width: 8),
                // Acesso à LIVE (aba de lives)
                GestureDetector(
                  onTap: () => onTabChanged(liveIndex),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isLive
                          ? const Color(0xFFFF2E4D).withValues(alpha: 0.22)
                          : colors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isLive
                            ? const Color(0xFFFF2E4D)
                            : colors.border.withValues(alpha: 0.6),
                        width: 1,
                      ),
                      boxShadow: isLive
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF2E4D)
                                    .withValues(alpha: 0.4),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.circle,
                          color: Color(0xFFFF2E4D),
                          size: 9,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (isLive) const SizedBox(width: 1),
                        if (isLive)
                          const Icon(
                            Icons.live_tv_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Perfil (conta)
                GestureDetector(
                  onTap: () => kNavIndex.value = 4,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surface.withValues(alpha: 0.7),
                      border:
                          Border.all(color: colors.border.withValues(alpha: 0.6)),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Notificações
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    KlayKIconButton(
                      icon: Icons.notifications_rounded,
                      onTap: onNotifications,
                      size: 34,
                    ),
                    if (notificationUnread > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: KlayKBadge(count: notificationUnread),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                // Pesquisa
                KlayKIconButton(
                  icon: Icons.search_rounded,
                  onTap: onSearch,
                  size: 34,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- Navegação / categorias ----
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: List.generate(
                _tabs.length,
                (index) {
                  final selected = feedTab == index;
                  return KlayKChip(
                    label: _tabs[index],
                    selected: selected,
                    onTap: () => onTabChanged(index),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// Wordmark "KLAY K" com gradiente roxo + ícone oficial do app.
  Widget _buildLogo(int current, ValueChanged<int> onTab, bool isLive) {
    return GestureDetector(
      onTap: () => onTab(0),
      behavior: HitTestBehavior.opaque,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/klay_k_icon.png',
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 24,
                  height: 24,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFC084F0),
                  Color(0xFF8B5CF6),
                  Color(0xFF6D28D9),
                ],
              ).createShader(bounds),
              child: const Text(
                'KLAY K',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  height: 1,
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
// VIDEO ITEM
// ============================================================

/// Página de anúncio fullscreen do feed. Rende um anúncio aprovado de forma
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
    final advertiser =
        ad.advertiserName.isNotEmpty ? ad.advertiserName : 'Anunciante';
    return Semantics(
      container: true,
      label: 'Anúncio de $advertiser${ad.title.isEmpty ? '' : ' · ${ad.title}'}',
      child: Container(
        color: kc(context).bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
          if (ad.mediaUrl.isNotEmpty)
            Image.network(
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
                              ? 'Anunciante'
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
                        const Text(
                          'Anúncio verificado',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ] else
                        const Text(
                          'Empresa anunciante',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11),
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

    _heartAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _heartController,
        curve: Curves.elasticOut,
      ),
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
  /// retomada de vídeos que já terminaram.
  void _onVideoTick() {
    final controller = _controller;
    if (!mounted || controller == null) return;

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
    if (_controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    if (_controller!.value.isPlaying) {
      _controller!.pause();

      setState(() {
        _showPlayIcon = true;
      });

      _playIconTimer?.cancel();

      _playIconTimer = Timer(
        const Duration(seconds: 1),
        () {
          if (mounted) {
            setState(() {
              _showPlayIcon = false;
            });
          }
        },
      );
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
      _heartTimer = Timer(
        const Duration(milliseconds: 700),
        () {
          if (mounted) {
            setState(() {
              _showHeart = false;
            });
          }
        },
      );
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
      _showSnack('Não foi possível atualizar a curtida');
    }
  }

  void _toggleHashtags() {
    setState(() {
      _hashtagsExpanded = !_hashtagsExpanded;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
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
      _showSnack('Vídeo atualizado.');
    } else {
      _showSnack('Não foi possível atualizar agora. Tente de novo.');
    }
  }

  Future<void> _deleteVideo() async {
    final go = await confirmDeleteDialog(
      context,
      title: 'Apagar vídeo?',
      message:
          'O vídeo, a capa, curtidas e comentários serão removidos '
          'permanentemente. Essa ação não pode ser desfeita.',
    );
    if (!go || !mounted) return;
    try {
      await ContentService.instance.deletePost(widget.video.id);
      if (!mounted) return;
      widget.onDeleted?.call();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Não foi possível apagar o vídeo.');
    }
  }

  Future<void> _openCreatorProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
            userId: widget.video.authorId ?? ''),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openAudioPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioScreen(video: widget.video),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openRelatedSearch() {
    if (widget.video.hashtags.isEmpty) return;
    final term = '#${widget.video.hashtags.first}';
    showSearch(
      context: context,
      delegate: KlayKSearchDelegate(queryHint: term),
    );
  }

  String get _shareLink =>
      'https://klayk.app/v/${widget.video.id}';

  Future<void> _showShareMenu() async {
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
    if (!context.mounted) return;

    switch (action) {
      case 'friend':
        final friend = await _pickFriend();
        if (friend == null) return;
        if (!SupabaseService.instance.isConfigured) return;
        await _sendVideoToFriend(friend);
      case 'messages':
        kNavIndex.value = 3;
        setState(() => widget.video.shares++);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _shareLink));
        _showSnack('Link copiado');
      case 'whatsapp':
        await _launchShareUrl(
          'https://wa.me/?text=${Uri.encodeComponent('Olha esse vídeo no KLAY K! $_shareLink')}',
          'WhatsApp',
        );
      case 'instagram':
        await _launchShareUrl(
          'https://www.instagram.com/',
          'Instagram',
        );
      case 'facebook':
        await _launchShareUrl(
          'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_shareLink)}',
          'Facebook',
        );
      case 'system':
        await Share.share(
          'Olha esse vídeo no KLAY K! 🎬\n$_shareLink\n${widget.video.videoUrl}',
        );
        setState(() => widget.video.shares++);
      case 'report':
        if (!mounted) return;
        await showReportDialog(
          context,
          targetId: widget.video.id,
          targetType: 'post',
          targetLabel: 'publicação',
        );
    }
  }

  Future<void> _launchShareUrl(String url, String label) async {
    final uri = Uri.parse(url);
    final available = await canLaunchUrl(uri);
    if (!available) {
      _showSnack('$label não disponível neste dispositivo');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      setState(() => widget.video.shares++);
    } else {
      _showSnack('Não foi possível abrir o $label');
    }
  }

  /// Seleciona um amigo real (backend) para receber o vídeo. Nunca usa lista
  /// falsa: sem amigos ou sem backend, mostra estado honesto (vazio/erro).
  Future<UserProfile?> _pickFriend() async {
    if (!SupabaseService.instance.isConfigured) {
      _showSnack('Conecte-se para enviar vídeos aos amigos.');
      return null;
    }
    List<UserProfile> friends;
    try {
      friends = await ProfileService.instance.fetchMutualFriends();
    } catch (_) {
      _showSnack('Não foi possível carregar seus amigos agora.');
      return null;
    }
    if (!mounted) return null;
    if (friends.isEmpty) {
      _showSnack('Você ainda não tem amigos para receber vídeos.');
      return null;
    }
    return showDialog<UserProfile>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C26),
        title: const Text(
          'Enviar para amigo',
          style: TextStyle(
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
              final name = f.displayName ?? f.username ?? 'Amigo';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF8B5CF6)
                      .withValues(alpha: 0.35),
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
                            color: Colors.white54, fontSize: 12),
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
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  /// Envia o vídeo para um amigo real via DM (conversa real no backend).
  Future<void> _sendVideoToFriend(UserProfile friend) async {
    try {
      final conv = await MessageService.instance
          .getOrCreateConversation(friend.id);
      final link = '🎬 ${widget.video.displayName}\n$_shareLink\n'
          '${widget.video.videoUrl}';
      await MessageService.instance.sendMessage(conv.id, link);
      if (!mounted) return;
      kNavIndex.value = 3;
      _showSnack('Vídeo enviado para ${friend.displayName ?? friend.username ?? 'amigo'}');
      setState(() => widget.video.shares++);
    } catch (_) {
      _showSnack('Não foi possível enviar o vídeo agora.');
    }
  }

  Widget _buildShareSheet() {
    return const SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Text(
              'Compartilhar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _ShareOption(
            icon: Icons.person_add_alt_1_rounded,
            color: Color(0xFF8B5CF6),
            label: 'Enviar para amigo',
            value: 'friend',
          ),
          _ShareOption(
            icon: Icons.chat_bubble_rounded,
            color: Color(0xFFFF4D6A),
            label: 'Mensagens',
            value: 'messages',
          ),
          _ShareOption(
            icon: Icons.link_rounded,
            color: Color(0xFFFFA53D),
            label: 'Copiar link',
            value: 'copy',
          ),
          _ShareOption(
            icon: Icons.ios_share_rounded,
            color: Color(0xFF22C55E),
            label: 'Compartilhar para outros aplicativos',
            value: 'system',
          ),
          _ShareOption(
            icon: Icons.chat_rounded,
            color: Color(0xFF25D366),
            label: 'WhatsApp',
            value: 'whatsapp',
          ),
          _ShareOption(
            icon: Icons.camera_alt_rounded,
            color: Color(0xFFE1306C),
            label: 'Instagram',
            value: 'instagram',
          ),
          _ShareOption(
            icon: Icons.thumb_up_alt_rounded,
            color: Color(0xFF1877F2),
            label: 'Facebook',
            value: 'facebook',
          ),
          _ShareOption(
            icon: Icons.more_horiz_rounded,
            color: Colors.white,
            label: 'Mais opções do Android',
            value: 'system',
          ),
          SizedBox(height: 4),
          Divider(color: Color(0xFF2A2A2A), height: 20),
          _ShareOption(
            icon: Icons.flag_rounded,
            color: Color(0xFFE4183C),
            label: 'Denunciar publicação',
            value: 'report',
          ),
          SizedBox(height: 10),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text(
                'Salvar',
                style: TextStyle(
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
                  ? 'Remover dos favoritos'
                  : 'Adicionar aos favoritos',
              value: 'favorite',
            ),
            const _ShareOption(
              icon: Icons.download_rounded,
              color: Color(0xFF22C55E),
              label: 'Baixar para o dispositivo',
              value: 'download',
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    switch (action) {
      case 'favorite':
        final wasSaved = widget.video.saved;
        setState(() => widget.video.saved = !widget.video.saved);
        _showSnack(widget.video.saved
            ? 'Adicionado aos favoritos'
            : 'Removido dos favoritos');
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
      _showSnack('Não foi possível atualizar o salvamento');
    }
  }

  Future<void> _downloadToDevice() async {
    if (_downloading) return;

    setState(() => _downloading = true);

    try {
      final response = await http.get(
        Uri.parse(widget.video.videoUrl),
      );

      if (response.statusCode != 200) {
        _showSnack('Não foi possível baixar o vídeo');
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.video.id}.mp4');
      await file.writeAsBytes(response.bodyBytes, flush: true);

      _showSnack('Vídeo baixado com sucesso! 📥');
    } catch (_) {
      _showSnack('Não foi possível baixar o vídeo');
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
            child: _controller != null &&
                    _controller!.value.isInitialized
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
          if (_error)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.white54,
                    size: 48,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Não foi possível carregar o vídeo',
                    style: TextStyle(color: Colors.white70),
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
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 16,
                    ),
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
          Positioned(
            left: 12,
            right: 92,
            bottom: bottomPadding + 110,
            child: _VideoInfo(
              video: widget.video,
              onOpenCreator: _openCreatorProfile,
              hashtagsExpanded: _hashtagsExpanded,
              onToggleHashtags: _toggleHashtags,
            ),
          ),
          Positioned(
            left: 12,
            right: 140,
            bottom: bottomPadding + 74,
            child: _AudioStrip(
              audioName: widget.video.audioName,
              onTap: _openAudioPage,
            ),
          ),
          // Pesquisa relacionada: só aparece com dados reais (hashtags do post).
          if (widget.video.hashtags.isNotEmpty)
            Positioned(
              left: 12,
              right: 140,
              bottom: bottomPadding + 46,
              child: _RelatedSearchStrip(
                query: widget.video.hashtags.first,
                onTap: _openRelatedSearch,
              ),
            ),
          Positioned(
            right: 10,
            bottom: bottomPadding + 90,
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
    return Container(
      color: const Color(0xFF181820),
      child: const Center(
        child: Icon(
          Icons.play_circle_outline,
          color: Colors.white24,
          size: 64,
        ),
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
  String? _replyTo;
  Comment? _editingComment;

  List<Comment> _comments = [];
  bool _loading = false;
  bool get _real =>
      SupabaseService.instance.isConfigured && widget.video.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.video.commentList);
    if (_real) _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final real = await ContentService.instance
          .fetchComments(widget.video.id);
      final mapped = real
          .map((c) => Comment(
                id: c.id,
                username: c.author?.username != null
                    ? '@${c.author!.username}'
                    : 'Usuário',
                text: c.text,
                timestamp: c.createdAt,
                replyTo: c.parentId != null ? 'resposta' : null,
                authorId: c.author?.id,
                avatarUrl: c.author?.avatarUrl,
                edited: c.editedAt != null,
                isVerified: c.author?.isVerified ?? false,
                mine: c.userId != null &&
                    c.userId ==
                        SupabaseService.instance.client.auth.currentUser?.id,
              ))
          .toList();
      if (mounted) {
        setState(() {
          _comments = mapped;
          widget.video.commentList = mapped;
          widget.video.comments = mapped.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() => _replyTo = null);
    _focusNode.unfocus();

    if (_real) {
      try {
        await ContentService.instance.addComment(widget.video.id, text);
        await _loadComments();
        if (mounted) {
          setState(() {
            widget.video.comments = _comments.length;
          });
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível enviar o comentário'),
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
          replyTo: _replyTo,
          mine: true,
        ),
      ];
      widget.video.commentList = _comments;
      widget.video.comments++;
    });
  }

  void _deleteComment(Comment comment, {required bool real}) {
    if (real) {
      ContentService.instance.deleteComment(comment.id).then((_) {
        _loadComments();
      }).catchError((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível excluir o comentário'),
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
    setState(() => _replyTo = comment.username);
    _focusNode.requestFocus();
  }

  void _startEditComment(Comment comment) {
    setState(() {
      _editingComment = comment;
      _replyTo = null;
      _controller.text = comment.text;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
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
          const SnackBar(
            content: Text('Comentário copiado.'),
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
      final applied = await ContentService.instance.editComment(target.id, text);
      if (!mounted) return;
      if (!applied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Edição indisponível no momento. Tente mais tarde.'),
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
      targetLabel: 'comentário de ${comment.username}',
    );
  }

  void _openCommentProfile(Comment comment) {
    final id = comment.authorId;
    if (id == null || id.isEmpty || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: id),
      ),
    );
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
              const Text(
                'Comentários',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
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
                  ? const KlaykEmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Seja o primeiro a comentar',
                      message: 'Compartilhe sua opinião sobre este vídeo.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        return _CommentTile(
                          comment: _comments[index],
                          onReply: () => _startReply(_comments[index]),
                          onEdit: () => _startEditComment(_comments[index]),
                          onCopy: () => _copyComment(_comments[index]),
                          onDelete: () => _deleteComment(
                            _comments[index],
                            real: _real,
                          ),
                          onToggle: () {
                            setState(() {
                              final c = _comments[index];
                              c.liked = !c.liked;
                              c.likes += c.liked ? 1 : -1;
                              if (c.likes < 0) c.likes = 0;
                            });
                          },
                          onReport: () =>
                              _reportComment(_comments[index]),
                          onProfile: () =>
                              _openCommentProfile(_comments[index]),
                        );
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            border: Border(
              top: BorderSide(color: Color(0xFF2A2A2A)),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.sentiment_satisfied_alt,
                color: Colors.white38,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_replyTo != null) ...[
                      InkWell(
                        onTap: () => setState(() => _replyTo = null),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            'Respondendo a $_replyTo ✕',
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
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 2),
                          child: Text(
                            'Editando comentário ✕',
                            style: TextStyle(
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
                            ? 'Edite seu comentário...'
                            : 'Adicionar comentário...',
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
                onTap: _editingComment != null ? _applyCommentEdit : _addComment,
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
              backgroundColor: const Color(0xFF8B5CF6)
                  .withValues(alpha: 0.4),
              backgroundImage: (comment.avatarUrl != null &&
                      comment.avatarUrl!.isNotEmpty)
                  ? NetworkImage(comment.avatarUrl!)
                  : null,
              child: (comment.avatarUrl == null ||
                      comment.avatarUrl!.isEmpty)
                  ? const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 20,
                    )
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
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Você',
                          style: TextStyle(
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
                      'Respondendo a ${comment.replyTo}',
                      style: TextStyle(
                        color: const Color(0xFF8B5CF6)
                            .withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                if (comment.edited)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Editada',
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
                      child: const Text(
                        'Responder',
                        style: TextStyle(
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
                        child: const Text(
                          'Copiar',
                          style: TextStyle(
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
                        child: const Text(
                          'Editar',
                          style: TextStyle(
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
                              title: const Text(
                                'Excluir comentário',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              content: const Text(
                                'Tem certeza que deseja excluir este comentário?',
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text(
                                    'Cancelar',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text(
                                    'Excluir',
                                    style: TextStyle(
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
                        child: const Text(
                          'Excluir',
                          style: TextStyle(
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
                        child: const Text(
                          'Denunciar',
                          style: TextStyle(
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

  const _RotatingDisc({
    required this.controller,
    required this.size,
  });

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
        ),
        const SizedBox(height: 16),
        _ActionIcon(
          icon: video.liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconWidget: _StyledAssetIcon(
            asset: 'assets/ic_curtir.png',
            size: 36,
            tint: video.liked ? const Color(0xFFFF4D6A) : Colors.white,
            shadow: true,
          ),
          label: _formatNumber(video.likes),
          active: video.liked,
          activeColor: const Color(0xFFFF4D6A),
          semanticLabel: 'Curtir',
          onTap: onLike,
        ),
        const SizedBox(height: 16),
        _ActionIcon(
          icon: Icons.chat_bubble_rounded,
          iconWidget: const _StyledAssetIcon(
            asset: 'assets/ic_comentario.png',
            size: 38,
            shadow: true,
          ),
          label: _formatNumber(video.comments),
          semanticLabel: 'Comentários',
          onTap: onComment,
        ),
        const SizedBox(height: 16),
        _ActionIcon(
          icon: Icons.reply_rounded,
          iconWidget: const _StyledAssetIcon(
            asset: 'assets/ic_compartilhar.png',
            size: 36,
            shadow: true,
          ),
          label: _formatNumber(video.shares),
          semanticLabel: 'Compartilhar',
          onTap: onShare,
        ),
        const SizedBox(height: 16),
        _ActionIcon(
          icon: video.saved
              ? Icons.verified_rounded
              : Icons.file_download_rounded,
          iconWidget: downloading
              ? const SizedBox(
                  width: 38,
                  height: 38,
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                )
              : _StyledAssetIcon(
                  asset: 'assets/ic_download.png',
                  size: 36,
                  tint: video.saved
                      ? const Color(0xFF8B5CF6)
                      : Colors.white,
                  shadow: true,
                ),
          label: video.saved ? 'Salvo' : '',
          semanticLabel: 'Salvar',
          onTap: onSave,
        ),
        const SizedBox(height: 18),
        Semantics(
          label: 'Música',
          button: true,
          child: GestureDetector(
            onTap: onAudio,
            child: Container(
              width: 46,
              height: 46,
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
              child: _RotatingDisc(controller: controller, size: 26),
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

  const _CreatorAvatar({
    required this.avatarUrl,
    required this.following,
    required this.onTap,
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
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: following
                      ? const Color(0xFF8B5CF6)
                      : Colors.white,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6)
                        .withValues(alpha: following ? 0.5 : 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -3,
              right: -3,
              child: Container(
                width: 22,
                height: 22,
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
                      ? const Color(0xFFFF4D6A)
                      : Colors.black,
                  size: 14,
                  weight: 800,
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
    _scale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _scale,
              builder: (_, child) => Transform.scale(
                scale: _scale.value,
                child: child,
              ),
              child: widget.iconWidget ??
                  Icon(
                    widget.icon,
                    color: widget.active
                        ? widget.activeColor
                        : Colors.white,
                    size: 34,
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
    );
  }
}

// ============================================================
// INFORMAÇÕES DO CRIADOR
// ============================================================

class _VideoInfo extends StatelessWidget {
  final KlayKVideo video;
  final VoidCallback onOpenCreator;
  final bool hashtagsExpanded;
  final VoidCallback onToggleHashtags;

  const _VideoInfo({
    required this.video,
    required this.onOpenCreator,
    required this.hashtagsExpanded,
    required this.onToggleHashtags,
  });

  bool get _needsMore =>
      video.description.length > 52 || video.hashtags.length > 3;

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final accent = colors.primarySoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onOpenCreator,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  video.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                      Shadow(
                          color: Color(0x998B5CF6),
                          blurRadius: 16,
                          offset: Offset(0, 0)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (video.isVerified)
                const VerifiedBadge(size: 18),
              const SizedBox(width: 5),
              const Text(
                '>',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  shadows: _kLabelShadow,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                video.description,
                maxLines: hashtagsExpanded ? null : 2,
                overflow: hashtagsExpanded
                    ? null
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.3,
                  shadows: _kLabelShadow,
                ),
              ),
              if (video.hashtags.isNotEmpty) ...[
                const SizedBox(height: 6),
                if (hashtagsExpanded)
                  Wrap(
                    spacing: 9,
                    runSpacing: 3,
                    children: video.hashtags
                        .map(
                          (t) => Text(
                            '#$t',
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              shadows: _kLabelShadow,
                            ),
                          ),
                        )
                        .toList(),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          video.hashtags
                              .take(3)
                              .map((t) => '#$t')
                              .join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            shadows: _kLabelShadow,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
              if (_needsMore)
                GestureDetector(
                  onTap: onToggleHashtags,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hashtagsExpanded ? 'Menos' : 'Mais',
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            shadows: _kLabelShadow,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          hashtagsExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: accent,
                          size: 16,
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
  }
}

// ============================================================
// FAIXA DE ÁUDIO
// ============================================================

class _AudioStrip extends StatelessWidget {
  final String audioName;
  final VoidCallback onTap;

  const _AudioStrip({
    required this.audioName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.music_note_rounded,
            color: Colors.white,
            size: 16,
            shadows: _kLabelShadow,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              audioName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
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
// PESQUISA RELACIONADA (barra discreta na base do vídeo)
// ============================================================

/// Pílula "🔎 Pesquisar: <termo relacionado>" na base do vídeo. Só é
/// criada quando há dados reais (hashtag do post) — nunca inventa termo.
class _RelatedSearchStrip extends StatelessWidget {
  final String query;
  final VoidCallback onTap;

  const _RelatedSearchStrip({required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = kc(context).primarySoft;
    return Semantics(
      label: 'Pesquisar $query',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_rounded,
                color: Colors.white,
                size: 16,
                shadows: _kLabelShadow,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Pesquisar: $query',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: _kLabelShadow,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: accent, size: 16),
            ],
          ),
        ),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Dados reais de posts que usam o mesmo áudio (Supabase). Sem modo demo:
  /// sem backend, os valores ficam em 0/vazio (nunca inventa números).
  Future<void> _load() async {
    final audioName = widget.video.audioName;
    if (audioName.isNotEmpty &&
        SupabaseService.instance.isConfigured) {
      try {
        final count = await ContentService.instance
            .countPostsByAudio(audioName);
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
        title: const Text(
          'Áudio',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
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
                        color: const Color(0xFF8B5CF6)
                            .withValues(alpha: 0.5),
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
                      Text(
                        widget.video.audioName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
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
                              '$totalUses vídeo${totalUses == 1 ? '' : 's'} usando este som',
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
                kNavIndex.value = 2;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Crie seu vídeo usando este som 🎬'),
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
                child: const Text(
                  'Usar este som',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Text(
              'Vídeos usando esse áudio',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
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
                    ? const SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Text(
                          'Nenhum vídeo usando esse áudio ainda',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _related.length,
                        itemBuilder: (context, index) {
                          final p = _related[index];
                          final name = p.author?.name ?? 'Usuário';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VideoPreviewScreen(post: p),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C1C26),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: p.coverUrl == null ||
                                              p.coverUrl!.isEmpty
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                            '${_format(p.likesCount)} curtidas',
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
      final lives = await SupabaseService.instance.fetchActiveLives();
      if (!mounted) return;
      setState(() => _activeLives = lives);
    } catch (_) {
      // Em caso de falha (sem rede, backend desligado), permanece no demo.
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live atualizada.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível atualizar agora. Tente de novo.')),
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
      await ContentService.instance.deleteLive(live.id, coverUrl: live.coverUrl);
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
    final isOwner = SupabaseService.instance.client.auth.currentUser?.id ==
        live.streamerId;
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
      title: 'Vídeo',
      description: 'Converse com seu público ao vivo',
      icon: Icons.videocam_rounded,
      accent: kkLivePurple,
    ),
    LiveFormat(
      id: 'audio',
      title: 'Áudio',
      description: 'Converse ao vivo sem câmera',
      icon: Icons.mic_rounded,
      accent: kkLiveMagenta,
    ),
    LiveFormat(
      id: 'friends',
      title: 'Amigos',
      description: 'Entre ao vivo com seus amigos',
      icon: Icons.people_rounded,
      accent: Color(0xFF22C55E),
    ),
    LiveFormat(
      id: 'filmes',
      title: 'Filmes',
      description:
          'Crie uma experiência ao vivo sobre filmes e entretenimento',
      icon: Icons.movie_rounded,
      accent: Color(0xFFF59E0B),
    ),
    LiveFormat(
      id: 'jogos',
      title: 'Jogos',
      description: 'Transmita seu jogo ao vivo',
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

  Future<void> _openVideoLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StartLiveScreen()),
    );
    _loadRealLives();
  }

  Future<void> _openAudioLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AudioRoomsScreen()),
    );
    _loadRealLives();
  }

  Future<void> _openFriendsLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AudioRoomsScreen(autoCreate: true, friendsMode: true),
      ),
    );
    _loadRealLives();
  }

  Future<void> _openFilmsLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const StartLiveScreen(
          initialCategory: 'Filmes',
          title: 'Live de Filmes',
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
      return Container(
        color: Colors.black,
        child: _buildCentral(topInset),
      );
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
    final liveNow = _realLivesByCategory(_exploreCategories[_categoryFilter]);
    final trending = _realLivesByCategory('Todos');

    return ListView(
      key: const PageStorageKey('live-central'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        // ---- Cabeçalho ----
        const Text(
          'Live',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            shadows: [Shadow(color: kkLivePurple, blurRadius: 22)],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'O que você quer fazer hoje?',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 18),

        // ---- Formatos (5 cards) ----
        LayoutBuilder(
          builder: (context, constraints) {
            final twoPerLine = constraints.maxWidth >= 420;
            final cards = _formats.map((f) => LiveTypeCard(
                  key: ValueKey('live-${f.id}'),
                  format: f,
                  onTap: () => _openFormat(f),
                ));
            if (twoPerLine) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in cards) SizedBox(width: (constraints.maxWidth - 12) / 2, child: c),
                ],
              );
            }
            // Celulares menores: 2 colunas com o último card ocupando a linha.
            return _FormatMobileGrid(
              formats: _formats,
              onOpen: _openFormat,
            );
          },
        ),
        const SizedBox(height: 26),

        // ---- Ao vivo agora ----
        const _SectionHeader(
          title: 'Ao vivo agora',
          subtitle: 'Veja o que está acontecendo no KLAY K',
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
            onHidden: () => setState(
              () => _hubAds.remove(_hubAds.ads.first.id),
            ),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 26),

        // ---- Em alta ----
        const _SectionHeader(
          title: 'Em alta',
          subtitle: 'Lives em destaque agora',
          icon: Icons.local_fire_department_rounded,
          accent: kkLiveMagenta,
        ),
        const SizedBox(height: 12),
        if (_liveLoading)
          const LiveNowSkeleton(rows: 1, rail: true)
        else if (trending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Lives em alta aparecem aqui quando houver transmissões.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
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
                  meta: live.streamerDisplayName ?? 'Transmissão',
                  viewers: live.viewerCount,
                  onTap: () => _openRealLive(live),
                );
              },
            ),
          ),
        const SizedBox(height: 26),

        // ---- Explorar Lives ----
        const _SectionHeader(
          title: 'Explorar Lives',
          subtitle: 'Navegue por categoria',
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
                  label: _exploreCategories[i],
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
                    shadows: [Shadow(color: Color(0xFF8B5CF6), blurRadius: 14)],
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
                child: const Text('Ver todas'),
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
      rows.add(Row(
        children: [
          Expanded(
            child: LiveTypeCard(format: first, onTap: () => onOpen(first)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LiveTypeCard(format: second, onTap: () => onOpen(second)),
          ),
        ],
      ));
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
        ..add(Row(
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
        ))
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
      title: 'Configure o Supabase para ver lives',
    );
  }
}

class _EmptyLiveState extends StatelessWidget {
  final VoidCallback onStart;
  final String title;

  const _EmptyLiveState({
    required this.onStart,
    this.title = 'Não há Lives acontecendo agora.',
  });

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.radio_button_checked_rounded,
              color: kkLiveRed, size: 30),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Que tal começar uma?',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: kkLivePurple,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.sensors_rounded, color: Colors.white),
            label: const Text(
              'Começar Live',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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
      SupabaseService.instance.client.auth.currentUser?.id ==
      live.streamerId;

  @override
  Widget build(BuildContext context) {
    final name = live.streamerDisplayName ?? 'Transmissão ao vivo';
    final isGame = live.category.toLowerCase().contains('jogo');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF251A45), Color(0xFF14142B)],
          ),
          border: Border.all(color: _kPurple.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (live.coverUrl != null && live.coverUrl!.isNotEmpty) ...[
              Positioned.fill(
                child: Image.network(
                  live.coverUrl!,
                  fit: BoxFit.cover,
                  // Falha de rede/URL inválida → volta ao gradiente do card.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
              ),
              // Scrim para manter legíveis badge/título/streamer sobre a capa.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kPurple.withValues(alpha: 0.18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kLiveRed,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _kLiveRed.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle,
                                color: Colors.white, size: 7),
                            SizedBox(width: 4),
                            Text('AO VIVO',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isGame
                            ? Icons.sports_esports_rounded
                            : Icons.videocam_rounded,
                        color: _kPurple,
                        size: 18,
                      ),
                      ContentOverflowMenu(
                        isOwner: _isOwner,
                        onEdit: onEditLive ?? () {},
                        onDelete: onDeleteLive ?? () {},
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.remove_red_eye_rounded,
                            color: Colors.white70, size: 13),
                        const SizedBox(width: 4),
                        Text('${live.viewerCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    live.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 8,
                        backgroundColor: _kPurple.withValues(alpha: 0.4),
                        backgroundImage: live.streamerAvatar != null
                            ? NetworkImage(live.streamerAvatar!)
                            : null,
                        child: const Icon(Icons.person,
                            color: Colors.white70, size: 9),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // CTA real (§21): o card inteiro é tocável, mas o botão
                  // explicita o acesso à sala da live.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kPurple, Color(0xFF6D28D9)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _kPurple.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Toque para entrar na Live',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
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
              child: _liveBadge(),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  const Icon(Icons.sports_esports_rounded,
                      color: Color(0xFFB794FF), size: 28),
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

  Widget _liveBadge() => Container(
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
              viewers > 0 ? 'AO VIVO • $viewers' : 'AO VIVO',
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

class _LiveCard extends StatelessWidget {
  final KlayKLive live;
  final VoidCallback onTap;

  const _LiveCard({
    required this.live,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: const BoxDecoration(color: Color(0xFF181820)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (live.isGame)
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B0764), Color(0xFF8B5CF6)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.sports_esports_rounded,
                      color: Colors.white70,
                      size: 54,
                    ),
                  ),
                )
              else
                Image.network(
                  live.avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF23232E),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white38,
                      size: 44,
                    ),
                  ),
                ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xCC000000),
                      Color(0xF2000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _kLiveRed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 6),
                      SizedBox(width: 3),
                      Text(
                        'AO VIVO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
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
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        live.viewers >= 1000
                            ? '${(live.viewers / 1000).toStringAsFixed(1)}k'
                            : '${live.viewers}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 9,
                right: 9,
                bottom: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ClipOval(
                          child: Image.network(
                            live.avatarUrl,
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 22,
                              height: 22,
                              color: Colors.grey[800],
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            live.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              shadows: _kLabelShadow,
                            ),
                          ),
                        ),
                        if (live.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 12),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      live.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: _kLabelShadow,
                      ),
                    ),
                    if (live.isGame) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: _kPurple,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              live.gameName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kPurple,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                shadows: _kLabelShadow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
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

  void _showGiftSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enviar presente',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _GiftOption(
                    emoji: '💜',
                    label: 'Rosa',
                    onTap: () {
                      setState(() => _giftCount++);
                      Navigator.pop(context);
                      _showGiftSnack('💜 Enviou 1 Rosa');
                    },
                  ),
                  _GiftOption(
                    emoji: '💖',
                    label: 'Coração',
                    onTap: () {
                      setState(() => _giftCount++);
                      Navigator.pop(context);
                      _showGiftSnack('💖 Enviou 1 Coração');
                    },
                  ),
                  _GiftOption(
                    emoji: '🎮',
                    label: 'Joystick',
                    onTap: () {
                      setState(() => _giftCount++);
                      Navigator.pop(context);
                      _showGiftSnack('🎮 Enviou 1 Joystick');
                    },
                  ),
                  _GiftOption(
                    emoji: '🚀',
                    label: 'Foguete',
                    onTap: () {
                      setState(() => _giftCount += 10);
                      Navigator.pop(context);
                      _showGiftSnack('🚀 Enviou 1 Foguete');
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showGiftSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
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
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
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
                      const SnackBar(
                        content: Text('Live encerrada'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    Navigator.pop(context, true);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'end',
                    child: Row(
                      children: [
                        Icon(
                          Icons.stop_circle_outlined,
                          color: Color(0xFFFF4D6A),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Encerrar live',
                          style: TextStyle(color: Colors.white),
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
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 7),
                      SizedBox(width: 5),
                      Text(
                        'AO VIVO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
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
                          _following ? 'Seguindo' : 'Seguir',
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
                  onTap: _showGiftSheet,
                ),
                const SizedBox(height: 18),
                _LiveAction(
                  icon: Icons.share_rounded,
                  color: Colors.white,
                  label: 'Compartilhar',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link da live copiado'),
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
                    if (widget.live.isVerified)
                      const VerifiedBadge(size: 16),
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
                          decoration: const InputDecoration(
                            hintText: 'Escreva um comentário...',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
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
                            'Comentários (${_comments.length})',
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
                                String name = 'Espectador';
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
                                                  fontWeight:
                                                      FontWeight.w700,
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

class _GiftOption extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _GiftOption({
    required this.emoji,
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
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kPurple.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
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

  const _DestaquesArea({
    required this.topPadding,
    required this.onWatchLive,
  });

  @override
  State<_DestaquesArea> createState() => _DestaquesAreaState();
}

class _DestaquesAreaState extends State<_DestaquesArea> {
  final List<Map<String, String>> _trending = const [
    {'displayName': 'SEM NOÇÃO TV', 'avatarUrl': 'https://i.pravatar.cc/150?img=12', 'views': '12,4M', 'tag': '#sucesso'},
    {'displayName': 'KLAY K BRASIL', 'avatarUrl': 'https://i.pravatar.cc/150?img=32', 'views': '9,1M', 'tag': '#brasil'},
    {'displayName': 'CRIADORES KLAY K', 'avatarUrl': 'https://i.pravatar.cc/150?img=45', 'views': '7,6M', 'tag': '#viral'},
    {'displayName': 'Maria K', 'avatarUrl': 'https://i.pravatar.cc/150?img=47', 'views': '5,2M', 'tag': '#klayk'},
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
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          color: _kPurple,
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Destaques',
                          style: TextStyle(
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
                    title: 'Vídeos em alta',
                    trailing: 'Ver todos',
                    onTrailing: () => _showSnack('Tudo em alta'),
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
                    title: 'Criadores em alta',
                    trailing: 'Ver todos',
                    onTrailing: () => _showSnack('Criadores em alta'),
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
                            'Perfil de ${_creators[index]['name']}',
                          ),
                          child: Container(
                            width: 78,
                            margin: const EdgeInsets.only(right: 8),
                            child: Column(
                              children: [
                                ClipOval(
                                  child: Image.network(
                                    _creators[index]['avatarUrl']!,
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
                    title: 'Jogos',
                    trailing: 'Ver todos',
                    onTrailing: () => _showSnack('Todos os jogos'),
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
                          onTap: () => _showSnack('Jogo ${game['name']}'),
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
                                        '${game['viewers']} assistindo',
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
                  const _SectionTitle(
                    title: 'Transmissões ao vivo',
                    trailing: 'Ver todos',
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
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
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
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                    ),
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
  const UploadScreen({super.key, this.draftsStore});

  /// Armazenamento de rascunhos injetável (mesmo padrão do `DraftsScreen`).
  /// Quando omitido, usa o `DraftsService.instance` real.
  final DraftStore? draftsStore;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController _descriptionController =
      TextEditingController();

  File? _selectedVideo;
  bool _picking = false;
  bool _publishing = false;
  bool _savingDraft = false;

  /// Upload do vídeo: inicia no momento em que o usuário escolhe o arquivo
  /// (não espera o tap em "Publicar"). Reaproveitado pelo publish — nunca
  /// envia o mesmo vídeo duas vezes.
  _VideoUploadTask? _videoTask;
  String? _uploadedVideoPath;
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
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
      );
      if (picked != null && mounted) {
        _cancelPendingUpload();
        final uploaded = _uploadedVideoPath;
        setState(() {
          _selectedVideo = File(picked.path);
          _uploadedVideoPath = null;
          _uploadProgress = null;
        });
        if (uploaded != null) {
          ContentService.instance.removeVideoObject(uploaded);
        }
        _startUploadIfConfigured();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível selecionar o vídeo'),
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
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();

    if (_publishing) return;

    if (!SupabaseService.instance.isConfigured) {
      _showMessage('Vídeo enviado com sucesso!');
      _descriptionController.clear();
      return;
    }

    final video = _selectedVideo;
    if (video == null) {
      _showMessage('Selecione um vídeo primeiro');
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
        audioName: 'Áudio original',
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
      _showMessage('Vídeo enviado com sucesso!');
    } on UploadCancelledException {
      if (mounted) _showMessage('Upload cancelado. Tente novamente.');
    } catch (_) {
      if (mounted) _showMessage('Não foi possível publicar o vídeo');
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

    if (_savingDraft) return;

    final store = widget.draftsStore ?? DraftsService.instance;
    final backend = widget.draftsStore != null || SupabaseService.instance.isConfigured;
    if (!backend) {
      _showMessage('Rascunho salvo!');
      _descriptionController.clear();
      return;
    }

    final video = _selectedVideo;
    if (video == null) {
      _showMessage('Selecione um vídeo primeiro');
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
        audioName: 'Áudio original',
        hashtags: _parseHashtags(description),
      );

      if (mounted) {
        setState(() {
          _selectedVideo = null;
          _descriptionController.clear();
        });
      }
      _showMessage('Rascunho salvo! Você pode finalizar em Rascunhos.');
    } catch (_) {
      _showMessage('Não foi possível salvar o rascunho');
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
        title: const Text(
          'Enviar vídeo',
          style: TextStyle(fontWeight: FontWeight.w800),
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
                                      ContentService.instance
                                          .removeVideoObject(uploaded);
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
                        const Text(
                          'Selecione um vídeo',
                          style: TextStyle(
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
                          label: const Text('Escolher da galeria'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF8A2BE2)),
                          ),
                        ),
                      ],
                    ),
            ),
            if (SupabaseService.instance.isConfigured && _videoTask != null) ...[
              const SizedBox(height: 12),
              _UploadProgressBar(
                progress: _uploadProgress ?? _videoTask!.progress,
                done: _uploadedVideoPath != null,
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Descrição',
              style: TextStyle(
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
                hintText: 'O que está acontecendo?',
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
                            value: _uploadProgress != null &&
                                    _uploadProgress! < 1
                                ? _uploadProgress
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _uploadProgress != null && _uploadProgress! < 1
                              ? 'Publicando ${(_uploadProgress! * 100).round()}%'
                              : 'Finalizando…',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Publicar',
                      style: TextStyle(
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
                _savingDraft ? 'Salvando...' : 'Salvar rascunho',
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
          done ? 'Vídeo pronto para publicar' : 'Enviando vídeo… $pct%',
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
        child: Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 48),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  children: _scopes.map((s) {
                    final sel = scope == s['value'];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(s['label']!,
                            style: TextStyle(
                                color: sel ? Colors.white : Colors.white70,
                                fontSize: 13)),
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
                    child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
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
                              ? Icon(typeIcon,
                                  color: const Color(0xFFB28DFF), size: 20)
                              : null)
                          : Icon(typeIcon,
                              color: const Color(0xFFB28DFF), size: 20),
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
                        ? const Icon(Icons.chevron_right, color: Colors.white24)
                        : null,
                    onTap: () {
                      _record();
                      switch (r.type) {
                        case 'user':
                          close(context, null);
                          _openAuthor(context, r.id);
                          break;
                        case 'hashtag':
                          query = '#${r.subtitle}';
                          _scope.value = 'post';
                          break;
                        default:
                          close(context, null);
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
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: userId),
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    if (!SupabaseService.instance.isConfigured) {
      return _buildLegacyHome(context);
    }
    return ValueListenableBuilder<int>(
      valueListenable: _homeTick,
      builder: (context, tick, _) {
        return FutureBuilder<({List<String> recents, List<HashtagTrend> trends})>(
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
                      icon: const Icon(Icons.delete_sweep_rounded,
                          color: Colors.white38, size: 20),
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
                  leading: const Icon(Icons.history_rounded,
                      color: Color(0xFFB28DFF)),
                  title: Text(term,
                      style: const TextStyle(color: Colors.white)),
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
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
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
            leading: const Icon(
              Icons.trending_up,
              color: Color(0xFFB28DFF),
            ),
            title: Text(
              term,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => close(context, term),
          ),
        ),
      ],
    );
  }

  Widget _buildResultList(BuildContext context, List<String> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Nada encontrado',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView(
      children: items.map(
        (term) => ListTile(
          leading: const Icon(Icons.search, color: Colors.white38),
          title: Text(
            term,
            style: const TextStyle(color: Colors.white),
          ),
          onTap: () => close(context, term),
        ),
      ).toList(),
    );
  }
}