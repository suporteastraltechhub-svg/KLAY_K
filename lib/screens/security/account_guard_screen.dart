import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/security_models.dart';
import '../../services/security_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Account Guard — sessões reais de auth + troca de senha com re-validação da
/// senha atual. O backend (auth real + edge account-guard) é quem autoriza;
/// este app apenas apresenta o resultado de forma honesta.
class AccountGuardScreen extends StatefulWidget {
  const AccountGuardScreen({super.key});

  @override
  State<AccountGuardScreen> createState() => _AccountGuardScreenState();
}

class _AccountGuardScreenState extends State<AccountGuardScreen> {
  final SecurityService _svc = SecurityService.instance;

  bool _loading = true;
  bool _working = false;
  AccountInfo? _account;
  List<AccountSession> _sessions = [];

  final TextEditingController _current = TextEditingController();
  final TextEditingController _newPwd = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure3 = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _current.dispose();
    _newPwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final account = await _svc.myAccount();
      final sessions = await _svc.authListSessions();
      if (!mounted) return;
      setState(() {
        _account = account;
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _revokeSession(AccountSession s) async {
    _setWorking(true);
    final l10n = AppLocalizations.of(context)!;
    try {
      await _svc.authRevokeSession(s.id);
      await _load();
      _snack(l10n.accountGuardSessionRevoked);
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _revokeOthers() async {
    final l10n = AppLocalizations.of(context)!;
    if (_sessions.length <= 1) {
      _snack(l10n.accountGuardOnlyThisSession);
      return;
    }
    final ok = await _confirmDialog(
      l10n.accountGuardRevokeOthersTitle,
      l10n.accountGuardRevokeOthersBody,
    );
    if (!ok) return;
    _setWorking(true);
    try {
      await _svc.authRevokeOtherSessions();
      await _load();
      _snack(l10n.accountGuardOthersRevoked);
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _changePassword() async {
    final l10n = AppLocalizations.of(context)!;
    final current = _current.text.trim();
    final next = _newPwd.text;
    final confirm = _confirm.text;
    if (current.isEmpty) {
      return _snack(l10n.accountGuardPwdRequired);
    }
    if (next.length < 8) {
      return _snack(l10n.accountGuardPwdMinLength);
    }
    if (next != confirm) return _snack(l10n.accountGuardPwdMismatch);
    if (next == current) {
      return _snack(l10n.accountGuardPwdSameAsCurrent);
    }
    _setWorking(true);
    try {
      await _svc.changePassword(currentPassword: current, newPassword: next);
      _current.clear();
      _newPwd.clear();
      _confirm.clear();
      await _load();
      _snack(l10n.accountGuardPwdChanged);
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<bool> _confirmDialog(String title, String body) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.confirm,
              style: const TextStyle(
                color: _kAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _setWorking(bool v) {
    if (mounted) setState(() => _working = v);
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.day}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.accountGuardTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoCard(l10n),
                const SizedBox(height: 24),
                _sectionHeader(l10n.accountGuardSessionsHeader),
                _sessionsCard(l10n),
                const SizedBox(height: 24),
                _sectionHeader(l10n.accountGuardPasswordHeader),
                _passwordCard(l10n),
                const SizedBox(height: 12),
                Text(
                  l10n.accountGuardPwdNote,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _infoCard(AppLocalizations l10n) {
    final a = _account;
    if (a == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, color: _kAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.email.isEmpty ? l10n.accountGuardAccountLabel : a.email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: a.emailConfirmed
                      ? const Color(0xFF34D399).withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  a.emailConfirmed
                      ? l10n.accountGuardVerified
                      : l10n.accountGuardNotVerified,
                  style: TextStyle(
                    color: a.emailConfirmed
                        ? const Color(0xFF34D399)
                        : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv(l10n.accountGuardLastAccess, _fmt(a.lastSignInAt)),
          _kv(l10n.accountGuardAccountCreated, _fmt(a.accountCreatedAt)),
          _kv(
            l10n.accountGuardProviders,
            a.providers.isEmpty ? '—' : a.providers.join(', '),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _sessionsCard(AppLocalizations l10n) {
    if (_working) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
          ),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1A26),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          l10n.accountGuardNoSessions,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16151F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (final s in _sessions)
            _sessionTile(s, l10n, isLast: identical(s, _sessions.last)),
          const Divider(height: 1, color: Colors.white12),
          ListTile(
            tileColor: Colors.transparent,
            leading: const Icon(
              Icons.devices_other_rounded,
              color: Color(0xFF4CAF50),
            ),
            title: Text(
              l10n.accountGuardRevokeOthers,
              style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 14),
            ),
            subtitle: Text(
              l10n.accountGuardKeepsThisDevice,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: _revokeOthers,
          ),
        ],
      ),
    );
  }

  Widget _sessionTile(
    AccountSession s,
    AppLocalizations l10n, {
    required bool isLast,
  }) {
    return ListTile(
      title: Row(
        children: [
          Icon(
            s.isMobile ? Icons.smartphone_rounded : Icons.desktop_windows,
            color: _kAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.deviceLabel,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.ip.isEmpty
                ? s.aal.toUpperCase()
                : 'IP ${s.ip} · ${s.aal.toUpperCase()}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          Text(
            l10n.accountGuardActivityTime(_fmt(s.refreshedAt)),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.logout_rounded, color: Colors.white38),
        onPressed: _working ? null : () => _revokeSession(s),
        tooltip: l10n.accountGuardRevokeSessionTooltip,
      ),
    );
  }

  Widget _passwordCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _pwdField(
            hint: l10n.accountGuardCurrentPwd,
            controller: _current,
            obscure: _obscure1,
            toggle: () => setState(() => _obscure1 = !_obscure1),
          ),
          const SizedBox(height: 10),
          _pwdField(
            hint: l10n.accountGuardNewPwd,
            controller: _newPwd,
            obscure: _obscure2,
            toggle: () => setState(() => _obscure2 = !_obscure2),
          ),
          const SizedBox(height: 10),
          _pwdField(
            hint: l10n.accountGuardConfirmPwd,
            controller: _confirm,
            obscure: _obscure3,
            toggle: () => setState(() => _obscure3 = !_obscure3),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _working ? null : _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white12,
              ),
              child: Text(
                l10n.accountGuardChangePwd,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pwdField({
    required String hint,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback toggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1B1A26),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
          ),
          onPressed: toggle,
        ),
      ),
    );
  }
}
