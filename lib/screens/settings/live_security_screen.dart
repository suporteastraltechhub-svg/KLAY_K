import 'package:flutter/material.dart';

import '../../services/account_service.dart';
import '../help_center_screen.dart';
import '../security/report_center_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1B1A26);
const Color _kMuted = Color(0xFF9A94AD);

class LiveSecurityScreen extends StatefulWidget {
  const LiveSecurityScreen({super.key});

  @override
  State<LiveSecurityScreen> createState() => _LiveSecurityScreenState();
}

class _LiveSecurityScreenState extends State<LiveSecurityScreen> {
  final AccountService _account = AccountService.instance;

  AccountSettings _settings = const AccountSettings();
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _account.fetchSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loaded = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = false;
        _loading = false;
        _error = 'Não foi possível carregar suas preferências. $e';
      });
    }
  }

  Future<void> _setSettings(
    AccountSettings Function(AccountSettings) update,
  ) async {
    if (_saving || !_loaded) return;
    final previous = _settings;
    final next = update(previous);
    setState(() {
      _settings = next;
      _saving = true;
    });
    try {
      await _account.saveSettings(next);
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _saving = false;
      });
      _snack('Não foi possível salvar. A preferência foi revertida. $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openReportCenter() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReportCenterScreen()));
  }

  void _openHelpCenter() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Segurança da Live',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (_error != null) ...[
                  _errorCard(_error!),
                  const SizedBox(height: 16),
                ],
                const _SectionHeader('DURANTE A LIVE'),
                _liveNote(),
                const SizedBox(height: 20),
                const _SectionHeader('MINHAS PREFERÊNCIAS'),
                _switchTile(
                  'Permitir comentários',
                  'Se desligado, o backend não aceita novos comentários seus.',
                  _settings.allowComments,
                  (v) => _setSettings((s) => s.copyWith(allowComments: v)),
                ),
                _switchTile(
                  'Confirmar antes de enviar presentes',
                  'Pede confirmação antes de cada presente enviado em live.',
                  _settings.securityConfirmActions,
                  (v) => _setSettings(
                    (s) => s.copyWith(securityConfirmActions: v),
                  ),
                ),
                _switchTile(
                  'Conta privada',
                  'Sua conta fica privada: só quem você aprova vê seu perfil.',
                  _settings.accountPrivate,
                  (v) => _setSettings((s) => s.copyWith(accountPrivate: v)),
                ),
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kAccent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionHeader('AJUDA E DENÚNCIAS'),
                _tile(
                  Icons.report_gmailerrorred_rounded,
                  'Central de denúncias',
                  'Acompanhe e registre denúncias reais do app.',
                  _openReportCenter,
                ),
                _tile(
                  Icons.help_outline_rounded,
                  'Central de ajuda',
                  'Dúvidas sobre live, presentes e segurança.',
                  _openHelpCenter,
                ),
                const SizedBox(height: 20),
                _scopeNote(),
              ],
            ),
    );
  }

  Widget _liveNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
      ),
      child: Semantics(
        label:
            'Durante a live você pode bloquear, silenciar ou denunciar '
            'diretamente na sala de live.',
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_rounded, color: _kAccent, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Durante uma LIVE você pode bloquear, silenciar e denunciar '
                'diretamente na própria sala de live, usando os botões de '
                'segurança que aparecem no topo da transmissão.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Semantics(
        label:
            'A moderação da sala é do criador da live e validada no backend. '
            'Verificação em duas etapas e login anônimo aguardam o backend.',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _kMuted, size: 18),
                SizedBox(width: 8),
                Text(
                  'O QUE NÃO ESTÁ NESTA TELA',
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'A moderação da sala (excluir mensagens, banir do chat) é do '
              'criador da live e sempre revalidada no backend. A verificação em '
              'duas etapas no login e o login anônimo continuam aguardando o '
              'backend: por isso não há interruptores para eles aqui.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    if (!_loaded) {
      return Semantics(
        label: '$title: indisponível, não foi possível verificar',
        child: Card(
          color: _kCard,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: const Text(
              'Não foi possível verificar sua preferência agora.',
              style: TextStyle(color: _kMuted, fontSize: 12),
            ),
            trailing: const Icon(Icons.block_rounded, color: _kMuted),
          ),
        ),
      );
    }
    return Semantics(
      label: title,
      toggled: value,
      child: Card(
        color: _kCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          value: value,
          onChanged: _saving ? null : onChanged,
          activeThumbColor: _kAccent,
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Semantics(
      label: title,
      button: true,
      child: Card(
        color: _kCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: Icon(icon, color: _kAccent),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF4D6A).withValues(alpha: 0.4),
        ),
      ),
      child: Semantics(
        label: message,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF4D6A),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _kAccent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
