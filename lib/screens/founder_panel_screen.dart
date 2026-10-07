import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dart:convert' show jsonEncode, jsonDecode;

import '../l10n/app_localizations.dart';
import '../models/gift_models.dart';
import '../services/admin_service.dart';
import '../services/finance_service.dart';
import '../services/founder_service.dart';
import '../services/gift_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../widgets/verified_badge.dart';
import 'ads_admin_screen.dart';

/// 👑 PAINEL DO FUNDADOR
///
/// Acesso restrito: além do gate visual (capabilities `my_caps()`), TODA ação
/// roda em RPCs `security definer` que re-validam `has_perm(...)` no backend.
/// Um usuário comum nunca acessa estes dados mudando rotas/UI. Modo
/// não-admin (staff com capabilities parciais) exibe apenas as abas liberadas.
class FounderPanelScreen extends StatefulWidget {
  const FounderPanelScreen({super.key});

  @override
  State<FounderPanelScreen> createState() => _FounderPanelScreenState();
}

class _FounderPanelScreenState extends State<FounderPanelScreen> {
  final FounderService _svc = FounderService.instance;
  final SocialService _social = SocialService.instance;
  final GiftService _gifts = GiftService.instance;
  final AdminService _admin = AdminService.instance;
  final FinanceService _financeSvc = FinanceService.instance;

  bool? _isAdmin;
  bool _adminError = false;
  bool _checking = true;
  String _role = 'user';
  List<String> _caps = const [];
  List<_PanelTab> _tabs = const [];

  late Future<Map<String, dynamic>> _overview;
  late Future<List<Map<String, dynamic>>> _reports;
  late Future<List<Map<String, dynamic>>> _users;
  late Future<List<Map<String, dynamic>>> _orders;
  late Future<Map<String, dynamic>> _lives;
  late Future<List<Map<String, dynamic>>> _admins;
  late Future<Map<String, dynamic>> _giftStats;
  late Future<List<Gift>> _catalog;
  late Future<Map<String, dynamic>> _store;
  late Future<List<Map<String, dynamic>>> _rules;
  late Future<List<Map<String, dynamic>>> _verifications;
  late Future<List<Map<String, dynamic>>> _tickets;
  late Future<List<Map<String, dynamic>>> _staff;
  late Future<Map<String, dynamic>> _economy;
  late Future<Map<String, dynamic>> _finance;
  late Future<List<Map<String, dynamic>>> _payouts;
  late Future<List<Map<String, dynamic>>> _financeOrders;
  late Future<Map<String, dynamic>> _chests;
  late Future<List<Map<String, dynamic>>> _chestCatalog;
  late Future<List<Map<String, dynamic>>> _audit;
  late Future<List<Map<String, dynamic>>> _professions;
  late Future<List<Map<String, dynamic>>> _bots;
  late Future<List<Map<String, dynamic>>> _pendingConversions;
  late Future<List<Map<String, dynamic>>> _posts;
  late Future<Map<String, dynamic>> _dash;
  bool _postBusy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool _has(String cap) => _caps.contains(cap);

