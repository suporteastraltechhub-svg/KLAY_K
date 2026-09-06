import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/klayk_live_models.dart';
import 'app_config.dart';

/// Identidade ativa do usuário no KLAY K (usada para nomear participações).
/// Este é o valor padrão do aplicativo; pode ser atualizado quando o perfil
/// for editado.
class KAppIdentity {
  String displayName = 'KLAY K OFICIAL';
  String username = '@klaykoficial';
  String? avatarUrl;

  KAppIdentity();
}

final KAppIdentity kAppIdentity = KAppIdentity();

/// Deep link de callback do Google Sign-In (OAuth via Supabase).
///
/// Precisa bater com o `redirectTo` usado em [SupabaseService.signInWithGoogle],
/// com o intent-filter `klayk://callback` no AndroidManifest e com o
/// `uri_allow_list` configurado em Supabase Auth. O valor em si não é segredo.
const String kGoogleAuthRedirect = 'klayk://callback';

class LiveKitCredentials {
  final String serverUrl;
  final String participantToken;

  const LiveKitCredentials({
    required this.serverUrl,
    required this.participantToken,
  });
}

/// Erro tipado quando o Supabase está configurado, mas a autenticação
/// anônima está desativada no projeto (Authentication → Providers →
/// Anonymous sign-ins). O app degrada com uma mensagem clara em vez de falhar.
class SupabaseAuthUnavailableException implements Exception {
  final String message;

  const SupabaseAuthUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Erro tratável do envio de mensagem em live (`RPC live_send_chat`).
/// `code` já vem pronto do backend ('banned', 'muted', 'rate_limited',
/// 'blocked', 'cleared', 'flagged', ...) para a UI exibir o aviso correto.
class LiveChatSendException implements Exception {
  final String message;
  final String? code;
  final bool flagged;

  const LiveChatSendException(
    this.message, {
    this.code,
    this.flagged = false,
  });

  @override
  String toString() => message;
}

class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  Future<void>? _initFuture;

  /// Caches de perfis para renderizar nome/foto de quem chateia em tempo real
  /// (joins não estão disponíveis em payloads de Realtime).
  final Map<String, Map<String, dynamic>?> _profileCache = {};

  /// Em flutter_test não há rede real por padrão; o Supabase não deve ser
  /// inicializado (as RPCs/Realtime gerariam timers/imagens pendentes).
  /// Mesmo critério usado no resto do app (LiveArea, AppGate, etc).
  /// Com `KLAY_E2E=true` um teste de integração ENGLOBA rede real de propósito
  /// (credenciais de conta de teste confirmadas via backend/admin).
  static final bool _inTests = Platform.environment['FLUTTER_TEST'] == 'true';
  static final bool _allowRealNetwork = Platform.environment['KLAY_E2E'] == 'true';

  bool get isConfigured =>
      AppConfig.isSupabaseConfigured && (!_inTests || _allowRealNetwork);

  SupabaseClient get client {
    if (!isConfigured) {
      throw StateError(
        'Supabase não configurado. Rode com '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
      );
    }
    return Supabase.instance.client;
  }

  Future<void> ensureReady() async {
    if (!isConfigured) return;
    _initFuture ??= _init();
    await _initFuture;
  }

