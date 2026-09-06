import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_models.dart';
import '../services/content_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import '../widgets/verified_badge.dart';
import '../design/klayk_design.dart';
import 'notification_prefs_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Central de notificações do KLAY K. Alimentada pela tabela real
/// `public.notifications` (curtidas, comentários, seguidores, lives etc.).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<AppNotification> _items = [];
  final _filter = ValueNotifier<String>('Todas');
  RealtimeChannel? _realtime;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    final c = _realtime;
    if (c != null) SupabaseService.instance.removeChannel(c);
    _filter.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    final sp = SupabaseService.instance;
    if (!sp.isConfigured || sp.client.auth.currentUser == null) return;
    try {
      _realtime = sp.subscribeToNotifications((record) {
        if (!mounted) return;
        // Nova notificação chegou: atualiza a lista preservando as já lidas.
        _prependNew(record);
      });
    } catch (_) {
      // Sem sessão/realtime indisponível — a lista continua funcionando.
    }
  }

  Future<void> _prependNew(Map<String, dynamic> record) async {
    final json = Map<String, dynamic>.from(
      record.map((k, v) => MapEntry(k.toString(), v)),
    );
    final actorId = json['actor_id']?.toString();
    if (actorId != null && actorId.isNotEmpty) {
      final actor = await SupabaseService.instance.profileFor(actorId);
      if (actor != null) {
        json['actor'] = {
          'display_name': actor['display_name'],
          'username': actor['username'],
          'avatar_url': actor['avatar_url'],
        };
      }
    }
    if (!mounted) return;
    setState(() {
      _items = [AppNotification.fromJson(json), ..._items];
    });
  }

  Future<void> _load() async {
    try {
      final items = await ContentService.instance.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await SupabaseService.instance.client.rpc('mark_all_notifications_read');
    } catch (_) {}
    await _load();
  }

  void _openPrefs() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotificationPrefsScreen(),
      ),
    );
  }

  Future<void> _openOne(AppNotification n) async {
    if (!n.read) {
      await ContentService.instance.markOneNotificationRead(n.id);
    }
    if (!mounted) return;
    setState(() {
      _items = [
        for (final it in _items)
          if (it.id == n.id)
            AppNotification(
              id: it.id,
              userId: it.userId,
              actorId: it.actorId,
              type: it.type,
              refId: it.refId,
              message: it.message,
              read: true,
              createdAt: it.createdAt,
              actor: it.actor,
            )
          else
            it,
      ];
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _load();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.comment_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      case 'live':
        return Icons.sensors_rounded;
      case 'mention':
        return Icons.alternate_email_rounded;
      case 'verification':
        return Icons.verified_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'like':
        return const Color(0xFFFF4D6A);
      case 'comment':
        return Colors.cyanAccent;
      case 'follow':
        return const Color(0xFF4CAF50);
      case 'live':
        return const Color(0xFFFF5722);
      case 'verification':
        return _kAccent;
      default:
        return Colors.amberAccent;
    }
  }

  String _titleFor(AppNotification n) {
    final name = n.actor?.name ?? 'Alguém';
    switch (n.type) {
      case 'like':
        return '$name curtiu seu vídeo';
      case 'comment':
        return '$name comentou: ${n.message.isNotEmpty ? n.message : 'no seu vídeo'}';
      case 'follow':
        return '$name começou a seguir você';
      case 'live':
        return '$name entrou ao vivo';
      case 'mention':
        return '$name mencionou você';
      case 'verification':
        return n.message.isNotEmpty ? n.message : 'Seu perfil de verificação';
      default:
        return n.message.isNotEmpty ? n.message : name;
    }
  }

  Widget _titleWidget(AppNotification n, bool unread) {
    final baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
    );
    final text = _titleFor(n);
    final actor = n.actor;
    if (actor == null || !actor.isVerified) return Text(text, style: baseStyle);
    final name = actor.name;
    if (!text.startsWith(name)) return Text(text, style: baseStyle);
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: name),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: 3),
              child: VerifiedBadge(size: 12),
            ),
          ),
          if (text.length > name.length)
            TextSpan(text: text.substring(name.length)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays < 7) return 'há ${diff.inDays} d';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text(
          'Notificações',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openPrefs,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Preferências',
          ),
          IconButton(
            onPressed: _markRead,
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Marcar como lidas',
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _filterChip('Todas', 'all'),
                _filterChip('Curtidas', 'like'),
                _filterChip('Comentários', 'comment'),
                _filterChip('Seguidores', 'follow'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const KlaykListSkeleton()
                : _items.isEmpty
                    ? const KlaykEmptyState(
                        icon: Icons.notifications_off_outlined,
                        title: 'Nenhuma notificação ainda',
                        message: 'Quando alguém curtir, comentar, seguir ou '
                            'mencionar você, aparece aqui.',
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        color: _kAccent,
                        child: ValueListenableBuilder<String>(
                          valueListenable: _filter,
                          builder: (context, filter, _) {
                            final visible = filter == 'all'
                                ? _items
                                : _items
                                    .where((n) =>
                                        _typeGroup(n.type) == filter)
                                    .toList();
                            if (visible.isEmpty) {
                              return ListView(children: const [
                                SizedBox(height: 160),
                                Center(
                                  child: Text('Nada nesta categoria',
                                      style:
                                          TextStyle(color: Colors.white54)),
                                ),
                              ]);
                            }
                            return _groupedList(visible);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _typeGroup(String type) {
    if (type == 'like') return 'like';
    if (type == 'comment' || type == 'mention') return 'comment';
    if (type == 'follow') return 'follow';
    return 'other';
  }

  String _sectionKey(DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (diff < 7) {
      const dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
      return dias[t.weekday - 1];
    }
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  Widget _groupedList(List<AppNotification> items) {
    final groups = <String, List<AppNotification>>{};
    for (final n in items) {
      groups.putIfAbsent(_sectionKey(n.createdAt), () => []).add(n);
    }
    final slivers = <Widget>[];
    final order = ['Hoje', 'Ontem', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        if (ia != -1 && ib != -1) return ia - ib;
        if (ia != -1) return -1;
        if (ib != -1) return 1;
        return b.compareTo(a);
      });
    for (final k in keys) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ));
      slivers.add(SliverList.builder(
        itemCount: groups[k]!.length,
        itemBuilder: (context, i) => _tile(groups[k]![i]),
      ));
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: slivers,
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ValueListenableBuilder<String>(
        valueListenable: _filter,
        builder: (context, current, _) {
          return KlayKChip(
            label: label,
            selected: current == value,
            onTap: () => _filter.value = value,
          );
        },
      ),
    );
  }

  Widget _tile(AppNotification n) {
    final unread = !n.read;
    return InkWell(
      onTap: () => _openOne(n),
      child: Container(
        color: unread
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF1E1B2E),
                  backgroundImage: n.actor?.avatarUrl != null &&
                          n.actor!.avatarUrl!.isNotEmpty
                      ? NetworkImage(n.actor!.avatarUrl!)
                      : null,
                  child: n.actor?.avatarUrl == null || n.actor!.avatarUrl!.isEmpty
                      ? const Icon(Icons.person, color: Colors.white54)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _colorFor(n.type),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_iconFor(n.type), size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _titleWidget(n, unread),
                  const SizedBox(height: 3),
                  Text(
                    _timeAgo(n.createdAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: _kAccent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
