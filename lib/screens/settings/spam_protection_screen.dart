import 'package:flutter/material.dart';

import '../../models/security_models.dart';
import '../../services/account_service.dart';
import '../../services/security_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1B1A26);
const Color _kOk = Color(0xFF34D399);
const Color _kWarn = Color(0xFFFBBF24);
const Color _kFail = Color(0xFFFF4D6A);
const Color _kMuted = Color(0xFF9A94AD);

class _ActionView {
  final String label;
  final Color color;
  final IconData icon;

  const _ActionView(this.label, this.color, this.icon);
}

const List<({String id, String label})> _scopes = [
  (id: 'comment', label: 'Comentário'),
  (id: 'chat', label: 'Chat'),
];

_ActionView _actionView(String action) {
  switch (action.toLowerCase()) {
    case 'ok':
    case 'allow':
    case 'allowed':
    case 'pass':
      return const _ActionView(
        'Liberado pelo filtro',
        _kOk,
        Icons.check_circle_rounded,
      );
    case 'flag':
    case 'flagged':
    case 'review':
    case 'warn':
      return const _ActionView(
        'Sinalizado para revisão',
        _kWarn,
        Icons.flag_rounded,
      );
    case 'block':
    case 'blocked':
    case 'reject':
    case 'deny':
      return const _ActionView(
        'Bloqueado pelo filtro',
        _kFail,
        Icons.block_rounded,
      );
    default:
      return _ActionView(
        'Resposta do backend: $action',
        _kMuted,
        Icons.help_outline_rounded,
      );
  }
}

class SpamProtectionScreen extends StatefulWidget {
  const SpamProtectionScreen({super.key});

  @override
  State<SpamProtectionScreen> createState() => _SpamProtectionScreenState();
}

class _SpamProtectionScreenState extends State<SpamProtectionScreen> {
  final SecurityService _security = SecurityService.instance;
  final AccountService _account = AccountService.instance;
  final TextEditingController _controller = TextEditingController();

  AccountSettings _settings = const AccountSettings();
  String _scope = 'comment';
  SpamScanResult? _result;
  bool _scanning = false;
  bool _saving = false;
  String? _scanError;
  String? _settingsError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _account.fetchSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _settingsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _settingsError =
            'Não foi possível verificar sua '
            'preferência. $e',
      );
    }
  }

  Future<void> _scan() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _result = null;
        _scanError = 'Escreva um texto para verificar.';
      });
      return;
    }
    setState(() {
      _scanning = true;
      _scanError = null;
      _result = null;
    });
    try {
      final result = await _security.scanSpam(text, scope: _scope);
      if (!mounted) return;
      setState(() {
        _result = result;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanError = 'Não foi possível verificar o texto. $e';
      });
    }
  }

  Future<void> _setConfirmActions(bool value) async {
    if (_saving || _settingsError != null) return;
    final previous = _settings;
    setState(() {
      _settings = previous.copyWith(securityConfirmActions: value);
      _saving = true;
    });
    try {
      await _account.saveSettings(_settings);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Proteção contra Spam',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const _SectionHeader('TESTAR UM TEXTO'),
          _scannerCard(),
          if (_scanning) ...[
            const SizedBox(height: 12),
            Semantics(
              label: 'Verificando texto no backend',
              child: const LinearProgressIndicator(
                color: _kAccent,
                backgroundColor: Color(0xFF2A2740),
                minHeight: 4,
              ),
            ),
          ],
          if (_scanError != null) ...[
            const SizedBox(height: 12),
            _messageCard(_scanError!, _kFail, Icons.error_outline_rounded),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            _resultCard(_result!),
          ],
          const SizedBox(height: 20),
          const _SectionHeader('CONFIRMAÇÃO DE AÇÕES'),
          _confirmTile(),
          const SizedBox(height: 20),
          const _SectionHeader('O QUE O APP FAZ E O QUE NÃO FAZ'),
          _rulesNote(),
        ],
      ),
    );
  }

  Widget _scannerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cole um comentário ou mensagem e veja o que o filtro real responde.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Texto para verificar contra o filtro de spam',
            textField: true,
            child: TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: _kAccent,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Escreva ou cole o texto aqui',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF141220),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2740)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2740)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kAccent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ONDE VERIFICAR',
            style: TextStyle(
              color: _kAccent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _scopes
                .map(
                  (s) => Semantics(
                    label: 'Verificar como ${s.label}',
                    selected: _scope == s.id,
                    button: true,
                    child: ChoiceChip(
                      label: Text(
                        s.label,
                        style: TextStyle(
                          color: _scope == s.id ? Colors.white : Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                      selected: _scope == s.id,
                      selectedColor: _kAccent,
                      backgroundColor: const Color(0xFF222032),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onSelected: (_) => setState(() => _scope = s.id),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'Verificar texto contra o filtro de spam',
            button: true,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.shield_rounded, size: 20),
              label: const Text(
                'VERIFICAR',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(SpamScanResult result) {
    final view = _actionView(result.action);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: view.color.withValues(alpha: 0.4)),
      ),
      child: Semantics(
        label: 'Resultado: ${view.label}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(view.icon, color: view.color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    view.label,
                    style: TextStyle(
                      color: view.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _resultRow('Escopo verificado', _scopeLabel(result.scope)),
            _resultRow('Ação do backend', result.action),
            _resultRow('Bloqueado', result.blocked ? 'Sim' : 'Não'),
            _resultRow(
              'Sinalizado para revisão',
              result.flagged ? 'Sim' : 'Não',
            ),
            _resultRow(
              'Correspondências encontradas',
              '${result.matches.length}',
            ),
            if (result.matches.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'O QUE O FILTRO ENCONTROU',
                style: TextStyle(
                  color: _kAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              ...result.matches.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $m',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Este é o resultado real da verificação. O app não decide o que é '
              'spam sozinho: quem aplica a regra é o backend.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scopeLabel(String scope) {
    for (final s in _scopes) {
      if (s.id == scope) return s.label;
    }
    return scope;
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmTile() {
    if (_settingsError != null) {
      return Semantics(
        label: 'Confirmar ações importantes: indisponível',
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
            title: const Text(
              'Confirmar ações importantes',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              _settingsError!,
              style: const TextStyle(color: _kMuted, fontSize: 12),
            ),
            trailing: const Icon(Icons.block_rounded, color: _kMuted),
          ),
        ),
      );
    }
    return Semantics(
      label: 'Confirmar ações importantes',
      toggled: _settings.securityConfirmActions,
      child: Card(
        color: _kCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          value: _settings.securityConfirmActions,
          activeThumbColor: _kAccent,
          onChanged: _saving ? null : _setConfirmActions,
          title: const Text(
            'Confirmar ações importantes',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Pede confirmação antes de enviar presentes, denunciar ou '
            'sair da conta.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _rulesNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Semantics(
        label:
            'O bloqueio de mensagens repetidas e de excesso de pedidos é '
            'aplicado pelas regras anti-spam do backend. O app nunca bloqueia '
            'um usuário sem os critérios do backend.',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _kMuted, size: 18),
                SizedBox(width: 8),
                Text(
                  'REGRAS ANTI-SPAM',
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
              'O bloqueio de mensagens repetidas e de excesso de pedidos é '
              'aplicado pelas regras anti-spam do backend, no envio. O app '
              'nunca bloqueia um usuário sozinho nem inventa critérios: o que '
              'acima é apenas a prévia do mesmo filtro usado no envio real.',
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

  Widget _messageCard(String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Semantics(
        label: message,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
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
