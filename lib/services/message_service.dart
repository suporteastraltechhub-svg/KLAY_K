import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_models.dart';
import 'account_service.dart';
import 'social_service.dart';
import 'supabase_service.dart';

/// Serviço de mensagens privadas (DMs) do KLAY K.
///
/// Toda a leitura/escrita passa pelo cliente com RLS: só participantes da
/// conversa acessam. "Marcar lida" e "não lidas" vão por RPC security definer
/// (valida participante no backend). Realtime RLS-aware para novos eventos.
class MessageService {
  MessageService._();

  static final MessageService instance = MessageService._();

  SupabaseService get _db => SupabaseService.instance;
  SupabaseClient get _client => _db.client;

  bool get _ready {
    try {
      return _db.isConfigured;
    } catch (_) {
      return false;
    }
  }

  Future<String> _me() async {
    final u = await _db.ensureAuthenticated();
    return u.id;
  }

  /// Lista de conversas do usuário, com o participante (peer) e não lidas.
  Future<List<Conversation>> fetchConversations() async {
    if (!_ready) throw StateError('Backend não configurado.');
    final me = await _me();
    final res = await _client
        .from('conversations')
        .select('*')
        .or('user_a_id.eq.$me,user_b_id.eq.$me')
        .order('last_message_at', ascending: false);
    final rows = (res as List).whereType<Map<dynamic, dynamic>>();
    final out = <Conversation>[];
    for (final row in rows) {
      final m = Map<String, dynamic>.from(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      final a = m['user_a_id'] as String? ?? '';
      final b = m['user_b_id'] as String? ?? '';
      final peerId = a == me ? b : a;
      final peer = await _db.profileFor(peerId).catchError((_) => null);
      out.add(_toConversation(m, me, peerId, peer));
    }
    return out;
  }

  Conversation _toConversation(
    Map<String, dynamic> m,
    String me,
    String peerId,
    Map<String, dynamic>? peer,
  ) {
    final unread = _countUnreadSync(m['unread'] as num?);
    return Conversation(
      id: m['id'] as String? ?? '',
      userAId: m['user_a_id'] as String? ?? '',
      userBId: m['user_b_id'] as String? ?? '',
      lastMessage: m['last_message'] as String? ?? '',
      lastMessageAt: m['last_message_at'] != null
          ? DateTime.tryParse(m['last_message_at'] as String)?.toLocal()
          : null,
      lastSenderId: m['last_sender_id'] as String?,
      peerId: peerId,
      peerName: peer?['display_name'] as String? ?? 'Usuário',
      peerUsername: peer?['username'] as String? ?? '',
      peerAvatar: peer?['avatar_url'] as String?,
      peerVerified: peer?['is_verified'] as bool? ?? false,
      unread: unread,
      createdAt:
          DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  int _countUnreadSync(num? r) => r == null ? 0 : r.toInt();

  /// Obtém (ou cria) a conversa com [partnerId] e marca não lidas como lidas.
  Future<Conversation> getOrCreateConversation(String partnerId) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final me = await _me();
    if (partnerId == me) throw StateError('Você não pode conversar consigo.');
    // normaliza par (a < b)
    final a = [me, partnerId].reduce((x, y) => x.compareTo(y) < 0 ? x : y);
    final b = [me, partnerId].reduce((x, y) => x.compareTo(y) > 0 ? x : y);

    var res = await _client
        .from('conversations')
        .select('*')
        .eq('user_a_id', a)
        .eq('user_b_id', b)
        .maybeSingle();

    if (res == null) {
      // RLS permite inserir apenas se não houver bloqueio recíproco.
      try {
        final r = await _client
            .from('conversations')
            .insert({'user_a_id': a, 'user_b_id': b})
            .select()
            .single();
        res = r;
      } catch (e) {
        throw StateError('Não foi possível iniciar a conversa (bloqueio?): $e');
      }
    }
    final peer = await _db.profileFor(partnerId).catchError((_) => null);
    return _toConversation(
      Map<String, dynamic>.from(res as Map),
      me,
      partnerId,
      peer,
    );
  }

  Future<List<DirectMessage>> fetchMessages(String conversationId) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final me = await _me();
    final res = await _client
        .from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(500);
    return (res as List).whereType<Map<dynamic, dynamic>>().map((row) {
      final m = Map<String, dynamic>.from(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      return DirectMessage.fromJson(m, myId: me);
    }).toList();
  }

  Future<DirectMessage> sendMessage(String conversationId, String text) async {
    if (!_ready) throw StateError('Backend não configurado.');
    final me = await _me();
    final res = await _client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': me,
          'text': text,
        })
        .select()
        .single();
    _notifyMessageReceived(conversationId, me, text);
    return DirectMessage.fromJson(
      Map<String, dynamic>.from(res as Map),
      myId: me,
    );
  }

  /// Notificação real de nova mensagem para o outro participante da conversa
  /// (evento verdadeiro do sistema de DMs, nunca dado falso).
  Future<void> _notifyMessageReceived(
    String conversationId,
    String me,
    String text,
  ) async {
    try {
      final conv = await _client
          .from('conversations')
          .select('user_a_id,user_b_id')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return;
      final a = conv['user_a_id'] as String? ?? '';
      final b = conv['user_b_id'] as String? ?? '';
      final peer = a == me ? b : a;
      if (peer.isEmpty || peer == me) return;
      final preview = text.length > 140 ? '${text.substring(0, 140)}…' : text;
      await _client.from('notifications').insert({
        'user_id': peer,
        'actor_id': me,
        'type': 'message',
        'ref_id': conversationId,
        'message': preview,
      });
    } catch (_) {}
  }

  /// Marca como lidas as mensagens da conversa (RPC security definer validada).
  Future<void> markRead(String conversationId) async {
    if (!_ready) return;
    try {
      await _client.rpc(
        'mark_messages_read',
        params: {'conv_id': conversationId},
      );
    } catch (_) {}
  }

  /// Total de mensagens não lidas do usuário (RPC security definer).
  Future<int> unreadCount() async {
    if (!_ready) return 0;
    try {
      final res = await _client.rpc('unread_message_count');
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Realtime: novas mensagens em uma conversa da qual sou participante.
  RealtimeChannel subscribeToMessages(
    void Function(DirectMessage msg) onMessage,
  ) {
    return _client
        .channel('dm-messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) {
            final m = Map<String, dynamic>.from(p.newRecord);
            final sender = m['sender_id'] as String? ?? '';
            onMessage(DirectMessage.fromJson(m, myId: sender));
          },
        )
        .subscribe();
  }

  /// Realtime: conversas novas/atualizadas (para atualizar a lista).
  RealtimeChannel subscribeToConversations(void Function() onChanged) {
    return _client
        .channel('dm-conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  Future<bool> isBlocked(String peerId) async {
    try {
      final blocked = await AccountService.instance.fetchBlockedIds();
      return blocked.contains(peerId);
    } catch (_) {
      return false;
    }
  }

  Future<void> blockUser(String userId) =>
      AccountService.instance.blockUser(userId);

  Future<void> unblockUser(String userId) =>
      AccountService.instance.unblockUser(userId);

  Future<void> reportConversation(
    String conversationId,
    String reason,
    String details,
  ) {
    return SocialService.instance.reportItem(
      targetId: conversationId,
      targetType: 'conversation',
      reason: reason,
      details: details,
    );
  }
}
