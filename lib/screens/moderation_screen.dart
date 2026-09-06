import 'package:flutter/material.dart';

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
    await SocialService.instance
        .modAddSpamRule(pattern, ruleType: _ruleType, scope: _ruleScope);
    _rulePattern.clear();
    await _loadAll();
  }

  Future<void> _removeRule(String id) async {
    await SocialService.instance.modRemoveSpamRule(id);
    await _loadAll();
  }

  Future<void> _flagProfile(SuspectProfile p) async {
    final reason = await _promptText(
      'Sinalizar perfil',
      '@${p.username} (${p.displayName})',
      hint: 'Motivo da sinalização',
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await SecurityService.instance
          .adminFlagProfile(p.id, reason.trim());
      await _loadAll();
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Moderação',
            style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : !_isAdmin
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gpp_bad_rounded,
                            color: Colors.white38, size: 56),
                        SizedBox(height: 12),
                        Text(
                          'Acesso restrito a administradores.',
                          style: TextStyle(color: Colors.white54),
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
                            horizontal: 12, vertical: 6),
                        children: [
                          _tabChip('Denúncias', 0),
                          _tabChip('Anti-spam', 1),
                          _tabChip('Fake Profile', 2),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _tab == 0
                          ? _buildReports()
                          : _tab == 1
                              ? _buildRules()
                              : _buildFakeProfile(),
                    ),
                  ],
                ),
    );
  }

  Future<void> _resolveFlag(ProfileFlagEntry f, String decision) async {
    String note = '';
    if (decision == 'attention') {
      final n = await _promptText(
        'Marcar atenção',
        'Decisão aplicará restrição de conta (account_restricted).',
        hint: 'Observação (opcional)',
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
    String title,
    String body, {
    String hint = '',
  }) async {
    final controller = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 18)),
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
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK',
                style: TextStyle(
                    color: _kAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    controller.dispose();
    return res;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _tabChip(String label, int value) {
    final sel = _tab == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.white70, fontSize: 13)),
        selected: sel,
        selectedColor: _kAccent,
        backgroundColor: const Color(0xFF1B1A26),
        onSelected: (_) => setState(() => _tab = value),
      ),
    );
  }

  Widget _buildReports() {
    if (_reports.isEmpty) {
      return const Center(
        child: Text('Nenhuma denúncia pendente',
            style: TextStyle(color: Colors.white54)),
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
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: const TextStyle(
                              color: _kAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        createdAt.length >= 16
                            ? createdAt.substring(0, 16)
                            : createdAt,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(reason,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(details,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60)),
                  ],
                  if ((r['resolution']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Resolução: ${r['resolution']}',
                      style: const TextStyle(
                          color: Color(0xFF34D399), fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text('Alvo: ${_targetLabel(r)}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12)),
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
                        child: const Text('Resolver'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _resolve(id, 'dismissed'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          minimumSize: const Size(0, 34),
                        ),
                        child: const Text('Dispensar'),
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

  String _targetLabel(Map<String, dynamic> r) {
    final type = r['target_type']?.toString() ?? '';
    final id = r['target_id']?.toString() ?? '';
    final short = id.length > 8 ? '${id.substring(0, 8)}…' : id;
    if (type == 'user') return 'usuário $short';
    if (type == 'post') return 'post $short';
    if (type == 'live') return 'live $short';
    if (type == 'comment') return 'comentário $short';
    if (type == 'message') return 'mensagem $short';
    if (type == 'conversation') return 'conversa $short';
    return 'chat $short';
  }

  Widget _buildRules() {
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
                      hintText: 'Padrão a bloquear (ex.: golpe, promo)',
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
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: const [
                          DropdownMenuItem(
                              value: 'block', child: Text('bloquear')),
                          DropdownMenuItem(
                              value: 'flag', child: Text('sinalizar')),
                          DropdownMenuItem(
                              value: 'warn', child: Text('aviso')),
                        ],
                        onChanged: (v) => setState(() => _ruleType = v ?? 'block'),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _ruleScope,
                        dropdownColor: const Color(0xFF1B1A26),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('tudo')),
                          DropdownMenuItem(
                              value: 'chat', child: Text('live chat')),
                          DropdownMenuItem(
                              value: 'comment', child: Text('comentários')),
                          DropdownMenuItem(
                              value: 'message', child: Text('mensagens')),
                        ],
                        onChanged: (v) => setState(() => _ruleScope = v ?? 'all'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _addRule,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Adicionar'),
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
                        leading: const Icon(Icons.filter_alt_rounded,
                            color: _kAccent),
                        title: Text(rule['pattern']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '${rule['rule_type']} • ${rule['scope']}'
                          '${(rule['active'] == true) ? '' : ' • inativa'}',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white38),
                          onPressed: () => _removeRule(
                              rule['id']?.toString() ?? ''),
                        ),
                      ),
                    if (activePatterns.isEmpty && _rules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Text('Nenhuma regra',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38)),
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

  Widget _buildFakeProfile() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'PERFIS SUSPEITOS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (_suspects.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Nenhum perfil suspeito nos últimos 3 dias.',
                style: TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final p in _suspects) _suspectTile(p),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              'SINALIZAÇÕES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (_flags.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Nenhuma sinalização de perfil.',
                style: TextStyle(color: Colors.white38),
              ),
            )
          else
            for (final f in _flags) _flagTile(f),
        ],
      ),
    );
  }

  Widget _suspectTile(SuspectProfile p) {
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
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                if (p.isDefaultUsername)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('username padrão',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '@${p.username} · conta com ${p.accountAgeDays}d',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _chip(p.hasAvatar, 'avatar'),
                _chip(p.hasBio, 'bio'),
                if (p.openFlags > 0)
                  _chip(false, '${p.openFlags} flag(s) aberta(s)'),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _flagProfile(p),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Sinalizar'),
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
          color: (present ? const Color(0xFF34D399) : Colors.white24)
              .withValues(alpha: 0.15),
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

  Widget _flagTile(ProfileFlagEntry f) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    open ? 'ABERTA' : f.decision.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Text('fonte: ${f.source.isEmpty ? 'manual' : f.source}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              f.reason.isEmpty ? 'USUÁRIO ${f.flaggedUserId}' : f.reason,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('Usuário: ${f.flaggedUserId}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            if (f.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Nota: ${f.note}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                    child: const Text('OK'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _resolveFlag(f, 'attention'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      minimumSize: const Size(0, 34),
                    ),
                    child: const Text('Atenção'),
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