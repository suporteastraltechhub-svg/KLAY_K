import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_models.dart';
import '../services/message_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import '../widgets/verified_badge.dart';
import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';

const Color _purple = Color(0xFF8B5CF6);
const Color _pink = Color(0xFFFF4D6A);

/// Lista real de conversas (DMs). Sem mocks: dados vêm do backend via
/// [MessageService]. Realtime atualiza a lista quando há novas conversas.
class RealMessagesScreen extends StatefulWidget {
  /// Quando `true`, renderiza apenas o conteúdo (sem Scaffold/AppBar) para
  /// ser embutido no hub de Mensagens (aba BATE-PAPOS).
  final bool embedded;

  /// Notifica quantas conversas têm mensagens não lidas (dado real do
  /// backend). Usado pelo hub para o badge das abas e navegação inferior.
  final ValueChanged<int>? onUnreadChanged;

  const RealMessagesScreen({
    super.key,
    this.embedded = false,
    this.onUnreadChanged,
  });

  @override
  State<RealMessagesScreen> createState() => RealMessagesScreenState();
}

class RealMessagesScreenState extends State<RealMessagesScreen> {
  final MessageService _svc = MessageService.instance;
  final List<Conversation> _convs = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;

  /// Soma real de não lidas nas conversas, repassada para o hub quando muda.
  void _emitUnread() {
    var c = 0;
    for (final cv in _convs) {
      c += cv.unread;
    }
    widget.onUnreadChanged?.call(c);
  }

  /// Recarrega a lista do backend (usado pelo hub após ações globais).
  Future<void> refresh() => _load();

  /// Fluxo de nova conversa (não lidas reais são atualizadas via realtime).
  Future<void> startNewConversation() => _startNew();

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!SupabaseService.instance.isConfigured) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = await _svc.fetchConversations();
      if (!mounted) return;
      setState(() {
        _convs
          ..clear()
          ..addAll(list);
        _loading = false;
      });
      _emitUnread();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _subscribe() {
    if (!SupabaseService.instance.isConfigured) return;
    _channel = _svc.subscribeToConversations(_load);
  }

  Future<void> _open(Conversation c) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final l10n = AppLocalizations.of(context)!;
    if (widget.embedded) return _buildBody();
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        title: Text(
          l10n.messagesTab,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: _purple),
            tooltip: l10n.newConversation,
            onPressed: _startNew,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _startNew() async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const NewConversationScreen()),
    );
    if (picked != null) {
      final peerId = picked['id'] as String?;
      if (peerId != null) {
        try {
          final c = await _svc.getOrCreateConversation(peerId);
          if (!mounted) return;
          await _open(c);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else {
      _load();
    }
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_error != null && _convs.isEmpty) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    if (_loading && _convs.isEmpty) {
      return const KlaykLoader();
    }
    if (_convs.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.messagesEmptyTitle,
        message: l10n.messagesEmptyBody,
        actionLabel: l10n.newConversation,
        onAction: _startNew,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kc(context).primary,
      child: ListView.separated(
        itemCount: _convs.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(color: kc(context).border, height: 1),
        ),
        itemBuilder: (context, index) {
          final c = _convs[index];
          final unread = c.unread > 0;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: kc(context).surfaceAlt,
                  backgroundImage: c.peerAvatar != null
                      ? NetworkImage(c.peerAvatar!)
                      : null,
                  child: c.peerAvatar == null
                      ? const Icon(Icons.person, color: Colors.white38)
                      : null,
                ),
                if (unread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kc(context).like,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        c.unread > 9 ? '9+' : '${c.unread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    c.peerName ?? l10n.user,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (c.peerVerified) ...[
                  const SizedBox(width: 4),
                  const VerifiedBadge(size: 14),
                ],
              ],
            ),
            subtitle: Text(
              c.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unread ? Colors.white70 : Colors.white38,
                fontSize: 13,
                fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            trailing: Text(
              _time(c.lastMessageAt),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            onTap: () => _open(c),
          );
        },
      ),
    );
  }

  String _time(DateTime? t) {
    if (t == null) return '';
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return l10n.notifTimeNow;
    if (d.inMinutes < 60) return l10n.msTimeMin(d.inMinutes);
    if (d.inHours < 24) return l10n.msTimeH(d.inHours);
    if (d.inDays == 1) return l10n.notifYesterday;
    if (d.inDays < 7) return l10n.msTimeD(d.inDays);
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }
}

