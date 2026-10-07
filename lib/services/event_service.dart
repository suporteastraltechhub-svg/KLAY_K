import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event_models.dart';
import 'supabase_service.dart';

/// Camada de acesso ao sistema de Eventos públicos do KLAY K.
///
/// Centraliza descoberta (com filtros de categoria/busca), categorias,
/// RSVP (confirmar presença) e "meus eventos". Segue o padrão
/// `XxxService.instance` do projeto.
class EventService {
  EventService._();

  static final EventService instance = EventService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  bool get _configured => SupabaseService.instance.isConfigured;

  String? get _myId => SupabaseService.instance.currentUser?.id;

  /// Eventos públicos, opcionalmente filtrados por categoria/busca.
  Future<List<KlayKEvent>> fetchEvents({
    String? query,
    String? category,
    int limit = 40,
  }) async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      var req = _db.from('events').select('*').eq('is_public', true);
      if (category != null && category.isNotEmpty) {
        req = req.eq('category', category);
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        req = req.or('title.ilike.%$q%,description.ilike.%$q%');
      }
      final res = req.order('starts_at', ascending: true).limit(limit);
      return _toEvents(res, markGoing: false);
    } catch (_) {
      return const [];
    }
  }

  /// Eventos que o usuário confirmou presença (com flag `i_am_going`).
  Future<List<KlayKEvent>> fetchMyEvents() async {
    final uid = _myId;
    if (!_configured || uid == null || uid.isEmpty) return const [];
    try {
      final idsRows = await _db.rpc('event_my_ids', params: {});
      final ids = _toIds(idsRows);
      if (ids.isEmpty) return const [];
      final res = await _db
          .from('events')
          .select('*')
          .inFilter('id', ids)
          .order('starts_at', ascending: true);
      return _toEvents(res, markGoing: true);
    } catch (_) {
      return const [];
    }
  }

  /// Categorias com contagem real de eventos.
  Future<List<KlayKEventCategory>> fetchCategories() async {
    await SupabaseService.instance.ensureAuthenticated();
    try {
      final res = await _db.rpc('event_categories', params: {});
      return (res as List)
          .whereType<Map>()
          .map(
            (r) => KlayKEventCategory(
              name: r['category']?.toString() ?? '',
              count: (r['cnt'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Se o usuário confirmou presença num evento.
  Future<bool> isGoing(String eventId) async {
    final uid = _myId;
    if (!_configured || uid == null || uid.isEmpty) return false;
    try {
      final res = await _db.rpc(
        'event_rsvp_state',
        params: {'p_event_id': eventId},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Alterna presença do usuário (RSVP) e retorna o novo estado.
  Future<bool> toggleGoing(String eventId) async {
    final uid = _myId;
    if (!_configured || uid == null || uid.isEmpty) return false;
    try {
      final currently = await isGoing(eventId);
      if (currently) {
        await _db
            .from('event_rsvps')
            .delete()
            .eq('event_id', eventId)
            .eq('user_id', uid);
      } else {
        await _db.from('event_rsvps').insert({
          'event_id': eventId,
          'user_id': uid,
        });
      }
      return !currently;
    } catch (_) {
      return false;
    }
  }

  List<String> _toIds(Object? res) {
    return (res as List? ?? const [])
        .whereType<Map>()
        .map((r) => r['event_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  List<KlayKEvent> _toEvents(Object? res, {required bool markGoing}) {
    return (res as List? ?? const [])
        .whereType<Map>()
        .map(
          (r) => KlayKEvent.fromJson(
            Map<String, dynamic>.from(
              r.map((k, v) => MapEntry(k.toString(), v)),
            ),
          ).copyWith(iAmGoing: markGoing),
        )
        .toList();
  }
}
