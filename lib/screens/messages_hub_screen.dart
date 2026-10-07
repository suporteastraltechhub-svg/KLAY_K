import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../widgets/klay_live_widgets.dart';
import '../l10n/app_localizations.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';

/// Hub da aba MENSAGENS: duas áreas reais — NOTIFICAÇÕES e BATE-PAPOS.
///
/// Nada aqui é mockado: a aba de notificações lê `public.notifications` e a
/// de bate-papos lê as conversas reais (DMs) do backend, ambas com realtime.
/// As badges nas abas usam contagens reais de não lidas.
class MessagesHubScreen extends StatefulWidget {
  /// Sobe a soma real de não lidas (notificações + mensagens) para a badge
  /// da aba MENSAGENS na navegação inferior.
  final ValueChanged<int>? onUnreadChanged;

  const MessagesHubScreen({super.key, this.onUnreadChanged});

  @override
  State<MessagesHubScreen> createState() => _MessagesHubScreenState();
}

class _MessagesHubScreenState extends State<MessagesHubScreen> {
  static const int kNotifTab = 0;
  static const int kMessagesTab = 1;

  int _tab = kMessagesTab;
  int _notifUnread = 0;
  int _dmUnread = 0;

  final _notifKey = GlobalKey<NotificationsScreenState>();
  final _messagesKey = GlobalKey<RealMessagesScreenState>();

  void _onNotifUnread(int c) {
    if (_notifUnread != c) {
      setState(() => _notifUnread = c);
    }
    _emitTotal();
  }

  void _onDmUnread(int c) {
    if (_dmUnread != c) {
      setState(() => _dmUnread = c);
    }
    _emitTotal();
  }

  void _emitTotal() {
    widget.onUnreadChanged?.call(_notifUnread + _dmUnread);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kkBg,
      appBar: AppBar(
        backgroundColor: kkBg,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.messagesTab,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_tab == kNotifTab) ...[
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.notifPrefs,
              onPressed: () => _notifKey.currentState?.openPrefs(),
            ),
            IconButton(
              icon: const Icon(Icons.done_all_rounded),
              tooltip: l10n.notifMarkRead,
              onPressed: () => _notifKey.currentState?.markAllRead(),
            ),
          ],
          if (_tab == kMessagesTab)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: l10n.newConversation,
              onPressed: () =>
                  _messagesKey.currentState?.startNewConversation(),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildTabs(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                NotificationsScreen(
                  key: _notifKey,
                  embedded: true,
                  onUnreadChanged: _onNotifUnread,
                ),
                RealMessagesScreen(
                  key: _messagesKey,
                  embedded: true,
                  onUnreadChanged: _onDmUnread,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          KlayCategoryTab(
            label: l10n.sectionNotifications,
            selected: _tab == kNotifTab,
            onTap: () => setState(() => _tab = kNotifTab),
            badge: _notifUnread > 0
                ? KlayKBadge(count: _notifUnread, color: kkAccent)
                : null,
          ),
          const SizedBox(width: 8),
          KlayCategoryTab(
            label: l10n.chatsTab,
            selected: _tab == kMessagesTab,
            onTap: () => setState(() => _tab = kMessagesTab),
            badge: _dmUnread > 0
                ? KlayKBadge(count: _dmUnread, color: kkAccent)
                : null,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
