import 'package:flutter/material.dart';

import '../models/gift_models.dart';
import '../services/admin_service.dart';
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
  late Future<Map<String, dynamic>> _chests;
  late Future<List<Map<String, dynamic>>> _chestCatalog;
  late Future<List<Map<String, dynamic>>> _audit;
  late Future<List<Map<String, dynamic>>> _professions;
  late Future<List<Map<String, dynamic>>> _bots;
  late Future<List<Map<String, dynamic>>> _pendingConversions;

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
      final caps = (results[2] as List?)?.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList() ?? const <String>[];
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
    final c = caps.toSet();
    bool has(String cap) => c.contains(cap);
    final tabs = <_PanelTab>[];
    if (admin) {
      tabs.add(const _PanelTab(Icons.insights_rounded, 'Visão Geral', _TabId.overview));
      tabs.add(const _PanelTab(Icons.shield_rounded, 'Moderação', _TabId.moderation));
    }
    if (admin || has('verification') || has('verification_view')) {
      tabs.add(const _PanelTab(Icons.badge_rounded, 'Verificação', _TabId.verification));
    }
    if (admin || has('support') || has('tickets')) {
      tabs.add(const _PanelTab(Icons.support_agent_rounded, 'Suporte', _TabId.tickets));
    }
    if (admin) {
      tabs.add(const _PanelTab(Icons.people_rounded, 'Usuários', _TabId.users));
    }
    if (has('roles')) {
      tabs.add(const _PanelTab(Icons.group_add_rounded, 'Equipe', _TabId.team));
    }
    if (has('economy')) {
      tabs.add(const _PanelTab(Icons.account_balance_wallet_rounded, 'Economia', _TabId.economy));
    }
    if (has('chests')) {
      tabs.add(const _PanelTab(Icons.inventory_2_rounded, 'Baús', _TabId.chests));
    }
    if (has('missions')) {
      tabs.add(const _PanelTab(Icons.military_tech_rounded, 'Missões', _TabId.missions));
    }
    if (admin) {
      tabs.add(const _PanelTab(Icons.card_giftcard_rounded, 'Presentes', _TabId.gifts));
      tabs.add(const _PanelTab(Icons.shopping_bag_rounded, 'Loja', _TabId.store));
      tabs.add(const _PanelTab(Icons.sensors_rounded, 'LIVE', _TabId.live));
    }
    if (has('audit')) {
      tabs.add(const _PanelTab(Icons.fact_check_rounded, 'Auditoria', _TabId.audit));
    }
    if (admin) {
      tabs.add(const _PanelTab(Icons.admin_panel_settings_rounded, 'Admin', _TabId.admin));
      tabs.add(const _PanelTab(Icons.work_rounded, 'Profissões', _TabId.professions));
      tabs.add(const _PanelTab(Icons.smart_toy_rounded, 'Bots', _TabId.bots));
      tabs.add(const _PanelTab(Icons.campaign_rounded, 'Publicidade', _TabId.ads));
    }
    return tabs;
  }

  void _refreshAll() {
    _overview = _svc.stats().catchError((_) => const <String, dynamic>{});
    _reports = _social.modListReports().catchError((_) => const <Map<String, dynamic>>[]);
    _users = _svc.listUsers().catchError((_) => const <Map<String, dynamic>>[]);
    _orders = _svc.listOrders().catchError((_) => const <Map<String, dynamic>>[]);
    _lives = _svc.liveStats().catchError((_) => const <String, dynamic>{});
    _admins = _svc.listAdmins().catchError((_) => const <Map<String, dynamic>>[]);
    _giftStats = _svc.giftStats().catchError((_) => const <String, dynamic>{});
    _catalog = _gifts.fetchPopular(limit: 15).catchError((_) => const <Gift>[]);
    _store = _svc.storeStats().catchError((_) => const <String, dynamic>{});
    _rules = _social.modListSpamRules().catchError((_) => const <Map<String, dynamic>>[]);
    _verifications = _admin.adminListVerifications('pending').catchError((_) => const <Map<String, dynamic>>[]);
    _tickets = _admin.adminListTickets('open').catchError((_) => const <Map<String, dynamic>>[]);
    _staff = _admin.adminListStaff().catchError((_) => const <Map<String, dynamic>>[]);
    _economy = _admin.adminEconomyStats().catchError((_) => const <String, dynamic>{});
    _chests = _admin.adminChestStats().catchError((_) => const <String, dynamic>{});
    _chestCatalog = _admin.adminListChests().catchError((_) => const <Map<String, dynamic>>[]);
    _audit = _admin.adminAuditList(limit: 80).catchError((_) => const <Map<String, dynamic>>[]);
    _professions = _admin.adminListProfessions().catchError((_) => const <Map<String, dynamic>>[]);
    _bots = _admin.adminListBots().catchError((_) => const <Map<String, dynamic>>[]);
    _pendingConversions = _adminPendingConversions();
  }

  void _reload() => setState(_refreshAll);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.isEmpty ? 1 : _tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0812),
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isAdmin == true
                    ? '👑 Painel do Fundador'
                    : '🛡️ Painel da Equipe',
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
              ),
              Text(
                'role: ${_role.isEmpty ? '…' : _role} · ${_caps.length} capabilities',
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
                      for (final t in _tabs) Tab(icon: Icon(t.icon), text: t.label),
                    ],
                  ),
                ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_adminError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white38, size: 44),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível verificar seu acesso.\nVerifique sua conexão e tente novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
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
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (_checking) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            SizedBox(height: 14),
            Text('Verificando permissões…',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (_isAdmin == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            SizedBox(height: 14),
            Text('Verificando permissões…',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (_tabs.isEmpty) {
      return const _RestrictedView();
    }
    return TabBarView(
      children: [for (final t in _tabs) _tabView(t.id)],
    );
  }

  Widget _tabView(_TabId id) {
    switch (id) {
      case _TabId.overview:
        return _overviewTab();
      case _TabId.moderation:
        return _moderationTab();
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
    }
  }

  // ---------------------------------------------------------------------------
  // 📊 Visão Geral
  // ---------------------------------------------------------------------------

  Widget _overviewTab() => RefreshIndicator(
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
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _statCard(Icons.people_rounded, 'Usuários', _num(s['users']), color: const Color(0xFF8B5CF6)),
                    _statCard(Icons.person_add_alt_1, 'Novos (7d)', _num(s['new_users_7d']), color: const Color(0xFFB794FF)),
                    _statCard(Icons.video_library_rounded, 'Vídeos', _num(s['videos']), color: const Color(0xFF22D3EE)),
                    _statCard(Icons.sensors_rounded, 'Lives', s['lives']?.toString() ?? '0'),
                    _statCard(Icons.flag_rounded, 'Denúncias abertas', _num(s['reports_pending']), color: const Color(0xFFFF6B81)),
                    _statCard(Icons.flag_outlined, 'Denúncias resolvidas', _num(s['reports_resolved'])),
                    _statCard(Icons.card_giftcard_rounded, 'Presentes enviados', _num(s['gift_transactions']), color: const Color(0xFFF59E0B)),
                    _statCard(Icons.savings_rounded, 'Créditos (presentes)', _num(s['gift_credits']), color: const Color(0xFFF59E0B)),
                    _statCard(Icons.receipt_long_rounded, 'Pedidos', _num(s['orders']), color: const Color(0xFF34D399)),
                    _statCard(Icons.payments_rounded, 'Receita da Loja', _money(s['orders_revenue']), color: const Color(0xFF34D399)),
                  ],
                ),
                const SizedBox(height: 18),
                _sectionTitle('Cadastros recentes'),
                const SizedBox(height: 8),
                if (recentSignups.isEmpty)
                  _empty('Sem cadastros ainda.')
                else
                  ...recentSignups.map(
                        (e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline,
                              color: Color(0xFFB794FF), size: 20),
                          title: Text(
                            '${e['display_name'] ?? '—'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          subtitle: Text('@${e['username'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          trailing: Text(
                            _relativeTime(e['created_at'] as String?),
                            style: const TextStyle(
                                color: Colors.white30, fontSize: 11),
                          ),
                        ),
                      ),
                const SizedBox(height: 18),
                _sectionTitle('Denúncias recentes'),
                const SizedBox(height: 8),
                if (recentReports.isEmpty)
                  _empty('Sem denúncias.')
                else
                  ...recentReports.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined,
                            color: Color(0xFFFF6B81), size: 20),
                        title: Text(
                          '${e['target_type']} · ${e['reason'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                        trailing: _statusChip(e['status'] as String?),
                      )),
              ],
            );
          },
        ),
      );

  // ---------------------------------------------------------------------------
  // 🛡️ Moderação
  // ---------------------------------------------------------------------------

  Widget _moderationTab() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _reports,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final reports = snap.data ?? const [];
          if (reports.isEmpty) return _emptyScroll('Nenhuma denúncia.');
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
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${r['target_type']}',
                          style: const TextStyle(
                              color: Color(0xFFB794FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      _statusChip(r['status'] as String?),
                      const Spacer(),
                      Text(
                        _relativeTime(r['created_at'] as String?),
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Alvo: ${r['target_id']}',
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
                        onPressed: () =>
                            _resolveReport(id, 'resolved'),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Resolver'),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF34D399)),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _resolveReport(id, 'dismissed'),
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Descartar'),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white54),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );

  Future<void> _resolveReport(String id, String status) async {
    await _svcGuard(() => _social.modUpdateReport(id, status));
    _reload();
  }

  // ---------------------------------------------------------------------------
  // 👥 Usuários
  // ---------------------------------------------------------------------------

  Widget _usersTab() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _users,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final users = snap.data ?? const [];
          if (users.isEmpty) return _emptyScroll('Nenhum usuário.');
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
                    (u['display_name']?.toString() ?? '?')
                        .characters
                        .first
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
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 15),
                    ],
                    if (admin) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.workspace_premium_rounded,
                          color: Color(0xFF8B5CF6), size: 15),
                    ],
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      const Text('você',
                          style: TextStyle(color: Colors.white30, fontSize: 11)),
                    ],
                  ],
                ),
                subtitle: Text('@${u['username'] ?? ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: isMe
                    ? const Text('—', style: TextStyle(color: Colors.white24))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Atribuir profissão',
                            icon: const Icon(Icons.badge_rounded,
                                color: Color(0xFFB794FF), size: 21),
                            onPressed: () => _openUserSheet(u),
                          ),
                          IconButton(
                            tooltip: verified
                                ? 'Remover verificação'
                                : 'Verificar perfil',
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
                                  () => _svc.setVerified(id, !verified));
                              _reload();
                            },
                          ),
                          IconButton(
                            tooltip: admin
                                ? 'Remover admin (Fundador)'
                                : 'Tornar admin (Fundador)',
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

  Widget _giftsTab() => FutureBuilder<Map<String, dynamic>>(
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
                  _statCard(Icons.card_giftcard_rounded, 'Transações', _num(s['transactions']), color: const Color(0xFFF59E0B)),
                  _statCard(Icons.savings_rounded, 'Créditos movimentados', _num(s['credits']), color: const Color(0xFFF59E0B)),
                  _statCard(Icons.auto_awesome, 'Presentes ativos', _num(s['gifts']), color: const Color(0xFFB794FF)),
                ],
              ),
              const SizedBox(height: 18),
              _sectionTitle('Mais enviados'),
              const SizedBox(height: 8),
              if (top.isEmpty)
                _empty('Sem envios registrados ainda.')
              else
                ...top.map((g) {
                  final name = '${g['name'] ?? g['id']}';
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    trailing: Text('${_num(g['count'])}x',
                        style: const TextStyle(
                            color: Color(0xFFB794FF),
                            fontWeight: FontWeight.w800)),
                  );
                }),
              const SizedBox(height: 18),
              _sectionTitle('Catálogo'),
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
                              strokeWidth: 2, color: Color(0xFF8B5CF6)),
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
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C2E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            '${g.icon} ${g.name}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
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

  // ---------------------------------------------------------------------------
  // 🛒 Loja
  // ---------------------------------------------------------------------------

  Widget _storeTab() => FutureBuilder<Map<String, dynamic>>(
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
                  _statCard(Icons.inventory_2_rounded, 'Produtos', _num(s['products']), color: const Color(0xFF34D399)),
                  _statCard(Icons.category_rounded, 'Categorias', _num(s['categories'])),
                  _statCard(Icons.storefront_rounded, 'Vendedores', _num(s['sellers'])),
                  _statCard(Icons.receipt_long_rounded, 'Pedidos', _num(s['orders']), color: const Color(0xFF34D399)),
                  _statCard(Icons.payments_rounded, 'Receita', _money(s['revenue']), color: const Color(0xFF34D399)),
                ],
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('Pedidos por status'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in status.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${e.key}: ${_num(e.value)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _sectionTitle('Últimos pedidos'),
              const SizedBox(height: 4),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _orders,
                builder: (context, snapO) {
                  if (snapO.connectionState != ConnectionState.done) {
                    return const SizedBox(height: 40);
                  }
                  final orders = snapO.data ?? const [];
                  if (orders.isEmpty) return _empty('Sem pedidos.');
                  return Column(
                    children: [
                      for (final o in orders)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.shopping_bag_rounded,
                              color: Color(0xFF34D399), size: 20),
                          title: Text(
                            '${o['buyer_username'] ?? o['buyer_name'] ?? '—'} → '
                            '${o['seller_username'] ?? o['seller_name'] ?? '—'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${_statusLabel(o['status'] as String?)} · ${_relativeTime(o['created_at'] as String?)}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                          trailing: Text(
                            _money(o['total']),
                            style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontWeight: FontWeight.w800,
                                fontSize: 13),
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

  // ---------------------------------------------------------------------------
  // 📺 LIVE
  // ---------------------------------------------------------------------------

  Widget _liveTab() => FutureBuilder<Map<String, dynamic>>(
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
                  _statCard(Icons.sensors_rounded, 'Lives totais', _num(s['total'])),
                  _statCard(Icons.live_tv_rounded, 'Ao vivo agora', _num(s['active']), color: const Color(0xFFFF2E4D)),
                ],
              ),
              const SizedBox(height: 16),
              _sectionTitle('Transmissões ativas'),
              const SizedBox(height: 8),
              if (list.isEmpty)
                _empty('Nenhuma live ativa no momento.')
              else
                ...list.map((l) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.circle,
                          color: Color(0xFFFF2E4D), size: 12),
                      title: Text(
                        '${l['title'] ?? '—'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${l['category'] ?? ''}${(l['game_name'] as String? ?? '').isNotEmpty ? ' · 🎮 ${l['game_name']}' : ''} · '
                        '${l['streamer_display'] ?? l['streamer_username'] ?? '—'} · '
                        '${_num(l['viewer_count'])} espect.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    )),
            ],
          );
        },
      );

  // ---------------------------------------------------------------------------
  // ⚙️ Administração
  // ---------------------------------------------------------------------------

  Widget _adminTab() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _admins,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final admins = snap.data ?? const [];
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle('Fundadores / Administradores'),
              const SizedBox(height: 8),
              if (admins.isEmpty)
                _empty('Nenhum administrador.')
              else
                ...admins.map((a) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.workspace_premium_rounded,
                          color: Color(0xFF8B5CF6)),
                      title: Text(
                        '${a['display_name'] ?? '—'}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('@${a['username'] ?? ''}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    )),
              const SizedBox(height: 18),
              _sectionTitle('Regras anti-spam'),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _rules,
                builder: (context, snapR) {
                  if (snapR.connectionState != ConnectionState.done) {
                    return const SizedBox(height: 30);
                  }
                  final rules = snapR.data ?? const [];
                  if (rules.isEmpty) return _empty('Sem regras anti-spam.');
                  return Column(
                    children: [
                      for (final r in rules)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.gpp_good_outlined,
                              color: Color(0xFFB794FF), size: 20),
                          title: Text(
                            '${r['pattern'] ?? '—'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${r['rule_type'] ?? ''} · ${r['scope'] ?? ''}${r['active'] == false ? ' · inativa' : ''}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
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

  // ---------------------------------------------------------------------------
  // ✅ Verificação (cap: verification / verification_view)
  // ---------------------------------------------------------------------------

  Widget _verificationTab() => FutureBuilder<List<Map<String, dynamic>>>(
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
                _sectionTitle('Pedidos de verificação'),
                const SizedBox(height: 4),
                Text(
                  canReview
                      ? 'Você pode aprovar ou rejeitar.'
                      : 'Visualização apenas (revisão exige cap de verificação).',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  _emptyScroll('Nenhum pedido pendente.')
                else
                  ...items.map((v) => _verificationCard(v, canReview)),
              ],
            ),
          );
        },
      );

  Widget _verificationCard(Map<String, dynamic> v, bool canReview) {
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
              const Icon(Icons.badge_rounded, color: Color(0xFFB794FF), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v['display_name']?.toString() ?? v['username']?.toString() ?? '—',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
            'pedido em ${_relativeTime(v['submitted_at']?.toString())}',
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
          if (canReview) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reviewVerification(v['id']?.toString(), true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF34D399),
                      side: const BorderSide(color: Color(0xFF34D399)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Aprovar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reviewVerification(v['id']?.toString(), false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B81),
                      side: const BorderSide(color: Color(0xFFFF6B81)),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rejeitar'),
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
    if (id == null) return;
    try {
      final res = await _admin.adminReviewVerification(id, approve: approve);
      final ok = res['ok'] == true || res['status'] != null;
      _okSnack(ok ? 'Verificação ${approve ? 'aprovada' : 'rejeitada'}!' : 'Sem resposta do servidor.');
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

  Widget _ticketsTab() => FutureBuilder<List<Map<String, dynamic>>>(
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
                _sectionTitle('Tickets abertos'),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  _emptyScroll('Nenhum ticket aberto.')
                else
                  ...items.map((t) => _ticketCard(t)),
              ],
            ),
          );
        },
      );

  Widget _ticketCard(Map<String, dynamic> t) {
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
              const Icon(Icons.support_agent_rounded, color: Color(0xFF8B5CF6), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t['username'] ?? '—'} · ${t['status'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openTicketDialog(t),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB794FF),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.reply_rounded, size: 16),
            label: const Text('Responder / atualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTicketDialog(Map<String, dynamic> t) async {
    final statusCtrl = TextEditingController(text: (t['status'] ?? 'open').toString());
    final replyCtrl = TextEditingController();
    final id = t['id']?.toString();
    if (id == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: const Text('Atualizar ticket',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: (t['status'] ?? 'open').toString(),
              dropdownColor: const Color(0xFF15131E),
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'open', child: Text('Aberto')),
                DropdownMenuItem(value: 'in_progress', child: Text('Em análise')),
                DropdownMenuItem(value: 'closed', child: Text('Fechado')),
              ],
              onChanged: (v) => statusCtrl.text = v ?? 'open',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: replyCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Resposta',
                hintText: 'Resposta enviada ao usuário (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
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
                _okSnack('Ticket atualizado.');
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
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 👥 Equipe (cap: roles — founder)
  // ---------------------------------------------------------------------------

  Widget _teamTab() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _staff,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final items = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _staff = _admin
                    .adminListStaff()
                    .catchError((_) => const <Map<String, dynamic>>[]);
              });
              await _staff;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              children: [
                _sectionTitle('Equipe & roles'),
                const SizedBox(height: 4),
                const Text(
                  'Só o fundador pode alterar roles (validação no backend).',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  _emptyScroll('Nenhum membro da equipe.')
                else
                  ...items.map((m) => _staffRow(m)),
              ],
            ),
          );
        },
      );

  Widget _staffRow(Map<String, dynamic> m) {
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
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text('@${m['username'] ?? ''}',
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roleChip(role),
          if (canManage) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => _openRoleDialog(m),
              icon: const Icon(Icons.edit_rounded, color: Color(0xFF8B5CF6), size: 18),
              tooltip: 'Alterar role',
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleChip(String role) {
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
        role.replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _openRoleDialog(Map<String, dynamic> m) async {
    final uid = m['id']?.toString();
    if (uid == null) return;
    final current = m['role']?.toString() ?? 'user';
    String selected = current;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: const Text('Alterar role',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: DropdownButtonFormField<String>(
          initialValue: current,
          dropdownColor: const Color(0xFF15131E),
          decoration: const InputDecoration(labelText: 'Role'),
          items: const [
            DropdownMenuItem(value: 'founder', child: Text('Founder')),
            DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
            DropdownMenuItem(value: 'moderator', child: Text('Moderador')),
            DropdownMenuItem(value: 'support', child: Text('Suporte')),
            DropdownMenuItem(value: 'user', child: Text('Usuário')),
          ],
          onChanged: (v) => selected = v ?? current,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (selected == current) return;
              try {
                await _admin.adminSetRole(uid, role: selected);
                _okSnack('Role atualizada para ${selected.replaceAll('_', ' ')}.');
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _staff = _admin
                      .adminListStaff()
                      .catchError((_) => const <Map<String, dynamic>>[]);
                });
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💰 Economia (cap: economy)
  // ---------------------------------------------------------------------------

  Widget _economyTab() => FutureBuilder<Map<String, dynamic>>(
        future: _economy,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final s = snap.data ?? const {};
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle('Total em circulação'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statCard(Icons.stars_rounded, 'Credits', _num(s['credits']), color: const Color(0xFFF59E0B)),
                  _statCard(Icons.diamond_outlined, 'Diamonds', _num(s['diamonds']), color: const Color(0xFF38BDF8)),
                  _statCard(Icons.diamond_outlined, 'Crystals', _num(s['crystals']), color: const Color(0xFFE879F9)),
                  _statCard(Icons.circle_rounded, 'Rubies', _num(s['rubies']), color: const Color(0xFFFF4D6A)),
                  _statCard(Icons.eco_rounded, 'Emeralds', _num(s['emeralds']), color: const Color(0xFF34D399)),
                  _statCard(Icons.diamond_rounded, 'Crystal Rare', _num(s['crystal_rare']), color: const Color(0xFFD4AF37)),
                ],
              ),
              const SizedBox(height: 18),
              _grantCurrencyForm(),
              const SizedBox(height: 18),
              _conversionsSection(),
            ],
          );
        },
      );

  // ---------------------------------------------------------------------------
  // 💱 Conversões/resgates (gestão admin/fundador)
  // ---------------------------------------------------------------------------

  Widget _conversionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Conversões pendentes'),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _pendingConversions,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
              ));
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
                child: const Text('Nenhuma conversão aguardando aprovação.',
                    style: TextStyle(color: Colors.white38)),
              );
            }
            return Column(
              children: [
                for (final r in list) _conversionTile(r),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _refreshPendingConversions,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Atualizar'),
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
    final from = r['from_currency']?.toString() ?? '?';
    final to = r['to_currency']?.toString() ?? '?';
    final amount = (r['amount'] as num?)?.toInt() ?? 0;
    final received = (r['received'] as num?)?.toInt() ?? 0;
    final userId = r['user_id']?.toString() ?? '';
    final shortId = userId.length > 8 ? '…${userId.substring(userId.length - 8)}' : userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$amount $from → $received $to',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text('Usuário: $shortId',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _decideConversion(r['id'], approve: true),
            tooltip: 'Aprovar',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x1FFFD700),
            ),
            icon: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF34D399), size: 20),
          ),
          IconButton(
            onPressed: () => _decideConversion(r['id'], approve: false),
            tooltip: 'Rejeitar (reembolsa)',
            style: IconButton.styleFrom(backgroundColor: const Color(0x22FF6B81)),
            icon: const Icon(Icons.cancel_rounded,
                color: Color(0xFFFF6B81), size: 20),
          ),
        ],
      ),
    );
  }

  Future<void> _decideConversion(Object? id, {required bool approve}) async {
    if (id == null) return;
    try {
      await _svc.decideConversion(id.toString(), approve: approve);
      _okSnack(approve
          ? 'Conversão aprovada e moeda creditada.'
          : 'Conversão rejeitada e saldo reembolsado.');
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
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nova regra de conversão',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              TextField(
                controller: idCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'ID (ex.: credits_to_diamonds)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: from,
                      dropdownColor: const Color(0xFF15131E),
                      decoration:
                          const InputDecoration(labelText: 'De'),
                      items: const [
                        DropdownMenuItem(
                            value: 'credits', child: Text('Credits')),
                        DropdownMenuItem(
                            value: 'diamonds', child: Text('Diamonds')),
                        DropdownMenuItem(
                            value: 'crystals', child: Text('Crystals')),
                        DropdownMenuItem(
                            value: 'rubies', child: Text('Rubies')),
                        DropdownMenuItem(
                            value: 'emeralds', child: Text('Emeralds')),
                      ],
                      onChanged: (v) => setLocalState(() => from = v ?? from),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: to,
                      dropdownColor: const Color(0xFF15131E),
                      decoration:
                          const InputDecoration(labelText: 'Para'),
                      items: const [
                        DropdownMenuItem(
                            value: 'credits', child: Text('Credits')),
                        DropdownMenuItem(
                            value: 'diamonds', child: Text('Diamonds')),
                        DropdownMenuItem(
                            value: 'crystals', child: Text('Crystals')),
                        DropdownMenuItem(
                            value: 'rubies', child: Text('Rubies')),
                        DropdownMenuItem(
                            value: 'emeralds', child: Text('Emeralds')),
                        DropdownMenuItem(
                            value: 'crystal_rare', child: Text('Crystal Rare')),
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
                      decoration: const InputDecoration(labelText: 'Taxa (1 De = X Para)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Mín'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Máx'),
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
                      decoration:
                          const InputDecoration(labelText: 'Taxa % (fee)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: status,
                      dropdownColor: const Color(0xFF15131E),
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Ativa')),
                        DropdownMenuItem(
                            value: 'paused', child: Text('Pausada')),
                      ],
                      onChanged: (v) => setLocalState(() => status = v ?? status),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: method,
                      dropdownColor: const Color(0xFF15131E),
                      decoration: const InputDecoration(labelText: 'Método'),
                      items: const [
                        DropdownMenuItem(
                            value: 'wallet', child: Text('Carteira')),
                        DropdownMenuItem(
                            value: 'rescue', child: Text('Resgate')),
                      ],
                      onChanged: (v) => setLocalState(() => method = v ?? method),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
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
                      _errSnack('Preencha id, nome, taxa, mín e máx.');
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
                      _okSnack('Regra de conversão salva.');
                    } catch (e) {
                      _errSnack(_admin.friendlyError(e));
                    }
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6)),
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Salvar regra'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grantCurrencyForm() {
    final userIdCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: '100');
    final noteCtrl = TextEditingController();
    String currency = 'credits';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conceder moeda (ledger auditado)',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: userIdCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'ID do usuário (uuid)',
              hintText: 'cole o uuid aqui',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: currency,
            dropdownColor: const Color(0xFF15131E),
            decoration: const InputDecoration(labelText: 'Moeda'),
            items: const [
              DropdownMenuItem(value: 'credits', child: Text('Credits')),
              DropdownMenuItem(value: 'diamonds', child: Text('Diamonds')),
              DropdownMenuItem(value: 'crystals', child: Text('Crystals')),
              DropdownMenuItem(value: 'rubies', child: Text('Rubies')),
              DropdownMenuItem(value: 'emeralds', child: Text('Emeralds')),
              DropdownMenuItem(value: 'crystal_rare', child: Text('Crystal Rare')),
            ],
            onChanged: (v) => currency = v ?? 'credits',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Quantidade'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final uid = userIdCtrl.text.trim();
                final amount = int.tryParse(amountCtrl.text.trim());
                if (uid.isEmpty || amount == null || amount <= 0) {
                  _errSnack('Informe o uuid e uma quantidade válida.');
                  return;
                }
                try {
                  await _admin.adminGrantCurrency(
                    uid,
                    currency: currency,
                    amount: amount,
                    note: noteCtrl.text,
                  );
                  _okSnack('+$amount $currency concedido e auditado.');
                } catch (e) {
                  _errSnack(_admin.friendlyError(e));
                }
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Conceder'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📦 Baús (cap: chests)
  // ---------------------------------------------------------------------------

  Widget _chestsTab() => FutureBuilder<Map<String, dynamic>>(
        future: _chests,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final s = snap.data ?? const {};
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _sectionTitle('Baús do servidor'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statCard(Icons.inventory_2_rounded, 'Baús ativos', _num(s['chests']), color: const Color(0xFFB794FF)),
                  _statCard(Icons.lock_open_rounded, 'Aberturas', _num(s['opens_total']), color: const Color(0xFF34D399)),
                  _statCard(Icons.trending_up_rounded, 'Aberturas (7d)', _num(s['opens_7d']), color: const Color(0xFF38BDF8)),
                  _statCard(Icons.people_rounded, 'Usuários c/ baú', _num(s['users_with_chests']), color: const Color(0xFFF59E0B)),
                ],
              ),
              const SizedBox(height: 18),
              _grantChestForm(),
              const SizedBox(height: 18),
              const Text('Catálogo',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _chestCatalog,
                builder: (context, snapC) {
                  final list = snapC.data ?? const [];
                  if (list.isEmpty) return _empty('Sem baús cadastrados.');
                  return Column(
                    children: [
                      for (final c in list)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Text(c['emoji']?.toString() ?? '📦',
                              style: const TextStyle(fontSize: 18)),
                          title: Text(
                            c['name']?.toString() ?? c['id']?.toString() ?? '—',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${c['frequency'] ?? ''} · ${c['status'] ?? ''}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
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

  Widget _grantChestForm() {
    final userIdCtrl = TextEditingController();
    String chestId = '';
    String source = 'admin';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB794FF).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conceder baú',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: userIdCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'ID do usuário (uuid)',
              hintText: 'cole o uuid aqui',
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _chestCatalog,
            builder: (context, snapC) {
              final list = snapC.data ?? const [];
              return DropdownButtonFormField<String>(
                initialValue: list.isNotEmpty ? (list.first['id']?.toString() ?? '') : null,
                dropdownColor: const Color(0xFF15131E),
                decoration: const InputDecoration(labelText: 'Baú'),
                items: [
                  for (final c in list)
                    DropdownMenuItem(
                      value: c['id']?.toString(),
                      child: Text('${c['emoji'] ?? '📦'} ${c['name'] ?? c['id']}'),
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
            decoration: const InputDecoration(labelText: 'Origem'),
            items: const [
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
              DropdownMenuItem(value: 'event', child: Text('Evento')),
              DropdownMenuItem(value: 'mission', child: Text('Missão')),
              DropdownMenuItem(value: 'free', child: Text('Grátis')),
              DropdownMenuItem(value: 'daily', child: Text('Diário')),
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
                  _errSnack('Informe o uuid e o baú.');
                  return;
                }
                try {
                  final res = await _admin.adminGrantChest(uid, chestId: chestId, source: source);
                  final ok = res['ok'] == true || res['status'] != null;
                  _okSnack(ok ? 'Baú concedido!' : 'Sem resposta do servidor.');
                } catch (e) {
                  _errSnack(_admin.friendlyError(e));
                }
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              icon: const Icon(Icons.card_giftcard, size: 16),
              label: const Text('Conceder'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎯 Missões (cap: missions — leitura do progresso do operador)
  // ---------------------------------------------------------------------------

  Widget _missionsTab() => FutureBuilder<Map<String, dynamic>>(
        future: _admin.myProgress(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final p = snap.data ?? const {};
          final level = (p['level'] as num?)?.toInt() ?? 1;
          final title = p['level_title']?.toString() ?? 'Novato';
          final list = (p['missions'] as List?) ?? const [];
          final total = (p['xp_total'] as num?)?.toInt() ?? 0;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _statCard(Icons.auto_awesome_rounded, 'Nível', '$level · $title', color: const Color(0xFF8B5CF6)),
              _statCard(Icons.stars_rounded, 'XP total', _num(total), color: const Color(0xFFF59E0B)),
              const SizedBox(height: 6),
              const Text(
                'Recompensas são creditadas automaticamente pelo backend ao concluir.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
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

  Widget _missionChip(Map<String, dynamic> m) {
    final target = (m['target'] as num?)?.toInt() ?? 1;
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final done = m['completed'] == true;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Text(m['icon']?.toString() ?? '✅', style: const TextStyle(fontSize: 18)),
      title: Text(
        m['title']?.toString() ?? '—',
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${m['xp_reward'] ?? 0} XP · ${done ? 'concluída' : '$progress/$target'}',
        style: TextStyle(color: done ? const Color(0xFF34D399) : Colors.white38, fontSize: 11),
      ),
      trailing: done
          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 20)
          : const SizedBox(width: 20),
    );
  }

  // ---------------------------------------------------------------------------
  // 🧾 Auditoria (cap: audit)
  // ---------------------------------------------------------------------------

  Widget _auditTab() => FutureBuilder<List<Map<String, dynamic>>>(
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
                _sectionTitle('Trilha de auditoria (últimas ações)'),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  _emptyScroll('Nenhum evento auditado ainda.')
                else
                  ...items.map((e) => _auditRow(e)),
              ],
            ),
          );
        },
      );

  Widget _auditRow(Map<String, dynamic> e) {
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
              const Icon(Icons.receipt_long_rounded, color: Color(0xFFB794FF), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e['action']?.toString() ?? '—',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _relativeTime(e['created_at']?.toString()),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          if (e['actor_email']?.toString().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'por ${e['actor_email'] ?? e['actor_name'] ?? '—'} · ${e['entity_type'] ?? ''} ${e['entity_id'] ?? ''}',
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

  Widget _professionsTab() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _professions,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final items = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _professions = _admin
                    .adminListProfessions()
                    .catchError((_) => const <Map<String, dynamic>>[]);
              });
              await _professions;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              children: [
                _sectionTitle('🎭 Profissões'),
                const SizedBox(height: 4),
                const Text(
                  'Disponíveis para os perfis. Validação de acesso no backend.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _openProfessionDialog,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nova profissão'),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  _emptyScroll('Nenhuma profissão criada ainda.')
                else
                  ...items.map((p) => _professionRow(p)),
              ],
            ),
          );
        },
      );

  Widget _professionRow(Map<String, dynamic> p) {
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
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${p['category'] ?? 'geral'} · ${active ? 'ativa' : 'inativa'}',
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
            tooltip: active ? 'Desativar' : 'Ativar',
          ),
          IconButton(
            onPressed: () => _openProfessionDialog(p),
            icon: const Icon(Icons.edit_rounded,
                color: Color(0xFF8B5CF6), size: 18),
            tooltip: 'Editar',
          ),
          IconButton(
            onPressed: () => _deleteProfession(p),
            icon: const Icon(Icons.delete_rounded,
                color: Color(0xFFEF4444), size: 18),
            tooltip: 'Remover',
          ),
        ],
      ),
    );
  }

  Future<void> _toggleProfessionStatus(Map<String, dynamic> p) async {
    final id = p['id']?.toString();
    if (id == null) return;
    final next =
        (p['status'] ?? 'active').toString() == 'active' ? 'inactive' : 'active';
    try {
      await _admin.adminSetProfessionStatus(id, next);
      _okSnack(next == 'active' ? 'Profissão ativada.' : 'Profissão desativada.');
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _professions = _admin
            .adminListProfessions()
            .catchError((_) => const <Map<String, dynamic>>[]);
      });
    }
  }

  Future<void> _deleteProfession(Map<String, dynamic> p) async {
    final id = p['id']?.toString();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text('Remover "${p['name']}"?',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Isso remove a profissão da lista disponível.',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _admin.adminDeleteProfession(id);
      _okSnack('Profissão removida.');
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _professions = _admin
            .adminListProfessions()
            .catchError((_) => const <Map<String, dynamic>>[]);
      });
    }
  }

  Future<void> _openProfessionDialog([Map<String, dynamic>? p]) async {
    final nameCtrl = TextEditingController(
        text: p?['name']?.toString() ?? '');
    final iconCtrl = TextEditingController(
        text: p?['icon']?.toString() ?? '');
    final categoryCtrl = TextEditingController(
        text: p?['category']?.toString() ?? 'geral');
    final editing = p != null;
    final editId = p?['id']?.toString();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(editing ? 'Editar profissão' : 'Nova profissão',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: iconCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Ícone (emoji)'),
              ),
              TextField(
                controller: categoryCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Categoria'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
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
                _okSnack(editing ? 'Profissão atualizada.' : 'Profissão criada.');
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _professions = _admin
                      .adminListProfessions()
                      .catchError((_) => const <Map<String, dynamic>>[]);
                });
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🤖 Bots (admin)
  // ---------------------------------------------------------------------------

  Widget _botsTab() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _bots,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _loadingList();
          }
          final items = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _bots = _admin
                    .adminListBots()
                    .catchError((_) => const <Map<String, dynamic>>[]);
              });
              await _bots;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              children: [
                _sectionTitle('🤖 Controle de bots'),
                const SizedBox(height: 4),
                const Text(
                  'Bots nunca recebem permissões administrativas automaticamente.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _openBotDialog,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar bot'),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  _emptyScroll('Nenhum bot criado ainda.')
                else
                  ...items.map((b) => _botRow(b)),
              ],
            ),
          );
        },
      );

  /// Publicidade (Sistema Oficial de Anúncios) embutida no painel, usando o
  /// mesmo AdsAdminScreen da seção "Publicidade" das Configurações (showAppBar
  /// false para não duplicar AppBar). Toda ação roda em RPCs security definer.
  Widget _adsTab() => const AdsAdminScreen(showAppBar: false);

  Widget _botRow(Map<String, dynamic> b) {
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
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${b['bot_role'] ?? 'support'} · $status',
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
            tooltip: status == 'active' ? 'Pausar' : 'Ativar',
          ),
          IconButton(
            onPressed: () => _openBotDialog(b),
            icon: const Icon(Icons.edit_rounded,
                color: Color(0xFF8B5CF6), size: 18),
            tooltip: 'Editar',
          ),
          IconButton(
            onPressed: () => _deleteBot(b),
            icon: const Icon(Icons.delete_rounded,
                color: Color(0xFFEF4444), size: 18),
            tooltip: 'Remover',
          ),
        ],
      ),
    );
  }

  Future<void> _cycleBotStatus(Map<String, dynamic> b) async {
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
      _okSnack('Bot $next.');
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _bots = _admin
            .adminListBots()
            .catchError((_) => const <Map<String, dynamic>>[]);
      });
    }
  }

  Future<void> _deleteBot(Map<String, dynamic> b) async {
    final id = b['id']?.toString();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text('Remover "${b['name']}"?',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Isso remove o bot da plataforma.',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _admin.adminDeleteBot(id);
      _okSnack('Bot removido.');
    } catch (e) {
      _errSnack(_admin.friendlyError(e));
    }
    if (mounted) {
      setState(() {
        _bots = _admin
            .adminListBots()
            .catchError((_) => const <Map<String, dynamic>>[]);
      });
    }
  }

  Future<void> _openBotDialog([Map<String, dynamic>? b]) async {
    final nameCtrl =
        TextEditingController(text: b?['name']?.toString() ?? '');
    final avatarCtrl =
        TextEditingController(text: b?['avatar']?.toString() ?? '');
    final bioCtrl = TextEditingController(text: b?['bio']?.toString() ?? '');
    final editing = b != null;
    final editId = b?['id']?.toString();
    var role = (b?['bot_role']?.toString() ?? 'support');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(editing ? 'Editar bot' : 'Criar bot',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: avatarCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Avatar (emoji)'),
              ),
              TextField(
                controller: bioCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                dropdownColor: const Color(0xFF15131E),
                decoration: const InputDecoration(labelText: 'Tipo de bot'),
                items: const [
                  DropdownMenuItem(value: 'support', child: Text('Suporte')),
                  DropdownMenuItem(value: 'moderation', child: Text('Moderação')),
                  DropdownMenuItem(value: 'voice', child: Text('Voz')),
                  DropdownMenuItem(value: 'system', child: Text('Sistema')),
                ],
                onChanged: (v) => role = v ?? role,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
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
                _okSnack(editing ? 'Bot atualizado.' : 'Bot criado.');
              } catch (e) {
                _errSnack(_admin.friendlyError(e));
              }
              if (mounted) {
                setState(() {
                  _bots = _admin
                      .adminListBots()
                      .catchError((_) => const <Map<String, dynamic>>[]);
                });
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Salvar'),
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
    try {
      await action();
    } on AdminAccessDeniedException catch (_) {
      _errSnack('Acesso restrito ao Painel do Fundador.');
    } catch (_) {
      _errSnack('Ação não autorizada ou falha de rede.');
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
            child: Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
          ),
        ],
      );

  Widget _emptyScroll(String text) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [Padding(padding: const EdgeInsets.only(top: 60), child: _empty(text))],
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
          _statusLabel(valid),
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _statusLabel(String? status) {
    const labels = {
      'pending': 'pendente',
      'reviewing': 'análise',
      'resolved': 'resolvida',
      'dismissed': 'descartada',
      'pendente': 'pendente',
      'pago': 'pago',
      'enviado': 'enviado',
      'concluido': 'concluído',
      'cancelado': 'cancelado',
    };
    return labels[status] ?? '—';
  }

  String _num(Object? value) {
    final n = value is num ? value.toDouble() : 0.0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n == n.truncateToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(0);
  }

  String _money(Object? value) {
    final n = value is num ? value.toDouble() : 0.0;
    return 'R\$ ${n.toStringAsFixed(2)}';
  }

  String _relativeTime(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes} min';
    if (diff.inDays < 1) return '${diff.inHours} h';
    if (diff.inDays < 30) return '${diff.inDays} d';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }
}

