import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/post_models.dart';
import '../../models/security_models.dart';
import '../../services/account_service.dart';
import '../../services/privacy_security_service.dart';
import '../../services/security_service.dart';
import '../help_center_screen.dart';
import '../history_screen.dart';
import 'report_center_screen.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _bg = Color(0xFF0A0812);
const Color _card = Color(0xFF1B1A26);
const Color _fieldBg = Color(0xFF222032);
const Color _ok = Color(0xFF34D399);
const Color _warn = Color(0xFFFFB020);
const Color _bad = Color(0xFFFF4D6A);

class PrivacyCenterScreen extends StatefulWidget {
  const PrivacyCenterScreen({super.key});

  @override
  State<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends State<PrivacyCenterScreen> {
  final PrivacySecurityService _privacy = PrivacySecurityService.instance;

  bool _loading = true;
  bool _deleted = false;

  String? _displayName;
  String? _username;
  String? _email;
  DateTime? _createdAt;
  bool? _emailConfirmed;
  bool? _privateAccount;
  int? _blockedCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    Map<String, dynamic>? profile;
    AccountInfo? account;
    AccountSettings? settings;
    int? blocked;
    final failures = <String>[];

    try {
      profile = await AccountService.instance.fetchMyProfile();
      if (profile == null) failures.add('perfil');
    } catch (_) {
      failures.add('perfil');
    }
    try {
      account = await SecurityService.instance.myAccount();
    } catch (_) {
      failures.add('conta');
    }
    try {
      settings = await AccountService.instance.fetchSettings();
    } catch (_) {
      failures.add('preferências');
    }
    try {
      blocked = (await AccountService.instance.fetchBlockedIds()).length;
    } catch (_) {
      failures.add('bloqueios');
    }

    if (!mounted) return;
    setState(() {
      _displayName = profile?['display_name']?.toString();
      _username = profile?['username']?.toString();
      _email = account == null || account.email.isEmpty ? null : account.email;
      _createdAt = account?.accountCreatedAt;
      _emailConfirmed = account?.emailConfirmed;
      _privateAccount = settings?.accountPrivate;
      _blockedCount = blocked;
      _error = failures.isEmpty
          ? null
          : 'Não foi possível verificar: ${failures.join(', ')}.';
      _loading = false;
    });
  }