  Future<void> _check() async {
    try {
      // Gate com timeout: nunca fica em "Verificando permissões…" para sempre.
      final results = await Future.wait<dynamic>([
        _svc.isAdmin(),
        _admin.myRole(),
        _admin.myCaps(),
      ]).timeout(const Duration(seconds: 15));
      final admin = results[0] == true;
      final role = results[1]?.toString() ?? 'user';
      final caps =
          (results[2] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      if (!mounted) return;
      final tabs = _buildTabs(admin, caps);
      setState(() {
        _isAdmin = admin;
        _adminError = false;
        _checking = false;
        _role = role;
        _caps = caps;
        _tabs = tabs;
      });
      // Só carrega dados administrativos quando há acesso (evita RPCs de admin
      // disparadas para usuário comum → exceções não tratadas).
      if (admin || caps.isNotEmpty) _refreshAll();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adminError = true;
        _checking = false;
      });
    }
  }

  List<_PanelTab> _buildTabs(bool admin, List<String> caps) {
    final l10n = AppLocalizations.of(context)!;
    final c = caps.toSet();
    bool has(String cap) => c.contains(cap);
    final tabs = <_PanelTab>[];
    if (admin) {
      tabs.add(
        _PanelTab(Icons.insights_rounded, l10n.overviewTab, _TabId.overview),
      );
      tabs.add(
        _PanelTab(Icons.shield_rounded, l10n.moderationTab, _TabId.moderation),
      );
    }
    if (admin || has('verification') || has('verification_view')) {
      tabs.add(
        _PanelTab(
          Icons.badge_rounded,
          l10n.verificationTab,
          _TabId.verification,
        ),
      );
    }
    if (has('moderation')) {
      tabs.add(
        _PanelTab(Icons.video_library_rounded, l10n.postsTab, _TabId.posts),
      );
    }
    if (admin || has('support') || has('tickets')) {
      tabs.add(
        _PanelTab(Icons.support_agent_rounded, l10n.supportTab, _TabId.tickets),
      );
      tabs.add(
        _PanelTab(
          Icons.feedback_rounded,
          l10n.founderFeedbackTab,
          _TabId.feedback,
        ),
      );
    }
    if (admin) {
      tabs.add(_PanelTab(Icons.people_rounded, l10n.usersTab, _TabId.users));
    }
    if (has('roles')) {
      tabs.add(_PanelTab(Icons.group_add_rounded, l10n.teamTab, _TabId.team));
      tabs.add(
        _PanelTab(
          Icons.currency_exchange_rounded,
          l10n.founderMoneyTab,
          _TabId.money,
        ),
      );
      tabs.add(
        _PanelTab(
          Icons.security_rounded,
          l10n.founderSecurityTab,
          _TabId.security,
        ),
      );
    }
    if (admin || has('guardian')) {
      tabs.add(
        _PanelTab(
          Icons.engineering_rounded,
          l10n.founderMaintenanceTab,
          _TabId.maintenance,
        ),
      );
    }
    if (admin || has('support') || has('moderation')) {
      tabs.add(
        _PanelTab(
          Icons.notifications_active_rounded,
          l10n.founderNotificationsTab,
          _TabId.notifications,
        ),
      );
    }
    if (admin || has('roles')) {
      tabs.add(
        _PanelTab(
          Icons.cleaning_services_rounded,
          l10n.founderKingTab,
          _TabId.king,
        ),
      );
    }
    if (admin || has('settings')) {
      tabs.add(
        _PanelTab(Icons.tune_rounded, l10n.founderConfigTab, _TabId.config),
      );
    }
    if (has('economy')) {
      tabs.add(
        _PanelTab(
          Icons.account_balance_wallet_rounded,
          l10n.economyTab,
          _TabId.economy,
        ),
      );
    }
    if (has('chests')) {
      tabs.add(
        _PanelTab(Icons.inventory_2_rounded, l10n.chestsTab, _TabId.chests),
      );
    }
    if (has('missions')) {
      tabs.add(
        _PanelTab(
          Icons.military_tech_rounded,
          l10n.missionsTab,
          _TabId.missions,
        ),
      );
    }
    if (admin) {
      tabs.add(
        _PanelTab(Icons.card_giftcard_rounded, l10n.giftsTitle, _TabId.gifts),
      );
      tabs.add(_PanelTab(Icons.shopping_bag_rounded, l10n.store, _TabId.store));
      tabs.add(
        _PanelTab(Icons.sensors_rounded, l10n.liveTabLabel, _TabId.live),
      );
    }
    if (has('audit')) {
      tabs.add(
        _PanelTab(Icons.fact_check_rounded, l10n.auditTab, _TabId.audit),
      );
    }
    if (admin) {
      tabs.add(
        _PanelTab(
          Icons.admin_panel_settings_rounded,
          l10n.adminTab,
          _TabId.admin,
        ),
      );
      tabs.add(
        _PanelTab(Icons.work_rounded, l10n.professionsTab, _TabId.professions),
      );
      tabs.add(_PanelTab(Icons.smart_toy_rounded, l10n.botsTab, _TabId.bots));
      tabs.add(_PanelTab(Icons.campaign_rounded, l10n.adsTab, _TabId.ads));
    }
    return tabs;
  }

  void _refreshAll() {
    _overview = _svc.stats().catchError((_) => const <String, dynamic>{});
    _reports = _social.modListReports().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _users = _svc.listUsers().catchError((_) => const <Map<String, dynamic>>[]);
    _orders = _svc.listOrders().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _lives = _svc.liveStats().catchError((_) => const <String, dynamic>{});
    _admins = _svc.listAdmins().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _giftStats = _svc.giftStats().catchError((_) => const <String, dynamic>{});
    _catalog = _gifts.fetchPopular(limit: 15).catchError((_) => const <Gift>[]);
    _store = _svc.storeStats().catchError((_) => const <String, dynamic>{});
    _rules = _social.modListSpamRules().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _verifications = _admin
        .adminListVerifications('pending')
        .catchError((_) => const <Map<String, dynamic>>[]);
    _tickets = _admin
        .adminListTickets('open')
        .catchError((_) => const <Map<String, dynamic>>[]);
    _staff = _admin.adminListStaff().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _economy = _admin.adminEconomyStats().catchError(
      (_) => const <String, dynamic>{},
    );
    _finance = _financeSvc.adminFinanceStats().catchError(
      (_) => const <String, dynamic>{},
    );
    _payouts = _financeSvc.adminListPayouts().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _financeOrders = _financeSvc
        .adminFinanceOrders(limit: 12)
        .catchError((_) => const <Map<String, dynamic>>[]);
    _chests = _admin.adminChestStats().catchError(
      (_) => const <String, dynamic>{},
    );
    _chestCatalog = _admin.adminListChests().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _audit = _admin
        .adminAuditList(limit: 80)
        .catchError((_) => const <Map<String, dynamic>>[]);
    _professions = _admin.adminListProfessions().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _bots = _admin.adminListBots().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _pendingConversions = _adminPendingConversions();
    _posts = _admin.adminListPosts().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    _dash = _svc.dashboard().catchError((_) => const <String, dynamic>{});
  }

  void _refreshDashboardOnly() {
    _dash = _svc.dashboard().catchError((_) => const <String, dynamic>{});
  }

  void _reload() => setState(_refreshAll);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: _tabs.isEmpty ? 1 : _tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0812),
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isAdmin == true ? l10n.founderPanelTitle : l10n.teamPanelTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                l10n.founderRoleCaps(_role.isEmpty ? '…' : _role, _caps.length),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0A0812),
          bottom: _tabs.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: TabBar(
                    isScrollable: true,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    indicatorColor: const Color(0xFF8B5CF6),
                    indicatorWeight: 3,
                    dividerColor: Colors.transparent,
                    tabs: [
                      for (final t in _tabs)
                        Tab(icon: Icon(t.icon), text: t.label),
                    ],
                  ),
                ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_adminError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white38,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.founderAccessFail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _checking = true;
                  _adminError = false;
                });
                _check();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                side: const BorderSide(color: Color(0xFF8B5CF6)),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    if (_checking) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            const SizedBox(height: 14),
            Text(
              l10n.checkingPermissions,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    if (_isAdmin == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            const SizedBox(height: 14),
            Text(
              l10n.checkingPermissions,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    if (_tabs.isEmpty) {
      return const _RestrictedView();
    }
    return TabBarView(children: [for (final t in _tabs) _tabView(t.id)]);
  }

  Widget _tabView(_TabId id) {
    switch (id) {
      case _TabId.overview:
        return _overviewTab();
      case _TabId.moderation:
        return _moderationTab();
      case _TabId.posts:
        return _postsTab();
      case _TabId.users:
        return _usersTab();
      case _TabId.team:
        return _teamTab();
      case _TabId.verification:
        return _verificationTab();
      case _TabId.tickets:
        return _ticketsTab();
      case _TabId.economy:
        return _economyTab();
      case _TabId.chests:
        return _chestsTab();
      case _TabId.missions:
        return _missionsTab();
      case _TabId.audit:
        return _auditTab();
      case _TabId.gifts:
        return _giftsTab();
      case _TabId.store:
        return _storeTab();
      case _TabId.live:
        return _liveTab();
      case _TabId.admin:
        return _adminTab();
      case _TabId.professions:
        return _professionsTab();
      case _TabId.bots:
        return _botsTab();
      case _TabId.ads:
        return _adsTab();
      case _TabId.money:
        return _FounderMoneyTab(
          onChanged: () {
            _reload();
            _refreshDashboardOnly();
          },
        );
      case _TabId.security:
        return const _FounderSecurityTab();
      case _TabId.feedback:
        return const _FounderFeedbackTab();
      case _TabId.maintenance:
        return const _FounderMaintenanceTab();
      case _TabId.notifications:
        return const _FounderNotificationsTab();
      case _TabId.king:
        return const _FounderKingTab();
      case _TabId.config:
        return const _FounderConfigTab();
    }
  }

  // ---------------------------------------------------------------------------
  // 📊 Visão Geral
  // ---------------------------------------------------------------------------

  Widget _overviewTab() {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _overview;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _overview,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final s = snap.data ?? const {};
          final recentSignups = (s['recent_signups'] as List? ?? const [])
              .whereType<Map>()
              .toList();
          final recentReports = (s['recent_reports'] as List? ?? const [])
              .whereType<Map>()
              .toList();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              if (_has('roles')) ...[
                _supremeStrip(),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statCard(
                    Icons.people_rounded,
                    l10n.usersTab,
                    _num(s['users'], l10n),
                    color: const Color(0xFF8B5CF6),
                  ),
                  _statCard(
                    Icons.person_add_alt_1,
                    l10n.newUsers7d,
                    _num(s['new_users_7d'], l10n),
                    color: const Color(0xFFB794FF),
                  ),
                  _statCard(
                    Icons.video_library_rounded,
                    l10n.videos,
                    _num(s['videos'], l10n),
                    color: const Color(0xFF22D3EE),
                  ),
                  _statCard(
                    Icons.sensors_rounded,
                    l10n.searchScopeLives,
                    s['lives']?.toString() ?? '0',
                  ),
                  _statCard(
                    Icons.flag_rounded,
                    l10n.openReports,
                    _num(s['reports_pending'], l10n),
                    color: const Color(0xFFFF6B81),
                  ),
                  _statCard(
                    Icons.flag_outlined,
                    l10n.resolvedReports,
                    _num(s['reports_resolved'], l10n),
                  ),
                  _statCard(
                    Icons.card_giftcard_rounded,
                    l10n.giftsSent,
                    _num(s['gift_transactions'], l10n),
                    color: const Color(0xFFF59E0B),
                  ),
                  _statCard(
                    Icons.savings_rounded,
                    l10n.giftCredits,
                    _num(s['gift_credits'], l10n),
                    color: const Color(0xFFF59E0B),
                  ),
                  _statCard(
                    Icons.receipt_long_rounded,
                    l10n.ordersLabel,
                    _num(s['orders'], l10n),
                    color: const Color(0xFF34D399),
                  ),
                  _statCard(
                    Icons.payments_rounded,
                    l10n.storeRevenue,
                    _money(s['orders_revenue'], l10n),
                    color: const Color(0xFF34D399),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionTitle(l10n.recentSignupsTitle),
              const SizedBox(height: 8),
              if (recentSignups.isEmpty)
                _empty(l10n.noRecentSignups)
              else
                ...recentSignups.map(
                  (e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.person_outline,
                      color: Color(0xFFB794FF),
                      size: 20,
                    ),
                    title: Text(
                      '${e['display_name'] ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    subtitle: Text(
                      '@${e['username'] ?? ''}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    trailing: Text(
                      _relativeTime(e['created_at'] as String?, l10n),
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              _sectionTitle(l10n.recentReportsTitle),
              const SizedBox(height: 8),
              if (recentReports.isEmpty)
                _empty(l10n.noReports)
              else
                ...recentReports.map(
                  (e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.flag_outlined,
                      color: Color(0xFFFF6B81),
                      size: 20,
                    ),
                    title: Text(
                      '${e['target_type']} · ${e['reason'] ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    trailing: _statusChip(e['status'] as String?),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 👑 Strip "Supremo" do Dashboard (founder apenas) — métricas em tempo real
  // agregadas no backend (`founder_dashboard()`) + selo de saúde dos serviços
  // (`guardian_health()` embutido). Nada é calculado no cliente.
  // ---------------------------------------------------------------------------
  Widget _supremeStrip() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _dash,
      builder: (context, snap) {
        final d = snap.data ?? const {};
        if (d.isEmpty) return const SizedBox.shrink();
        final health = d['health'] is Map
            ? Map<String, dynamic>.from(d['health'] as Map)
            : const <String, dynamic>{};
        final alertsOpen = (health['alerts_open'] as num?)?.toInt() ?? 0;
        final maintenance =
            (health['active_maintenance'] as num?)?.toInt() ?? 0;
        final statusColor = alertsOpen > 0
            ? const Color(0xFFFF3B4D)
            : maintenance > 0
            ? const Color(0xFFFFB300)
            : const Color(0xFF2E7D32);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF211447), Color(0xFF161130), Color(0xFF0E1124)],
            ),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.founderStatusLabel(alertsOpen, maintenance),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _relativeTime(d['generated_at'] as String?, l10n),
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statCard(
                    Icons.sensors_rounded,
                    l10n.founderLiveNow,
                    '${d['active_lives'] ?? 0}',
                    color: const Color(0xFFFF3B4D),
                  ),
                  _statCard(
                    Icons.visibility_rounded,
                    l10n.founderViewersNow,
                    _num(d['total_viewers'], l10n),
                    color: const Color(0xFFB794FF),
                  ),
                  _statCard(
                    Icons.card_giftcard_rounded,
                    l10n.founderGiftsToday,
                    _num(d['gifts_today'], l10n),
                    color: const Color(0xFFF59E0B),
                  ),
                  _statCard(
                    Icons.diamond_outlined,
                    l10n.founderDiamonds7d,
                    _num(d['diamonds_spent_7d'], l10n),
                    color: const Color(0xFF38BDF8),
                  ),
                  _statCard(
                    Icons.trending_up_rounded,
                    l10n.founderRetentionD30,
                    '${d['retention_d30'] ?? 0}%',
                    color: const Color(0xFF34D399),
                  ),
                  _statCard(
                    Icons.group_rounded,
                    l10n.founderNew7d,
                    _num(d['new_users_7d'], l10n),
                    color: const Color(0xFFE879F9),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🛡️ Moderação
  // ---------------------------------------------------------------------------

  Widget _moderationTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _reports,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final reports = snap.data ?? const [];
        if (reports.isEmpty) return _emptyScroll(l10n.noReports);
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
          itemBuilder: (context, index) {
            final r = reports[index];
            final id = r['id']?.toString() ?? '';
            return Column(
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
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${r['target_type']}',
                        style: const TextStyle(
                          color: Color(0xFFB794FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _statusChip(r['status'] as String?),
                    const Spacer(),
                    Text(
                      _relativeTime(r['created_at'] as String?, l10n),
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.reportTarget('${r['target_id']}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  r['reason']?.toString() ?? '—',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                if ((r['details'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    r['details'].toString(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _resolveReport(id, 'resolved'),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(l10n.resolveAction),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF34D399),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _resolveReport(id, 'dismissed'),
                      icon: const Icon(Icons.block, size: 18),
                      label: Text(l10n.dismissAction),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _resolveReport(String id, String status) async {
    await _svcGuard(() => _social.modUpdateReport(id, status));
    _reload();
  }

  // ---------------------------------------------------------------------------
  // 📹 Publicações (cap: moderation — exclusão de conteúdo de qualquer autor)
  // ---------------------------------------------------------------------------

  Widget _postsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _posts,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final posts = snap.data ?? const [];
        if (posts.isEmpty) return _emptyScroll(l10n.noPosts);
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _posts = _admin.adminListPosts().catchError(
                (_) => const <Map<String, dynamic>>[],
              );
            });
            await _posts;
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
            itemBuilder: (context, index) => _postRow(posts[index]),
          ),
        );
      },
    );
  }

  Widget _postRow(Map<String, dynamic> p) {
    final l10n = AppLocalizations.of(context)!;
    final rawAuthor = p['profiles'];
    final author = rawAuthor is Map
        ? Map<String, dynamic>.from(
            rawAuthor.map((k, v) => MapEntry(k.toString(), v)),
          )
        : const <String, dynamic>{};
    final authorName =
        author['display_name']?.toString() ?? author['username']?.toString();
    final username = author['username']?.toString() ?? '';
    final desc = (p['description']?.toString() ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desc.isEmpty ? l10n.videoNoDescription : desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (authorName != null && authorName.isNotEmpty)
                        authorName,
                      if (username.isNotEmpty) '@$username',
                      _relativeTime(p['created_at'] as String?, l10n),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.likesAndComments(
                      _num(p['likes_count'], l10n),
                      _num(p['comments_count'], l10n),
                    ),
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.deletePostTooltip,
              onPressed: _postBusy ? null : () => _deletePost(p),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deletePost(Map<String, dynamic> p) async {
    final l10n = AppLocalizations.of(context)!;
    final id = p['id']?.toString();
    if (id == null || _postBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.deletePostTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          l10n.deletePostBody,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _postBusy = true);
    bool done = false;
    try {
      final res = await _admin.adminDeletePost(id);
      done = res['ok'] == true || res['id'] != null;
      _okSnack(done ? l10n.postDeleted : l10n.noServerResponse);
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    } finally {
      if (mounted) setState(() => _postBusy = false);
    }
    if (mounted) {
      setState(() {
        _posts = _admin.adminListPosts().catchError(
          (_) => const <Map<String, dynamic>>[],
        );
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 👥 Usuários
  // ---------------------------------------------------------------------------

  Widget _usersTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final users = snap.data ?? const [];
        if (users.isEmpty) return _emptyScroll(l10n.noUsers);
        final me = SupabaseService.instance.currentUser?.id;
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
          itemBuilder: (context, index) {
            final u = users[index];
            final id = u['id']?.toString() ?? '';
            final isMe = id == me;
            final verified = u['is_verified'] == true;
            final admin = u['is_admin'] == true;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _openUserSheet(u),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF2A2145),
                child: Text(
                  (u['display_name']?.toString() ?? '?').characters.first
                      .toUpperCase(),
                  style: const TextStyle(color: Color(0xFFB794FF)),
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      '${u['display_name'] ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    const VerifiedBadge(size: 15),
                  ],
                  if (admin) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 15,
                    ),
                  ],
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Text(
                      l10n.youLabel,
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                '@${u['username'] ?? ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: isMe
                  ? const Text('—', style: TextStyle(color: Colors.white24))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.assignProfessionTooltip,
                          icon: const Icon(
                            Icons.badge_rounded,
                            color: Color(0xFFB794FF),
                            size: 21,
                          ),
                          onPressed: () => _openUserSheet(u),
                        ),
                        IconButton(
                          tooltip: verified
                              ? l10n.unverifyTooltip
                              : l10n.verifyProfileTooltip,
                          icon: Icon(
                            verified
                                ? Icons.verified_rounded
                                : Icons.verified_outlined,
                            color: verified
                                ? const Color(0xFF22D3EE)
                                : Colors.white38,
                            size: 21,
                          ),
                          onPressed: () async {
                            await _svcGuard(
                              () => _svc.setVerified(id, !verified),
                            );
                            _reload();
                          },
                        ),
                        IconButton(
                          tooltip: admin
                              ? l10n.removeAdminTooltip
                              : l10n.makeAdminTooltip,
                          icon: Icon(
                            admin
                                ? Icons.workspace_premium_rounded
                                : Icons.workspace_premium_outlined,
                            color: admin
                                ? const Color(0xFF8B5CF6)
                                : Colors.white38,
                            size: 21,
                          ),
                          onPressed: () async {
                            await _svcGuard(() => _svc.setAdmin(id, !admin));
                            _reload();
                          },
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🎭 Profissão do usuário (tab Usuários)
  // ---------------------------------------------------------------------------

  Future<void> _openUserSheet(Map<String, dynamic> u) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15131E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _UserProfessionSheet(user: u, onRefresh: _reload),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎁 Presentes
  // ---------------------------------------------------------------------------

  Widget _giftsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _giftStats,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final s = snap.data ?? const {};
        final top = (s['top'] as List? ?? const []).whereType<Map>().toList();
        final catalog = _catalog;
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  Icons.card_giftcard_rounded,
                  l10n.transactionsLabel,
                  _num(s['transactions'], l10n),
                  color: const Color(0xFFF59E0B),
                ),
                _statCard(
                  Icons.savings_rounded,
                  l10n.creditsMoved,
                  _num(s['credits'], l10n),
                  color: const Color(0xFFF59E0B),
                ),
                _statCard(
                  Icons.auto_awesome,
                  l10n.activeGifts,
                  _num(s['gifts'], l10n),
                  color: const Color(0xFFB794FF),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle(l10n.mostSentTitle),
            const SizedBox(height: 8),
            if (top.isEmpty)
              _empty(l10n.noGiftSendsYet)
            else
              ...top.map((g) {
                final name = '${g['name'] ?? g['id']}';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  trailing: Text(
                    '${_num(g['count'], l10n)}x',
                    style: const TextStyle(
                      color: Color(0xFFB794FF),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }),
            const SizedBox(height: 18),
            _sectionTitle(l10n.catalogLabel),
            const SizedBox(height: 8),
            FutureBuilder<List<Gift>>(
              future: catalog,
              builder: (context, snapG) {
                if (snapG.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                  );
                }
                final gifts = snapG.data ?? const [];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in gifts)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C2E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFF8B5CF6,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '${g.icon} ${g.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🛒 Loja
  // ---------------------------------------------------------------------------

  Widget _storeTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _store,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final s = snap.data ?? const {};
        final status = (s['by_status'] as Map? ?? const {});
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  Icons.inventory_2_rounded,
                  l10n.productsLabel,
                  _num(s['products'], l10n),
                  color: const Color(0xFF34D399),
                ),
                _statCard(
                  Icons.category_rounded,
                  l10n.categoriesLabel,
                  _num(s['categories'], l10n),
                ),
                _statCard(
                  Icons.storefront_rounded,
                  l10n.sellersLabel,
                  _num(s['sellers'], l10n),
                ),
                _statCard(
                  Icons.receipt_long_rounded,
                  l10n.ordersLabel,
                  _num(s['orders'], l10n),
                  color: const Color(0xFF34D399),
                ),
                _statCard(
                  Icons.payments_rounded,
                  l10n.revenueLabel,
                  _money(s['revenue'], l10n),
                  color: const Color(0xFF34D399),
                ),
              ],
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionTitle(l10n.ordersByStatusTitle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in status.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_statusLabel(e.key, l10n)}: ${_num(e.value, l10n)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle(l10n.lastOrdersTitle),
            const SizedBox(height: 4),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _orders,
              builder: (context, snapO) {
                if (snapO.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 40);
                }
                final orders = snapO.data ?? const [];
                if (orders.isEmpty) return _empty(l10n.noOrders);
                return Column(
                  children: [
                    for (final o in orders)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.shopping_bag_rounded,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                        title: Text(
                          '${o['buyer_username'] ?? o['buyer_name'] ?? '—'} → '
                          '${o['seller_username'] ?? o['seller_name'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${_statusLabel(o['status'] as String?, l10n)} · ${_relativeTime(o['created_at'] as String?, l10n)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Text(
                          _money(o['total'], l10n),
                          style: const TextStyle(
                            color: Color(0xFF34D399),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 📺 LIVE
  // ---------------------------------------------------------------------------

  Widget _liveTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _lives,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final s = snap.data ?? const {};
        final list = (s['active_list'] as List? ?? const [])
            .whereType<Map>()
            .toList();
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  Icons.sensors_rounded,
                  l10n.totalLives,
                  _num(s['total'], l10n),
                ),
                _statCard(
                  Icons.live_tv_rounded,
                  l10n.liveNowLabel,
                  _num(s['active'], l10n),
                  color: const Color(0xFFFF2E4D),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle(l10n.activeStreamsTitle),
            const SizedBox(height: 8),
            if (list.isEmpty)
              _empty(l10n.noActiveLives)
            else
              ...list.map(
                (l) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.circle,
                    color: Color(0xFFFF2E4D),
                    size: 12,
                  ),
                  title: Text(
                    '${l['title'] ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${l['category'] ?? ''}${(l['game_name'] as String? ?? '').isNotEmpty ? ' · 🎮 ${l['game_name']}' : ''} · '
                    '${l['streamer_display'] ?? l['streamer_username'] ?? '—'} · '
                    '${_num(l['viewer_count'], l10n)} ${l10n.viewersAbbrev}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ⚙️ Administração
  // ---------------------------------------------------------------------------

  Widget _adminTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _admins,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final admins = snap.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _sectionTitle(l10n.foundersAdminsTitle),
            const SizedBox(height: 8),
            if (admins.isEmpty)
              _empty(l10n.noAdmins)
            else
              ...admins.map(
                (a) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFF8B5CF6),
                  ),
                  title: Text(
                    '${a['display_name'] ?? '—'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '@${a['username'] ?? ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            _sectionTitle(l10n.antispamRulesTitle),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _rules,
              builder: (context, snapR) {
                if (snapR.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 30);
                }
                final rules = snapR.data ?? const [];
                if (rules.isEmpty) return _empty(l10n.noAntispamRules);
                return Column(
                  children: [
                    for (final r in rules)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.gpp_good_outlined,
                          color: Color(0xFFB794FF),
                          size: 20,
                        ),
                        title: Text(
                          '${r['pattern'] ?? '—'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${r['rule_type'] ?? ''} · ${r['scope'] ?? ''}${r['active'] == false ? ' · ${l10n.inactiveLabel}' : ''}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ Verificação (cap: verification / verification_view)
  // ---------------------------------------------------------------------------

  Widget _verificationTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _verifications,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final items = snap.data ?? const [];
        final canReview = _has('verification');
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _verifications = _admin
                  .adminListVerifications('pending')
                  .catchError((_) => const <Map<String, dynamic>>[]);
            });
            await _verifications;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle(l10n.verificationRequestsTitle),
              const SizedBox(height: 4),
              Text(
                canReview
                    ? l10n.canApproveOrRejectHint
                    : l10n.viewOnlyVerificationHint,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                _emptyScroll(l10n.noPendingRequests)
              else
                ...items.map((v) => _verificationCard(v, canReview)),
            ],
          ),
        );
      },
    );
  }

  Widget _verificationCard(Map<String, dynamic> v, bool canReview) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.badge_rounded,
                color: Color(0xFFB794FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v['display_name']?.toString() ??
                      v['username']?.toString() ??
                      '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _statusChip(v['status']?.toString()),
            ],
          ),
          Text(
            '@${v['username'] ?? ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (v['reason']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              v['reason'].toString(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          Text(
            l10n.submittedAt(
              _relativeTime(v['submitted_at']?.toString(), l10n),
            ),
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
          if (canReview) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _reviewVerification(v['id']?.toString(), true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF34D399),
                      side: const BorderSide(color: Color(0xFF34D399)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(l10n.approveAction),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _reviewVerification(v['id']?.toString(), false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B81),
                      side: const BorderSide(color: Color(0xFFFF6B81)),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(l10n.rejectAction),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reviewVerification(String? id, bool approve) async {
    final l10n = AppLocalizations.of(context)!;
    if (id == null) return;
    try {
      final res = await _admin.adminReviewVerification(id, approve: approve);
      final ok = res['ok'] == true || res['status'] != null;
      _okSnack(
        ok
            ? (approve ? l10n.verificationApproved : l10n.verificationRejected)
            : l10n.noServerResponse,
      );
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _verifications = _admin
            .adminListVerifications('pending')
            .catchError((_) => const <Map<String, dynamic>>[]);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 🎫 Suporte / Tickets (cap: support / tickets)
  // ---------------------------------------------------------------------------

  Widget _ticketsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tickets,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final items = snap.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _tickets = _admin
                  .adminListTickets('open')
                  .catchError((_) => const <Map<String, dynamic>>[]);
            });
            await _tickets;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle(l10n.openTicketsTitle),
              const SizedBox(height: 10),
              if (items.isEmpty)
                _emptyScroll(l10n.noOpenTickets)
              else
                ...items.map((t) => _ticketCard(t)),
            ],
          ),
        );
      },
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final l10n = AppLocalizations.of(context)!;
    final message = t['subject']?.toString() ?? t['message']?.toString() ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.support_agent_rounded,
                color: Color(0xFF8B5CF6),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t['username'] ?? '—'} · ${t['status'] ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openTicketDialog(t),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB794FF),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.reply_rounded, size: 16),
            label: Text(l10n.replyUpdateAction),
          ),
        ],
      ),
    );
  }

  Future<void> _openTicketDialog(Map<String, dynamic> t) async {
    final l10n = AppLocalizations.of(context)!;
    final statusCtrl = TextEditingController(
      text: (t['status'] ?? 'open').toString(),
    );
    final replyCtrl = TextEditingController();
    final id = t['id']?.toString();
    if (id == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.updateTicketTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: (t['status'] ?? 'open').toString(),
              dropdownColor: const Color(0xFF15131E),
              decoration: InputDecoration(labelText: l10n.statusLabel),
              items: [
                DropdownMenuItem(value: 'open', child: Text(l10n.statusOpen)),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text(l10n.statusInProgress),
                ),
                DropdownMenuItem(
                  value: 'closed',
                  child: Text(l10n.statusClosed),
                ),
              ],
              onChanged: (v) => statusCtrl.text = v ?? 'open',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: replyCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: l10n.replyLabel,
                hintText: l10n.replyHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await _admin.adminReplyTicket(
                  id,
                  status: statusCtrl.text,
                  reply: replyCtrl.text,
                );
                _okSnack(l10n.ticketUpdated);
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _tickets = _admin
                      .adminListTickets('open')
                      .catchError((_) => const <Map<String, dynamic>>[]);
                });
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 👥 Equipe (cap: roles — founder)
  // ---------------------------------------------------------------------------

  Widget _teamTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _staff,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final items = snap.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _staff = _admin.adminListStaff().catchError(
                (_) => const <Map<String, dynamic>>[],
              );
            });
            await _staff;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle(l10n.teamAndRolesTitle),
              const SizedBox(height: 4),
              Text(
                l10n.onlyFounderRolesHint,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                _emptyScroll(l10n.noTeamMembers)
              else
                ...items.map((m) => _staffRow(m)),
            ],
          ),
        );
      },
    );
  }

  Widget _staffRow(Map<String, dynamic> m) {
    final l10n = AppLocalizations.of(context)!;
    final role = m['role']?.toString() ?? 'user';
    final canManage = _has('roles');
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFF2A1B54),
        child: Icon(Icons.person_rounded, color: Color(0xFFB794FF), size: 20),
      ),
      title: Text(
        m['display_name']?.toString() ?? m['username']?.toString() ?? '—',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '@${m['username'] ?? ''}',
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roleChip(role),
          if (canManage) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => _openRoleDialog(m),
              icon: const Icon(
                Icons.edit_rounded,
                color: Color(0xFF8B5CF6),
                size: 18,
              ),
              tooltip: l10n.changeRoleTooltip,
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleChip(String role) {
    final l10n = AppLocalizations.of(context)!;
    const colors = {
      'founder': Color(0xFFD4AF37),
      'super_admin': Color(0xFFF59E0B),
      'admin': Color(0xFF8B5CF6),
      'moderator': Color(0xFF38BDF8),
      'support': Color(0xFF34D399),
    };
    final color = colors[role] ?? Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _roleLabel(role, l10n),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _roleLabel(String role, AppLocalizations l10n) {
    return switch (role) {
      'founder' => l10n.roleFounder,
      'super_admin' => l10n.roleSuperAdmin,
      'admin' => l10n.roleAdmin,
      'moderator' => l10n.roleModerator,
      'support' => l10n.roleSupport,
      'user' => l10n.roleUser,
      _ => role.replaceAll('_', ' '),
    };
  }

  Future<void> _openRoleDialog(Map<String, dynamic> m) async {
    final l10n = AppLocalizations.of(context)!;
    final uid = m['id']?.toString();
    if (uid == null) return;
    final current = m['role']?.toString() ?? 'user';
    String selected = current;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.changeRoleTooltip,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: DropdownButtonFormField<String>(
          initialValue: current,
          dropdownColor: const Color(0xFF15131E),
          decoration: InputDecoration(labelText: l10n.roleLabel),
          items: [
            DropdownMenuItem(value: 'founder', child: Text(l10n.roleFounder)),
            DropdownMenuItem(
              value: 'super_admin',
              child: Text(l10n.roleSuperAdmin),
            ),
            DropdownMenuItem(value: 'admin', child: Text(l10n.roleAdmin)),
            DropdownMenuItem(
              value: 'moderator',
              child: Text(l10n.roleModerator),
            ),
            DropdownMenuItem(value: 'support', child: Text(l10n.roleSupport)),
            DropdownMenuItem(value: 'user', child: Text(l10n.roleUser)),
          ],
          onChanged: (v) => selected = v ?? current,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (selected == current) return;
              try {
                await _admin.adminSetRole(uid, role: selected);
                _okSnack(l10n.roleUpdated(_roleLabel(selected, l10n)));
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _staff = _admin.adminListStaff().catchError(
                    (_) => const <Map<String, dynamic>>[],
                  );
                });
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💰 Economia (cap: economy)
  // ---------------------------------------------------------------------------

  Widget _economyTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _economy,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final s = snap.data ?? const {};
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _sectionTitle(l10n.totalInCirculationTitle),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  Icons.stars_rounded,
                  'Credits',
                  _num(s['credits'], l10n),
                  color: const Color(0xFFF59E0B),
                ),
                _statCard(
                  Icons.diamond_outlined,
                  'Diamonds',
                  _num(s['diamonds'], l10n),
                  color: const Color(0xFF38BDF8),
                ),
                _statCard(
                  Icons.diamond_outlined,
                  'Crystals',
                  _num(s['crystals'], l10n),
                  color: const Color(0xFFE879F9),
                ),
                _statCard(
                  Icons.circle_rounded,
                  'Rubies',
                  _num(s['rubies'], l10n),
                  color: const Color(0xFFFF4D6A),
                ),
                _statCard(
                  Icons.eco_rounded,
                  'Emeralds',
                  _num(s['emeralds'], l10n),
                  color: const Color(0xFF34D399),
                ),
                _statCard(
                  Icons.diamond_rounded,
                  'Crystal Rare',
                  _num(s['crystal_rare'], l10n),
                  color: const Color(0xFFD4AF37),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _grantCurrencyForm(),
            const SizedBox(height: 18),
            _conversionsSection(),
            const SizedBox(height: 26),
            _financeSection(),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 💳 Finanças centralizadas (KLAY K FINANCE — cap economy)
  // ---------------------------------------------------------------------------

  Widget _financeSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('KLAY K FINANCE'),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, dynamic>>(
          future: _finance,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _loadingList();
            }
            final s = snap.data ?? const {};
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  Icons.receipt_long_rounded,
                  l10n.financeOrdersTotal,
                  _num(s['orders_total'], l10n),
                  color: const Color(0xFF8B5CF6),
                ),
                _statCard(
                  Icons.check_circle_outline_rounded,
                  l10n.financeOrdersPaid,
                  _num(s['orders_paid'], l10n),
                  color: const Color(0xFF34D399),
                ),
                _statCard(
                  Icons.payments_rounded,
                  l10n.financeRevenueLabel,
                  _money(_centsToReais(s['revenue_cents']), l10n),
                  color: const Color(0xFFF59E0B),
                ),
                _statCard(
                  Icons.emoji_events_rounded,
                  l10n.financeGiftNet,
                  _num(s['gift_earnings_net'], l10n),
                  color: const Color(0xFFFF4D6A),
                ),
                _statCard(
                  Icons.percent_rounded,
                  l10n.financeGiftFees,
                  _num(s['gift_earnings_fees'], l10n),
                  color: const Color(0xFF38BDF8),
                ),
                _statCard(
                  Icons.volunteer_activism_rounded,
                  l10n.financeCreatorAvailable,
                  _num(s['creator_available'], l10n),
                  color: const Color(0xFF34D399),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _sectionTitle(l10n.financePendingPayouts),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _payouts,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                ),
              );
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF15131E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.financeNoPending,
                  style: const TextStyle(color: Colors.white38),
                ),
              );
            }
            return Column(
              children: [for (final r in list) _payoutTile(r, l10n)],
            );
          },
        ),
        const SizedBox(height: 16),
        _sectionTitle(l10n.financeIntegrityTitle),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _checkIntegrity,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF8B5CF6),
            side: const BorderSide(color: Color(0xFF8B5CF6)),
          ),
          icon: const Icon(Icons.shield_rounded, size: 18),
          label: Text(l10n.financeIntegrityCheck),
        ),
        const SizedBox(height: 16),
        _sectionTitle(l10n.financeRecentOrders),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _financeOrders,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _loadingList();
            }
            if ((snap.data ?? const []).isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF15131E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.financeNoData,
                  style: const TextStyle(color: Colors.white38),
                ),
              );
            }
            return Column(
              children: [
                for (final o in snap.data!) _financeOrderTile(o, l10n),
              ],
            );
          },
        ),
      ],
    );
  }

  double _centsToReais(Object? cents) {
    final c = cents is num ? cents.toDouble() : 0;
    return c / 100;
  }

  Future<void> _checkIntegrity() async {
    final l10n = AppLocalizations.of(context)!;
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1B1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Padding(
          padding: EdgeInsets.all(22),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Color(0xFF8B5CF6),
                ),
              ),
              SizedBox(width: 16),
              Text(
                'Verificando integridade…',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final res = await _financeSvc.financeIntegrityCheck();
      if (!mounted) return;
      Navigator.of(context).pop();
      final anomalies = res['anomalies'];
      final alert = res['integrity']?.toString() == 'FINANCIAL_INTEGRITY_ALERT';
      final count = anomalies is List ? anomalies.length : 0;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1B1A26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            alert ? l10n.financeIntegrityAlert : l10n.financeIntegrityOk,
            style: TextStyle(
              color: alert ? const Color(0xFFFF6B81) : const Color(0xFF34D399),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            l10n.financeIntegrityResult(count),
            style: const TextStyle(color: Colors.white54),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              child: Text(l10n.okLabel),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Widget _payoutTile(Map<String, dynamic> r, AppLocalizations l10n) {
    final amount = (r['amount_credits'] as num?)?.toInt() ?? 0;
    final userId = r['user_id']?.toString() ?? '';
    final shortId = userId.length > 8
        ? '…${userId.substring(userId.length - 8)}'
        : userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_num(amount, l10n)} credits',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.userColon}$shortId',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _decidePayout(r['id'], approve: true),
            tooltip: l10n.approveAction,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x1F34D399),
            ),
            icon: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF34D399),
              size: 20,
            ),
          ),
          IconButton(
            onPressed: () => _decidePayout(r['id'], approve: false),
            tooltip: l10n.rejectAction,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x22FF6B81),
            ),
            icon: const Icon(
              Icons.cancel_rounded,
              color: Color(0xFFFF6B81),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _decidePayout(Object? id, {required bool approve}) async {
    if (id == null) return;
    try {
      await _financeSvc.adminPayoutDecision(id.toString(), approve: approve);
      if (!mounted) return;
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FinanceService.friendlyError('not_admin'))),
      );
    }
  }

  Widget _financeOrderTile(Map<String, dynamic> o, AppLocalizations l10n) {
    final status = o['status']?.toString() ?? '';
    final priceCents = (o['total_price_cents'] as num?)?.toDouble() ?? 0;
    final product = o['product_name']?.toString() ?? '—';
    final username = o['username']?.toString() ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@$username · ${_statusLabel(status, l10n)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            _money(_centsToReais(priceCents), l10n),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💱 Conversões/resgates (gestão admin/fundador)
  // ---------------------------------------------------------------------------

  Widget _conversionsSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.pendingConversionsTitle),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _pendingConversions,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                ),
              );
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF15131E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.noPendingConversions,
                  style: const TextStyle(color: Colors.white38),
                ),
              );
            }
            return Column(
              children: [
                for (final r in list) _conversionTile(r),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _refreshPendingConversions,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(l10n.refreshLabel),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _conversionSettingsForm(),
      ],
    );
  }

  Widget _conversionTile(Map<String, dynamic> r) {
    final l10n = AppLocalizations.of(context)!;
    final from = r['from_currency']?.toString() ?? '?';
    final to = r['to_currency']?.toString() ?? '?';
    final amount = (r['amount'] as num?)?.toInt() ?? 0;
    final received = (r['received'] as num?)?.toInt() ?? 0;
    final userId = r['user_id']?.toString() ?? '';
    final shortId = userId.length > 8
        ? '…${userId.substring(userId.length - 8)}'
        : userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_num(amount, l10n)} $from → ${_num(received, l10n)} $to',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.userColon}$shortId',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _decideConversion(r['id'], approve: true),
            tooltip: l10n.approveAction,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x1FFFD700),
            ),
            icon: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF34D399),
              size: 20,
            ),
          ),
          IconButton(
            onPressed: () => _decideConversion(r['id'], approve: false),
            tooltip: l10n.rejectRefundsTooltip,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x22FF6B81),
            ),
            icon: const Icon(
              Icons.cancel_rounded,
              color: Color(0xFFFF6B81),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _decideConversion(Object? id, {required bool approve}) async {
    final l10n = AppLocalizations.of(context)!;
    if (id == null) return;
    try {
      await _svc.decideConversion(id.toString(), approve: approve);
      _okSnack(approve ? l10n.conversionApproved : l10n.conversionRejected);
      _refreshPendingConversions();
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
  }

  void _refreshPendingConversions() {
    setState(() {
      _pendingConversions = _adminPendingConversions();
    });
  }

  Future<List<Map<String, dynamic>>> _adminPendingConversions() async {
    try {
      return await _svc.pendingConversions();
    } catch (_) {
      return const [];
    }
  }

  Widget _conversionSettingsForm() {
    final l10n = AppLocalizations.of(context)!;
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '1');
    final minCtrl = TextEditingController(text: '100');
    final maxCtrl = TextEditingController(text: '10000');
    final feeCtrl = TextEditingController(text: '0');
    final descCtrl = TextEditingController();
    String from = 'credits';
    String to = 'diamonds';
    String status = 'active';
    String method = 'wallet';
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF15131E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.newConversionRuleTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: idCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.ruleIdLabel),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.nameLabel),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: from,
                      dropdownColor: const Color(0xFF15131E),
                      decoration: InputDecoration(labelText: l10n.fromLabel),
                      items: const [
                        DropdownMenuItem(
                          value: 'credits',
                          child: Text('Credits'),
                        ),
                        DropdownMenuItem(
                          value: 'diamonds',
                          child: Text('Diamonds'),
                        ),
                        DropdownMenuItem(
                          value: 'crystals',
                          child: Text('Crystals'),
                        ),
                        DropdownMenuItem(
                          value: 'rubies',
                          child: Text('Rubies'),
                        ),
                        DropdownMenuItem(
                          value: 'emeralds',
                          child: Text('Emeralds'),
                        ),
                      ],
                      onChanged: (v) => setLocalState(() => from = v ?? from),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: to,
                      dropdownColor: const Color(0xFF15131E),
                      decoration: InputDecoration(labelText: l10n.toLabel),
                      items: const [
                        DropdownMenuItem(
                          value: 'credits',
                          child: Text('Credits'),
                        ),
                        DropdownMenuItem(
                          value: 'diamonds',
                          child: Text('Diamonds'),
                        ),
                        DropdownMenuItem(
                          value: 'crystals',
                          child: Text('Crystals'),
                        ),
                        DropdownMenuItem(
                          value: 'rubies',
                          child: Text('Rubies'),
                        ),
                        DropdownMenuItem(
                          value: 'emeralds',
                          child: Text('Emeralds'),
                        ),
                        DropdownMenuItem(
                          value: 'crystal_rare',
                          child: Text('Crystal Rare'),
                        ),
                      ],
                      onChanged: (v) => setLocalState(() => to = v ?? to),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(labelText: l10n.rateLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(labelText: l10n.minLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(labelText: l10n.maxLabel),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: feeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(labelText: l10n.feeLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: status,
                      dropdownColor: const Color(0xFF15131E),
                      decoration: InputDecoration(labelText: l10n.statusLabel),
                      items: [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text(l10n.ruleActive),
                        ),
                        DropdownMenuItem(
                          value: 'paused',
                          child: Text(l10n.rulePaused),
                        ),
                      ],
                      onChanged: (v) =>
                          setLocalState(() => status = v ?? status),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: method,
                      dropdownColor: const Color(0xFF15131E),
                      decoration: InputDecoration(labelText: l10n.methodLabel),
                      items: [
                        DropdownMenuItem(
                          value: 'wallet',
                          child: Text(l10n.walletLabel),
                        ),
                        DropdownMenuItem(
                          value: 'rescue',
                          child: Text(l10n.rescueLabel),
                        ),
                      ],
                      onChanged: (v) =>
                          setLocalState(() => method = v ?? method),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.descriptionOptionalLabel,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final id = idCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    final rate = double.tryParse(rateCtrl.text.trim());
                    final min = int.tryParse(minCtrl.text.trim());
                    final max = int.tryParse(maxCtrl.text.trim());
                    final fee = double.tryParse(feeCtrl.text.trim()) ?? 0;
                    if (id.isEmpty ||
                        name.isEmpty ||
                        rate == null ||
                        rate <= 0 ||
                        min == null ||
                        max == null) {
                      _errSnack(l10n.fillRuleFieldsError);
                      return;
                    }
                    try {
                      await _svc.saveConversionSettings(
                        id: id,
                        name: name,
                        fromCurrency: from,
                        toCurrency: to,
                        rate: rate,
                        min: min,
                        max: max,
                        feePercent: fee,
                        status: status,
                        method: method,
                        description: descCtrl.text.trim(),
                      );
                      _okSnack(l10n.conversionRuleSaved);
                    } catch (e) {
                      _errSnack(_admin.friendlyError(e));
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text(l10n.saveRuleAction),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grantCurrencyForm() {
    final l10n = AppLocalizations.of(context)!;
    final userIdCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: '100');
    final noteCtrl = TextEditingController();
    String currency = 'credits';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.grantCurrencyTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: userIdCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.userIdLabel,
              hintText: l10n.pasteUuidHint,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: currency,
            dropdownColor: const Color(0xFF15131E),
            decoration: InputDecoration(labelText: l10n.currencyLabel),
            items: const [
              DropdownMenuItem(value: 'credits', child: Text('Credits')),
              DropdownMenuItem(value: 'diamonds', child: Text('Diamonds')),
              DropdownMenuItem(value: 'crystals', child: Text('Crystals')),
              DropdownMenuItem(value: 'rubies', child: Text('Rubies')),
              DropdownMenuItem(value: 'emeralds', child: Text('Emeralds')),
              DropdownMenuItem(
                value: 'crystal_rare',
                child: Text('Crystal Rare'),
              ),
            ],
            onChanged: (v) => currency = v ?? 'credits',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: l10n.quantityLabel),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: l10n.reasonOptionalLabel),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final uid = userIdCtrl.text.trim();
                final amount = int.tryParse(amountCtrl.text.trim());
                if (uid.isEmpty || amount == null || amount <= 0) {
                  _errSnack(l10n.invalidUuidAmountError);
                  return;
                }
                try {
                  await _admin.adminGrantCurrency(
                    uid,
                    currency: currency,
                    amount: amount,
                    note: noteCtrl.text,
                  );
                  _okSnack(l10n.amountGranted(amount, currency));
                } catch (e) {
                  _errSnack(_admin.friendlyError(e));
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(l10n.grantAction),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📦 Baús (cap: chests)
  // ---------------------------------------------------------------------------

  Widget _chestsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _chests,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final s = snap.data ?? const {};
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _sectionTitle(l10n.serverChestsTitle),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  Icons.inventory_2_rounded,
                  l10n.activeChests,
                  _num(s['chests'], l10n),
                  color: const Color(0xFFB794FF),
                ),
                _statCard(
                  Icons.lock_open_rounded,
                  l10n.chestOpens,
                  _num(s['opens_total'], l10n),
                  color: const Color(0xFF34D399),
                ),
                _statCard(
                  Icons.trending_up_rounded,
                  l10n.chestOpens7d,
                  _num(s['opens_7d'], l10n),
                  color: const Color(0xFF38BDF8),
                ),
                _statCard(
                  Icons.people_rounded,
                  l10n.usersWithChests,
                  _num(s['users_with_chests'], l10n),
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _grantChestForm(),
            const SizedBox(height: 18),
            Text(
              l10n.catalogLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _chestCatalog,
              builder: (context, snapC) {
                final list = snapC.data ?? const [];
                if (list.isEmpty) return _empty(l10n.noChests);
                return Column(
                  children: [
                    for (final c in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(
                          c['emoji']?.toString() ?? '📦',
                          style: const TextStyle(fontSize: 18),
                        ),
                        title: Text(
                          c['name']?.toString() ?? c['id']?.toString() ?? '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${c['frequency'] ?? ''} · ${c['status'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _grantChestForm() {
    final l10n = AppLocalizations.of(context)!;
    final userIdCtrl = TextEditingController();
    String chestId = '';
    String source = 'admin';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFB794FF).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.grantChestTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: userIdCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.userIdLabel,
              hintText: l10n.pasteUuidHint,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _chestCatalog,
            builder: (context, snapC) {
              final list = snapC.data ?? const [];
              return DropdownButtonFormField<String>(
                initialValue: list.isNotEmpty
                    ? (list.first['id']?.toString() ?? '')
                    : null,
                dropdownColor: const Color(0xFF15131E),
                decoration: InputDecoration(labelText: l10n.chestLabel),
                items: [
                  for (final c in list)
                    DropdownMenuItem(
                      value: c['id']?.toString(),
                      child: Text(
                        '${c['emoji'] ?? '📦'} ${c['name'] ?? c['id']}',
                      ),
                    ),
                ],
                onChanged: (v) => chestId = v ?? '',
              );
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: 'admin',
            dropdownColor: const Color(0xFF15131E),
            decoration: InputDecoration(labelText: l10n.originLabel),
            items: [
              DropdownMenuItem(value: 'admin', child: Text(l10n.originAdmin)),
              DropdownMenuItem(value: 'event', child: Text(l10n.originEvent)),
              DropdownMenuItem(
                value: 'mission',
                child: Text(l10n.originMission),
              ),
              DropdownMenuItem(value: 'free', child: Text(l10n.originFree)),
              DropdownMenuItem(value: 'daily', child: Text(l10n.originDaily)),
            ],
            onChanged: (v) => source = v ?? 'admin',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final uid = userIdCtrl.text.trim();
                if (uid.isEmpty || chestId.isEmpty) {
                  _errSnack(l10n.invalidUuidChestError);
                  return;
                }
                try {
                  final res = await _admin.adminGrantChest(
                    uid,
                    chestId: chestId,
                    source: source,
                  );
                  final ok = res['ok'] == true || res['status'] != null;
                  _okSnack(ok ? l10n.chestGranted : l10n.noServerResponse);
                } catch (e) {
                  _errSnack(_admin.friendlyError(e));
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              icon: const Icon(Icons.card_giftcard, size: 16),
              label: Text(l10n.grantAction),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎯 Missões (cap: missions — leitura do progresso do operador)
  // ---------------------------------------------------------------------------

  Widget _missionsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _admin.myProgress(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final p = snap.data ?? const {};
        final level = (p['level'] as num?)?.toInt() ?? 1;
        final title = p['level_title']?.toString() ?? l10n.newcomerTitle;
        final list = (p['missions'] as List?) ?? const [];
        final total = (p['xp_total'] as num?)?.toInt() ?? 0;
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _statCard(
              Icons.auto_awesome_rounded,
              l10n.levelLabel,
              '$level · $title',
              color: const Color(0xFF8B5CF6),
            ),
            _statCard(
              Icons.stars_rounded,
              l10n.totalXp,
              _num(total, l10n),
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.missionsAutoRewardHint,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),
            ...list.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              return _missionChip(m);
            }),
          ],
        );
      },
    );
  }

  Widget _missionChip(Map<String, dynamic> m) {
    final l10n = AppLocalizations.of(context)!;
    final target = (m['target'] as num?)?.toInt() ?? 1;
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final done = m['completed'] == true;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Text(
        m['icon']?.toString() ?? '✅',
        style: const TextStyle(fontSize: 18),
      ),
      title: Text(
        m['title']?.toString() ?? '—',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${m['xp_reward'] ?? 0} XP · ${done ? l10n.completedLabel : '$progress/$target'}',
        style: TextStyle(
          color: done ? const Color(0xFF34D399) : Colors.white38,
          fontSize: 11,
        ),
      ),
      trailing: done
          ? const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF34D399),
              size: 20,
            )
          : const SizedBox(width: 20),
    );
  }

  // ---------------------------------------------------------------------------
  // 🧾 Auditoria (cap: audit)
  // ---------------------------------------------------------------------------

  Widget _auditTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _audit,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final items = snap.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _audit = _admin
                  .adminAuditList(limit: 80)
                  .catchError((_) => const <Map<String, dynamic>>[]);
            });
            await _audit;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle(l10n.auditTrailTitle),
              const SizedBox(height: 10),
              if (items.isEmpty)
                _emptyScroll(l10n.noAuditEvents)
              else
                ...items.map((e) => _auditRow(e)),
            ],
          ),
        );
      },
    );
  }

  Widget _auditRow(Map<String, dynamic> e) {
    final l10n = AppLocalizations.of(context)!;
    final details = e['details'];
    final detailText = details is Map
        ? details.entries.map((en) => '${en.key}: ${en.value}').join(', ')
        : details?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFFB794FF),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e['action']?.toString() ?? '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _relativeTime(e['created_at']?.toString(), l10n),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          if (e['actor_email']?.toString().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.auditBy(
                  '${e['actor_email'] ?? e['actor_name'] ?? '—'}',
                  '${e['entity_type'] ?? ''}',
                  '${e['entity_id'] ?? ''}',
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          if (detailText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detailText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎭 Profissões (admin)
  // ---------------------------------------------------------------------------

  Widget _professionsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _professions,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final items = snap.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _professions = _admin.adminListProfessions().catchError(
                (_) => const <Map<String, dynamic>>[],
              );
            });
            await _professions;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle(l10n.professionsTitle),
              const SizedBox(height: 4),
              Text(
                l10n.professionsHint,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openProfessionDialog,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.newProfessionAction),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                _emptyScroll(l10n.noProfessions)
              else
                ...items.map((p) => _professionRow(p)),
            ],
          ),
        );
      },
    );
  }

  Widget _professionRow(Map<String, dynamic> p) {
    final l10n = AppLocalizations.of(context)!;
    final active = (p['status'] ?? 'active').toString() == 'active';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFF2A1B54),
        child: Text(
          (p['icon']?.toString().isNotEmpty ?? false)
              ? p['icon'].toString()
              : '🎭',
          style: const TextStyle(fontSize: 18),
        ),
      ),
      title: Text(
        p['name']?.toString() ?? '—',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${p['category'] ?? 'geral'} · ${active ? l10n.activeLabel : l10n.inactiveLabel}',
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _toggleProfessionStatus(p),
            icon: Icon(
              active ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: active ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
              size: 18,
            ),
            tooltip: active ? l10n.disableTooltip : l10n.enableTooltip,
          ),
          IconButton(
            onPressed: () => _openProfessionDialog(p),
            icon: const Icon(
              Icons.edit_rounded,
              color: Color(0xFF8B5CF6),
              size: 18,
            ),
            tooltip: l10n.edit,
          ),
          IconButton(
            onPressed: () => _deleteProfession(p),
            icon: const Icon(
              Icons.delete_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
            tooltip: l10n.removeAction,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleProfessionStatus(Map<String, dynamic> p) async {
    final l10n = AppLocalizations.of(context)!;
    final id = p['id']?.toString();
    if (id == null) return;
    final next = (p['status'] ?? 'active').toString() == 'active'
        ? 'inactive'
        : 'active';
    try {
      await _admin.adminSetProfessionStatus(id, next);
      _okSnack(
        next == 'active' ? l10n.professionEnabled : l10n.professionDisabled,
      );
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _professions = _admin.adminListProfessions().catchError(
          (_) => const <Map<String, dynamic>>[],
        );
      });
    }
  }

  Future<void> _deleteProfession(Map<String, dynamic> p) async {
    final l10n = AppLocalizations.of(context)!;
    final id = p['id']?.toString();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.removeNameTitle('${p['name']}'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          l10n.removeProfessionBody,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: Text(l10n.removeAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _admin.adminDeleteProfession(id);
      _okSnack(l10n.professionRemoved);
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _professions = _admin.adminListProfessions().catchError(
          (_) => const <Map<String, dynamic>>[],
        );
      });
    }
  }

  Future<void> _openProfessionDialog([Map<String, dynamic>? p]) async {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: p?['name']?.toString() ?? '');
    final iconCtrl = TextEditingController(text: p?['icon']?.toString() ?? '');
    final categoryCtrl = TextEditingController(
      text: p?['category']?.toString() ?? 'geral',
    );
    final editing = p != null;
    final editId = p?['id']?.toString();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          editing ? l10n.editProfessionTitle : l10n.newProfessionAction,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.nameLabel),
              ),
              TextField(
                controller: iconCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.iconLabel),
              ),
              TextField(
                controller: categoryCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.categoryLabel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop();
              try {
                await _admin.adminUpsertProfession(
                  id: editing ? editId : null,
                  name: name,
                  icon: iconCtrl.text.trim(),
                  category: categoryCtrl.text.trim().isEmpty
                      ? 'geral'
                      : categoryCtrl.text.trim(),
                );
                _okSnack(
                  editing ? l10n.professionUpdated : l10n.professionCreated,
                );
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _professions = _admin.adminListProfessions().catchError(
                    (_) => const <Map<String, dynamic>>[],
                  );
                });
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🤖 Bots (admin)
  // ---------------------------------------------------------------------------

  Widget _botsTab() {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _bots,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingList();
        }
        final items = snap.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _bots = _admin.adminListBots().catchError(
                (_) => const <Map<String, dynamic>>[],
              );
            });
            await _bots;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle(l10n.botControlTitle),
              const SizedBox(height: 4),
              Text(
                l10n.botsNoAdminHint,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openBotDialog,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.createBotAction),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                _emptyScroll(l10n.noBots)
              else
                ...items.map((b) => _botRow(b)),
            ],
          ),
        );
      },
    );
  }

  /// Publicidade (Sistema Oficial de Anúncios) embutida no painel, usando o
  /// mesmo AdsAdminScreen da seção "Publicidade" das Configurações (showAppBar
  /// false para não duplicar AppBar). Toda ação roda em RPCs security definer.
  Widget _adsTab() => const AdsAdminScreen(showAppBar: false);

  Widget _botRow(Map<String, dynamic> b) {
    final l10n = AppLocalizations.of(context)!;
    final status = (b['status'] ?? 'inactive').toString();
    const colors = {
      'active': Color(0xFF34D399),
      'inactive': Color(0xFF94A3B8),
      'paused': Color(0xFFF59E0B),
    };
    final color = colors[status] ?? Colors.white38;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFF2A1B54),
        child: Text(
          (b['avatar']?.toString().isNotEmpty ?? false)
              ? b['avatar'].toString()
              : '🤖',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      title: Text(
        b['name']?.toString() ?? '—',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${_botRoleLabel(b['bot_role']?.toString(), l10n)} · ${_statusLabel(status, l10n)}',
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _cycleBotStatus(b),
            icon: Icon(
              status == 'active'
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              color: color,
              size: 20,
            ),
            tooltip: status == 'active'
                ? l10n.pauseTooltip
                : l10n.enableTooltip,
          ),
          IconButton(
            onPressed: () => _openBotDialog(b),
            icon: const Icon(
              Icons.edit_rounded,
              color: Color(0xFF8B5CF6),
              size: 18,
            ),
            tooltip: l10n.edit,
          ),
          IconButton(
            onPressed: () => _deleteBot(b),
            icon: const Icon(
              Icons.delete_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
            tooltip: l10n.removeAction,
          ),
        ],
      ),
    );
  }

  String _botRoleLabel(String? role, AppLocalizations l10n) {
    return switch (role) {
      'support' => l10n.roleSupport,
      'moderation' => l10n.moderationTab,
      'voice' => l10n.botRoleVoice,
      'system' => l10n.botRoleSystem,
      _ => role ?? 'support',
    };
  }

  Future<void> _cycleBotStatus(Map<String, dynamic> b) async {
    final l10n = AppLocalizations.of(context)!;
    final id = b['id']?.toString();
    if (id == null) return;
    final cur = (b['status'] ?? 'inactive').toString();
    final next = cur == 'active'
        ? 'paused'
        : cur == 'paused'
        ? 'active'
        : 'active';
    try {
      await _admin.adminSetBotStatus(id, next);
      _okSnack(l10n.botStatusChanged(_statusLabel(next, l10n)));
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _bots = _admin.adminListBots().catchError(
          (_) => const <Map<String, dynamic>>[],
        );
      });
    }
  }

  Future<void> _deleteBot(Map<String, dynamic> b) async {
    final l10n = AppLocalizations.of(context)!;
    final id = b['id']?.toString();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.removeNameTitle('${b['name']}'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          l10n.removeBotBody,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: Text(l10n.removeAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _admin.adminDeleteBot(id);
      _okSnack(l10n.botRemoved);
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _bots = _admin.adminListBots().catchError(
          (_) => const <Map<String, dynamic>>[],
        );
      });
    }
  }

  Future<void> _openBotDialog([Map<String, dynamic>? b]) async {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: b?['name']?.toString() ?? '');
    final avatarCtrl = TextEditingController(
      text: b?['avatar']?.toString() ?? '',
    );
    final bioCtrl = TextEditingController(text: b?['bio']?.toString() ?? '');
    final editing = b != null;
    final editId = b?['id']?.toString();
    var role = (b?['bot_role']?.toString() ?? 'support');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          editing ? l10n.editBotTitle : l10n.createBotAction,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.nameLabel),
              ),
              TextField(
                controller: avatarCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.avatarLabel),
              ),
              TextField(
                controller: bioCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.descriptionLabel),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                dropdownColor: const Color(0xFF15131E),
                decoration: InputDecoration(labelText: l10n.botTypeLabel),
                items: [
                  DropdownMenuItem(
                    value: 'support',
                    child: Text(l10n.roleSupport),
                  ),
                  DropdownMenuItem(
                    value: 'moderation',
                    child: Text(l10n.moderationTab),
                  ),
                  DropdownMenuItem(
                    value: 'voice',
                    child: Text(l10n.botRoleVoice),
                  ),
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(l10n.botRoleSystem),
                  ),
                ],
                onChanged: (v) => role = v ?? role,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop();
              try {
                await _admin.adminUpsertBot(
                  id: editing ? editId : null,
                  name: name,
                  avatar: avatarCtrl.text.trim(),
                  bio: bioCtrl.text.trim(),
                  botRole: role,
                );
                _okSnack(editing ? l10n.botUpdated : l10n.botCreated);
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _bots = _admin.adminListBots().catchError(
                    (_) => const <Map<String, dynamic>>[],
                  );
                });
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _okSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF0F8A4D),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers (UI)
  // ---------------------------------------------------------------------------

  Future<void> _svcGuard(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
    } on AdminAccessDeniedException catch (_) {
      _errSnack(l10n.restrictedAccessPanel);
    } catch (_) {
      _errSnack(l10n.unauthorizedOrNetwork);
    }
  }

  void _errSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE4183C),
      ),
    );
  }

  Widget _loadingList() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
      ),
    ],
  );

  Widget _emptyScroll(String text) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      Padding(padding: const EdgeInsets.only(top: 60), child: _empty(text)),
    ],
  );

  Widget _empty(String text) => Center(
    child: Text(text, style: const TextStyle(color: Colors.white38)),
  );

  Widget _statCard(IconData icon, String label, String value, {Color? color}) {
    final accent = color ?? const Color(0xFFB794FF);
    return Container(
      width: (MediaQuery.of(context).size.width - 38) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _statusChip(String? status) {
    final l10n = AppLocalizations.of(context)!;
    final valid = status ?? 'pending';
    final colors = {
      'resolved': const Color(0xFF34D399),
      'dismissed': Colors.white38,
      'reviewing': const Color(0xFFF59E0B),
      'pending': const Color(0xFFFF6B81),
    };
    final color = colors[valid] ?? Colors.white38;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _statusLabel(valid, l10n),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _statusLabel(String? status, AppLocalizations l10n) {
    return switch (status) {
      'pending' => l10n.statusPending,
      'reviewing' => l10n.statusReviewing,
      'resolved' => l10n.statusResolved,
      'dismissed' => l10n.statusDismissed,
      'pendente' => l10n.statusPending,
      'pago' => l10n.statusPaid,
      'enviado' => l10n.statusShipped,
      'concluido' => l10n.statusCompleted,
      'cancelado' => l10n.statusCancelled,
      'active' => l10n.statusActive,
      'inactive' => l10n.statusInactive,
      'paused' => l10n.statusPaused,
      _ => '—',
    };
  }

  String _num(Object? value, AppLocalizations l10n) {
    final n = value is num ? value.toDouble() : 0.0;
    return NumberFormat.compact(locale: l10n.localeName).format(n);
  }

  String _money(Object? value, AppLocalizations l10n) {
    final n = value is num ? value.toDouble() : 0.0;
    return NumberFormat.currency(
      locale: l10n.localeName,
      symbol: 'R\$',
      decimalDigits: 2,
    ).format(n);
  }

  String _relativeTime(String? iso, AppLocalizations l10n) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return l10n.notifTimeNow;
    if (diff.inHours < 1) return l10n.notifTimeMin(diff.inMinutes);
    if (diff.inDays < 1) return l10n.notifTimeH(diff.inHours);
    if (diff.inDays < 30) return l10n.notifTimeD(diff.inDays);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }
}

class _RestrictedView extends StatelessWidget {
  const _RestrictedView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE4183C).withValues(alpha: 0.12),
                border: Border.all(color: const Color(0xFFE4183C)),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Color(0xFFFF6B81),
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.restrictedAccessTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.restrictedAccessBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Especificação de uma aba do painel (ícone, rótulo e conteúdo).
class _PanelTab {
  final IconData icon;
  final String label;
  final _TabId id;

  const _PanelTab(this.icon, this.label, this.id);
}

/// Folha de detalhe de usuário com seção 🎭 PROFISSÃO (apenas admin/fundador).
/// Toda alteração chama RPC `security definer` re-validando permissão.
class _UserProfessionSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onRefresh;

  const _UserProfessionSheet({required this.user, required this.onRefresh});

  @override
  State<_UserProfessionSheet> createState() => _UserProfessionSheetState();
}

