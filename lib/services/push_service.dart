import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/klayk_live_models.dart';
import '../models/post_models.dart';
import '../screens/live_room_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/profile/video_preview_screen.dart';
import 'app_config.dart';
import 'live_kit_service.dart';
import 'message_service.dart';
import 'supabase_service.dart';

/// Navegador raiz do app. Usado pelo [PushService] para abrir o destino de um
/// push mesmo quando o app já está aberto em outra tela (deep-link global).
final GlobalKey<NavigatorState> kAppNavigatorKey = GlobalKey<NavigatorState>();

/// Canal de notificação Android do KLAY K. Precisa ser o MESMO id enviado no
/// payload da Edge Function `send-push` e criado no `MainActivity`.
const String kPushChannelId = 'klay_k_notifications';

/// Handler de mensagens em background/termineu (isolate próprio do FCM).
///
/// O payload sempre inclui `notification`, então o Android exibe a notificação
/// na barra automaticamente — não há trabalho de dados a fazer aqui. O toque
/// no push reabre o app e o roteamento acontece via
/// `onMessageOpenedApp`/`getInitialMessage` no [PushService].
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  // No-op intencional: ver comentário acima.
}

/// Central de push do KLAY K (FCM como transporte; Supabase continua backend).
///
/// Responsabilidades:
///  - inicializar o Firebase com as opções PÚBLICAS do app (AppConfig);
///  - pedir permissão (Android 13+) e registrar/atualizar o token em
///    `public.push_tokens` via RPC segura (`register_push_token`);
///  - desassociar tokens no logout (`clear_push_tokens`);
///  - rotear o toque no push para o conteúdo real (post/mensagem/Live/perfil).
///
/// Regras:
///  - Em primeiro plano NÃO mostra push (o app já tem in-app + Realtime);
///  - Só funciona fora de flutter_test e com Supabase + Firebase configurados;
///  - Nenhuma credencial administrativa toca o cliente.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static final bool _inTests = Platform.environment['FLUTTER_TEST'] == 'true';

  FirebaseMessaging? _messaging;
  bool _ready = false;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Condições para o push existir: app real, Firebase + Supabase ativos.
  bool get pushConfigured =>
      !_inTests &&
      AppConfig.isFirebaseConfigured &&
      SupabaseService.instance.isConfigured;

  bool get isReady => _ready;

  /// Inicializa o FCM e registra o token para a sessão atual (se houver).
  /// Seguro para chamar sempre: vira no-op fora das condições.
  Future<void> init() async {
    if (!pushConfigured || _ready) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseMessagingSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (_) {
      return; // Firebase fora do ar/sem configuração → app segue sem push.
    }

    final messaging = FirebaseMessaging.instance;
    _messaging = messaging;

    // Android 13+: pede a permissão POST_NOTIFICATIONS uma única vez.
    // Em Android <=12 a permissão já nasce concedida (requestPermission
    // retorna authorized sem abrir diálogo nenhum). Só abre o diálogo quando o
    // usuário ainda NÃO foi perguntado (notDetermined) — respeita o estado
    // retornado e nunca fica re-perguntando em cada boot.
    try {
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (_) {
      // Sem Play Services/emulador: o app segue sem push, nunca quebra o boot.
    }

    // Foreground: o push NÃO é exibido — o KLAY K já entrega in-app via
    // `notifications` + Realtime. Nada duplicado em primeiro plano.
    try {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (_) {}

    // Nada daqui pode derrubar o boot: o FCM é transporte opcional. Se o
    // plugin falhar ao registrar handlers (sem Play Services, por exemplo),
    // o app segue delivering push in-app via Supabase Realtime.
    try {
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);

      // Toque em um push com o app em background.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleOpen(message.data);
      });

      // Token renovado pelo FCM (instalação/expiração): re-registra.
      _tokenRefreshSub = messaging.onTokenRefresh.listen(_registerToken);
    } catch (_) {
      // Sem Play Services/emulador: o app segue sem push, nunca quebra o boot.
    }

    // App encerrado: push tocado abre o app. Roteia após a navegação montar.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleOpen(initial.data);
        });
      }
    } catch (_) {}

    // Sessão já existente no boot → registra o token deste dispositivo.
    if (SupabaseService.instance.hasSession) {
      await register();
    }
    _ready = true;
  }

  /// Registra o token atual do dispositivo para a sessão logada.
  /// Chamar após login e após `init()` (é idempotente no backend).
  Future<void> register() async {
    if (!pushConfigured || !SupabaseService.instance.hasSession) return;
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(token);
    } catch (_) {
      // Sem permissão/emulador sem Play Services: nunca quebra o app.
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await SupabaseService.instance.client.rpc(
        'register_push_token',
        params: {'p_token': token, 'p_platform': 'android'},
      );
    } catch (_) {
      // Token local continua válido; será re-registrado no próximo refresh.
    }
  }

  /// Desassocia os tokens deste usuário (logout em todos os dispositivos).
  Future<void> logout() async {
    if (_inTests || !SupabaseService.instance.isConfigured) return;
    // Para de escutar renovação de token quando não há mais sessão.
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    try {
      await SupabaseService.instance.client.rpc('clear_push_tokens');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Deep-link do push: abre o conteúdo real referenciado pelo evento.
  // ---------------------------------------------------------------------------

  void _handleOpen(Map<String, dynamic> data) {
    if (data.isEmpty || data['klayk_id'] == null) return;
    final navigator = kAppNavigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    _route(navigator.context, data);
  }

  Future<void> _route(BuildContext context, Map<String, dynamic> data) async {
    final type = data['klayk_type']?.toString() ?? '';
    final ref = data['klayk_ref']?.toString() ?? '';
    final actor = data['klayk_actor']?.toString() ?? '';

    final messenger = ScaffoldMessenger.of(context);
    void snack(String msg) {
      messenger.showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }

    switch (type) {
      case 'like':
      case 'comment':
      case 'comment_reply':
      case 'mention':
      case 'share':
        await _openPost(context, ref, snack);
        break;
      case 'message':
        await _openConversation(context, actor, snack);
        break;
      case 'live':
        await _openLive(context, ref, snack);
        break;
      case 'follow':
      case 'live_viewer':
      case 'live_end':
      case 'record':
      case 'reward':
      case 'gift':
      case 'gift_send':
      case 'gift_sent':
        if (actor.isEmpty) break;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserProfileScreen(userId: actor)),
        );
        break;
      default:
        snack('Conteúdo não disponível.');
    }
  }

  Future<void> _openPost(
    BuildContext context,
    String postId,
    void Function(String) snack,
  ) async {
    if (postId.isEmpty) {
      snack('Conteúdo não disponível.');
      return;
    }
    try {
      final row = await SupabaseService.instance.client
          .from('posts')
          .select(
            '*, profiles:user_id(display_name, username, avatar_url, is_verified)',
          )
          .eq('id', postId)
          .maybeSingle();
      if (row == null) {
        snack('Conteúdo não disponível.');
        return;
      }
      if (!context.mounted) return;
      final post = FeedPost.fromJson(
        Map<String, dynamic>.from(
          (row as Map).map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => VideoPreviewScreen(post: post)));
    } catch (_) {
      snack('Não foi possível abrir o vídeo agora.');
    }
  }

  Future<void> _openLive(
    BuildContext context,
    String liveId,
    void Function(String) snack,
  ) async {
    if (liveId.isEmpty) {
      snack('Conteúdo não disponível.');
      return;
    }
    try {
      final row = await SupabaseService.instance.client
          .from('lives')
          .select(
            '*, profiles:streamer_id(display_name, username, avatar_url, is_verified)',
          )
          .eq('id', liveId)
          .maybeSingle();
      if (row == null) {
        snack('Conteúdo não disponível.');
        return;
      }
      final live = RealLive.fromJson(
        Map<String, dynamic>.from(
          (row as Map).map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
      if (live.status != 'live') {
        snack('Esta Live já terminou.');
        return;
      }
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveRoomScreen(live: live, role: LiveRole.viewer),
        ),
      );
    } catch (_) {
      snack('Não foi possível abrir a Live agora.');
    }
  }

  Future<void> _openConversation(
    BuildContext context,
    String actorId,
    void Function(String) snack,
  ) async {
    if (actorId.isEmpty) {
      snack('Conteúdo não disponível.');
      return;
    }
    try {
      final conv = await MessageService.instance.getOrCreateConversation(
        actorId,
      );
      if (!context.mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
    } catch (_) {
      snack('Não foi possível abrir a conversa agora.');
    }
  }
}
