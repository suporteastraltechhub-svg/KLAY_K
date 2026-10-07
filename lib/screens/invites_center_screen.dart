import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/invite_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';

/// Central de Convites: código pessoal, copiar/compartilhar, lista de
/// convidados e reivindicação de cristais por convidados validados.
/// Tudo persistido/válido no backend (RPCs security definer).
class InvitesCenterScreen extends StatefulWidget {
  const InvitesCenterScreen({super.key});

  @override
  State<InvitesCenterScreen> createState() => _InvitesCenterScreenState();
}

class _InvitesCenterScreenState extends State<InvitesCenterScreen> {
  final _svc = InviteService.instance;
  InviteSummary _summary = const InviteSummary();
  List<InviteRecord> _invites = const [];
  bool _loading = true;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await _svc.summary();
    final invites = await _svc.invites();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _invites = invites;
      _loading = false;
    });
  }

  Future<void> _copyCode() async {
    if (_summary.code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _summary.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.inviteCodeCopied)),
    );
  }

  Future<void> _share() async {
    final text = _svc.shareText(
      _summary.code,
      kAppIdentity.username.replaceFirst('@', ''),
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.inviteMessageCopied),
      ),
    );
  }

  Future<void> _claim() async {
    final l10n = AppLocalizations.of(context)!;
    if (_claiming) return;
    setState(() => _claiming = true);
    final result = await _svc.claimRewards();
    if (!mounted) return;
    setState(() => _claiming = false);
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimed > 0
                ? l10n.inviteClaimSuccess(result.crystals)
                : l10n.inviteNoPendingRewards,
          ),
        ),
      );
      await _load();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.inviteClaimFail)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invites)),
      body: KlaykScreenBackground(
        child: _loading
            ? const Center(child: KlaykLoader())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHero(),
                    const SizedBox(height: 20),
                    _buildStats(),
                    const SizedBox(height: 20),
                    _buildInviteList(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHero() {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return KlaykCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.primaryFaint, colors.surfaceAlt],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.inviteHeroTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.inviteHeroBody,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _copyCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _summary.code,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.copy_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _share,
                icon: const Icon(Icons.share_rounded),
                tooltip: l10n.inviteCopyTooltip,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _statCard(colors, '👥', '${_summary.invited}', l10n.inviteInvitedStat),
        const SizedBox(width: 12),
        _statCard(
          colors,
          '✅',
          '${_summary.pendingRewards}',
          l10n.invitePendingStat,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KlaykCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            onTap: _claim,
            child: Column(
              children: [
                Icon(
                  _claiming ? Icons.hourglass_top : Icons.card_giftcard,
                  color: colors.gold,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.inviteClaimButton,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '🔮 ${_summary.pendingRewards * 5}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    KlaykColors colors,
    String emoji,
    String value,
    String label,
  ) {
    return Expanded(
      child: KlaykCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteList() {
    final l10n = AppLocalizations.of(context)!;
    if (_invites.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.group_add_rounded,
        title: l10n.inviteEmptyTitle,
        message: l10n.inviteEmptyBody,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KlaykSectionTitle(l10n.inviteInvitedStat),
        const SizedBox(height: 8),
        ..._invites.map(
          (inv) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KlaykCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    child: Icon(Icons.person_rounded, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusLabel(inv.status, l10n),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusChip(inv.status, l10n),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status, AppLocalizations l10n) {
    switch (status) {
      case 'validated':
        return l10n.inviteStatusValidated;
      case 'rewarded':
        return l10n.inviteStatusRewarded;
      case 'blocked':
        return l10n.inviteStatusBlocked;
      default:
        return l10n.inviteStatusRegistered;
    }
  }

  Widget _statusChip(String status, AppLocalizations l10n) {
    final colors = kcolors(context);
    final (label, bg, fg) = switch (status) {
      'rewarded' => (
        l10n.inviteChipRewarded,
        colors.success.withValues(alpha: .15),
        colors.success,
      ),
      'validated' => (
        l10n.inviteChipValidated,
        colors.info.withValues(alpha: .15),
        colors.info,
      ),
      'blocked' => (
        l10n.blockedSuffix,
        colors.danger.withValues(alpha: .15),
        colors.danger,
      ),
      _ => (
        l10n.inviteChipPending,
        colors.warning.withValues(alpha: .15),
        colors.warning,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}
