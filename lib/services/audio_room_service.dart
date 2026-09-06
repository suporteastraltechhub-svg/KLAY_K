import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/audio_room_models.dart';
import 'live_kit_service.dart';
import 'supabase_service.dart';

/// Camada de acesso às Salas de Voz (território Áudio) do KLAY K.
///
/// Centraliza descoberta (com filtros de categoria), categorias, criação e
/// a conexão real via LiveKit (só áudio). Segue o padrão
/// `XxxService.instance` do projeto.
class AudioRoomService {
  AudioRoomService._();

  static final AudioRoomService instance = AudioRoomService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  String? get _myId => SupabaseService.instance.currentUser?.id;

  LiveKitService get _liveKit => LiveKitService.instance;

  /// Salas de voz ativas, opcionalmente filtradas por categoria/busca.
  Future<List<AudioRoom>> fetchRooms({
    String? query,
    String? category,
    int limit = 40,
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      var req = _db
          .from('audio_rooms')
          .select('*, profiles:owner_id(display_name, username, avatar_url)')
          .eq('status', 'live')
          .eq('is_public', true);
      if (category != null && category.isNotEmpty) {
        req = req.eq('category', category);
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        req = req.or('title.ilike.%$q%,description.ilike.%$q%');
      }
      final res = req.order('created_at', ascending: false).limit(limit);
      return _toRooms(res);
    } catch (_) {
      return const [];
    }
  }

  /// Salas de voz do usuário atual que estão ao vivo (via `audio_rooms_my_ids`).
  Future<List<AudioRoom>> fetchMyAudioRooms({int limit = 20}) async {
    final uid = _myId;
    if (!SupabaseService.instance.isConfigured || uid == null || uid.isEmpty) {
      return const [];
    }
    try {
      final idsRows = await _db.rpc('audio_rooms_my_ids', params: {});
      final ids = (idsRows as List? ?? const [])
          .whereType<Map>()
          .map((r) => r['room_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return const [];
      final res = await _db
          .from('audio_rooms')
          .select('*, profiles:owner_id(display_name, username, avatar_url)')
          .inFilter('id', ids)
          .order('created_at', ascending: false)
          .limit(limit);
      return _toRooms(res);
    } catch (_) {
      return const [];
    }
  }

  /// Categorias com contagem real de salas ativas.
  Future<List<AudioRoomCategory>> fetchCategories() async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('audio_room_categories', params: {});
      return (res as List)
          .whereType<Map>()
          .map((r) => AudioRoomCategory(
                name: r['category']?.toString() ?? '',
                count: (r['cnt'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Cria uma sala de voz no backend e conecta o dono via LiveKit (só áudio).
  Future<AudioRoom> createAndJoin({
    required String title,
    String description = '',
    String category = '',
    bool joinWithMic = true,
  }) async {
    final res = await SupabaseService.instance.createAudioRoom(
      title: title,
      description: description,
      category: category,
    );
    await _liveKit.startAudioRoom(
      roomName: res.roomName,
      withMic: joinWithMic,
    );
    return AudioRoom(
      id: res.audioRoomId,
      title: title,
      description: description,
      category: category,
      roomName: res.roomName,
      ownerId: _myId ?? '',
      iOwnIt: true,
    );
  }

  /// Entra numa sala como speaker (publica mic) ou listener (só ouve).
  Future<void> joinRoom(AudioRoom room, {required bool asSpeaker}) async {
    final name = kAppIdentity.displayName.isNotEmpty
        ? kAppIdentity.displayName
        : kAppIdentity.username;
    if (asSpeaker) {
      await _liveKit.connectToVoiceRoomAsSpeaker(
        roomName: room.roomName,
        displayName: name,
      );
    } else {
      await _liveKit.connectToVoiceRoomAsListener(
        roomName: room.roomName,
        displayName: name,
      );
    }
  }

  /// Encerra uma sala (somente o dono) e desconecta.
  Future<void> endRoom(AudioRoom room) async {
    try {
      await SupabaseService.instance.endAudioRoom(room.id);
    } catch (_) {
      // Encerra local mesmo se o backend falhar pontualmente.
    }
    await _liveKit.disconnectFromLive();
  }

  /// Alterna o microfone do participante local.
  Future<void> toggleMicrophone({required bool enabled}) async {
    if (enabled) {
      await _liveKit.publishMicrophone();
    } else {
      await _liveKit.stopMicrophone();
    }
  }

  List<AudioRoom> _toRooms(Object? res) {
    final myId = _myId ?? '';
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((r) {
          final room = AudioRoom.fromJson(
            Map<String, dynamic>.from(r.map((k, v) => MapEntry(k.toString(), v))),
          );
          final isMine = myId.isNotEmpty && myId == room.ownerId;
          return AudioRoom(
            id: room.id,
            title: room.title,
            slug: room.slug,
            description: room.description,
            category: room.category,
            roomName: room.roomName,
            ownerId: room.ownerId,
            ownerDisplayName: room.ownerDisplayName,
            ownerUsername: room.ownerUsername,
            ownerAvatarUrl: room.ownerAvatarUrl,
            participantCount: room.participantCount,
            speakerCount: room.speakerCount,
            isPublic: room.isPublic,
            iOwnIt: isMine,
          );
        })
        .toList();
  }
}