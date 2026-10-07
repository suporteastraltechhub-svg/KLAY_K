import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/privacy_security_service.dart';
import '../../services/settings_diagnostics_service.dart';
import 'account_guard_screen.dart';
import 'report_center_screen.dart';
import 'youth_shield_screen.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _bg = Color(0xFF0A0812);
const Color _card = Color(0xFF1B1A26);
const Color _ok = Color(0xFF34D399);
const Color _warn = Color(0xFFFFB020);
const Color _bad = Color(0xFFFF4D6A);

enum _Level { ok, warn, bad, none }

class _Row {
  final String label;
  final String detail;
  final _Level level;

  const _Row(this.label, this.detail, this.level);
}

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  final PrivacySecurityService _privacy = PrivacySecurityService.instance;

  bool _loading = false;
  SecuritySummary? _summary;
  String? _error;

  bool _mfaLoading = true;
  bool _mfaProtected = false;
  bool _mfaWorking = false;
  String? _mfaError;
  List<({String id, String friendlyName, String status})> _factors = const [];

  bool _alertsLoading = true;
  String? _alertsError;
  List<LoginAlert> _alerts = const [];
  int _alertsLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadMfa();
    _loadAlerts();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _authMessage(Object error, String fallback) {
    if (error is AuthException) {
      return switch (error.code ?? '') {
        'otp_expired' =>
          'O código expirou. Gere um novo código no app '
              'autenticador.',
        'otp_disabled' => 'O 2FA está desativado no servidor.',
        'invalid_factor' ||
        'mfa_factor_not_found' => 'O servidor não encontrou este autenticador.',
        'mfa_factor_name_conflict' =>
          'Já existe um autenticador com esse nome.',
        'otp_validation_failed' ||
        'invalid_code' ||
        'mfa_verification_failed' =>
          'Código inválido. Confira os 6 dígitos do aplicativo autenticador.',
        'insufficient_aal' || 'aal2_required' || 'unverified' =>
          'Esta sessão ainda não passou pelo 2FA. Confirme o código antes.',
        'session_not_found' => 'Sua sessão não é válida. Entre de novo.',
        _ => '$fallback (${error.message})',
      };
    }
    return '$fallback ($error)';
  }

  Future<void> _loadMfa() async {
    setState(() {
      _mfaLoading = true;
      _mfaError = null;
    });
    try {
      final protectedNow = await _privacy.mfaIsProtected();
      final factors = await _privacy.listMfaFactors();
      if (!mounted) return;
      setState(() {
        _mfaProtected = protectedNow;
        _factors = factors;
        _mfaLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mfaLoading = false;
        _mfaError = _authMessage(e, 'Não foi possível verificar o 2FA.');
      });
    }
  }

  Future<void> _enroll() async {
    setState(() {
      _mfaWorking = true;
      _mfaError = null;
    });
    late final ({String factorId, String qrCode, String secret}) enroll;
    try {
      enroll = await _privacy.enrollMfa(friendlyName: 'Autenticador KLAY K');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mfaWorking = false;
        _mfaError = _authMessage(e, 'Não foi possível iniciar o 2FA.');
      });
      return;
    }
    if (!mounted) return;
    setState(() => _mfaWorking = false);
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _MfaCodeDialog(qrCode: enroll.qrCode, secret: enroll.secret),
    );
    if (!mounted) return;
    if (code == null) {
      _snack(
        'Você não confirmou o código. O autenticador fica sem verificação até '
        'você terminar a ativação.',
      );
      await _loadMfa();
      return;
    }
    await _verifyEnroll(enroll.factorId, code);
  }

  Future<void> _verifyEnroll(String factorId, String code) async {
    setState(() {
      _mfaWorking = true;
      _mfaError = null;
    });
    try {
      await _privacy.challengeMfa(factorId);
      await _privacy.verifyMfa(factorId, code);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mfaWorking = false;
        _mfaError = _authMessage(e, 'Não foi possível confirmar o 2FA.');
      });
      _snack('O 2FA não foi ativado. Confira o código e tente de novo.');
      return;
    }
    if (!mounted) return;
    setState(() => _mfaWorking = false);
    _snack('2FA ativado e confirmado pelo servidor.');
    await _loadMfa();
  }

  Future<void> _unenroll(String factorId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Desativar 2FA',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          'O autenticador "$name" será removido da conta. Depois disso, o '
          'login passa a depender apenas da senha.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Desativar',
              style: TextStyle(color: _bad, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _mfaWorking = true;
      _mfaError = null;
    });
    try {
      await _privacy.unenrollMfa(factorId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mfaWorking = false;
        _mfaError = _authMessage(
          e,
          'Não foi possível desativar este autenticador.',
        );
      });
      return;
    }
    if (!mounted) return;
    setState(() => _mfaWorking = false);
    _snack('Autenticador removido pelo servidor.');
    await _loadMfa();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _alertsLoading = true;
      _alertsError = null;
    });
    try {
      final alerts = await _privacy.fetchLoginAlerts(limit: _alertsLimit);
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _alertsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _alerts = const [];
        _alertsLoading = false;
        _alertsError =
            'Não foi possível verificar. '
            '${_privacy.lastCode ?? e}';
      });
    }
  }

  String _eventLabel(String type) => switch (type) {
    'login' => 'Entrada na conta',
    'logout' => 'Saída da conta',
    'password_change' => 'Senha alterada',
    'mfa_enrolled' => '2FA ativado',
    'mfa_unenrolled' => '2FA desativado',
    'token_revoked' => 'Sessão encerrada',
    'suspicious' => 'Atividade marcada como suspeita',
    _ => type,
  };

  IconData _eventIcon(String type) => switch (type) {
    'login' => Icons.login_rounded,
    'logout' => Icons.logout_rounded,
    'password_change' => Icons.password_rounded,
    'mfa_enrolled' => Icons.verified_user_rounded,
    'mfa_unenrolled' => Icons.shield_outlined,
    'token_revoked' => Icons.block_rounded,
    'suspicious' => Icons.warning_amber_rounded,
    _ => Icons.history_rounded,
  };

  String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  String _alertDetail(LoginAlert a) {
    final parts = <String>[];
    if (a.deviceLabel.isNotEmpty) parts.add(a.deviceLabel);
    if (a.userAgent.isNotEmpty) parts.add(a.userAgent);
    if (a.ip.isNotEmpty) parts.add('IP ${a.ip}');
    if (a.aal.isNotEmpty) parts.add(a.aal.toUpperCase());
    return parts.isEmpty
        ? 'Sem detalhes registrados pelo servidor.'
        : parts.join(' · ');
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await SettingsDiagnosticsService.instance
          .loadSecuritySummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível rodar a verificação: $e';
      });
    }
  }

  List<_Row> _rows() {
    final s = _summary;
    if (s == null || !s.loaded) {
      return const [
        _Row(
          'Segurança da conta',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
        _Row(
          'Privacidade',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
        _Row(
          'Mensagens',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
        _Row(
          'Comentários',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
        _Row(
          'Spam',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
        _Row(
          'Proteção para menores',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
        _Row(
          'Sessões',
          'Sem verificação — toque em VERIFICAR SEGURANÇA',
          _Level.none,
        ),
      ];
    }

    final general = s.state;
    final level = switch (general) {
      ProbeState.ok => _Level.ok,
      ProbeState.warning ||
      ProbeState.checking ||
      ProbeState.pending => _Level.warn,
      ProbeState.failed => _Level.bad,
      ProbeState.unavailable => _Level.none,
    };

    return [
      _Row(
        'Segurança da conta',
        s.emailConfirmed
            ? 'E-mail confirmado e sessão autenticada'
            : (s.authenticated
                  ? 'Sessão autenticada, mas o e-mail não foi confirmado'
                  : 'Nenhuma sessão autenticada'),
        s.emailConfirmed
            ? _Level.ok
            : (s.authenticated ? _Level.warn : _Level.bad),
      ),
      _Row(
        'Privacidade',
        s.privacyPrivate
            ? 'Conta privada ativa'
            : 'Conta pública: seu perfil fica visível para qualquer pessoa',
        s.privacyPrivate ? _Level.ok : _Level.warn,
      ),
      _Row(
        'Mensagens',
        s.messagesRestricted
            ? 'Mensagens não estão abertas para todos'
            : 'Qualquer pessoa pode te enviar mensagem',
        s.messagesRestricted ? _Level.ok : _Level.warn,
      ),
      _Row(
        'Comentários',
        s.commentsAllowed
            ? 'Comentários abertos na sua conta'
            : 'Comentários desativados',
        s.commentsAllowed ? _Level.warn : _Level.ok,
      ),
      _Row(
        'Spam',
        'Bloqueio de spam é aplicado no banco ao enviar comentários e '
            'mensagens · ${s.reportCount} denúncia(s) registrada(s)',
        level,
      ),
      _Row(
        'Proteção para menores',
        s.youthProtected
            ? 'Idade provada: proteção total ativa'
            : 'Defina sua data de nascimento para proteção total',
        s.youthProtected ? _Level.ok : _Level.warn,
      ),
      _Row(
        'Sessões',
        s.sessionCount == 0
            ? 'Nenhuma sessão retornada pelo servidor'
            : '${s.sessionCount} sessão(ões) ativa(s)'
                  '${s.confirmActions ? '' : ' · confirmação de ações desligada'}',
        s.sessionCount == 0
            ? _Level.warn
            : (s.sessionCount <= 3 ? _Level.ok : _Level.warn),
      ),
    ];
  }

  String _levelLabel(_Level l) => switch (l) {
    _Level.ok => 'Protegido',
    _Level.warn => 'Atenção',
    _Level.bad => 'Problema',
    _Level.none => 'Não verificado',
  };

  Color _levelColor(_Level l) => switch (l) {
    _Level.ok => _ok,
    _Level.warn => _warn,
    _Level.bad => _bad,
    _Level.none => Colors.white38,
  };

  String _activitySubtitle(SecuritySummary? s) => (s == null || !s.loaded)
      ? 'Verifique a segurança para ver os números reais'
      : '${s.sessionCount} sessão(ões) · ${s.reportCount} denúncia(s)';

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'KLAY K SAFETY CENTER',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Controle sua segurança e privacidade em um só lugar.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: 'Verificar segurança agora',
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'VERIFICANDO…',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      )
                    : const Text(
                        'VERIFICAR SEGURANÇA',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: _bad, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 24),
          _header('Situação geral'),
          _scoreCard(s),
          const SizedBox(height: 24),
          _header('Verificações'),
          _statusCard(_rows()),
          if (s != null && s.issues.isNotEmpty) ...[
            const SizedBox(height: 24),
            _header('Pontos de atenção'),
            _issuesCard(s.issues),
          ],
          const SizedBox(height: 24),
          _header('Ferramentas'),
          _tile(
            Icons.person_pin_rounded,
            'Proteção da conta',
            'Sessões reais e troca de senha',
            () => _open(const AccountGuardScreen()),
          ),
          _tile(
            Icons.shield_rounded,
            'Proteção para menores',
            'Idade provada, Modo Jovem e conteúdo adulto',
            () => _open(const YouthShieldScreen()),
          ),
          _tile(
            Icons.report_gmailerrorred_rounded,
            'Minhas denúncias',
            'Denúncias que você enviou e o histórico delas',
            () => _open(const ReportCenterScreen()),
          ),
          _tile(
            Icons.insights_rounded,
            'Ver atividade de segurança',
            _activitySubtitle(s),
            _showActivity,
          ),
          const SizedBox(height: 24),
          _header('Verificação em duas etapas (2FA)'),
          _mfaCard(),
          const SizedBox(height: 24),
          _header('Alertas de login'),
          _alertsCard(),
          const SizedBox(height: 24),
          const Text(
            'Nenhum item aparece como "Protegido" sem uma resposta real do '
            'servidor. Se a consulta falhar, mostramos o erro em vez de um '
            'estado inventado.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _scoreCard(SecuritySummary? s) {
    final missing = s == null || !s.loaded;
    final score = missing ? 0 : s.score;
    final level = switch (missing ? ProbeState.unavailable : s.state) {
      ProbeState.ok => _Level.ok,
      ProbeState.warning => _Level.warn,
      ProbeState.failed => _Level.bad,
      _ => _Level.none,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: missing
                      ? 'Pontuação de segurança ainda não verificada'
                      : 'Pontuação de segurança $score de 100',
                  child: Text(
                    missing ? '—/100' : '$score/100',
                    style: TextStyle(
                      color: _levelColor(level),
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _levelColor(level).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  missing ? 'Não verificado' : _levelLabel(level),
                  style: TextStyle(
                    color: _levelColor(level),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: missing ? 0 : score / 100,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(_levelColor(level)),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'A pontuação é calculada a partir do que o servidor respondeu '
            'agora. Ela não é um selo permanente.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(List<_Row> rows) => Container(
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Colors.white12),
          _statusTile(rows[i]),
        ],
      ],
    ),
  );

  Widget _statusTile(_Row row) => Semantics(
    label: '${row.label}. ${_levelLabel(row.level)}. ${row.detail}',
    container: true,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _levelColor(row.level).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          row.level == _Level.ok
              ? Icons.verified_user_rounded
              : Icons.shield_outlined,
          size: 19,
          color: _levelColor(row.level),
        ),
      ),
      title: Text(
        row.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        row.detail,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      trailing: Text(
        _levelLabel(row.level),
        style: TextStyle(
          color: _levelColor(row.level),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );

  Widget _issuesCard(List<String> issues) {
    if (issues.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Nenhum problema encontrado nesta verificação.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < issues.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Colors.white12),
            Builder(
              builder: (context) {
                final hard = issues[i].startsWith('!');
                final text = hard ? issues[i].substring(1) : issues[i];
                return Semantics(
                  label: hard ? 'Falha: $text' : 'Atenção: $text',
                  container: true,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      hard
                          ? Icons.error_outline_rounded
                          : Icons.info_outline_rounded,
                      color: hard ? _bad : _warn,
                      size: 20,
                    ),
                    title: Text(
                      text,
                      style: TextStyle(
                        color: hard ? _bad : Colors.white70,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    subtitle: hard
                        ? const Text(
                            'Não foi possível verificar este item',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          )
                        : null,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Card(
    color: _card,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: _accent),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    ),
  );

  Widget _mfaCard() {
    if (_mfaLoading) {
      return _panelBox(
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          ),
        ),
      );
    }
    if (_mfaError != null && _factors.isEmpty) {
      return _panelBox(
        _errorBlock(
          Icons.cloud_off_rounded,
          _mfaError!,
          'Não foi possível verificar.',
          _loadMfa,
        ),
      );
    }
    final verified = _factors.where((f) => f.status == 'verified').length;
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _mfaProtected
                    ? Icons.verified_user_rounded
                    : Icons.phonelink_lock_rounded,
                color: _mfaProtected ? _ok : _warn,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _mfaProtected
                      ? 'Sessão atual protegida (2FA ativo)'
                      : (_factors.isEmpty
                            ? 'Nenhum autenticador cadastrado'
                            : 'Autenticador cadastrado, sessão ainda em 1º nível'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_mfaWorking)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _mfaProtected
                ? 'Esta sessão já passou pelo 2FA. O servidor valida o código '
                      'do aplicativo autenticador a cada login.'
                : (_factors.isEmpty
                      ? 'Com o 2FA ativo, a senha sozinha não entra na conta: '
                            'o servidor também exige o código de 6 dígitos do '
                            'aplicativo autenticador.'
                      : (verified > 0
                            ? 'O autenticador está verificado, mas esta sessão '
                                  'ainda não passou pelo 2FA. Saia da conta e '
                                  'entre de novo para o servidor pedir o código.'
                            : 'Existe um autenticador sem verificação. Gere um '
                                  'novo código para concluir a ativação.')),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          for (final f in _factors) ...[
            const Divider(height: 20, color: Colors.white12),
            Row(
              children: [
                Icon(
                  f.status == 'verified'
                      ? Icons.check_circle_rounded
                      : Icons.pending_rounded,
                  color: f.status == 'verified' ? _ok : _warn,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.friendlyName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        f.status == 'verified'
                            ? 'Verificado pelo servidor'
                            : 'Pendente: o código ainda não foi confirmado',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _mfaWorking
                      ? null
                      : () => _unenroll(f.id, f.friendlyName),
                  child: Text(
                    f.status == 'verified' ? 'Desativar' : 'Remover',
                    style: TextStyle(
                      color: f.status == 'verified' ? _bad : Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_mfaError != null) ...[
            const SizedBox(height: 10),
            Text(
              _mfaError!,
              style: const TextStyle(
                color: Color(0xFFFFB020),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (verified == 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _mfaWorking ? null : _enroll,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  _factors.isEmpty ? 'ATIVAR 2FA' : 'GERAR NOVO CÓDIGO',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _mfaWorking ? null : _loadMfa,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Atualizar estado',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _alertsCard() {
    if (_alertsLoading) {
      return _panelBox(
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          ),
        ),
      );
    }
    if (_alertsError != null) {
      return _panelBox(
        _errorBlock(
          Icons.cloud_off_rounded,
          _alertsError!,
          'Não foi possível verificar.',
          _loadAlerts,
        ),
      );
    }
    if (_alerts.isEmpty) {
      return _panelBox(
        const Text(
          'Nenhum evento registrado no servidor até agora. O histórico começa '
          'a aparecer a partir do próximo acesso à conta.',
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
        ),
      );
    }
    return _panelBox(
      Column(
        children: [
          for (var i = 0; i < _alerts.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Colors.white12),
            _alertTile(_alerts[i]),
          ],
          if (_alerts.length >= _alertsLimit && _alertsLimit < 30) ...[
            const Divider(height: 1, color: Colors.white12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() => _alertsLimit += 10);
                  _loadAlerts();
                },
                child: const Text(
                  'Ver alertas mais antigos',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertTile(LoginAlert alert) {
    final label = _eventLabel(alert.eventType);
    final detail = _alertDetail(alert);
    return Semantics(
      label: '$label. $detail. ${_stamp(alert.createdAt)}',
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _eventIcon(alert.eventType),
                size: 18,
                color: _accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _stamp(alert.createdAt),
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBlock(
    IconData icon,
    String message,
    String short,
    VoidCallback onRetry,
  ) => Semantics(
    label: '$short $message',
    container: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white38, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            child: const Text(
              'Tentar de novo',
              style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _panelBox(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Future<void> _showActivity() async {
    final s = _summary;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Atividade de segurança',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Somente o que o servidor devolveu na última verificação.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (s == null || !s.loaded)
              const Text(
                'Execute "VERIFICAR SEGURANÇA" para consultar sessões e '
                'denúncias. Nenhum número é estimado.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              )
            else ...[
              _activityRow(
                Icons.devices_rounded,
                'Sessões ativas',
                '${s.sessionCount}',
              ),
              _activityRow(
                Icons.report_gmailerrorred_rounded,
                'Denúncias enviadas',
                '${s.reportCount}',
              ),
              _activityRow(
                Icons.person_off_rounded,
                'Usuários bloqueados',
                '${s.blockedCount}',
              ),
              _activityRow(
                Icons.mark_email_unread_rounded,
                'E-mail confirmado',
                s.emailConfirmed ? 'Sim' : 'Não',
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: _accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

String _mfaQrSvg(String qrCode) {
  var raw = qrCode.trim();
  if (raw.toLowerCase().startsWith('data:')) {
    final comma = raw.indexOf(',');
    if (comma < 0) return '';
    raw = raw.substring(comma + 1);
  }
  try {
    raw = Uri.decodeFull(raw);
  } catch (_) {}
  return raw.contains('<svg') ? raw : '';
}

class _MfaCodeDialog extends StatefulWidget {
  const _MfaCodeDialog({required this.qrCode, required this.secret});

  final String qrCode;
  final String secret;

  @override
  State<_MfaCodeDialog> createState() => _MfaCodeDialogState();
}

class _MfaCodeDialogState extends State<_MfaCodeDialog> {
  final TextEditingController _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Digite o código de 6 dígitos para confirmar.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final svg = _mfaQrSvg(widget.qrCode);
    return AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Ativar verificação em duas etapas',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (svg.isNotEmpty) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SvgPicture.string(
                    svg,
                    width: 190,
                    height: 190,
                    placeholderBuilder: (_) => const SizedBox(
                      width: 190,
                      height: 190,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Leia o QR Code com o aplicativo autenticador (Google '
                'Authenticator, Authy ou equivalente).',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
            ] else
              const Text(
                'O servidor não devolveu um QR Code desenhável. Use a chave '
                'abaixo para cadastrar o autenticador manualmente.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            const Text(
              'Chave de configuração',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF11101A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                widget.secret,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                letterSpacing: 4,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(color: Colors.white38),
                counterText: '',
                filled: true,
                fillColor: Color(0xFF222032),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFFB020),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Depois de confirmar, o servidor exige este código a cada login. '
              'Sem a confirmação, nada é ativado.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Agora não',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            'Confirmar código',
            style: TextStyle(color: _accent, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