/// Tela de uma conversa individual (DM real via MessageService + Realtime).
class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessageService _svc = MessageService.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<DirectMessage> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  String? _error;
  bool _blocked = false;
  String _myId = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final me = await SupabaseService.instance.ensureAuthenticated();
    if (!mounted) return;
    _myId = me.id;
    setState(() {});
    _blocked = await _svc.isBlocked(widget.conversation.peerId ?? '');
    _channel = _svc.subscribeToMessages(_onMessage);
    await _svc.markRead(widget.conversation.id);
    _load();
  }

  void _onMessage(DirectMessage m) {
    if (m.conversationId != widget.conversation.id) return;
    if (!mounted) return;
    setState(() {
      if (!_messages.any((x) => x.id == m.id)) _messages.add(m);
    });
    _scrollToBottom();
    if (m.senderId != _myId) {
      _svc.markRead(widget.conversation.id);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _svc.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _loading = false;
      });
      _scrollToBottom(animated: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: animated
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      final msg = await _svc.sendMessage(widget.conversation.id, text);
      if (!mounted) return;
      setState(() => _messages.add(msg));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openModeration() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: kc(context).surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_blocked ? Icons.block : Icons.block, color: _pink),
              title: Text(
                _blocked ? l10n.unblockUser : l10n.blockUser,
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                if (_blocked) {
                  await _svc.unblockUser(widget.conversation.peerId!);
                } else {
                  await _svc.blockUser(widget.conversation.peerId!);
                }
                if (mounted) {
                  setState(() => _blocked = !_blocked);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.flag_rounded, color: kc(context).primarySoft),
              title: Text(
                l10n.reportConversation,
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final reason = await _pickReportReason(ctx);
                if (reason != null) {
                  await _svc.reportConversation(
                    widget.conversation.id,
                    reason,
                    '',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.reportConversationSent)),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickReportReason(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    final reasons = [
      l10n.reportSpam,
      l10n.reportHarassment,
      l10n.reportOffensiveContent,
      l10n.reportImpostor,
      l10n.reportFraud,
      l10n.reportOther,
    ];
    return showModalBottomSheet<String>(
      context: ctx,
      backgroundColor: kc(ctx).surfaceAlt,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in reasons)
              ListTile(
                title: Text(r, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(c, r),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.surfaceAlt,
              backgroundImage: widget.conversation.peerAvatar != null
                  ? NetworkImage(widget.conversation.peerAvatar!)
                  : null,
              child: widget.conversation.peerAvatar == null
                  ? const Icon(Icons.person, color: Colors.white38, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.conversation.peerName ?? l10n.user,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.conversation.peerVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  Text(
                    '@${widget.conversation.peerUsername ?? ''}'
                    '${_blocked ? ' • ${l10n.blockedSuffix}' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onPressed: _openModeration,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_blocked) {
      return KlaykEmptyState(
        icon: Icons.block,
        title: l10n.blockedThisUserTitle,
        message: l10n.blockedThisUserBody,
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white54)),
      );
    }
    if (_loading && _messages.isEmpty) {
      return const KlaykLoader();
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final m = _messages[index];
              final mine = m.senderId == _myId;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: mine ? _purple : kc(context).surfaceAlt,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(m.text, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(
                        _hm(m.createdAt),
                        style: TextStyle(
                          color: mine ? Colors.white70 : Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 6,
              bottom: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: _purple,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.typeMessageHint,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: kc(context).surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  style: IconButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Escolha de usuário para iniciar nova conversa (busca real de perfis).
class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final SupabaseService _db = SupabaseService.instance;
  final TextEditingController _q = TextEditingController();
  final _searchDebounce = KlaykDebouncer(const Duration(milliseconds: 300));
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  void _onSearchChanged(String v) => _searchDebounce.run(() => _search(v));

  Future<void> _search(String v) async {
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _db.client
          .from('profiles')
          .select('id, display_name, username, avatar_url, is_verified')
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(20);
      if (!mounted) return;
      setState(() {
        _results = (res as List)
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (r) => Map<String, dynamic>.from(
                r.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bgElevated,
        title: Text(
          l10n.newConversation,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              style: const TextStyle(color: Colors.white),
              cursorColor: _purple,
              onChanged: _onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.searchUserHint,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: kc(context).surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const KlaykLoader()
                : _results.isEmpty
                ? KlaykEmptyState(
                    icon: Icons.search_off_rounded,
                    title: l10n.noResults,
                    message: l10n.noResultsBody,
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colors.surfaceAlt,
                          backgroundImage: r['avatar_url'] != null
                              ? NetworkImage(r['avatar_url'] as String)
                              : null,
                          child: r['avatar_url'] == null
                              ? const Icon(Icons.person, color: Colors.white38)
                              : null,
                        ),
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                r['display_name'] as String? ?? l10n.user,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            if (r['is_verified'] == true) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(size: 14),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '@${r['username'] ?? ''}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () => Navigator.of(context).pop(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
