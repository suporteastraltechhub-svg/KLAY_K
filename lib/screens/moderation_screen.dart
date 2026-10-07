import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/security_models.dart';
import '../services/security_service.dart';
import '../services/social_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Painel administrativo de moderação do KLAY K.
/// Acesso apenas com profiles.is_admin = true (verificado no backend via RPCs
/// security definer). Gestão de denúncias + regras anti-spam.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  bool _loading = true;
  bool _isAdmin = false;
  int _tab = 0;

  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _rules = [];
  List<SuspectProfile> _suspects = [];
  List<ProfileFlagEntry> _flags = [];
  final TextEditingController _rulePattern = TextEditingController();
  String _ruleType = 'block';
  String _ruleScope = 'all';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _rulePattern.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final s = SocialService.instance;
    final admin = await s.isAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _loading = false;
    });
    if (!admin) return;
    await _loadAll();
  }

  Future<void> _loadAll() async {
    final s = SocialService.instance;
    final sec = SecurityService.instance;
    final reports = await s.modListReports();
    final rules = await s.modListSpamRules();
    List<SuspectProfile> suspects = const [];
    List<ProfileFlagEntry> flags = const [];
    try {
      suspects = await sec.adminSuspectProfiles();
    } catch (_) {}
    try {
      flags = await sec.adminListProfileFlags();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _rules = rules;
      _suspects = suspects;
      _flags = flags;
    });
  }

  Future<void> _resolve(String id, String status) async {
    await SocialService.instance.modUpdateReport(id, status);
    await _loadAll();
  }

  Future<void> _addRule() async {
    final pattern = _rulePattern.text.trim();
    if (pattern.isEmpty) return;
    await SocialService.instance.modAddSpamRule(
      pattern,
      ruleType: _ruleType,
      scope: _ruleScope,
    );
    _rulePattern.clear();
    await _loadAll();
  }

  Future<void> _removeRule(String id) async {
    await SocialService.instance.modRemoveSpamRule(id);
    await _loadAll();
  }

  Future<void> _flagProfile(SuspectProfile p) async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await _promptText(
      l10n,
      l10n.moderationFlagProfileTitle,
      '@${p.username} (${p.displayName})',
      hint: l10n.moderationFlagProfileHint,
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await SecurityService.instance.adminFlagProfile(p.id, reason.trim());
      await _loadAll();
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.moderation,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : !_isAdmin
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.gpp_bad_rounded,
                      color: Colors.white38,
                      size: 56,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.moderationAdminRestricted,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    children: [
                      _tabChip(l10n, l10n.moderationTabReports, 0),
                      _tabChip(l10n, l10n.moderationTabAntispam, 1),
                      _tabChip(l10n, l10n.moderationTabFakeProfile, 2),
                    ],
                  ),
                ),
                Expanded(
                  child: _tab == 0
                      ? _buildReports(l10n)
                      : _tab == 1
                      ? _buildRules(l10n)
                      : _buildFakeProfile(l10n),
                ),
              ],
            ),
    );
  }

  Future<void> _resolveFlag(ProfileFlagEntry f, String decision) async {
    final l10n = AppLocalizations.of(context)!;
    String note = '';
    if (decision == 'attention') {
      final n = await _promptText(
        l10n,
        l10n.moderationMarkAttentionTitle,
        l10n.moderationMarkAttentionBody,
        hint: l10n.moderationNoteHint,
      );
      if (n == null) return;
      note = n;
    }
    try {
      await SecurityService.instance.adminResolveProfileFlag(
        flagId: f.id,
        decision: decision,
        note: note,
      );
      await _loadAll();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<String?> _promptText(
    AppLocalizations l10n,
    String title,
    String body, {
    String hint = '',
  }) async {
    final controller = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF16151F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(
              'OK',
              style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    return res;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _tabChip(AppLocalizations l10n, String label, int value) {
    final sel = _tab == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : Colors.white70,
            fontSize: 13,
          ),
        ),
        selected: sel,
        selectedColor: _kAccent,
        backgroundColor: const Color(0xFF1B1A26),
        onSelected: (_) => setState(() => _tab = value),
      ),
    );
  }

  Widget _buildReports(AppLocalizations l10n) {
    if (_reports.isEmpty) {
      return Center(
        child: Text(
          l10n.moderationNoReports,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _kAccent,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _reports.length,
        itemBuilder: (context, i) {
          final r = _reports[i];
          final type = r['target_type']?.toString() ?? '';
          final id = r['id']?.toString() ?? '';
          final reason = r['reason']?.toString() ?? '';
          final details = r['details']?.toString() ?? '';
          final createdAt = r['created_at']?.toString() ?? '';
          return Card(
            color: const Color(0xFF16151F),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: const TextStyle(
                            color: _kAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        createdAt.length >= 16
                            ? createdAt.substring(0, 16)
                            : createdAt,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                  if ((r['resolution']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.moderationResolutionLabel(r['resolution']),
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    l10n.moderationTargetLabel(_targetLabel(l10n, r)),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _resolve(id, 'resolved'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4CAF50),
                          side: const BorderSide(color: Color(0xFF4CAF50)),
                          minimumSize: const Size(0, 34),
                        ),
                        child: Text(l10n.moderationResolve),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _resolve(id, 'dismissed'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          minimumSize: const Size(0, 34),
                        ),
                        child: Text(l10n.moderationDismiss),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _targetLabel(AppLocalizations l10n, Map<String, dynamic> r) {
    final type = r['target_type']?.toString() ?? '';
    final id = r['target_id']?.toString() ?? '';
    final short = id.length > 8 ? '${id.substring(0, 8)}…' : id;
    if (type == 'user') return l10n.moderationTargetUser(short);
    if (type == 'post') return l10n.moderationTargetPost(short);
    if (type == 'live') return l10n.moderationTargetLive(short);
    if (type == 'comment') return l10n.moderationTargetComment(short);
    if (type == 'message') return l10n.moderationTargetMessage(short);
    if (type == 'conversation') return l10n.moderationTargetConversation(short);
    return l10n.moderationTargetChat(short);
  }

  Widget _buildRules(AppLocalizations l10n) {
    final s = SocialService.instance;
    return FutureBuilder<List<String>>(
      future: s.loadSpamRules(),
      builder: (context, snap) {
        final activePatterns = snap.data ?? const <String>[];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _rulePattern,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: l10n.moderationRuleHint,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1B1A26),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      DropdownButton<String>(
                        value: _ruleType,
                        dropdownColor: const Color(0xFF1B1A26),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'block',
                            child: Text(l10n.moderationRuleTypeBlock),
                          ),
                          DropdownMenuItem(
                            value: 'flag',
                            child: Text(l10n.moderationRuleTypeFlag),
                          ),
                          DropdownMenuItem(
                            value: 'warn',
                            child: Text(l10n.moderationRuleTypeWarn),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _ruleType = v ?? 'block'),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _ruleScope,
                        dropdownColor: const Color(0xFF1B1A26),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(l10n.moderationRuleScopeAll),
                          ),
                          DropdownMenuItem(
                            value: 'chat',
                            child: Text(l10n.moderationRuleScopeChat),
                          ),
                          DropdownMenuItem(
                            value: 'comment',
                            child: Text(l10n.moderationRuleScopeComment),
                          ),
                          DropdownMenuItem(
                            value: 'message',
                            child: Text(l10n.moderationRuleScopeMessage),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _ruleScope = v ?? 'all'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _addRule,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(l10n.moderationAddRule),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAll,
                color: _kAccent,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final rule in _rules)
                      ListTile(
                        leading: const Icon(
                          Icons.filter_alt_rounded,
                          color: _kAccent,
                        ),
                        title: Text(
                          rule['pattern']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          '${rule['rule_type']} • ${rule['scope']}'
                          '${(rule['active'] == true) ? '' : ' • ${l10n.moderationRuleInactive}'}',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white38,
                          ),
                          onPressed: () =>
                              _removeRule(rule['id']?.toString() ?? ''),
                        ),
                      ),
                    if (activePatterns.isEmpty && _rules.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Text(
                          l10n.moderationNoRules,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white38),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFakeProfile(AppLocalizations l10n) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              l10n.moderationSuspectProfilesHeader,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (_suspects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l10n.moderationNoSuspects,
                style: const TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final p in _suspects) _suspectTile(l10n, p),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              l10n.moderationFlagsHeader,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (_flags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l10n.moderationNoFlags,
                style: const TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final f in _flags) _flagTile(l10n, f),
        ],
      ),
    );
  }

  Widget _suspectTile(AppLocalizations l10n, SuspectProfile p) {
    return Card(
      color: const Color(0xFF16151F),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.displayName.isNotEmpty ? p.displayName : '@${p.username}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (p.isDefaultUsername)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.moderationDefaultUsername,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.moderationAccountAgeDays(p.username, p.accountAgeDays),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _chip(p.hasAvatar, l10n.moderationChipAvatar),
                _chip(p.hasBio, l10n.moderationChipBio),
                if (p.openFlags > 0)
                  _chip(false, l10n.moderationOpenFlags(p.openFlags)),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _flagProfile(p),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: Text(l10n.moderationFlagProfile),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kAccent),
                minimumSize: const Size(0, 34),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(bool present, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (present ? const Color(0xFF34D399) : Colors.white24).withValues(
        alpha: 0.15,
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '${present ? '✓' : '✗'} $label',
      style: TextStyle(
        color: present ? const Color(0xFF34D399) : Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _flagTile(AppLocalizations l10n, ProfileFlagEntry f) {
    final open = f.isOpen;
    final statusColor = open ? Colors.orange : const Color(0xFF34D399);
    return Card(
      color: const Color(0xFF16151F),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    open ? l10n.moderationFlagOpen : f.decision.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.moderationFlagSource(
                    f.source.isEmpty
                        ? l10n.moderationFlagSourceManual
                        : f.source,
                  ),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              f.reason.isEmpty ? 'USUÁRIO ${f.flaggedUserId}' : f.reason,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.moderationFlagUser(f.flaggedUserId),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            if (f.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.moderationFlagNote(f.note),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            if (open) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _resolveFlag(f, 'ok'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF34D399),
                      side: const BorderSide(color: Color(0xFF34D399)),
                      minimumSize: const Size(0, 34),
                    ),
                    child: Text(l10n.moderationResolutionOk),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _resolveFlag(f, 'attention'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      minimumSize: const Size(0, 34),
                    ),
                    child: Text(l10n.moderationResolutionAttention),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