class _UserProfessionSheetState extends State<_UserProfessionSheet> {
  final AdminService _admin = AdminService.instance;
  late Future<List<Map<String, dynamic>>> _professions;

  String? get _userId => widget.user['id']?.toString();
  String? get _current =>
      widget.user['profession']?.toString().trim().isNotEmpty == true
      ? widget.user['profession'].toString()
      : null;

  @override
  void initState() {
    super.initState();
    _professions = _admin.adminListProfessions().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
  }

  void _reloadProfessions() {
    setState(() {
      _professions = _admin.adminListProfessions().catchError(
        (_) => const <Map<String, dynamic>>[],
      );
    });
  }

  void _ok(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF0F8A4D)),
    );
  }

  void _err(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_admin.friendlyError(e)),
        backgroundColor: const Color(0xFFE4183C),
      ),
    );
  }

  Future<void> _assign(String? profession) async {
    final l10n = AppLocalizations.of(context)!;
    final uid = _userId;
    if (uid == null) return;
    try {
      if (profession == null || profession.isEmpty) {
        await _admin.adminClearUserProfession(uid);
        _ok(l10n.professionRemovedFromProfile);
      } else {
        await _admin.adminSetUserProfession(uid, profession);
        _ok(l10n.professionAssigned(profession));
      }
      widget.onRefresh();
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _openChangeDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final items = await _professions;
    final active = items
        .where((p) => (p['status'] ?? 'active').toString() == 'active')
        .toList();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B1A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.selectProfessionTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in active)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      leading: Text(
                        (p['icon']?.toString().isNotEmpty ?? false)
                            ? p['icon'].toString()
                            : '🎭',
                        style: const TextStyle(fontSize: 18),
                      ),
                      title: Text(
                        p['name']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: _current == p['name']
                          ? const Icon(
                              Icons.check,
                              color: Color(0xFF34D399),
                              size: 18,
                            )
                          : null,
                      onTap: () => Navigator.of(ctx).pop(p['name']?.toString()),
                    ),
                  const Divider(color: Colors.white12, height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: const Text('➕', style: TextStyle(fontSize: 18)),
                    title: Text(
                      l10n.createNewProfessionAction,
                      style: const TextStyle(
                        color: Color(0xFFB794FF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.of(ctx).pop('__new__'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == '__new__') {
      await _createAndAssign();
      return;
    }
    await _assign(chosen);
  }

  Future<void> _createAndAssign() async {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController();
    final iconCtrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.createNewProfessionTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.nameLabel),
              ),
              TextField(
                controller: iconCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.avatarLabel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.createAction),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty || !mounted) return;
    try {
      await _admin.adminUpsertProfession(
        name: saved,
        icon: iconCtrl.text.trim(),
      );
      _reloadProfessions();
      await _assign(saved);
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.removeProfessionTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          l10n.clearProfessionBody(widget.user['username']?.toString() ?? ''),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: Text(l10n.removeAction),
          ),
        ],
      ),
    );
    if (ok == true) await _assign(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final display = widget.user['display_name']?.toString() ?? l10n.roleUser;
    final username = widget.user['username']?.toString() ?? '';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF2A2145),
                  child: Text(
                    display.characters.first.toUpperCase(),
                    style: const TextStyle(color: Color(0xFFB794FF)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              l10n.professionHeader,
              style: const TextStyle(
                color: Color(0xFFB794FF),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FounderProfessionChip(profession: _current),
                if (_current != null)
                  TextButton.icon(
                    onPressed: _confirmClear,
                    icon: const Icon(
                      Icons.delete_rounded,
                      color: Color(0xFFEF4444),
                      size: 16,
                    ),
                    label: Text(
                      l10n.removeFromUserAction,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openChangeDialog,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
                icon: const Icon(Icons.edit_rounded),
                label: Text(l10n.changeProfessionAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de exibição da profissão atual (reutilizado no detalhe de usuário).
class _FounderProfessionChip extends StatelessWidget {
  final String? profession;

  const _FounderProfessionChip({this.profession});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (profession == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          l10n.noProfessionDefined,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '🎭 $profession',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Identificadores das abas — resolvidos em [_FounderPanelScreenState._tabView].
enum _TabId {
  overview,
  moderation,
  posts,
  users,
  team,
  verification,
  tickets,
  economy,
  chests,
  missions,
  audit,
  gifts,
  store,
  live,
  admin,
  professions,
  bots,
  ads,
  money,
  security,
  feedback,
  maintenance,
  notifications,
  king,
  config,
}
// ---------------------------------------------------------------------------
// 👑 GERENCIADOR DE MOEDAS (tab fundador)
// ---------------------------------------------------------------------------

/// Gerenciador de moedas do founder: busca usuário, escolhe moeda, quantidade
/// (positiva adiciona / negativa remove) e motivo obrigatório, com confirmação
/// dupla e auditoria no backend (`founder_adjust_currency`).
class _FounderMoneyTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _FounderMoneyTab({required this.onChanged});

  @override
  State<_FounderMoneyTab> createState() => _FounderMoneyTabState();
}

class _FounderMoneyTabState extends State<_FounderMoneyTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  final TextEditingController _search = TextEditingController();
  final TextEditingController _qty = TextEditingController(text: '100');
  final TextEditingController _reason = TextEditingController();

  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic> _wallet = const {};
  List<Map<String, dynamic>> _recent = const [];
  String _currency = 'credits';
  bool _busy = false;
  bool _searching = false;

  static const List<(String, String)> _currencies = [
    ('credits', '🪙'),
    ('diamonds', '💎'),
    ('crystals', '🔮'),
    ('rubies', '❤️'),
    ('emeralds', '🟢'),
    ('crystal_rare', '🟣'),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _search.dispose();
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final r = await _svc.recentAdjustments().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    if (mounted) {
      setState(() => _recent = r);
    }
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _results = const [];
      _selected = null;
      _wallet = const {};
    });
    final r = await _svc
        .searchUsers(q)
        .catchError((_) => const <Map<String, dynamic>>[]);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = r;
    });
  }

  Future<void> _selectUser(Map<String, dynamic> u) async {
    setState(() {
      _selected = u;
      _wallet = const {};
    });
    final w = await _svc
        .userWallet(u['id'].toString())
        .catchError((_) => const <String, dynamic>{});
    if (!mounted) return;
    setState(() {
      _wallet = w;
    });
  }

  Future<void> _execute(AppLocalizations l10n) async {
    final user = _selected;
    final delta = int.tryParse(_qty.text.trim());
    final reason = _reason.text.trim();
    if (user == null) {
      _err(l10n.fmPickUser);
      return;
    }
    if (delta == null || delta == 0) {
      _err(l10n.fmBadQty);
      return;
    }
    if (reason.length < 4) {
      _err(l10n.fmEmptyReason);
      return;
    }
    final emoji = _currencies.firstWhere((c) => c.$1 == _currency).$2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.fmConfirmTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '${user['display_name'] ?? user['username']} (@${user['username']})\n'
          '$emoji $_currency = $delta\n\n$reason',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final res = await _svc.adjustCurrency(
        userId: user['id'].toString(),
        currency: _currency,
        delta: delta,
        reason: reason,
      );
      final newBalance = res['balance'];
      if (mounted) {
        _ok(
          l10n.fmBalance(
            newBalance == null
                ? '${(_wallet[_currency] ?? 0)}'
                : newBalance.toString(),
          ),
        );
        await _selectUser(user);
        await _loadRecent();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) _err(_admin.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _ok(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF0F8A4D)),
    );
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE4183C)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionCard(
          children: [
            Text(
              l10n.fmSearchTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: l10n.fmSearchHint,
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                    onSubmitted: (_) => _doSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _searching ? null : _doSearch,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                  ),
                  icon: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                ),
              ],
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final u in _results.take(6))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _selectUser(u),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(
                      0xFF8B5CF6,
                    ).withValues(alpha: 0.2),
                    onBackgroundImageError: (_, __) {},
                    foregroundImage:
                        (u['avatar_url']?.toString().isNotEmpty == true)
                        ? NetworkImage(u['avatar_url'].toString())
                        : null,
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFFB794FF),
                      size: 18,
                    ),
                  ),
                  title: Text(
                    u['display_name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    '@${u['username'] ?? ''} · ${u['role'] ?? ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: Icon(
                    _selected?['id']?.toString() == u['id']?.toString()
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: _selected?['id']?.toString() == u['id']?.toString()
                        ? const Color(0xFF8B5CF6)
                        : Colors.white24,
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (_selected != null) ...[
          _sectionCard(
            children: [
              Text(
                l10n.fmSelectedUser,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_selected!['display_name'] ?? '—'} (@${_selected!['username'] ?? ''})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (k, e) in _currencies)
                    _walletChip(e, k.toUpperCase(), _wallet[k]),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _currency,
                dropdownColor: const Color(0xFF1B1A26),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.fmCurrency),
                items: [
                  for (final (k, e) in _currencies)
                    DropdownMenuItem(value: k, child: Text('$e $k')),
                ],
                onChanged: (v) => setState(() => _currency = v ?? 'credits'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.fmQuantity),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _qty.text = '100'),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(l10n.fmQuickAdd),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _qty.text = '-100'),
                      icon: const Icon(Icons.remove_rounded, size: 16),
                      label: Text(l10n.fmQuickRemove),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.fmReasonRequired),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _execute(l10n),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.swap_vert_rounded, size: 18),
                  label: Text(l10n.fmExecute),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text(
          l10n.fmRecentTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (_recent.isEmpty)
          _emptyBox(l10n.fmNoRecent)
        else
          for (final r in _recent.take(12))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFFB794FF),
                size: 18,
              ),
              title: Text(
                '${r['target_name'] ?? '—'} → ${r['details']?['delta'] ?? '?'} ${r['details']?['currency'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              subtitle: Text(
                '${r['details']?['note'] ?? ''} · ${_ago(r['created_at'] as String?)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _sectionCard({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF15131E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _walletChip(String emoji, String label, dynamic v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
    ),
    child: Text(
      '$emoji ${v ?? 0} $label',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _emptyBox(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF15131E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(color: Colors.white38)),
  );

  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// 🛡️ SEGURANÇA MÁXIMA (tab fundador)
