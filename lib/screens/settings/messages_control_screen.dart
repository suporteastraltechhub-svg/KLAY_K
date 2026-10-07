import 'package:flutter/material.dart';

import '../../models/post_models.dart';
import '../../services/account_service.dart';
import '../../services/privacy_security_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1B1A26);
const Color _kMuted = Color(0xFF9A94AD);
const Color _kDanger = Color(0xFFFF4D6A);

const List<({String id, String label, String hint})> _messageOptions = [
  (
    id: 'everyone',
    label: 'Todos',
    hint: 'Qualquer pessoa do KLAY K pode te enviar mensagem.',
  ),
  (
    id: 'followers',
    label: 'Pessoas que sigo',
    hint: 'Só quem você segue consegue te enviar mensagem.',
  ),
  (
    id: 'friends',
    label: 'Amigos',
    hint: 'Só quem também segue você consegue te enviar mensagem.',
  ),
  (id: 'none', label: 'Ninguém', hint: 'Ninguém consegue te enviar mensagem.'),
];

String _hintFor(String value) {
  for (final option in _messageOptions) {
    if (option.id == value) return option.hint;
  }
  return 'Valor atual do backend: $value';
}

class MessagesControlScreen extends StatefulWidget {
  const MessagesControlScreen({super.key});

  @override
  State<MessagesControlScreen> createState() => _MessagesControlScreenState();
}

class _MessagesControlScreenState extends State<MessagesControlScreen> {
  final AccountService _account = AccountService.instance;
  final PrivacySecurityService _privacy = PrivacySecurityService.instance;

