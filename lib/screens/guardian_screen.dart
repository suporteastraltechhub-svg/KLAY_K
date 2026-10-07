import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/admin_service.dart';
import '../services/guardian_service.dart';

/// 🛡️ KLAY GUARDIAN
///
/// Central de operações: monitoramento honesto (health real), manutenção
/// global/por recurso, motor de regras, alertas e recomendações.
///
/// Acesso validado SEMPRE no backend (`guardian_*` security definer +
/// `has_perm`). A UI só esconde botões por capability local; toda ação é
/// re-validada pelo servidor.
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen>
    with SingleTickerProviderStateMixin {
  final GuardianService _g = GuardianService.instance;
  final AdminService _admin = AdminService.instance;

  bool _loaded = false;
  bool _hasGuardian = false;
  bool _hasRoles = false;
  String _role = '';

  late Map<String, dynamic> _health = const {};
  late List<GuardianWindow> _windows = const [];
  late List<Map<String, dynamic>> _alerts = const [];
  late List<Map<String, dynamic>> _history = const [];
  late List<Map<String, dynamic>> _rules = const [];
  late List<Map<String, dynamic>> _recs = const [];
  String _severityFilter = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final caps = await _admin.myCaps();
    final role = await _admin.myRole();
    if (!mounted) return;
    setState(() {
      _hasGuardian = caps.contains('guardian');
      _hasRoles = caps.contains('roles');
      _role = role;
      _loaded = true;
    });
    await _reload();
  }

  Future<void> _reload() async {
    if (_hasGuardian) {
      final results = await Future.wait<dynamic>([
        _g.health().catchError((_) => const <String, dynamic>{}),
        _g.listMaintenance().catchError((_) => const <Map<String, dynamic>>[]),
        _g
            .listAlerts(
              status: _severityFilter == 'all' ? null : _severityFilter,
            )
            .catchError((_) => const <Map<String, dynamic>>[]),
        _g.listRules().catchError((_) => const <Map<String, dynamic>>[]),
        _g.listRecommendations().catchError(
          (_) => const <Map<String, dynamic>>[],
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _health = results[0] as Map<String, dynamic>;
        _history = (results[1] as List).cast<Map<String, dynamic>>();
        _alerts = (results[2] as List).cast<Map<String, dynamic>>();
        _rules = (results[3] as List).cast<Map<String, dynamic>>();
        _recs = (results[4] as List).cast<Map<String, dynamic>>();
      });
    }
    final windows = await _g.status().catchError(
      (_) => const <GuardianWindow>[],
    );
    if (mounted) setState(() => _windows = windows);
  }

  String _num(dynamic v) {
    if (v == null) return '0';
    return v.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
  }

  String _byteSize(dynamic bytes) {
    final b = (bytes is num ? bytes.toDouble() : 0);
    if (b <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    var v = b;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  void _err(Object? e) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(_g.friendlyError(e))));

  void _ok(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run() async {
    if (!_hasGuardian) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final r = await _g.runRules();
      final checks = r['checks']?.toString() ?? '?';
      _ok('${l10n.guardianScanDone} ($checks ${l10n.guardianChecks})');
      await _reload();
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEmergency() async {
    final l10n = AppLocalizations.of(context)!;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.guardianEmergencyTitle,
          style: const TextStyle(
            color: Color(0xFFFF6B81),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.guardianEmergencyBody,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.guardianEmergencyFounder,
              style: const TextStyle(color: Color(0xFFB794FF), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            child: Text(l10n.guardianConfirmEmergency),
          ),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      final r = await _g.emergency(message: '');
      final okFlag = r['ok'] == true || r['mode'] != null;
      if (okFlag) {
        _ok(l10n.guardianEmergencyActiveConfirm);
      } else {
        _err(l10n.guardianEmergencyNotConfirmed);
      }
      await _reload();
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0812),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0812),
        appBar: AppBar(
          title: Column(
            children: [
              const Text(
                '🛡️ KLAY GUARDIAN',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'role: ${_role.isEmpty ? '…' : _role}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0A0812),
          actions: [
            if (_hasGuardian)
              IconButton(
                tooltip: l10n.guardianRunScanTooltip,
                onPressed: _busy ? null : _run,
                icon: const Icon(
                  Icons.play_circle_outline,
                  color: Color(0xFFB794FF),
                ),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            indicatorColor: const Color(0xFF8B5CF6),
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(
                icon: const Icon(Icons.monitor_heart_rounded),
                text: l10n.guardianTabDashboard,
              ),
              Tab(
                icon: const Icon(Icons.notifications_active_rounded),
                text: l10n.guardianTabAlerts,
              ),
              Tab(
                icon: const Icon(Icons.build_rounded),
                text: l10n.guardianTabMaint,
              ),
              Tab(
                icon: const Icon(Icons.rule_rounded),
                text: l10n.guardianTabRules,
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [_dashboard(), _alertsTab(), _maintTab(), _rulesTab()],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1) Dashboard (health + emergência + status de manutenção)
  // ---------------------------------------------------------------------------

  Widget _dashboard() {
    final l10n = AppLocalizations.of(context)!;
    if (_windows.any((w) => w.isEmergency)) {
      return _bannerStrip(l10n, emergency: true);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle(l10n.guardianHealthTitle),
          const SizedBox(height: 4),
          _hint(l10n.guardianHealthHint),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statCard(
                Icons.people_outline,
                l10n.guardianStatUsers,
                _num(_health['users_total']),
                const Color(0xFF8B5CF6),
              ),
              _statCard(
                Icons.person_add_alt_1,
                l10n.guardianStatNew30d,
                _num(_health['users_last_30d']),
                const Color(0xFFB794FF),
              ),
              _statCard(
                Icons.video_library_outlined,
                l10n.guardianStatTotalVideos,
                _num(_health['posts_total']),
                const Color(0xFF22D3EE),
              ),
              _statCard(
                Icons.publish,
                l10n.guardianStatPosts24h,
                _num(_health['posts_last_24h']),
                const Color(0xFF22D3EE),
              ),
              _statCard(
                Icons.support_agent_outlined,
                l10n.guardianStatOpenSupport,
                _num(_health['support_open']),
                const Color(0xFF34D399),
              ),
              _statCard(
                Icons.badge_outlined,
                l10n.guardianStatPendingVerif,
                _num(_health['verification_pending']),
                const Color(0xFF34D399),
              ),
              _statCard(
                Icons.notifications_active_outlined,
                l10n.guardianStatOpenAlerts,
                _num(_health['alerts_open']),
                const Color(0xFFF59E0B),
              ),
              _statCard(
                Icons.error_outline,
                l10n.guardianStatCriticalAlerts,
                _num(_health['alerts_critical']),
                const Color(0xFFFF6B81),
              ),
              _statCard(
                Icons.storage_outlined,
                l10n.guardianStatDatabase,
                _byteSize(_health['db_size_bytes']),
                const Color(0xFF34D399),
              ),
              _statCard(
                Icons.fact_check_outlined,
                l10n.guardianStatAudit24h,
                _num(_health['audit_actions_24h']),
                const Color(0xFFB794FF),
              ),
            ],
          ),
          if (_hasGuardian) ...[
            const SizedBox(height: 18),
            _sectionTitle(l10n.guardianOpsActions),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _run,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                    ),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(
                      _busy ? l10n.guardianScanRunning : l10n.guardianRunScan,
                    ),
                  ),
                ),
                if (_hasRoles) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _confirmEmergency,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B81),
                        side: const BorderSide(color: Color(0xFFFF6B81)),
                      ),
                      icon: const Icon(Icons.warning_amber_rounded),
                      label: Text(l10n.guardianEmergency),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 18),
          _sectionTitle(l10n.guardianActiveMaint),
          const SizedBox(height: 8),
          if (_windows.isEmpty)
            _card([
              ListTile(
                leading: const Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF34D399),
                ),
                title: Text(
                  l10n.guardianAllOperational,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  l10n.guardianNoActiveWindows,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ])
          else
            _card([
              for (final w in _windows)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    w.isEmergency
                        ? Icons.crisis_alert_rounded
                        : w.isGlobal
                        ? Icons.public_rounded
                        : Icons.construction_rounded,
                    color: w.isEmergency
                        ? const Color(0xFFFF6B81)
                        : w.isGlobal
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF8B5CF6),
                  ),
                  title: Text(
                    '${w.isGlobal ? l10n.guardianScopeGlobal : w.feature} · ${l10n.guardianModePattern(w.mode)}${w.isEmergency ? l10n.guardianEmergencySuffix : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    w.message.isEmpty
                        ? l10n.guardianSince(_rel(l10n, w.startedAt))
                        : '${w.message} · ${l10n.guardianSince(_rel(l10n, w.startedAt))}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ]),
          const SizedBox(height: 18),
          _sectionTitle(l10n.guardianRecs),
          const SizedBox(height: 8),
          if (_recs.isEmpty)
            _card([
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFB794FF),
                ),
                title: Text(
                  l10n.guardianNoRecs,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ])
          else
            _card([
              for (final r in _recs.take(5))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: _sevIcon(r['severity']?.toString()),
                  title: Text(
                    r['title']?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    r['action']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _bannerStrip(AppLocalizations l10n, {required bool emergency}) {
    final w = _windows.firstWhere(
      (x) => x.isEmergency,
      orElse: () => _windows.first,
    );
    return Container(
      width: double.infinity,
      color: emergency ? const Color(0xFF2B0F14) : const Color(0xFF1E1B12),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            emergency ? Icons.crisis_alert_rounded : Icons.construction_rounded,
            color: emergency
                ? const Color(0xFFFF6B81)
                : const Color(0xFFF59E0B),
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            emergency
                ? l10n.guardianEmergencyActive
                : l10n.guardianMaintInProgress,
            style: TextStyle(
              color: emergency
                  ? const Color(0xFFFF6B81)
                  : const Color(0xFFF59E0B),
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${w.isGlobal ? l10n.guardianScopeAll : l10n.guardianScopeFeature(w.feature)} · ${l10n.guardianModePattern(w.mode)}'
            '${w.message.isEmpty ? '' : '\n\n${w.message}'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _reload,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.guardianCheckAgain),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2) Alertas
  // ---------------------------------------------------------------------------

  Widget _alertsTab() {
    if (!_hasGuardian) return _noAccess();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final s in const [
                'all',
                'critical',
                'high',
                'medium',
                'low',
                'info',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: _severityFilter == s,
                    onSelected: (_) async {
                      setState(() => _severityFilter = s);
                      await _reload();
                    },
                    selectedColor: const Color(0xFF8B5CF6),
                    labelStyle: TextStyle(
                      color: _severityFilter == s
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 12,
                    ),
                    backgroundColor: const Color(0xFF15131E),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: _alerts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: Color(0xFF34D399),
                              size: 42,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.guardianNoAlerts,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: _alerts.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, index) =>
                        _alertTile(l10n, _alerts[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _alertTile(AppLocalizations l10n, Map<String, dynamic> a) {
    final id = a['id']?.toString() ?? '';
    final status = a['status']?.toString() ?? 'open';
    final open = status == 'open' || status == 'ack';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sevIcon(a['severity']?.toString()),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a['title']?.toString() ?? '—',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _chip(a['severity']?.toString() ?? 'info', const Color(0xFF8B5CF6)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          a['message']?.toString() ?? '',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          '${a['category'] ?? ''} · ${_rel(l10n, DateTime.tryParse((a['created_at'] as String?) ?? ''))}'
          '${status.isEmpty ? '' : ' · $status'}',
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _resolve(id),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(l10n.resolveAction),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF34D399),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _resolve(String id) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final r = await _g.resolveAlert(
        alertId: id,
        note: 'resolvido pelo painel',
      );
      if (r['ok'] == true) _ok(l10n.guardianAlertResolved);
      await _reload();
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3) Manutenção
  // ---------------------------------------------------------------------------

  Widget _maintTab() {
    if (!_hasGuardian) return _noAccess();
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle(l10n.guardianNewWindow),
          const SizedBox(height: 4),
          _hint(l10n.guardianModeHint),
          const SizedBox(height: 10),
          _card([
            Padding(
              padding: const EdgeInsets.all(12),
              child: _MaintForm(
                l10n: l10n,
                onDone: () async {
                  try {
                    await _reload();
                  } finally {
                    if (mounted) setState(() {});
                  }
                },
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle(l10n.guardianActiveWindows),
          const SizedBox(height: 8),
          if (_history
              .where((w) => w['status']?.toString() == 'active')
              .isEmpty)
            _card([
              ListTile(
                leading: const Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF34D399),
                ),
                title: Text(
                  l10n.guardianNoActiveWindowsShort,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ])
          else
            _card([
              for (final w in _history.where(
                (w) => w['status']?.toString() == 'active',
              ))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(
                    Icons.construction_rounded,
                    color: Color(0xFFF59E0B),
                  ),
                  title: Text(
                    '${w['feature'] ?? 'all'} · ${l10n.guardianModePattern(w['mode']?.toString() ?? '')}'
                    '${w['emergency'] == true ? l10n.guardianEmergencySuffix : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${w['message'] ?? ''} · por ${w['created_by'] ?? '—'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.guardianEndTooltip,
                    onPressed: _busy
                        ? null
                        : () => _endWindow(w['id']?.toString()),
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: 18),
          _sectionTitle(l10n.guardianRecentHistory),
          const SizedBox(height: 8),
          if (_history
              .where((w) => w['status']?.toString() != 'active')
              .isEmpty)
            _card([
              ListTile(
                leading: const Icon(Icons.history, color: Color(0xFFB794FF)),
                title: Text(
                  l10n.guardianNoHistory,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ])
          else
            _card([
              for (final w
                  in _history
                      .where((w) => w['status']?.toString() != 'active')
                      .take(10))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(
                    Icons.history,
                    color: Color(0xFFB794FF),
                    size: 20,
                  ),
                  title: Text(
                    '${w['feature'] ?? ''} · ${w['status'] ?? ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${w['mode'] ?? ''} · ${w['message'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Future<void> _endWindow(String? id) async {
    if (id == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final r = await _g.endMaintenance(
        windowId: id,
        reason: 'encerrado pelo painel',
      );
      if (r['ok'] == true) _ok(l10n.guardianWindowEnded);
      await _reload();
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 4) Regras
  // ---------------------------------------------------------------------------

  Widget _rulesTab() {
    if (!_hasGuardian) return _noAccess();
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle(l10n.guardianRulesEngine),
          const SizedBox(height: 4),
          _hint(l10n.guardianRulesHint),
          const SizedBox(height: 10),
          if (_rules.isEmpty)
            _card([
              ListTile(
                leading: const Icon(Icons.rule, color: Color(0xFFB794FF)),
                title: Text(
                  l10n.guardianNoRules,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ])
          else
            _card([
              for (final r in _rules)
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    r['description']?.toString() ?? r['id']?.toString() ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${r['id'] ?? ''} · sensibilidade ${r['threshold'] ?? '?'}'
                    '${(r['config'] is Map && (r['config'] as Map).isNotEmpty) ? ' · ${(r['config'] as Map).entries.map((e) => '${e.key}=${e.value}').join(' ')}' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  value: r['enabled'] == true,
                  activeThumbColor: const Color(0xFF8B5CF6),
                  onChanged: _busy
                      ? null
                      : (v) => _toggle(r['id']?.toString(), v),
                ),
            ]),
        ],
      ),
    );
  }

  Future<void> _toggle(String? id, bool enabled) async {
    if (id == null || id.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final r = await _g.toggleRule(ruleId: id, enabled: enabled);
      if (r['ok'] == true) {
        _ok(
          l10n.guardianRuleState(
            enabled ? l10n.guardianRuleEnabled : l10n.guardianRuleDisabled,
          ),
        );
      }
      await _reload();
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers visuais
  // ---------------------------------------------------------------------------

  Widget _noAccess() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: Color(0xFF8B5CF6),
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.guardianNoAccess,
            style: const TextStyle(color: Colors.white54),
          ),
          Text(
            l10n.guardianNoAccessSub,
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _hint(String t) =>
      Text(t, style: const TextStyle(color: Colors.white38, fontSize: 11));

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children:
            children
                .expand(
                  (w) => [w, const Divider(color: Colors.white12, height: 1)],
                )
                .toList()
              ..removeLast(),
      ),
    );
  }

  Widget _sevIcon(String? sev) {
    final c = _sevColor(sev);
    return Icon(
      sev == 'critical'
          ? Icons.error_rounded
          : sev == 'high'
          ? Icons.warning_amber_rounded
          : sev == 'low'
          ? Icons.info_outline_rounded
          : Icons.circle_notifications_outlined,
      color: c,
      size: 20,
    );
  }

  Color _sevColor(String? sev) {
    switch (sev) {
      case 'critical':
        return const Color(0xFFFF6B81);
      case 'high':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF22D3EE);
      default:
        return const Color(0xFFB794FF);
    }
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _rel(AppLocalizations l10n, DateTime? dt) {
    if (dt == null) return '—';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return l10n.guardianRelNow;
    if (d.inMinutes < 60) return l10n.guardianRelMinutes(d.inMinutes);
    if (d.inHours < 24) return l10n.guardianRelHours(d.inHours);
    return l10n.guardianRelDays(d.inDays);
  }
}

// ---------------------------------------------------------------------------
// Formulário de manutenção (novo/ global | por recurso)
// ---------------------------------------------------------------------------

class _MaintForm extends StatefulWidget {
  final AppLocalizations l10n;
  final VoidCallback onDone;
  const _MaintForm({required this.l10n, required this.onDone});

  @override
  State<_MaintForm> createState() => _MaintFormState();
}

class _MaintFormState extends State<_MaintForm> {
  final GuardianService _g = GuardianService.instance;
  String _mode = 'medium';
  String _feature = 'all';
  final TextEditingController _msg = TextEditingController();
  bool _saving = false;

  static const _features = [
    'all',
    'store',
    'live',
    'messages',
    'feed',
    'economy',
    'chests',
    'verification',
    'support',
  ];

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = widget.l10n;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final r = await _g.setMaintenance(
        mode: _mode,
        feature: _feature,
        message: _msg.text.trim(),
      );
      final okFlag = r['ok'] == true || r['id'] != null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              okFlag ? l10n.guardianMaintStarted : _g.friendlyError(r),
            ),
          ),
        );
      }
      widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_g.friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _mode,
          dropdownColor: const Color(0xFF15131E),
          decoration: InputDecoration(labelText: l10n.guardianModeLabel),
          items: [
            DropdownMenuItem(value: 'low', child: Text(l10n.guardianModeLow)),
            DropdownMenuItem(
              value: 'medium',
              child: Text(l10n.guardianModeMedium),
            ),
            DropdownMenuItem(value: 'max', child: Text(l10n.guardianModeMax)),
          ],
          onChanged: (v) => setState(() => _mode = v ?? 'medium'),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _feature,
          dropdownColor: const Color(0xFF15131E),
          decoration: InputDecoration(labelText: l10n.guardianFeatureLabel),
          items: [
            for (final f in _features)
              DropdownMenuItem(
                value: f,
                child: Text(f == 'all' ? l10n.guardianFeatureAll : f),
              ),
          ],
          onChanged: (v) => setState(() => _feature = v ?? 'all'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _msg,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: l10n.guardianMessageLabel,
            hintText: l10n.guardianMessageHint,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              _saving ? l10n.guardianOpening : l10n.guardianStartMaint,
            ),
          ),
        ),
      ],
    );
  }
}