  String _date(DateTime? d) {
    if (d == null) return 'Não foi possível verificar';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'CENTRAL DE PRIVACIDADE',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: _deleted
          ? const _DeletedBody()
          : _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Veja o que o KLAY K guarda sobre você e para onde você vai '
                  'quando precisa de ajuda.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFFB020),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _header('Sua conta'),
                _panel([
                  _row(
                    Icons.person_rounded,
                    'Nome de exibição',
                    _displayName == null || _displayName!.isEmpty
                        ? 'Não foi possível verificar'
                        : _displayName!,
                  ),
                  _row(
                    Icons.alternate_email_rounded,
                    'Nome de usuário',
                    _username == null || _username!.isEmpty
                        ? 'Não foi possível verificar'
                        : '@$_username',
                  ),
                  _row(
                    Icons.mail_rounded,
                    'E-mail',
                    _email ?? 'Não foi possível verificar',
                  ),
                  _row(
                    Icons.mark_email_read_rounded,
                    'E-mail confirmado',
                    _emailConfirmed == null
                        ? 'Não foi possível verificar'
                        : (_emailConfirmed! ? 'Sim' : 'Não'),
                  ),
                  _row(
                    Icons.cake_rounded,
                    'Conta criada em',
                    _date(_createdAt),
                  ),
                ]),
                const SizedBox(height: 24),
                _header('Privacidade'),
                _panel([
                  _row(
                    Icons.lock_rounded,
                    'Conta privada',
                    _privateAccount == null
                        ? 'Não foi possível verificar'
                        : (_privateAccount! ? 'Ativada' : 'Desativada'),
                  ),
                  _row(
                    Icons.person_off_rounded,
                    'Usuários bloqueados',
                    _blockedCount == null
                        ? 'Não foi possível verificar'
                        : '$_blockedCount',
                  ),
                ]),
                const SizedBox(height: 12),
                _navTile(
                  Icons.history_rounded,
                  'Histórico de visualização',
                  'O que você assistiu, com opção de limpar',
                  () => _open(const HistoryScreen()),
                ),
                const SizedBox(height: 24),
                _header('O que o app guarda'),
                const Text(
                  'Estas são as informações que o KLAY K guarda hoje. A lista é '
                  'fixa e real — não mostramos números inventados.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _panel([
                  _row(
                    Icons.badge_rounded,
                    'perfil',
                    'Nome, usuário, foto e bio',
                  ),
                  _row(
                    Icons.article_rounded,
                    'publicações',
                    'Seus posts, vídeos e comentários',
                  ),
                  _row(
                    Icons.settings_rounded,
                    'configurações',
                    'Preferências de conta, privacidade e reprodução',
                  ),
                  _row(
                    Icons.block_rounded,
                    'blocked_users',
                    'Quem você bloqueou',
                  ),
                  _row(
                    Icons.support_agent_rounded,
                    'support_tickets',
                    'Chamados que você abriu com o suporte',
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Além disso, o aparelho guarda apenas as suas preferências de '
                  'acessibilidade e de bem-estar digital.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _header('Ajuda e segurança'),
                _navTile(
                  Icons.report_gmailerrorred_rounded,
                  'Central de Denúncias',
                  'Ver e enviar denúncias',
                  () => _open(const ReportCenterScreen()),
                ),
                _navTile(
                  Icons.person_off_rounded,
                  'Usuários bloqueados',
                  'Revogar bloqueios existentes',
                  _openBlocked,
                ),
                _navTile(
                  Icons.help_outline_rounded,
                  'Central de Ajuda',
                  'Perguntas frequentes e contato',
                  () => _open(const HelpCenterScreen()),
                ),
                const SizedBox(height: 24),
                _header('Seus direitos'),
                _deletionTile(),
                const SizedBox(height: 12),
                const Text(
                  'A exclusão é real e feita pelo servidor: ela apaga o perfil e '
                  'tudo que está ligado a esta conta. Exigimos a senha atual e '
                  'o e-mail exato para confirmar a intenção. Se algo der errado, '
                  'a conta continua inteira e o app mostra o erro.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.5,
                  ),
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

  Widget _panel(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Colors.white12),
          children[i],
        ],
      ],
    ),
  );

  Widget _row(IconData icon, String label, String value) => Semantics(
    label: '$label: $value',
    container: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _navTile(
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
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    ),
  );

  Widget _deletionTile() => Semantics(
    label: 'Exclusão da conta. Remove o perfil e tudo o que está ligado a ele.',
    container: true,
    child: Card(
      color: _card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0x33FF4D6A)),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.delete_forever_rounded, color: _bad),
        title: const Text(
          'Exclusão da conta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text(
          'Remove o perfil, as publicações e as configurações. Definitivo.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white38,
        ),
        onTap: _deleted ? null : _showDeletionDialog,
      ),
    ),
  );

  Future<void> _showDeletionDialog() async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeletionDialog(email: _email, onDelete: _deleteAccount),
    );
    if (done != true) return;
    await _confirmDeletedState();
  }

  Future<void> _deleteAccount({
    required String password,
    required String email,
    required String reason,
  }) async {
    await _privacy.deleteAccount(
      currentPassword: password,
      confirmEmail: email,
      reason: reason,
    );
    if (mounted) setState(() => _deleted = true);
  }

  Future<void> _confirmDeletedState() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _ok, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conta excluída',
                style: TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
          ],
        ),
        content: const Text(
          'O servidor KLAY K confirmou a exclusão desta conta. Perfil, '
          'publicações, mensagens, presentes, curtidas e configurações '
          'ligados a ela foram removidos. Não há como desfazer.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Sair',
              style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    nav.popUntil((route) => route.isFirst);
    try {
      await AccountService.instance.signOut();
    } catch (_) {}
    messenger.showSnackBar(
      const SnackBar(content: Text('Sua conta foi excluída.')),
    );
  }

  Future<void> _openBlocked() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _BlockedSheet(),
    );
  }
}

String _deletionCode(FunctionException e) {
  final details = e.details;
  if (details is Map) return details['error']?.toString() ?? '';
  if (details is String) {
    try {
      final decoded = jsonDecode(details);
      if (decoded is Map) return decoded['error']?.toString() ?? '';
    } catch (_) {}
  }
  return '';
}