// ---------------------------------------------------------------------------

/// Painel de Segurança do founder: scores de suspeição, bloqueios de IP e
/// dispositivo, alertas, tentativas de login e modo de emergência. Todas as
/// ações são RPCs `security definer` com auditoria (`founder_security_*`).
class _FounderSecurityTab extends StatefulWidget {
  const _FounderSecurityTab();

  @override
  State<_FounderSecurityTab> createState() => _FounderSecurityTabState();
}

class _FounderSecurityTabState extends State<_FounderSecurityTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  Map<String, dynamic> _o = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.securityOverview().catchError(
      (_) => const <String, dynamic>{},
    );
    if (mounted) {
      setState(() => _o = r);
    }
  }

  Future<void> _withBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_admin.friendlyError(e)),
            backgroundColor: const Color(0xFFE4183C),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _ok(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF0F8A4D)),
    );
  }

  Future<void> _blockIp(AppLocalizations l10n) async {
    final ip = await _askTextDialog(
      l10n,
      l10n.fsecIpLabel,
      l10n.fsecReasonLabel,
    );
    if (ip == null) return;
    final reason = ip.$1;
    if (reason.isEmpty || ip.$2.length < 4) {
      _err(l10n.fmEmptyReason);
      return;
    }
    await _withBusy(() async {
      await _svc.blockIp(reason, ip.$2);
      _ok(l10n.fsecActionOk);
    });
  }

  Future<void> _blockDevice(AppLocalizations l10n) async {
    final dev = await _askTextDialog(
      l10n,
      l10n.fsecDeviceLabel,
      l10n.fsecReasonLabel,
    );
    if (dev == null) return;
    if (dev.$1.isEmpty || dev.$2.length < 4) {
      _err(l10n.fmEmptyReason);
      return;
    }
    await _withBusy(() async {
      await _svc.blockDevice(dev.$1, dev.$2);
      _ok(l10n.fsecActionOk);
    });
  }

  Future<void> _unblockIp(String ip) async {
    final l10n = AppLocalizations.of(context)!;
    await _withBusy(() async {
      await _svc.unblockIp(ip);
      _ok(l10n.fsecActionOk);
    });
  }

  Future<void> _unblockDevice(String deviceId) async {
    final l10n = AppLocalizations.of(context)!;
    await _withBusy(() async {
      await _svc.unblockDevice(deviceId);
      _ok(l10n.fsecActionOk);
    });
  }

  Future<void> _adjustScore(String userId, int delta) async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await _askTextDialog(l10n, '', l10n.fsecReasonLabel);
    if (reason == null || reason.$2.length < 4) {
      _err(l10n.fmEmptyReason);
      return;
    }
    await _withBusy(() async {
      final res = await _svc.setSecurityScore(
        userId: userId,
        delta: delta,
        reason: reason.$2,
      );
      _ok('${l10n.fsecScoreResult} ${res['score']}');
    });
  }

  Future<void> _emergency(AppLocalizations l10n) async {
    final msg = await _askTextDialog(l10n, '', l10n.fsecEmergencyMsg);
    if (msg == null || msg.$2.isEmpty) return;
    await _withBusy(() async {
      await _svc.activateEmergency(msg.$2);
      _ok(l10n.fsecActionOk);
    });
  }

  Future<(String, String)?> _askTextDialog(
    AppLocalizations l10n,
    String label1,
    String label2,
  ) async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label1.isNotEmpty) ...[
              TextField(
                controller: c1,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: label1),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: c2,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(labelText: label2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              label1.isEmpty ? 'x' : c1.text.trim(),
              c2.text.trim(),
            )),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    return res;
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE4183C)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ips = ((_o['blocked_ip_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final devices = ((_o['blocked_device_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final scores = ((_o['top_suspicious'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final alerts = ((_o['recent_alerts'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final logins = ((_o['recent_login_attempts'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final emergency = _o['emergency_active'] == true;

    return RefreshIndicator(
      color: const Color(0xFF8B5CF6),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          // Status geral de segurança.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF211447),
                  Color(0xFF161130),
                  Color(0xFF0E1124),
                ],
              ),
              border: Border.all(
                color:
                    (emergency
                            ? const Color(0xFFFF3B4D)
                            : const Color(0xFF8B5CF6))
                        .withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      emergency
                          ? Icons.warning_amber_rounded
                          : Icons.verified_user_rounded,
                      color: emergency
                          ? const Color(0xFFFF3B4D)
                          : const Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      emergency ? l10n.fsecEmergencyActive : l10n.fsecTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _secStat('🛡️', l10n.fsecBlockedIps, _o['blocked_ips']),
                    _secStat(
                      '📱',
                      l10n.fsecBlockedDevices,
                      _o['blocked_devices'],
                    ),
                    _secStat('🚨', l10n.fsecOpenAlerts, _o['open_alerts']),
                    _secStat('🔥', l10n.fsecCritical, _o['critical_alerts']),
                    _secStat('⚠️', l10n.fsecSuspicious, _o['suspicious']),
                    _secStat('⛔', l10n.fsecBlockedUsers, _o['blocked_users']),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Ações rápidas do fundador.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _blockIp(l10n),
                icon: const Icon(Icons.block_rounded, size: 16),
                label: Text(l10n.fsecBlockIp),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _blockDevice(l10n),
                icon: const Icon(Icons.phonelink_erase_rounded, size: 16),
                label: Text(l10n.fsecBlockDevice),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _emergency(l10n),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B4D),
                  side: const BorderSide(color: Color(0xFFFF3B4D)),
                ),
                icon: const Icon(Icons.local_fire_department_rounded, size: 16),
                label: Text(l10n.fsecEmergency),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _secTitle(l10n.fsecTopSuspicious),
          const SizedBox(height: 8),
          if (scores.isEmpty)
            _secEmpty(l10n.fsecNoSuspicious)
          else
            for (final s in scores)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(
                    0xFFFF3B4D,
                  ).withValues(alpha: 0.15),
                  child: Text(
                    '${s['score'] ?? 0}',
                    style: const TextStyle(
                      color: Color(0xFFFF3B4D),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: Text(
                  '${s['display_name'] ?? '—'} (@${s['username'] ?? ''})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${s['role'] ?? ''} · atualizado ${_ago(s['updated_at'] as String?)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.fsecScoreDown,
                      onPressed: _busy
                          ? null
                          : () => _adjustScore(s['id'].toString(), -10),
                      icon: const Icon(
                        Icons.thumb_down_alt_outlined,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.fsecScoreUp,
                      onPressed: _busy
                          ? null
                          : () => _adjustScore(s['id'].toString(), 10),
                      icon: const Icon(
                        Icons.thumb_up_alt_rounded,
                        color: Color(0xFFFF3B4D),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 18),
          _secTitle(l10n.fsecBlockedList),
          const SizedBox(height: 4),
          _secSub(l10n.fsecBlockedIps),
          const SizedBox(height: 4),
          if (ips.isEmpty)
            _secEmpty(l10n.fsecNoBlocked)
          else
            for (final b in ips)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.lan_rounded,
                  color: Color(0xFFFFB300),
                  size: 18,
                ),
                title: Text(
                  '${b['ip']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${b['reason'] ?? ''}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: IconButton(
                  tooltip: l10n.fsecUnblock,
                  onPressed: _busy
                      ? null
                      : () => _unblockIp(b['ip'].toString()),
                  icon: const Icon(
                    Icons.lock_open_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
              ),
          const SizedBox(height: 8),
          _secSub(l10n.fsecBlockedDevices),
          const SizedBox(height: 4),
          if (devices.isEmpty)
            _secEmpty(l10n.fsecNoBlocked)
          else
            for (final b in devices)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.phonelink_rounded,
                  color: Color(0xFF38BDF8),
                  size: 18,
                ),
                title: Text(
                  '${b['device_id']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${b['reason'] ?? ''}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: IconButton(
                  tooltip: l10n.fsecUnblock,
                  onPressed: _busy
                      ? null
                      : () => _unblockDevice(b['device_id'].toString()),
                  icon: const Icon(
                    Icons.lock_open_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
              ),
          const SizedBox(height: 18),
          _secTitle(l10n.fsecRecentAlerts),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            _secEmpty(l10n.fsecNoAlerts)
          else
            for (final a in alerts)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: _sevIcon(a['severity']?.toString() ?? ''),
                title: Text(
                  '${a['title'] ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${a['category'] ?? ''} · ${a['status'] ?? ''} · ${_ago(a['created_at'] as String?)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          const SizedBox(height: 18),
          _secTitle(l10n.fsecLoginAttempts),
          const SizedBox(height: 8),
          if (logins.isEmpty)
            _secEmpty(l10n.fsecNoLogins)
          else
            for (final l in logins)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  l['success'] == true
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: l['success'] == true
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFFF3B4D),
                  size: 18,
                ),
                title: Text(
                  '${l['email_or_username'] ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${l['device_id']?.toString().isNotEmpty == true ? '${l['device_id']} · ' : ''}${_ago(l['created_at'] as String?)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _secStat(String emoji, String label, dynamic v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${v ?? 0}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _secTitle(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _secSub(String t) => Text(
    t.toUpperCase(),
    style: const TextStyle(
      color: Colors.white54,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
    ),
  );

  Widget _secEmpty(String t) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF15131E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(t, style: const TextStyle(color: Colors.white38)),
  );

  Widget _sevIcon(String sev) => Icon(
    sev == 'critical'
        ? Icons.dangerous_rounded
        : sev == 'high'
        ? Icons.warning_amber_rounded
        : Icons.info_outline_rounded,
    color: sev == 'critical'
        ? const Color(0xFFFF3B4D)
        : sev == 'high'
        ? const Color(0xFFFFB300)
        : const Color(0xFF8B5CF6),
    size: 18,
  );

  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// 💬 FEEDBACKS (tab equipe — cap `support`)
// ---------------------------------------------------------------------------

/// Painel de feedbacks: agregados, filtro por estado e revisão/arquivamento.
/// Toda ação chama RPC `security definer` com auditoria (`mod_update_feedback`).
class _FounderFeedbackTab extends StatefulWidget {
  const _FounderFeedbackTab();

  @override
  State<_FounderFeedbackTab> createState() => _FounderFeedbackTabState();
}

class _FounderFeedbackTabState extends State<_FounderFeedbackTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _stats = const {};
  String? _filter;
  bool _busy = false;

  static const List<String> _filters = ['new', 'reviewed', 'archived'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final listFuture = _svc.listFeedbacks(status: _filter);
    final statsFuture = _svc.feedbackStats();
    final list = await listFuture.catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    final stats = await statsFuture.catchError(
      (_) => const <String, dynamic>{},
    );
    if (!mounted) return;
    setState(() {
      _items = list;
      _stats = stats;
    });
  }

  Future<void> _setStatus(String id, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _svc.updateFeedbackStatus(feedbackId: id, status: status);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.fbActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat('📥', l10n.fbStatsTotal, _stats['total']),
              _stat('🆕', l10n.fbStatsNew, _stats['new']),
              _stat('✅', l10n.fbStatsReviewed, _stats['reviewed']),
              _stat('📅', l10n.fbToday, _stats['today']),
              _stat('⭐', l10n.fbAvgRating, _stats['avg_rating']),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.fbFilterAll),
                selected: _filter == null,
                onSelected: (_) {
                  setState(() => _filter = null);
                  _load();
                },
              ),
              for (final f in _filters)
                ChoiceChip(
                  label: Text(_filterLabel(f, l10n)),
                  selected: _filter == f,
                  onSelected: (_) {
                    setState(() => _filter = f);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF15131E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.fbEmpty,
                style: const TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final it in _items) _card(it, l10n),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> it, AppLocalizations l10n) {
    final status = it['status']?.toString() ?? 'new';
    final category = it['category']?.toString() ?? 'other';
    final rating = (it['rating'] as num?)?.toInt() ?? 0;
    final display = it['display_name']?.toString() ?? '';
    final username = it['username']?.toString() ?? '';
    final user = [
      if (display.isNotEmpty) display,
      if (username.isNotEmpty) '@$username',
    ].join(' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _categoryLabel(category, l10n),
                  style: const TextStyle(
                    color: Color(0xFFB794FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _fbStatusChip(status, l10n),
              const Spacer(),
              Text(
                List.filled(rating.clamp(0, 5), '⭐').join(),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            it['message']?.toString() ?? '—',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (user.isNotEmpty) user,
              _ago(it['created_at'] as String?),
            ].where((e) => e.isNotEmpty).join(' · '),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if ((it['notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              it['notes'].toString(),
              style: const TextStyle(color: Color(0xFFB794FF), fontSize: 11),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (status == 'archived')
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _setStatus(it['id'].toString(), 'reviewed'),
                  icon: const Icon(Icons.unarchive_rounded, size: 18),
                  label: Text(l10n.fbRestore),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB794FF),
                  ),
                )
              else ...[
                if (status == 'new')
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _setStatus(it['id'].toString(), 'reviewed'),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text(l10n.fbMarkReviewed),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF34D399),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _setStatus(it['id'].toString(), 'archived'),
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: Text(l10n.fbArchive),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String emoji, String label, dynamic v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              '${v ?? 0}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _fbStatusChip(String status, AppLocalizations l10n) {
    final color = switch (status) {
      'new' => const Color(0xFFFF6B81),
      'reviewed' => const Color(0xFF34D399),
      'archived' => Colors.white38,
      _ => Colors.white38,
    };
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _filterLabel(status, l10n),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _filterLabel(String s, AppLocalizations l10n) => switch (s) {
    'new' => l10n.fbFilterNew,
    'reviewed' => l10n.fbFilterReviewed,
    'archived' => l10n.fbFilterArchived,
    _ => l10n.fbFilterAll,
  };

  String _categoryLabel(String c, AppLocalizations l10n) => switch (c) {
    'suggestion' => l10n.fbCategorySuggestion,
    'bug' => l10n.fbCategoryBug,
    'praise' => l10n.fbCategoryPraise,
    _ => l10n.fbCategoryOther,
  };

  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// 🛠️ MANUTENÇÃO (tab equipe — cap `guardian`)
// ---------------------------------------------------------------------------

/// Gerenciador de janelas de manutenção: iniciar/encerrar com escopo, modo,
/// mensagem e emergência. Toda ação chama RPC `security definer` auditada
/// (`guardian_set_maintenance` / `guardian_end_maintenance`).
class _FounderMaintenanceTab extends StatefulWidget {
  const _FounderMaintenanceTab();

  @override
  State<_FounderMaintenanceTab> createState() => _FounderMaintenanceTabState();
}

class _FounderMaintenanceTabState extends State<_FounderMaintenanceTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  List<Map<String, dynamic>> _items = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _svc.listMaintenance().catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    if (!mounted) return;
    setState(() => _items = list);
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    String mode = 'medium';
    String feature = 'all';
    String message = '';
    bool emergency = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1B1A26),
          title: Text(
            l10n.mtStart,
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mtMode,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const ['low', 'medium', 'max'])
                      ChoiceChip(
                        label: Text(_modeLabel(m, l10n)),
                        selected: mode == m,
                        onSelected: (_) => setDialog(() => mode = m),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: l10n.mtFeature,
                    hintText: l10n.mtFeatureHint,
                    filled: true,
                    fillColor: const Color(0xFF15131E),
                  ),
                  onChanged: (v) => feature = v.trim(),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: l10n.mtMessage,
                    filled: true,
                    fillColor: const Color(0xFF15131E),
                  ),
                  onChanged: (v) => message = v.trim(),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: emergency,
                  title: Text(
                    l10n.mtEmergency,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  activeTrackColor: const Color(0xFF8B5CF6),
                  onChanged: (v) => setDialog(() {
                    emergency = v;
                    if (v) mode = 'max';
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.startMaintenance(
        mode: emergency ? 'max' : mode,
        feature: feature.isEmpty ? 'all' : feature,
        message: message,
        emergency: emergency,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.mtActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(Map<String, dynamic> w) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.mtEndConfirmTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: reason,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.mtEndReason,
            filled: true,
            fillColor: const Color(0xFF15131E),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    final reasonText = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.endMaintenance(
        windowId: w['id'].toString(),
        reason: reasonText,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.mtActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = _items
        .where((w) => (w['status']?.toString()) == 'active')
        .length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mtActiveCount(active),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(l10n.mtStart),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF15131E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.mtNone,
                style: const TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final w in _items) _card(w, l10n),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> w, AppLocalizations l10n) {
    final status = w['status']?.toString() ?? 'ended';
    final active = status == 'active';
    final mode = w['mode']?.toString() ?? 'medium';
    final feature = w['feature']?.toString() ?? 'all';
    final emergency = (w['is_emergency'] as bool?) ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (active ? const Color(0xFF34D399) : const Color(0xFF8B5CF6))
              .withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _statusLabel(status, l10n),
                style: TextStyle(
                  color: active ? const Color(0xFF34D399) : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _modeColor(mode).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _modeLabel(mode, l10n),
                  style: TextStyle(
                    color: _modeColor(mode),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (emergency) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4183C).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n.mtEmergency,
                    style: const TextStyle(
                      color: Color(0xFFFF6B81),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            feature,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((w['message'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              w['message'].toString(),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            [
              '🕐 ${_ago(w['started_at'] as String?)}',
              if (w['end_at'] != null) '🏁 ${_ago(w['end_at'] as String?)}',
            ].join(' · '),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (active)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _end(w),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(l10n.mtEnd),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE4183C),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _modeLabel(String m, AppLocalizations l10n) => switch (m) {
    'low' => l10n.mtModeLow,
    'medium' => l10n.mtModeMedium,
    'max' => l10n.mtModeMax,
    _ => m,
  };

  Color _modeColor(String m) => switch (m) {
    'low' => const Color(0xFF34D399),
    'medium' => const Color(0xFFF59E0B),
    'max' => const Color(0xFFE4183C),
    _ => Colors.white38,
  };

  String _statusLabel(String status, AppLocalizations l10n) =>
      status == 'active' ? l10n.mtActive : l10n.mtEnded;

  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// 📢 NOTIFICAÇÕES (tab equipe — cap roles/moderation/support)
// ---------------------------------------------------------------------------

/// Visão de notificações da plataforma: agregados, filtros (tipo/usuário) e
/// broadcast oficial para todos os usuários. Toda ação chama RPC
/// `security definer` auditada (`founder_broadcast_notification`).
class _FounderNotificationsTab extends StatefulWidget {
  const _FounderNotificationsTab();

  @override
  State<_FounderNotificationsTab> createState() =>
      _FounderNotificationsTabState();
}

class _FounderNotificationsTabState extends State<_FounderNotificationsTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  final TextEditingController _userFilter = TextEditingController();

  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _stats = const {};
  String? _typeFilter;
  bool _busy = false;

  static const List<String> _types = [
    'broadcast',
    'announcement',
    'event',
    'alert',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final listFuture = _svc.listNotifications(
      type: _typeFilter,
      username: _userFilter.text.trim().isEmpty
          ? null
          : _userFilter.text.trim(),
      limit: 100,
    );
    final statsFuture = _svc.notificationStats();
    final list = await listFuture.catchError(
      (_) => const <Map<String, dynamic>>[],
    );
    final stats = await statsFuture.catchError(
      (_) => const <String, dynamic>{},
    );
    if (!mounted) return;
    setState(() {
      _items = list;
      _stats = stats;
    });
  }

  Future<void> _broadcast() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    String type = 'broadcast';
    final message = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1B1A26),
          title: Text(
            l10n.ntBroadcast,
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.ntType,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in _types)
                      ChoiceChip(
                        label: Text(_typeLabel(t, l10n)),
                        selected: type == t,
                        onSelected: (_) => setDialog(() => type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: l10n.ntMessage,
                    filled: true,
                    fillColor: const Color(0xFF15131E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.ntConfirmBody,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              child: Text(l10n.ntSend),
            ),
          ],
        ),
      ),
    );
    final msgText = message.text.trim();
    message.dispose();
    if (ok != true) return;
    if (msgText.length < 4) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.ntBadMessage),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _svc.broadcastNotification(type: type, message: msgText);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.ntActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat('📥', l10n.ntStatsTotal, _stats['total']),
              _stat('✉️', l10n.ntStatsUnread, _stats['unread']),
              _stat('🕐', l10n.ntStatsToday, _stats['today']),
              _stat('📢', l10n.ntStatsBroadcasts, _stats['broadcasts_7d']),
              _stat('📱', l10n.ntStatsTokens, _stats['active_tokens']),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _userFilter,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    labelText: l10n.ntFilterUser,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: _load,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF15131E),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _broadcast,
                icon: const Icon(Icons.campaign_rounded, size: 18),
                label: Text(l10n.ntBroadcast),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.ntFilterTypeAll),
                selected: _typeFilter == null,
                onSelected: (_) {
                  setState(() => _typeFilter = null);
                  _load();
                },
              ),
              for (final t in _types)
                ChoiceChip(
                  label: Text(_typeLabel(t, l10n)),
                  selected: _typeFilter == t,
                  onSelected: (_) {
                    setState(() => _typeFilter = t);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF15131E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.ntEmpty,
                style: const TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final it in _items) _card(it, l10n),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> it, AppLocalizations l10n) {
    final type = it['type']?.toString() ?? 'system';
    final read = (it['read'] as bool?) ?? false;
    final display = it['display_name']?.toString() ?? '';
    final username = it['username']?.toString() ?? '';
    final user = [
      if (display.isNotEmpty) display,
      if (username.isNotEmpty) '@$username',
    ].join(' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _typeColor(type).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _typeColor(type).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _typeLabel(type, l10n),
                  style: TextStyle(
                    color: _typeColor(type),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                read ? Icons.done_all_rounded : Icons.circle,
                color: read ? Colors.white24 : const Color(0xFFF59E0B),
                size: read ? 18 : 10,
              ),
              const SizedBox(width: 4),
              Text(
                read ? l10n.ntRead : l10n.ntUnread,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            it['message']?.toString() ?? '—',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (user.isNotEmpty) user,
              _ago(it['created_at'] as String?),
            ].where((e) => e.isNotEmpty).join(' · '),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _stat(String emoji, String label, dynamic v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              '${v ?? 0}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  String _typeLabel(String t, AppLocalizations l10n) => switch (t) {
    'broadcast' => l10n.ntTypeBroadcast,
    'announcement' => l10n.ntTypeAnnouncement,
    'event' => l10n.ntTypeEvent,
    'alert' => l10n.ntTypeAlert,
    _ => t,
  };

  Color _typeColor(String t) => switch (t) {
    'broadcast' => const Color(0xFF8B5CF6),
    'announcement' => const Color(0xFF34D399),
    'event' => const Color(0xFFF59E0B),
    'alert' => const Color(0xFFE4183C),
    _ => Colors.white38,
  };

  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// 👑 FERRAMENTAS DE REI (tab founder — motor anti-hack Guardian)
// ---------------------------------------------------------------------------

/// Controle do motor de regras anti-abuso + central de alertas. Liga/desliga
/// regras (founder-only), roda a varredura e resolve alertas — tudo auditado.
class _FounderKingTab extends StatefulWidget {
  const _FounderKingTab();

  @override
  State<_FounderKingTab> createState() => _FounderKingTabState();
}

class _FounderKingTabState extends State<_FounderKingTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  bool _rules = true;
  List<Map<String, dynamic>> _rulesList = const [];
  List<Map<String, dynamic>> _alerts = const [];
  String? _severity;
  bool _busy = false;

  static const List<String> _severities = [
    'critical',
    'high',
    'medium',
    'low',
    'info',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_rules) {
      final r = await _svc.kingRules().catchError(
        (_) => const <Map<String, dynamic>>[],
      );
      if (!mounted) return;
      setState(() => _rulesList = r);
    } else {
      final a = await _svc
          .kingAlerts(severity: _severity)
          .catchError((_) => const <Map<String, dynamic>>[]);
      if (!mounted) return;
      setState(() => _alerts = a);
    }
  }

  Future<void> _toggleRule(Map<String, dynamic> r, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await _svc.kingToggleRule(ruleId: r['id'].toString(), enabled: enabled);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.ktActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runScan() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final res = await _svc.kingRunRules();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.ktScanOk((res['checks'] as num?)?.toInt() ?? 0)),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(Map<String, dynamic> a) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.ktAlertResolveTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: note,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.ktAlertNote,
            filled: true,
            fillColor: const Color(0xFF15131E),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    final noteText = note.text.trim();
    note.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.kingResolveAlert(alertId: a['id'].toString(), note: noteText);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.ktActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(l10n.ktRules)),
              ButtonSegment(value: false, label: Text(l10n.ktAlerts)),
            ],
            selected: {_rules},
            onSelectionChanged: (s) {
              setState(() => _rules = s.first);
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (_rules) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.ktRulesCount(_rulesList.length),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _runScan,
                  icon: const Icon(Icons.run_circle_rounded, size: 18),
                  label: Text(l10n.ktRunScan),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_rulesList.isEmpty)
              _emptyCard(l10n.ktRulesEmpty)
            else
              for (final r in _rulesList) _ruleCard(r, l10n),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.ktSevAll),
                  selected: _severity == null,
                  onSelected: (_) {
                    setState(() => _severity = null);
                    _load();
                  },
                ),
                for (final s in _severities)
                  ChoiceChip(
                    label: Text(_sevLabel(s, l10n)),
                    selected: _severity == s,
                    onSelected: (_) {
                      setState(() => _severity = s);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_alerts.isEmpty)
              _emptyCard(l10n.ktAlertsEmpty)
            else
              for (final a in _alerts) _alertCard(a, l10n),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _emptyCard(String label) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF15131E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(label, style: const TextStyle(color: Colors.white38)),
  );

  Widget _ruleCard(Map<String, dynamic> r, AppLocalizations l10n) {
    final id = r['id']?.toString() ?? '';
    final enabled = (r['enabled'] as bool?) ?? false;
    final category = r['category']?.toString() ?? '';
    final priority = (r['priority'] as num?)?.toInt() ?? 0;
    final desc = r['description']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (enabled ? const Color(0xFF8B5CF6) : Colors.white24)
              .withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  id,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: _busy ? null : (v) => _toggleRule(r, v),
                activeTrackColor: const Color(0xFF8B5CF6),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xFFB794FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${l10n.ktPriority}: $priority',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertCard(Map<String, dynamic> a, AppLocalizations l10n) {
    final sev = a['severity']?.toString() ?? 'info';
    final status = a['status']?.toString() ?? 'open';
    final open = status == 'open' || status == 'ack';
    final message = a['message']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _sevColor(sev).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _sevColor(sev).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _sevLabel(sev, l10n),
                  style: TextStyle(
                    color: _sevColor(sev),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                open ? l10n.ktAlertsOpen : l10n.ktAlertsResolved,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              Text(
                _ago(a['created_at'] as String?),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            a['title']?.toString() ?? '—',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (open)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _resolve(a),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(l10n.ktAlertResolve),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF34D399),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _sevLabel(String s, AppLocalizations l10n) => switch (s) {
    'critical' => l10n.ktSevCritical,
    'high' => l10n.ktSevHigh,
    'medium' => l10n.ktSevMedium,
    'low' => l10n.ktSevLow,
    'info' => l10n.ktSevInfo,
    _ => s,
  };

  Color _sevColor(String s) => switch (s) {
    'critical' => const Color(0xFFE4183C),
    'high' => const Color(0xFFFFB300),
    'medium' => const Color(0xFFF59E0B),
    'low' => const Color(0xFF34D399),
    'info' => const Color(0xFF8B5CF6),
    _ => Colors.white38,
  };

  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// ⚙️ CONFIG GLOBAIS (tab equipe — cap roles/settings)
// ---------------------------------------------------------------------------

/// Chaves globais de runtime (chave → valor JSON + descrição): criar, editar e
/// excluir com validação local e RPC `security definer` auditada.
class _FounderConfigTab extends StatefulWidget {
  const _FounderConfigTab();

  @override
  State<_FounderConfigTab> createState() => _FounderConfigTabState();
}

class _FounderConfigTabState extends State<_FounderConfigTab> {
  final FounderService _svc = FounderService.instance;
  final AdminService _admin = AdminService.instance;

  List<MapEntry<String, Map<String, dynamic>>> _entries = const [];
  bool _busy = false;

  static final RegExp _keyRe = RegExp(r'^[A-Za-z0-9._-]{2,64}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await _svc.configList().catchError(
      (_) => const <String, dynamic>{},
    );
    if (!mounted) return;
    setState(() {
      _entries =
          raw.entries
              .map(
                (e) => MapEntry(
                  e.key,
                  (e.value is Map)
                      ? Map<String, dynamic>.from(e.value as Map)
                      : <String, dynamic>{'value': e.value},
                ),
              )
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
    });
  }

  Future<void> _edit([MapEntry<String, Map<String, dynamic>>? existing]) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final keyCtl = TextEditingController(text: existing?.key ?? '');
    final descCtl = TextEditingController(
      text: existing?.value['description']?.toString() ?? '',
    );
    final valueCtl = TextEditingController(
      text: existing == null ? '' : _prettyJson(existing.value['value']),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          existing == null ? l10n.cfgAdd : l10n.cfgEdit,
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtl,
                decoration: InputDecoration(
                  labelText: l10n.cfgKey,
                  hintText: 'economy.gift_spend_multiplier',
                  filled: true,
                  fillColor: const Color(0xFF15131E),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtl,
                decoration: InputDecoration(
                  labelText: l10n.cfgDescription,
                  filled: true,
                  fillColor: const Color(0xFF15131E),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: valueCtl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.cfgValue,
                  hintText: '1.0, true, "texto", {"a": 1}',
                  filled: true,
                  fillColor: const Color(0xFF15131E),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(l10n.cfgSave),
          ),
        ],
      ),
    );
    final key = keyCtl.text.trim();
    final desc = descCtl.text.trim();
    final valueText = valueCtl.text.trim();
    keyCtl.dispose();
    descCtl.dispose();
    valueCtl.dispose();
    if (ok != true) return;

    if (!_keyRe.hasMatch(key)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cfgBadKey),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
      return;
    }
    if (valueText.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cfgBadJson),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
      return;
    }
    dynamic parsed;
    try {
      parsed = jsonDecode(valueText);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cfgBadJson),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _svc.setConfig(key: key, value: parsed, description: desc);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cfgActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(e)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(MapEntry<String, Map<String, dynamic>> e) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          l10n.cfgDeleteConfirmTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '${e.key}\n${l10n.cfgDelete}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE4183C),
            ),
            child: Text(l10n.cfgDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.deleteConfig(e.key);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cfgActionOk),
          backgroundColor: const Color(0xFF0F8A4D),
        ),
      );
      await _load();
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_admin.friendlyError(err)),
          backgroundColor: const Color(0xFFE4183C),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cfgCount(_entries.length),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.cfgAdd),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_entries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF15131E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.cfgEmpty,
                style: const TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final e in _entries) _configCard(e, l10n),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _configCard(
    MapEntry<String, Map<String, dynamic>> e,
    AppLocalizations l10n,
  ) {
    final v = e.value['value'];
    final desc = e.value['description']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              desc,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0E15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _prettyJson(v),
              style: const TextStyle(
                color: Color(0xFFB794FF),
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _edit(e),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(l10n.cfgEdit),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _delete(e),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(l10n.cfgDelete),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE4183C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _prettyJson(dynamic v) {
    if (v is String) {
      try {
        final d = jsonDecode(v);
        if (d is! String) return jsonEncode(d);
      } catch (_) {}
      return '"$v"';
    }
    return jsonEncode(v);
  }
}
