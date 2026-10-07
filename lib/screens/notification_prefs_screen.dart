import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/notif_prefs_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';

/// Preferências de notificação: categorias de evento + toggles persistidos no
/// backend (`notification_preferences`, via RPCs security definer). A flag
/// `push_enabled` prepara o futuro push real.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  NotificationPrefs? _prefs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await NotifPrefsService.instance.fetch();
    if (!mounted) return;
    setState(() => _prefs = prefs);
  }

  Future<void> _update(NotificationPrefs next) async {
    setState(() {
      _prefs = next;
      _saving = true;
    });
    final saved = await NotifPrefsService.instance.save(next);
    if (!mounted) return;
    setState(() {
      _prefs = saved;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final prefs = _prefs;
    return Scaffold(
      backgroundColor: kcolors(context).bg,
      appBar: AppBar(title: Text(l10n.notifPrefsTitle)),
      body: prefs == null
          ? const Center(child: KlaykLoader())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _toggle(
                    l10n.notifLikesTitle,
                    l10n.notifLikesSub,
                    Icons.thumb_up_rounded,
                    prefs.likes,
                    (v) => _update(prefs.copyWith(likes: v)),
                  ),
                  _toggle(
                    l10n.notifCommentsTitle,
                    l10n.notifCommentsSub,
                    Icons.chat_bubble_rounded,
                    prefs.comments,
                    (v) => _update(prefs.copyWith(comments: v)),
                  ),
                  _toggle(
                    l10n.notifRepliesTitle,
                    l10n.notifRepliesSub,
                    Icons.reply_rounded,
                    prefs.replies,
                    (v) => _update(prefs.copyWith(replies: v)),
                  ),
                  _toggle(
                    l10n.notifMentionsTitle,
                    l10n.notifMentionsSub,
                    Icons.alternate_email_rounded,
                    prefs.mentions,
                    (v) => _update(prefs.copyWith(mentions: v)),
                  ),
                  _toggle(
                    l10n.notifFollowsTitle,
                    l10n.notifFollowsSub,
                    Icons.people_alt_rounded,
                    prefs.follows,
                    (v) => _update(prefs.copyWith(follows: v)),
                  ),
                  _toggle(
                    l10n.notifMessagesTitle,
                    l10n.notifMessagesSub,
                    Icons.mail_rounded,
                    prefs.messages,
                    (v) => _update(prefs.copyWith(messages: v)),
                  ),
                  _toggle(
                    l10n.notifLiveTitle,
                    l10n.notifLiveSub,
                    Icons.live_tv_rounded,
                    prefs.live,
                    (v) => _update(prefs.copyWith(live: v)),
                  ),
                  _toggle(
                    l10n.notifMissionsTitle,
                    l10n.notifMissionsSub,
                    Icons.military_tech_rounded,
                    prefs.missions,
                    (v) => _update(prefs.copyWith(missions: v)),
                  ),
                  _toggle(
                    l10n.notifRewardsTitle,
                    l10n.notifRewardsSub,
                    Icons.card_giftcard_rounded,
                    prefs.rewards,
                    (v) => _update(prefs.copyWith(rewards: v)),
                  ),
                  _toggle(
                    l10n.notifGiftsTitle,
                    l10n.notifGiftsSub,
                    Icons.redeem_rounded,
                    prefs.gifts,
                    (v) => _update(prefs.copyWith(gifts: v)),
                  ),
                  _toggle(
                    l10n.notifNewsTitle,
                    l10n.notifNewsSub,
                    Icons.campaign_rounded,
                    prefs.news,
                    (v) => _update(prefs.copyWith(news: v)),
                  ),
                  const SizedBox(height: 8),
                  _pushCard(l10n, prefs.pushEnabled),
                ],
              ),
            ),
    );
  }

  Widget _toggle(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        value: value,
        activeTrackColor: const Color(0xFF8B5CF6),
        secondary: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        onChanged: _saving ? null : onChanged,
      ),
    );
  }

  Widget _pushCard(AppLocalizations l10n, bool enabled) {
    return KlaykCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.notifPushTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                activeTrackColor: const Color(0xFF8B5CF6),
                onChanged: _saving
                    ? null
                    : (v) => _update(_prefs!.copyWith(pushEnabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.notifPushBody,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