String _deletionFailure(Object error) {
  if (error is FunctionException) {
    final code = _deletionCode(error);
    if (error.status == 0) {
      return 'Sem conexão com o servidor. Nada foi excluído.';
    }
    return switch (code) {
      'current_password_required' =>
        'Informe a senha atual da conta. Nada foi excluído.',
      'confirm_required' =>
        'Digite o seu e-mail para confirmar. Nada foi excluído.',
      'confirm_mismatch' =>
        'O e-mail digitado não é o e-mail desta conta. Nada foi excluído.',
      'wrong_password' => 'Senha atual incorreta. Nada foi excluído.',
      'account_lookup_failed' =>
        'O servidor não conseguiu verificar sua conta. Nada foi excluído.',
      'unauthorized' =>
        'Sua sessão não vale mais. Saia da conta e tente de novo. Nada foi excluído.',
      'delete_failed' =>
        'O servidor não conseguiu excluir a conta agora. Nada foi excluído.',
      _ => 'O servidor recusou a exclusão. Nada foi excluído.',
    };
  }
  return 'Não foi possível excluir a conta agora. Nada foi excluído.';
}

class _DeletedBody extends StatelessWidget {
  const _DeletedBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Semantics(
          label:
              'Conta excluída. O servidor KLAY K confirmou a exclusão e você '
              'vai sair da conta agora.',
          container: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, color: _ok, size: 30),
                SizedBox(height: 12),
                Text(
                  'Conta excluída',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'O servidor confirmou a exclusão. Perfil, publicações, '
                  'mensagens, presentes, curtidas e configurações ligados a '
                  'esta conta foram removidos.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeletionDialog extends StatefulWidget {
  const _DeletionDialog({required this.email, required this.onDelete});

  final String? email;
  final Future<void> Function({
    required String password,
    required String email,
    required String reason,
  })
  onDelete;

  @override
  State<_DeletionDialog> createState() => _DeletionDialogState();
}

class _DeletionDialogState extends State<_DeletionDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmEmail = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmEmail.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    final email = _confirmEmail.text.trim();
    if (password.isEmpty) {
      setState(() => _error = 'Informe a senha atual da conta.');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'Digite o seu e-mail para confirmar.');
      return;
    }
    final known = widget.email;
    if (known != null &&
        known.isNotEmpty &&
        email.toLowerCase() != known.toLowerCase()) {
      setState(() => _error = 'O e-mail digitado não é o e-mail desta conta.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete(
        password: password,
        email: email,
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _deletionFailure(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.delete_forever_rounded, color: _bad, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Exclusão da conta',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta ação é definitiva. Perfil, publicações, mensagens, '
              'presentes, curtidas e configurações ligados a esta conta serão '
              'removidos pelo servidor. Para confirmar, informe a senha atual e '
              'digite o e-mail exato da conta.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            _field(
              controller: _password,
              hint: 'Senha atual',
              obscure: _obscure,
              toggle: () => setState(() => _obscure = !_obscure),
            ),
            const SizedBox(height: 10),
            _field(
              controller: _confirmEmail,
              hint: 'Digite seu e-mail para confirmar',
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            _field(controller: _reason, hint: 'Motivo (opcional)'),
            if (widget.email != null && widget.email!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Confirme com: ${widget.email}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                label: 'Erro: $_error',
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: _warn,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _bad),
                )
              : const Text(
                  'Excluir minha conta',
                  style: TextStyle(color: _bad, fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    VoidCallback? toggle,
    TextInputType? keyboard,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    enabled: !_busy,
    keyboardType: keyboard,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: _fieldBg,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide.none,
      ),
      suffixIcon: toggle == null
          ? null
          : IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.white38,
              ),
              onPressed: toggle,
            ),
    ),
  );
}

class _BlockedSheet extends StatefulWidget {
  const _BlockedSheet();

  @override
  State<_BlockedSheet> createState() => _BlockedSheetState();
}

class _BlockedSheetState extends State<_BlockedSheet> {
  final AccountService _svc = AccountService.instance;
  List<PostAuthor> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _svc.fetchBlocked();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar a lista: $e';
      });
    }
  }

  Future<void> _unblock(PostAuthor user) async {
    try {
      await _svc.unblockUser(user.id);
      if (!mounted) return;
      setState(() => _items = _items.where((u) => u.id != user.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível desbloquear: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Usuários bloqueados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Lista real lida do servidor.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFFFB020),
                fontSize: 13,
                height: 1.4,
              ),
            )
          else if (_items.isEmpty)
            const Text(
              'Nenhum usuário bloqueado no momento.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final u = _items[i];
                  final avatar = u.avatarUrl ?? '';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF2A2740),
                      backgroundImage: avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar.isEmpty
                          ? const Icon(Icons.person, color: Colors.white54)
                          : null,
                    ),
                    title: Text(
                      u.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '@${u.username ?? ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => _unblock(u),
                      child: const Text(
                        'Desbloquear',
                        style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
