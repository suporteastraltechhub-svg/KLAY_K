import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/moment_models.dart';
import '../services/moment_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import '../l10n/app_localizations.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Momentos do KLAY K: publicações efémeras (texto + sticker opcional) que
/// expiran tras un tiempo. Composer para criar o seu e feed com os ativos.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final TextEditingController _composerCtrl = TextEditingController();
  final _composerFocus = FocusNode();
  List<KlayKMoment> _all = [];
  List<KlayKMoment> _mine = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _publishing = false;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      if (!SupabaseService.instance.isConfigured) {
        throw Exception('Supabase não configurado');
      }
      final mine = await MomentService.instance.fetchMyMoments();
      final all = await MomentService.instance.fetchFeed();
      if (!mounted) return;
      final myIds = mine.map((m) => m.id).toSet();
      setState(() {
        _mine = mine;
        _all = [
          for (final m in all)
            myIds.contains(m.id)
                ? KlayKMoment(
                    id: m.id,
                    userId: m.userId,
                    text: m.text,
                    imageUrl: m.imageUrl,
                    sticker: m.sticker,
                    createdAt: m.createdAt,
                    expiresAt: m.expiresAt,
                    authorDisplayName: m.authorDisplayName,
                    authorUsername: m.authorUsername,
                    authorAvatarUrl: m.authorAvatarUrl,
                    authorVerified: m.authorVerified,
                    isMine: true,
                  )
                : m,
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _publish() async {
    final l10n = AppLocalizations.of(context)!;
    final text = _composerCtrl.text.trim();
    if (text.isEmpty || _publishing) return;
    setState(() => _publishing = true);
    try {
      await MomentService.instance.create(text: text);
      _composerCtrl.clear();
      _composerFocus.unfocus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.momentPublished)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is StateError ? e.message : l10n.momentPublishFail),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
    _load();
  }

  Future<void> _delete(KlayKMoment m) async {
    if (_deleting.contains(m.id)) return;
    setState(() => _deleting.add(m.id));
    await MomentService.instance.delete(m.id);
    if (!mounted) return;
    setState(() => _deleting.remove(m.id));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.moments,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: Column(
        children: [
          _composer(),
          const SizedBox(height: 4),
          Expanded(
            child: _loading ? const KlaykListSkeleton(rows: 6) : _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF17141F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2540)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composerCtrl,
                focusNode: _composerFocus,
                maxLines: 3,
                minLines: 1,
                maxLength: 280,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.shareMomentHint,
                  hintStyle: const TextStyle(color: Colors.white38),
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _publishing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kAccent,
                      ),
                    ),
                  )
                : Material(
                    color: _kAccent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _publish,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: l10n.errorLoading,
        message: l10n.momentsLoadFail,
        actionLabel: l10n.retry,
        actionIcon: Icons.refresh_rounded,
        onAction: _load,
      );
    }
    if (_all.isEmpty && _mine.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: l10n.momentsEmptyTitle,
        message: l10n.momentsEmptyBody,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_bottom_rounded,
                  color: _kAccent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.momentsNow,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          for (final m in _all)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _momentCard(m),
            ),
        ],
      ),
    );
  }

  Widget _momentCard(KlayKMoment m) {
    final colors = kc(context);
    final l10n = AppLocalizations.of(context)!;
    final remaining = m.remainingLabel;
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KlayKAvatar(imageUrl: m.authorAvatarUrl ?? '', size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.authorName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (m.authorVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            color: _kAccent,
                            size: 15,
                          ),
                        ],
                        if (m.isMine) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.person_pin_rounded,
                            color: Colors.white38,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      remaining ?? '',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (m.isMine)
                IconButton(
                  tooltip: l10n.deleteMoment,
                  onPressed: _deleting.contains(m.id) ? null : () => _delete(m),
                  icon: _deleting.contains(m.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      : const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (m.sticker.isNotEmpty) ...[
            Text(m.sticker, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
          ],
          Text(
            m.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.hourglass_bottom_rounded,
                color: colors.primarySoft,
                size: 15,
              ),
              const SizedBox(width: 4),
              Text(
                m.isMine ? l10n.onlyYouSeeIt : l10n.disappearsSoon,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
