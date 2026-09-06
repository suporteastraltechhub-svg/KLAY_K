import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/moment_models.dart';
import 'supabase_service.dart';

/// Camada de acesso aos Momentos (território Momentos) do KLAY K.
///
/// Centraliza o feed efémero (RPC `moment_feed`), criação, exclusão e os meus
/// momentos (RPC `moments_my_ids`). Nada é persistido sem backend real.
class MomentService {
  MomentService._();

  static final MomentService instance = MomentService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  String? get _myId => SupabaseService.instance.currentUser?.id;

  /// Feed de momentos ativos (não expirados), mais recentes primeiro.
  Future<List<KlayKMoment>> fetchFeed({int limit = 50}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('moment_feed', params: {'p_limit': limit});
      final rows = res as List? ?? const [];
      // Amplía cada row com dados reais do autor (join nidificado).
      final authorIds = rows.whereType<Map>()
          .map((r) => r['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      Map<String, Map<String, dynamic>> profiles = const {};
      if (authorIds.isNotEmpty) {
        final pRes = await _db
            .from('profiles')
            .select('id, display_name, username, avatar_url, is_verified')
            .inFilter('id', authorIds);
        profiles = {
          for (final p in (pRes as List? ?? const []).whereType<Map>())
            (p['id']?.toString() ?? ''): Map<String, dynamic>.from(
              p.map((k, v) => MapEntry(k.toString(), v)),
            ),
        };
      }
      final myId = _myId;
      return rows.whereType<Map>().map((r) {
        final uid = r['user_id']?.toString() ?? '';
        final author = Map<String, dynamic>.from(
          (profiles[uid] ?? const {}).map((k, v) => MapEntry(k.toString(), v)),
        );
        final enriched = Map<String, dynamic>.from(
          r.map((k, v) => MapEntry(k.toString(), v)),
        );
        enriched['profiles'] = author;
        return KlayKMoment.fromJson(enriched, myId: myId);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Momentos ativos criados pelo usuário logado (para o hub "Meu KLAY K").
  Future<List<KlayKMoment>> fetchMyMoments({int limit = 20}) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final idsRes = await _db.rpc('moments_my_ids', params: {});
      final ids = (idsRes as List? ?? const [])
          .whereType<Map>()
          .map((r) => r['moment_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return const [];
      final res = await _db
          .from('moments')
          .select('*, profiles:user_id(display_name, username, avatar_url, is_verified)')
          .inFilter('id', ids)
          .order('created_at', ascending: false)
          .limit(limit);
      final myId = _myId;
      return (res as List? ?? const [])
          .whereType<Map>()
          .map((r) => KlayKMoment.fromJson(
                Map<String, dynamic>.from(r.map((k, v) => MapEntry(k.toString(), v))),
                myId: myId,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Cria um momento com duração definida (default 24h). Retorna o objeto.
  Future<KlayKMoment> create({
    required String text,
    String? imageUrl,
    String? sticker,
    Duration lifetime = const Duration(hours: 24),
  }) async {
    final user = await SupabaseService.instance.ensureAuthenticated();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Digite algo para publicar seu momento.');
    }
    final res = await _db.from('moments').insert({
      'user_id': user.id,
      'text': trimmed,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (sticker != null && sticker.isNotEmpty) 'sticker': sticker,
      'expires_at': DateTime.now().add(lifetime).toUtc().toIso8601String(),
    }).select('id').single();
    final id = res['id']?.toString() ?? '';
    return KlayKMoment(
      id: id,
      userId: user.id,
      text: trimmed,
      imageUrl: imageUrl ?? '',
      sticker: sticker ?? '',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(lifetime),
      isMine: true,
    );
  }

  /// Exclui um momento (somente o dono, RLS protege).
  Future<void> delete(String momentId) async {
    await SupabaseService.instance.ensureAuthenticated();
    await _db.from('moments').delete().eq('id', momentId);
  }
}