class _RestrictedView extends StatelessWidget {
  const _RestrictedView();

  @override
  Widget build(BuildContext context) {
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
              child: const Icon(Icons.lock_rounded,
                  color: Color(0xFFFF6B81), size: 40),
            ),
            const SizedBox(height: 18),
            const Text(
              'Acesso restrito',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O Painel do Fundador é exclusivo para administradores do KLAY K. '
              'A permissão é validada no backend (capabilities + funções '
              'seguras), então este aviso também aparece se a tentativa vier '
              'de outra rota.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
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

  const _UserProfessionSheet({
    required this.user,
    required this.onRefresh,
  });

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
    _professions = _admin
        .adminListProfessions()
        .catchError((_) => const <Map<String, dynamic>>[]);
  }

  void _reloadProfessions() {
    setState(() {
      _professions = _admin
          .adminListProfessions()
          .catchError((_) => const <Map<String, dynamic>>[]);
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
    final uid = _userId;
    if (uid == null) return;
    try {
      if (profession == null || profession.isEmpty) {
        await _admin.adminClearUserProfession(uid);
        _ok('Profissão removida do perfil.');
      } else {
        await _admin.adminSetUserProfession(uid, profession);
        _ok('Profissão "$profession" atribuída.');
      }
      widget.onRefresh();
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _openChangeDialog() async {
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '🎭 Selecionar profissão',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in active)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
                          ? const Icon(Icons.check,
                              color: Color(0xFF34D399), size: 18)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(p['name']?.toString()),
                    ),
                  const Divider(color: Colors.white12, height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    leading: const Text('➕', style: TextStyle(fontSize: 18)),
                    title: const Text('Criar nova profissão…',
                        style: TextStyle(
                            color: Color(0xFFB794FF),
                            fontWeight: FontWeight.w700)),
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
    final nameCtrl = TextEditingController();
    final iconCtrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: const Text('Criar nova profissão',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: iconCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Ícone (emoji)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Criar'),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: const Text('Remover profissão do usuário?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Isso limpa a profissão de @${widget.user['username'] ?? ''}.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) await _assign(null);
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.user['display_name']?.toString() ?? 'Usuário';
    final username = widget.user['username']?.toString() ?? '';
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                            fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '@$username',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
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
            const Text(
              '🎭 PROFISSÃO',
              style: TextStyle(
                  color: Color(0xFFB794FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6),
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
                    icon: const Icon(Icons.delete_rounded,
                        color: Color(0xFFEF4444), size: 16),
                    label: const Text('Remover do usuário',
                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openChangeDialog,
                style:
                    FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('✏️ Alterar profissão'),
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
    if (profession == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Sem profissão definida',
          style: TextStyle(color: Colors.white54, fontSize: 12),
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
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}


/// Identificadores das abas — resolvidos em [_FounderPanelScreenState._tabView].
enum _TabId {
  overview,
  moderation,
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
}