  AccountSettings _settings = const AccountSettings();
  PrivacySettings? _privacyData;
  String _allowMessages = 'everyone';
  int _blockedCount = 0;
  bool _blockedLoaded = false;
  bool _loaded = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _privacyError;

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
      _privacyError = null;
    });
    AccountSettings settings;
    try {
      settings = await _account.fetchSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blockedLoaded = false;
        _loaded = false;
        _loading = false;
        _error = 'Não foi possível carregar suas preferências. $e';
      });
      return;
    }
    PrivacySettings? privacy;
    Object? privacyError;
    try {
      privacy = await _privacy.fetchPrivacySettings();
    } catch (e) {
      privacyError = e;
    }
    final blocked = await _account
        .fetchBlockedIds()
        .then((ids) => ids.length)
        .catchError((_) => -1);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _privacyData = privacy;
      _allowMessages = privacy?.allowMessages ?? settings.allowMessages;
      _privacyError = privacyError == null
          ? null
          : 'O servidor não devolveu o bloco novo de privacidade, então o valor '
                'abaixo vem da configuração antiga e "Amigos" fica '
                'indisponível. ${_privacy.lastCode ?? privacyError}';
      _blockedCount = blocked < 0 ? 0 : blocked;
      _blockedLoaded = blocked >= 0;
      _loaded = true;
      _loading = false;
    });
  }

  bool _canPick(String option) {
    if (!_loaded || _saving) return false;
    if (option == 'friends' && _privacyData == null) return false;
    return true;
  }

  Future<void> _setAllowMessages(String value) async {
    if (!_canPick(value) || value == _allowMessages) return;
    final previous = _allowMessages;
    setState(() {
      _allowMessages = value;
      _saving = true;
    });
    try {
      if (_privacyData != null) {
        final saved = await _privacy.savePrivacySettings(allowMessages: value);
        if (!mounted) return;
        setState(() {
          _privacyData = saved;
          _allowMessages = saved.allowMessages;
          _saving = false;
        });
      } else {
        final next = _settings.copyWith(allowMessages: value);
        await _account.saveSettings(next);
        if (!mounted) return;
        setState(() {
          _settings = next;
          _saving = false;
        });
      }
      if (!mounted) return;
      _snack('Salvo: ${_labelFor(_allowMessages)}');
    } catch (e) {
      if (!mounted) return;
      final reason = _privacyData != null ? (_privacy.lastCode ?? e) : e;
      setState(() {
        _allowMessages = previous;
        _saving = false;
      });
      _snack('Não foi possível salvar. A preferência foi revertida. $reason');
    }
  }

  String _labelFor(String value) {
    for (final option in _messageOptions) {
      if (option.id == value) return option.label;
    }
    return value;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openBlocked() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _BlockedListScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Mensagens',
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
                const _SectionHeader('QUEM PODE ENVIAR MENSAGENS'),
                _choicesCard(),
                const SizedBox(height: 20),
                const _SectionHeader('BLOQUEADOS'),
                _blockedTile(),
                const SizedBox(height: 20),
                const _SectionHeader('COMO ISSO FUNCIONA'),
                _backendNote(),
              ],
            ),
    );
  }

  Widget _choicesCard() {
    final current = _allowMessages;
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
          if (!_loaded) ...[
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block_rounded, color: _kMuted, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Não foi possível carregar suas preferências. Toque em '
                    'Configurações e abra esta tela novamente para tentar de '
                    'novo — nada é alterado enquanto isso.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _messageOptions
                  .map(
                    (option) => Semantics(
                      label: 'Permitir mensagens de ${option.label}',
                      selected: current == option.id,
                      button: true,
                      child: ChoiceChip(
                        label: Text(
                          option.label,
                          style: TextStyle(
                            color: current == option.id
                                ? Colors.white
                                : Colors.white60,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selected: current == option.id,
                        selectedColor: _kAccent,
                        backgroundColor: const Color(0xFF222032),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: _canPick(option.id)
                            ? (_) => _setAllowMessages(option.id)
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Semantics(
            label: _loaded ? _hintFor(current) : 'Preferência indisponível',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: _kMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loaded
                        ? _hintFor(current)
                        : 'Sem valor carregado do backend para exibir.',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_privacyError != null) ...[
            const SizedBox(height: 12),
            _errorCard(_privacyError!),
          ],
          if (_saving) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kAccent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _blockedTile() {
    final subtitle = _blockedLoaded
        ? '$_blockedCount ${_blockedCount == 1 ? 'pessoa bloqueada' : 'pessoas bloqueadas'}'
        : 'Não foi possível verificar a lista de bloqueados.';
    return Semantics(
      label: 'Pessoas bloqueadas. $subtitle',
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
          leading: const Icon(Icons.person_off_rounded, color: _kAccent),
          title: const Text(
            'Pessoas bloqueadas',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: _openBlocked,
        ),
      ),
    );
  }

  Widget _backendNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Semantics(
        label:
            'As quatro opções são validadas no banco de dados, que aceita '
            'everyone, followers, friends ou none. Amigos significa seguidores '
            'mútuos.',
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.storage_rounded, color: _kMuted, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Estas quatro opções são validadas no banco de dados, que aceita '
                'everyone, followers, friends ou none. "Amigos" significa '
                'seguidores mútuos: a outra pessoa precisa seguir você e você '
                'também precisa seguir ela. Qualquer outro valor é recusado pelo '
                'servidor.',
                style: TextStyle(
                  color: Colors.white54,
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

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kDanger.withValues(alpha: 0.4)),
      ),
      child: Semantics(
        label: message,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kDanger, size: 20),
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

class _BlockedListScreen extends StatefulWidget {
  const _BlockedListScreen();

  @override
  State<_BlockedListScreen> createState() => _BlockedListScreenState();
}

class _BlockedListScreenState extends State<_BlockedListScreen> {
  final AccountService _account = AccountService.instance;

  List<PostAuthor> _items = [];
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _account.fetchBlocked();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar a lista. $e';
      });
    }
  }

  Future<void> _unblock(String id) async {
    try {
      await _account.unblockUser(id);
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e.id == id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuário desbloqueado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível desbloquear. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Pessoas bloqueadas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          : _items.isEmpty
          ? const Center(
              child: Text(
                'Ninguém bloqueado.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final entry = _items[i];
                return Card(
                  color: _kCard,
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF2A2740),
                      backgroundImage: (entry.avatarUrl ?? '').isNotEmpty
                          ? NetworkImage(entry.avatarUrl!)
                          : null,
                      child: (entry.avatarUrl ?? '').isEmpty
                          ? const Icon(Icons.person, color: Colors.white54)
                          : null,
                    ),
                    title: Text(
                      entry.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '@${entry.username ?? ''}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: TextButton(
                      onPressed: () => _unblock(entry.id),
                      child: const Text(
                        'Desbloquear',
                        style: TextStyle(color: _kAccent),
                      ),
                    ),
                  ),
                );
              },
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
