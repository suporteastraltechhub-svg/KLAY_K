// Modelos de mensagens privadas (DMs) do KLAY K.
// Fontes reais: tabelas `conversations` e `messages` (backend Supabase).

class Conversation {
  final String id;
  final String userAId;
  final String userBId;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final String? peerId;
  final String? peerName;
  final String? peerUsername;
  final String? peerAvatar;
  final bool peerVerified;
  final int unread;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    required this.userAId,
    required this.userBId,
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastSenderId,
    this.peerId,
    this.peerName,
    this.peerUsername,
    this.peerAvatar,
    this.peerVerified = false,
    this.unread = 0,
    required this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? peer;
    if (json['peer'] is Map) {
      peer = Map<String, dynamic>.from(json['peer'] as Map);
    }
    return Conversation(
      id: json['id'] as String? ?? '',
      userAId: json['user_a_id'] as String? ?? '',
      userBId: json['user_b_id'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'] as String)?.toLocal()
          : null,
      lastSenderId: json['last_sender_id'] as String?,
      peerId: json['peer_id'] as String?,
      peerName: peer?['display_name'] as String?,
      peerUsername: peer?['username'] as String?,
      peerAvatar: peer?['avatar_url'] as String?,
      peerVerified: peer?['is_verified'] as bool? ?? false,
      unread: (json['unread'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}

class DirectMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime? readAt;
  final bool deleted;
  final DateTime createdAt;
  final bool isMine;

  const DirectMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    this.readAt,
    this.deleted = false,
    required this.createdAt,
    required this.isMine,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json, {String? myId}) {
    final senderId = json['sender_id'] as String? ?? '';
    return DirectMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: senderId,
      text: json['text'] as String? ?? '',
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)?.toLocal()
          : null,
      deleted: json['deleted'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now(),
      isMine: senderId.isNotEmpty && senderId == myId,
    );
  }
}