  Future<void> _init() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
  }

  /// Garante uma sessão anônima autenticada (o padrão do KLAY K não exige
  /// cadastro para assistir). Retorna o usuário autenticado.
  Future<User> ensureAuthenticated({
    String? displayName,
    String? username,
  }) async {
    await ensureReady();
    final name = displayName ?? kAppIdentity.displayName;
    final userName = username ?? kAppIdentity.username;

    var user = client.auth.currentUser;
    if (user == null) {
      try {
        final res = await client.auth.signInAnonymously();
        user = res.user;
      } on AuthException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('anonymous') &&
            (msg.contains('disabled') || msg.contains('not enabled'))) {
          throw const SupabaseAuthUnavailableException(
            'Lives reais exigem login. Ative "Anonymous sign-ins" no '
            'Supabase (Authentication → Sign In / Providers) para que o '
            'KLAY K possa criar a sessão anônima automaticamente.',
          );
        }
        rethrow;
      }
    }
    if (user != null) {
      await _syncIdentity(user, name, userName);
    }
    return user!;
  }

  Future<void> _syncIdentity(User user, String name, String userName) async {
    try {
      final meta = {
        'full_name': name,
        'username': userName.replaceFirst(RegExp(r'^@'), ''),
      };
      final current = client.auth.currentUser?.userMetadata ?? {};
      final needsUpdate =
          current['full_name'] != name || current['username'] != meta['username'];
      if (needsUpdate) {
        await client.auth.updateUser(UserAttributes(data: meta));
      }
      await client
          .from('profiles')
          .upsert({
            'id': user.id,
            'display_name': name,
            'username': userName.replaceFirst(RegExp(r'^@'), ''),
          }, onConflict: 'id')
          .then((_) {})
          .catchError((Object e) {});
    } catch (_) {
      // Identidade opcional: nunca quebra o fluxo.
    }
  }

  // ---------------------------------------------------------------------------
  // Edge Functions (o token do LiveKit vem SOMENTE daqui; o app nunca guarda a
  // API key / secret do LiveKit).
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> invoke(
    String name, {
    Map<String, dynamic>? body,
  }) async {
    await ensureReady();
    try {
      final res = await client.functions.invoke(name, body: body);
      final data = res.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw StateError('Resposta inesperada da função "$name".');
    } on FunctionException catch (e) {
      throw StateError('Erro ao chamar "$name" (${e.status}): ${e.details}');
    }
  }

  Future<LiveKitCredentials> getLiveKitCredentials({
    required String roomName,
    required bool isStreamer,
    String? displayName,
    String? role,
  }) async {
    final user = await ensureAuthenticated();
    final res = await invoke('livekit-token', body: {
      'roomName': roomName,
      'isStreamer': isStreamer,
      if (role != null && role.isNotEmpty) 'role': role,
      'displayName': displayName ?? kAppIdentity.displayName,
    });
    final serverUrl = res['server_url'] as String? ?? '';
    final participantToken = res['participant_token'] as String? ?? '';
    if (serverUrl.isEmpty || participantToken.isEmpty || user.id.isEmpty) {
      throw StateError('Falha ao obter credenciais temporárias do LiveKit.');
    }
    return LiveKitCredentials(
      serverUrl: serverUrl,
      participantToken: participantToken,
    );
  }

  Future<RealLive> createLive({
    required String title,
    String description = '',
    String category = '',
    List<String> hashtags = const [],
    String privacy = 'public',
    String? gameName,
    String? coverUrl,
    bool ageRestricted = false,
  }) async {
    final res = await invoke('create-live', body: {
      'title': title,
      'description': description,
      'category': category,
      'hashtags': hashtags,
      'privacy': privacy,
      if (gameName != null && gameName.isNotEmpty) 'game_name': gameName,
      if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
      if (ageRestricted) 'age_restricted': true,
    });
    final id = res['live_id'] as String?;
    final roomName = res['room_name'] as String?;
    if (id == null || roomName == null) {
      throw StateError('A live não pôde ser criada no backend.');
    }
    return RealLive(
      id: id,
      roomName: roomName,
      streamerId: client.auth.currentUser?.id ?? '',
      title: title,
      description: description,
      category: category,
      hashtags: hashtags,
      privacy: privacy,
      startedAt: DateTime.now(),
      gameName: gameName,
      coverUrl: coverUrl,
      ageRestricted: ageRestricted,
      streamerDisplayName: kAppIdentity.displayName,
      streamerUsername: kAppIdentity.username,
    );
  }

  Future<void> endLive(String liveId) async {
    await invoke('end-live', body: {'live_id': liveId});
  }

  /// Consulta o status real de uma live no backend (sem depender do estado
  /// local). Usado para distinguir "Esta Live terminou" de erro de conexão.
  Future<String?> fetchLiveStatus(String liveId) async {
    try {
      final res = await client
          .from('lives')
          .select('status')
          .eq('id', liveId)
          .maybeSingle();
      return res?['status']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Cria uma sala de voz (Áudio) e retorna o id + nome da sala no LiveKit.
  Future<({String audioRoomId, String roomName})> createAudioRoom({
    required String title,
    String description = '',
    String category = '',
  }) async {
    final res = await invoke('create-audio-room', body: {
      'title': title,
      'description': description,
      'category': category,
    });
    final id = res['audio_room_id'] as String?;
    final roomName = res['room_name'] as String?;
    if (id == null || roomName == null) {
      throw StateError('A sala de voz não pôde ser criada no backend.');
    }
    return (audioRoomId: id, roomName: roomName);
  }

  /// Encerra uma sala de voz (somente o dono).
  Future<void> endAudioRoom(String audioRoomId) async {
    await invoke('end-audio-room', body: {'audio_room_id': audioRoomId});
  }

  Future<List<RealLive>> fetchActiveLives() async {
    await ensureReady();
    if (client.auth.currentUser == null) {
      await ensureAuthenticated();
    }
    final res = await client.from('lives').select(
          '*, profiles:streamer_id(display_name, username, avatar_url, is_verified)',
        ).eq('status', 'live').order('started_at', ascending: false).limit(50);
    final rows = res as List;
    return rows.whereType<Map<dynamic, dynamic>>().map((row) {
      final m = Map<String, dynamic>.from(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      return RealLive.fromJson(m);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Chat (Supabase Realtime).
  // ---------------------------------------------------------------------------

  Future<List<LiveChatMessage>> loadRecentChat(String liveId) async {
    await ensureReady();
    final me = client.auth.currentUser?.id;
    final res = await client
        .from('live_chat')
        .select('*, sender:user_id(display_name, username, avatar_url, is_verified)')
        .eq('live_id', liveId)
        .order('created_at', ascending: true)
        .limit(200);
    final rows = res as List;
    return rows.whereType<Map<dynamic, dynamic>>().map((row) {
      final m = Map<String, dynamic>.from(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      return LiveChatMessage.fromJson(m, myId: me);
    }).toList();
  }

  RealtimeChannel subscribeToChat(
    String liveId,
    void Function(LiveChatMessage message) onInsert,
  ) {
    final me = client.auth.currentUser?.id;
    final channel = client
        .channel('live-chat-$liveId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_chat',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'live_id',
            value: liveId,
          ),
          callback: (payload) async {
            final msg = LiveChatMessage.fromJson(
              Map<String, dynamic>.from(payload.newRecord),
              myId: me,
            );
            await _hydrateSender(msg);
            onInsert(msg);
          },
        )
        .subscribe();
    return channel;
  }

  Future<LiveChatMessage> _hydrateSender(LiveChatMessage msg) async {
    if (msg.userId == null) return msg;
    if (msg.senderDisplayName != null) return msg;
    final profile = await profileFor(msg.userId!);
    if (profile == null) return msg;
    return msg.copyWith(
      senderDisplayName: profile['display_name'] as String?,
      senderAvatar: profile['avatar_url'] as String?,
      senderVerified: profile['is_verified'] == true,
    );
  }

  Future<Map<String, dynamic>?> profileFor(String userId) async {
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }
    Map<String, dynamic>? result;
    try {
      final res = await client
          .from('profiles')
          .select('id, display_name, username, avatar_url, is_verified')
          .eq('id', userId)
          .maybeSingle();
      if (res != null) {
        result = Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    _profileCache[userId] = result;
    return result;
  }

  RealtimeChannel subscribeToLiveChanges(
    String liveId,
    void Function(Map<String, dynamic> record) onChange,
  ) {
    return client
        .channel('live-row-$liveId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'lives',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: liveId,
          ),
          callback: (payload) => onChange(
            Map<String, dynamic>.from(payload.newRecord),
          ),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToLiveEvents(
    String liveId,
    void Function(LiveRoomEvent event) onEvent,
  ) {
    return client
        .channel('live-events-$liveId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'live_id',
            value: liveId,
          ),
          callback: (payload) => onEvent(
            LiveRoomEvent.fromJson(Map<String, dynamic>.from(payload.newRecord)),
          ),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToBroadcast(
    String liveId,
    String event,
    void Function(Map<String, dynamic> payload) callback,
  ) =>
      client
          .channel('live-broadcast-$liveId')
          .onBroadcast(event: event, callback: callback)
          .subscribe();

  Future<void> sendBroadcast(
    String liveId,
    String event,
    Map<String, dynamic> payload,
  ) async {
    await client
        .channel('live-broadcast-$liveId')
        .sendBroadcastMessage(event: event, payload: payload);
  }

  void removeChannel(RealtimeChannel channel) {
    client.removeChannel(channel);
  }

  /// Assina inserts em `public.notifications` destinados ao usuário atual.
  /// Usado pela central de notificações para atualizar em tempo real.
  RealtimeChannel subscribeToNotifications(
    void Function(Map<String, dynamic> record) onInsert,
  ) {
    final me = client.auth.currentUser?.id;
    if (me == null) {
      throw StateError('Usuário não autenticado para notificações em tempo real.');
    }
    return client
        .channel('notifications-$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: (payload) =>
              onInsert(Map<String, dynamic>.from(payload.newRecord)),
        )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  // Escrita (participantes, eventos, presentes, chat).
  // ---------------------------------------------------------------------------

  Future<void> recordParticipant(
    String liveId, {
    required bool isStreamer,
  }) async {
    final user = await ensureAuthenticated();
    if (user.id.isEmpty) return;
    try {
      await client.from('live_participants').upsert(
        {
          'live_id': liveId,
          'user_id': user.id,
          'is_streamer': isStreamer,
        },
        onConflict: 'live_id,user_id',
        ignoreDuplicates: true,
      ).then((_) {});
    } catch (_) {}
    if (!isStreamer) {
      await logEvent(liveId, 'USER_JOINED',
          userId: user.id, username: kAppIdentity.displayName);
    }
  }

  Future<void> recordParticipantLeft(String liveId) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await client
          .from('live_participants')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('live_id', liveId)
          .eq('user_id', user.id)
          .isFilter('left_at', null)
          .then((_) {});
    } catch (_) {}
    await logEvent(liveId, 'USER_LEFT',
        userId: user.id, username: kAppIdentity.displayName);
  }

  /// Envia mensagem no chat da live via RPC `live_send_chat` — o backend
  /// valida autenticação, live ativa, banimento/silenciamento, tamanho e
  /// anti-flood/anti-spam. O cliente NUNCA insere em `live_chat` direto.
  ///
  /// Retorna [LiveChatMessage] construído com o id gerado no backend. Lança
  /// [LiveChatSendException] para erros de validação/anti-flood tratáveis.
  Future<LiveChatMessage> insertChat(String liveId, String message) async {
    final user = await ensureAuthenticated();
    try {
      final res = await client.rpc('live_send_chat',
          params: {'p_live_id': liveId, 'p_message': message});
      final data = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (data['ok'] != true || data['id'] == null) {
        throw LiveChatSendException(
          data['error']?.toString() ??
              'Não foi possível enviar a mensagem. Tente novamente.',
        );
      }
      return LiveChatMessage.fromJson(
        {
          'id': data['id'],
          'live_id': liveId,
          'user_id': user.id,
          'message': message,
          'created_at': data['created_at'],
        },
        myId: user.id,
      );
    } on PostgrestException catch (e) {
      final code = e.message.trim();
      throw LiveChatSendException(
        code,
        code: code,
      );
    }
  }

  Future<void> deleteChatMessage(String messageId) async {
    try {
      await client.from('live_chat').delete().eq('id', messageId).then((_) {});
    } catch (_) {}
  }

  /// Edita a própria mensagem de chat via RPC `live_edit_chat` (backend valida
  /// posse e tamanho). Retorna `true` se editado com sucesso; `false` se a
  /// migração/RPC ainda não estiver aplicada no backend.
  Future<bool> editChat(String messageId, String newMessage) async {
    try {
      final res = await client
          .rpc('live_edit_chat', params: {'p_message_id': messageId, 'p_message': newMessage});
      final data = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (data['ok'] != true || data['id'] == null) return false;
      return true;
    } on PostgrestException catch (e) {
      final msg = e.message.toString();
      if ((e.details?.toString() ?? '').contains('404') ||
          msg.contains('404') ||
          msg.contains('function') ||
          e.code == 'PGRST202') {
        return false;
      }
      rethrow;
    }
  }

  Future<void> recordGift({
    required String liveId,
    required String receiverId,
    required GiftCatalogItem gift,
    required int amount,
  }) async {
    final user = await ensureAuthenticated();
    final giftMessage =
        '🎁 ${kAppIdentity.displayName} enviou ${gift.name} x$amount';
    try {
      await insertChat(liveId, giftMessage);
    } catch (_) {}
    try {
      await client.from('live_gifts').insert({
        'live_id': liveId,
        'sender_id': user.id,
        'receiver_id': receiverId,
        'gift_id': gift.id,
        'gift_name': gift.name,
        'gift_amount': amount,
      }).then((_) {});
    } catch (_) {}
    await logEvent(liveId, 'GIFT_RECEIVED',
        userId: user.id,
        username: kAppIdentity.displayName,
        metadata: {
          'gift_id': gift.id,
          'gift_name': gift.name,
          'gift_amount': amount,
          'message': giftMessage,
        });
  }

  Future<void> logEvent(
    String liveId,
    String eventType, {
    String? userId,
    String? username,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await ensureReady();
      final uid = userId ?? client.auth.currentUser?.id;
      await client.from('live_events').insert({
        'live_id': liveId,
        'event_type': eventType,
        'user_id': uid,
        'username': username ?? kAppIdentity.displayName,
        'metadata': metadata,
      }).then((_) {});
    } catch (_) {}
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    await client.auth.signOut();
    _initFuture = null;
  }

  // ---------------------------------------------------------------------------
  // Autenticação real (e-mail/senha) — usada pela Splash + Login/Cadastro.
  // Nada de autenticação falsa: tudo passa por Supabase Auth.
  // ---------------------------------------------------------------------------

  /// Sessão ativa (qualquer tipo: e-mail, anônima, OAuth) ou `null`.
  Session? get currentSession {
    if (!isConfigured) return null;
    try {
      return client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser {
    if (!isConfigured) return null;
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// `true` quando há uma sessão (real ou anônima) ativa.
  bool get hasSession => currentSession != null;

  /// Login com e-mail e senha (Supabase Auth real).
  Future<User> signInWithEmail(String email, String password) async {
    await ensureReady();
    final res = await client.auth.signInWithPassword(email: email, password: password);
    final user = res.user;
    if (user == null) {
      throw const AuthException('Credenciais inválidas.');
    }
    await _syncIdentity(
      user,
      user.userMetadata?['full_name'] as String? ?? kAppIdentity.displayName,
      user.userMetadata?['username'] as String? ?? kAppIdentity.username,
    );
    return user;
  }

  /// Login com Google (OAuth real via Supabase Auth, fluxo PKCE + deep link).
  ///
  /// Usa o provider Google já configurado no projeto (Web Client ID/Secret).
  /// Abre o navegador do Google e, ao voltar via `klayk://callback`, o
  /// supabase_flutter troca o código por sessão e o [AppGate] redireciona para
  /// a Home automaticamente. Não expõe token/secret em lugar algum.
  ///
  /// Se já houver uma sessão (ex.: anônima), encerra antes para evitar erro de
  /// "user already linked"/conflito de identidades.
  Future<void> signInWithGoogle() async {
    ensureGoogleEnabled();
    await ensureReady();
    final auth = client.auth;
    if (auth.currentSession != null) {
      await auth.signOut();
    }
    final launched = await auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kGoogleAuthRedirect,
    );
    if (!launched) {
      throw const AuthException(
        'Não foi possível abrir o fluxo do Google neste dispositivo.',
      );
    }
  }

  /// Login com GitHub via Supabase Auth (OAuth + deep link `klayk://callback`).
  Future<void> signInWithGitHub() async {
    ensureGoogleEnabled();
    await ensureReady();
    final auth = client.auth;
    if (auth.currentSession != null) {
      await auth.signOut();
    }
    final launched = await auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: kGoogleAuthRedirect,
    );
    if (!launched) {
      throw const AuthException(
        'Não foi possível abrir o fluxo do GitHub neste dispositivo.',
      );
    }
  }

  void ensureGoogleEnabled() {
    if (!isConfigured) {
      throw StateError(
        'Supabase não configurado. Rode com '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
      );
    }
  }

  /// Cadastro (Supabase Auth real). O perfil é criado pelo trigger do banco
  /// `handle_new_user` a partir de `raw_user_meta_data` — sem duplicar perfis.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
    required String username,
    String? inviteCode,
  }) async {
    await ensureReady();
    final data = <String, dynamic>{
      'full_name': displayName,
      'username': username.replaceFirst(RegExp(r'^@'), ''),
    };
    if (inviteCode != null && inviteCode.trim().isNotEmpty) {
      data['invite_code'] = inviteCode.trim();
    }
    return client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  /// Recuperação de senha (Supabase Auth envio de e-mail).
  Future<void> resetPassword(String email) async {
    await ensureReady();
    await client.auth.resetPasswordForEmail(email);
  }

  /// "Entrar sem conta" — sessão anônima real do Supabase (não é fake).
  Future<User> ensureAnonymous() async {
    await ensureReady();
    final res = await client.auth.signInAnonymously();
    final user = res.user;
    if (user == null) {
      throw const AuthException('Não foi possível entrar como visitante.');
    }
    await _syncIdentity(user, kAppIdentity.displayName, kAppIdentity.username);
    return user;
  }
}