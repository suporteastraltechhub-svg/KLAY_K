import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/klayk_live_models.dart';
import '../models/post_models.dart';
import '../services/content_service.dart';
import '../services/live_kit_service.dart';
import '../services/message_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import '../widgets/verified_badge.dart';
import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import 'live_room_screen.dart';
import 'messages_screen.dart';
import 'notification_prefs_screen.dart';
import 'profile/user_profile_screen.dart';
import 'profile/video_preview_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1C1C26);
const Color _kLiveRed = Color(0xFFFF4757);

/// Central de notificações do KLAY K. Alimentada PELOS EVENTOS REAIS do
/// sistema (`public.notifications`): curtidas, comentários, respostas,
/// menções, compartilhamentos, seguidores, mensagens, Lives, jogos e
/// recompensas. Nunca cria conteúdo artificial — apenas organiza o que o
/// backend recebeu.
class NotificationsScreen extends StatefulWidget {
  /// Quando `true`, renderiza apenas o conteúdo (sem Scaffold/AppBar) para
  /// ser embutido no hub de Mensagens (aba NOTIFICAÇÕES).
  final bool embedded;

  /// Notifica quantas notificações não lidas existem (dado real do backend).
  /// Usado pelo hub para o badge das abas e pela badge da navegação inferior.
  final ValueChanged<int>? onUnreadChanged;

  const NotificationsScreen({
    super.key,
    this.embedded = false,
    this.onUnreadChanged,
  });

  @override
  State<NotificationsScreen> createState() => NotificationsScreenState();
}

class NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<AppNotification> _items = [];
  final _filter = ValueNotifier<String>('all');
  RealtimeChannel? _realtime;

  /// Contagem real de não lidas, repassada para o hub quando muda.
  void _emitUnread() {
    var c = 0;
    for (final n in _items) {
      if (!n.read) c++;
    }
    widget.onUnreadChanged?.call(c);
  }

  /// Recarrega a lista do backend (usado pelo hub após ações globais).
  Future<void> refresh() => _load();

  /// Marca todas como lidas (RPC real) e recarrega.
  Future<void> markAllRead() => _markRead();

  /// Abre as preferências de notificação.
  Future<void> openPrefs() async => _openPrefs();

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
    _emitUnread();
  }

  Future<void> _load() async {
    try {
      final items = await ContentService.instance.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      _emitUnread();
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationPrefsScreen()));
  }

  // ---------------------------------------------------------------------------
  // Agrupamento inteligente: eventos semelhantes ao mesmo conteúdo viram um
  // único card (ex.: "João, Maria e outras 8 pessoas curtiram seu vídeo").
  // Mensagens, presentes, Lives e conquistas permanecem individuais.
  // ---------------------------------------------------------------------------

  bool _groupableType(String type) =>
      type == 'like' ||
      type == 'comment' ||
      type == 'mention' ||
      type == 'share' ||
      type == 'comment_reply';

  static const int _groupWindowMinutes = 45;
  static const int _maxGroupSize = 6;

  List<_NotifDisplayItem> _buildDisplay(List<AppNotification> source) {
    final sorted = [...source]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final out = <_NotifDisplayItem>[];
    for (final n in sorted) {
      if (_groupableType(n.type) &&
          n.refId != null &&
          n.refId!.isNotEmpty &&
          out.isNotEmpty) {
        final last = out.last;
        final prev = last.items.last;
        final sameBatch =
            prev.type == n.type &&
            last.refId == n.refId &&
            n.createdAt.difference(last.createdAt).abs().inMinutes <=
                _groupWindowMinutes;
        if (sameBatch && last.items.length < _maxGroupSize) {
          last.items.add(n);
          last.read = last.read && n.read;
          continue;
        }
      }
      out.add(_NotifDisplayItem([n], n.type, n.refId, n.createdAt, n.read));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Navegação real para o conteúdo da notificação
  // ---------------------------------------------------------------------------

  Future<void> _openDisplayItem(_NotifDisplayItem item) async {
    final ids = item.items.where((n) => !n.read).map((n) => n.id).toList();
    if (ids.isNotEmpty) {
      for (final id in ids) {
        ContentService.instance.markOneNotificationRead(id);
      }
      setState(() {
        _items = [
          for (final n in _items)
            ids.contains(n.id)
                ? AppNotification(
                    id: n.id,
                    userId: n.userId,
                    actorId: n.actorId,
                    type: n.type,
                    refId: n.refId,
                    message: n.message,
                    read: true,
                    createdAt: n.createdAt,
                    actor: n.actor,
                  )
                : n,
        ];
      });
      _emitUnread();
    }
    await _navigateFor(item.type, item.refId, item.items.first.actorId);
  }

  Future<void> _navigateFor(String type, String? refId, String? actorId) async {
    switch (type) {
      case 'like':
      case 'comment':
      case 'comment_reply':
      case 'mention':
      case 'share':
        await _openPost(refId);
        break;
      case 'message':
        await _openConversation(actorId);
        break;
      case 'live':
        await _openLive(refId);
        break;
      case 'follow':
      case 'live_viewer':
      case 'live_end':
      case 'record':
      case 'reward':
        _openProfile(actorId);
        break;
      default:
        break;
    }
  }

  Future<void> _openPost(String? postId) async {
    if (postId == null || postId.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final row = await SupabaseService.instance.client
          .from('posts')
          .select(
            '*, profiles:user_id(display_name, username, avatar_url, is_verified)',
          )
          .eq('id', postId)
          .maybeSingle();
      if (row == null) {
        _snack(l10n.notifVideoNotFound);
        return;
      }
      if (!mounted) return;
      final post = FeedPost.fromJson(
        Map<String, dynamic>.from(
          (row as Map).map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => VideoPreviewScreen(post: post)));
    } catch (_) {
      _snack(l10n.notifVideoOpenFail);
    }
  }

  Future<void> _openLive(String? liveId) async {
    if (liveId == null || liveId.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final row = await SupabaseService.instance.client
          .from('lives')
          .select(
            '*, profiles:streamer_id(display_name, username, avatar_url, is_verified)',
          )
          .eq('id', liveId)
          .maybeSingle();
      if (row == null) {
        _snack(l10n.notifLiveNotFound);
        return;
      }
      final live = RealLive.fromJson(
        Map<String, dynamic>.from(
          (row as Map).map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
      if (live.status != 'live') {
        _snack(l10n.notifLiveEnded);
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveRoomScreen(live: live, role: LiveRole.viewer),
        ),
      );
    } catch (_) {
      _snack(l10n.notifLiveOpenFail);
    }
  }

  Future<void> _openConversation(String? actorId) async {
    if (actorId == null || actorId.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final conv = await MessageService.instance.getOrCreateConversation(
        actorId,
      );
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
    } catch (_) {
      _snack(l10n.notifChatOpenFail);
    }
  }

  void _openProfile(String? userId) {
    if (userId == null || userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _load();
  }

  // ---------------------------------------------------------------------------
  // Mapa visual (ícone + cor por tipo)
  // ---------------------------------------------------------------------------

  IconData _iconFor(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.comment_rounded;
      case 'comment_reply':
        return Icons.reply_rounded;
      case 'mention':
        return Icons.alternate_email_rounded;
      case 'share':
        return Icons.share_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'live':
        return Icons.sensors_rounded;
      case 'live_viewer':
        return Icons.visibility_rounded;
      case 'live_end':
        return Icons.videocam_off_rounded;
      case 'record':
        return Icons.emoji_events_rounded;
      case 'reward':
        return Icons.workspace_premium_rounded;
      case 'gift':
        return Icons.card_giftcard_rounded;
      case 'sale':
        return Icons.storefront_rounded;
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
      case 'comment_reply':
        return Colors.cyanAccent;
      case 'mention':
        return _kAccent;
      case 'share':
        return const Color(0xFF38BDF8);
      case 'follow':
        return const Color(0xFF4CAF50);
      case 'message':
        return const Color(0xFF2DD4BF);
      case 'live':
      case 'live_end':
        return _kLiveRed;
      case 'live_viewer':
        return const Color(0xFFFFB020);
      case 'record':
        return const Color(0xFFFFC53D);
      case 'reward':
      case 'gift':
        return const Color(0xFFE879F9);
      case 'sale':
        return const Color(0xFF22C55E);
      case 'verification':
        return _kAccent;
      default:
        return Colors.amberAccent;
    }
  }

  String _singleTitle(AppNotification n) {
    final l10n = AppLocalizations.of(context)!;
    final name = n.actor?.name ?? l10n.notifSomeone;
    switch (n.type) {
      case 'like':
        return l10n.notifLikedVideo(name);
      case 'comment':
        return n.message.isNotEmpty
            ? l10n.notifCommentedMsg(name, n.message)
            : l10n.notifCommentedNoMsg(name);
      case 'comment_reply':
        return l10n.notifReplied(name);
      case 'mention':
        return l10n.notifMentioned(name);
      case 'share':
        return l10n.notifShared(name);
      case 'follow':
        return l10n.notifFollowed(name);
      case 'message':
        return l10n.notifSentMessage(name);
      case 'live':
        return l10n.notifStartedLive(name);
      case 'live_viewer':
        return l10n.notifJoinedLive(name);
      case 'live_end':
        return n.message.isNotEmpty ? n.message : l10n.notifLiveEndedMsg;
      case 'record':
        return n.message.isNotEmpty
            ? l10n.notifRecord(n.message)
            : l10n.notifRecordFallback;
      case 'reward':
        return n.message.isNotEmpty
            ? l10n.notifReward(n.message)
            : l10n.notifRewardReceived;
      case 'gift':
        return n.message.isNotEmpty ? n.message : l10n.notifGiftFallback;
      case 'sale':
        return l10n.notifSale;
      case 'verification':
        return n.message.isNotEmpty ? n.message : l10n.notifVerifFallback;
      default:
        return n.message.isNotEmpty ? n.message : name;
    }
  }

  String _groupTitle(_NotifDisplayItem item) {
    final l10n = AppLocalizations.of(context)!;
    final names = <String>[];
    for (final it in item.items) {
      final nm = it.actor?.name;
      if (nm != null && !names.contains(nm)) names.add(nm);
      if (names.length == 2) break;
    }
    final other = item.items.length - names.length;
    final joined = names.join(', ');
    final base = joined.isEmpty
        ? (other > 0
              ? l10n.notifOtherPeopleCount(other)
              : l10n.notifPeopleFallback)
        : joined;
    switch (item.type) {
      case 'like':
        return other > 0
            ? l10n.notifGroupLiked(base, other)
            : l10n.notifGroupLikedSingle(base);
      case 'mention':
        return other > 0
            ? l10n.notifGroupMentioned(base, other)
            : l10n.notifGroupMentionedSingle(base);
      case 'share':
        return other > 0
            ? l10n.notifGroupShared(base, other)
            : l10n.notifGroupSharedSingle(base);
      case 'comment_reply':
      case 'comment':
        return other > 0
            ? l10n.notifGroupCommented(base, other)
            : l10n.notifGroupCommentedSingle(base);
      default:
        return l10n.notifGroupInteractions(base, item.items.length - 1);
    }
  }

  Widget _titleForDisplay(_NotifDisplayItem item, bool unread) {
    final n = item.items.first;
    final baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      height: 1.3,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
    );
    if (item.items.length > 1) {
      return Text(_groupTitle(item), style: baseStyle);
    }
    final text = _singleTitle(n);
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
    final l10n = AppLocalizations.of(context)!;
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return l10n.notifTimeNow;
    if (diff.inMinutes < 60) return l10n.notifTimeMin(diff.inMinutes);
    if (diff.inHours < 24) return l10n.notifTimeH(diff.inHours);
    if (diff.inDays < 7) return l10n.notifTimeD(diff.inDays);
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Estrutura visual
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = _content();
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          l10n.notifications,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openPrefs,
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.notifPrefs,
          ),
          IconButton(
            onPressed: _markRead,
            icon: const Icon(Icons.done_all_rounded),
            tooltip: l10n.notifMarkRead,
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _content() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _filterChip(l10n.notifAll, 'all'),
              _filterChip(l10n.notifLikes, 'like'),
              _filterChip(l10n.notifComments, 'comment'),
              _filterChip(l10n.notifFollowers, 'follow'),
              _filterChip(l10n.notifWarnings, 'other'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const KlaykListSkeleton()
              : _items.isEmpty
              ? KlaykEmptyState(
                  icon: Icons.notifications_off_outlined,
                  title: l10n.notifEmptyTitle,
                  message: l10n.notifEmptyBody,
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: _kAccent,
                  backgroundColor: _kCard,
                  child: ValueListenableBuilder<String>(
                    valueListenable: _filter,
                    builder: (context, filter, _) {
                      final visible = filter == 'all'
                          ? _items
                          : _items
                                .where((n) => _typeGroup(n.type) == filter)
                                .toList();
                      if (visible.isEmpty) {
                        return ListView(
                          children: [
                            const SizedBox(height: 160),
                            Center(
                              child: Text(
                                l10n.notifCategoryEmpty,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ),
                          ],
                        );
                      }
                      return _groupedList(visible);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String _typeGroup(String type) {
    if (type == 'like') return 'like';
    if (type == 'comment' ||
        type == 'comment_reply' ||
        type == 'mention' ||
        type == 'share') {
      return 'comment';
    }
    if (type == 'follow') return 'follow';
    return 'other';
  }

  String _sectionKey(DateTime t) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return l10n.notifToday;
    if (diff == 1) return l10n.notifYesterday;
    if (diff < 7) return l10n.notifThisWeek;
    return l10n.notifOlder;
  }

  Widget _groupedList(List<AppNotification> items) {
    final l10n = AppLocalizations.of(context)!;
    final display = _buildDisplay(items);
    final groups = <String, List<_NotifDisplayItem>>{};
    for (final it in display) {
      groups.putIfAbsent(_sectionKey(it.createdAt), () => []).add(it);
    }
    final order = [
      l10n.notifToday,
      l10n.notifYesterday,
      l10n.notifThisWeek,
      l10n.notifOlder,
    ];
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        if (ia != -1 && ib != -1) return ia - ib;
        if (ia != -1) return -1;
        if (ib != -1) return 1;
        return 0;
      });
    final slivers = <Widget>[];
    for (final k in keys) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text(
              k,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      );
      slivers.add(
        SliverList.builder(
          itemCount: groups[k]!.length,
          itemBuilder: (context, i) => _tile(groups[k]![i]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(slivers: slivers),
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

  Widget _tile(_NotifDisplayItem item) {
    final unread = !item.read;
    final n = item.items.first;
    final grouped = item.items.length > 1;
    final isLive = item.type == 'live';
    return InkWell(
      onTap: () => _openDisplayItem(item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: unread
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.09)
              : const Color(0xFF15131E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: unread
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.04),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grouped) _groupAvatars(item) else _singleAvatar(n),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLive) ...[_liveBadge(n), const SizedBox(height: 4)],
                  _titleForDisplay(item, unread),
                  if (isLive && n.message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      n.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(item.createdAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 8, left: 6),
                decoration: BoxDecoration(
                  color: _kAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _kAccent.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _liveBadge(AppNotification n) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: _kLiveRed.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kLiveRed.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cell_tower_rounded, size: 10, color: _kLiveRed),
              const SizedBox(width: 3),
              Text(
                l10n.liveBadge,
                style: const TextStyle(
                  color: _kLiveRed,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _singleAvatar(AppNotification n) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF1E1B2E),
          backgroundImage:
              n.actor?.avatarUrl != null && n.actor!.avatarUrl!.isNotEmpty
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
              border: Border.all(color: const Color(0xFF15131E), width: 1.5),
            ),
            child: Icon(_iconFor(n.type), size: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _groupAvatars(_NotifDisplayItem item) {
    final actors = [
      for (final it in item.items)
        if (it.actor != null) it.actor!,
    ].take(3).toList();
    final size = actors.length;
    if (size == 1) return _singleAvatar(item.items.first);
    const avatarSize = 26.0;
    return SizedBox(
      width: 22 + size * avatarSize * 0.55,
      height: avatarSize + 8,
      child: Stack(
        children: [
          for (var i = 0; i < actors.length; i++)
            Positioned(
              left: i * avatarSize * 0.55,
              top: 0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF15131E), width: 2),
                ),
                child: CircleAvatar(
                  radius: avatarSize / 2,
                  backgroundColor: const Color(0xFF1E1B2E),
                  backgroundImage:
                      actors[i].avatarUrl != null &&
                          actors[i].avatarUrl!.isNotEmpty
                      ? NetworkImage(actors[i].avatarUrl!)
                      : null,
                  child:
                      actors[i].avatarUrl == null ||
                          actors[i].avatarUrl!.isEmpty
                      ? const Icon(
                          Icons.person,
                          color: Colors.white54,
                          size: 15,
                        )
                      : null,
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _colorFor(item.type),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF15131E), width: 1.5),
              ),
              child: Icon(_iconFor(item.type), size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Item de exibição da central: 1 notificação ou um grupo de interações
/// semelhantes ao mesmo conteúdo (agrupamento inteligente de Curtidas, etc.).
class _NotifDisplayItem {
  _NotifDisplayItem(
    this.items,
    this.type,
    this.refId,
    this.createdAt,
    this.read,
  );

  final List<AppNotification> items;
  final String type;
  final String? refId;
  final DateTime createdAt;
  bool read;
}
