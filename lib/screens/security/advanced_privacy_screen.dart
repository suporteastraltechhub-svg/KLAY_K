import 'package:flutter/material.dart';

import '../../models/post_models.dart';
import '../../services/account_service.dart';
import '../../services/privacy_security_service.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _bg = Color(0xFF0A0812);
const Color _card = Color(0xFF1B1A26);
const Color _danger = Color(0xFFFF4D6A);

const List<(String, String)> _messageScopes = [
  ('everyone', 'Todos'),
  ('followers', 'Somente seguidores'),
  ('none', 'Ninguém'),
];

class AdvancedPrivacyScreen extends StatefulWidget {
  const AdvancedPrivacyScreen({super.key});

  @override
  State<AdvancedPrivacyScreen> createState() => _AdvancedPrivacyScreenState();
}

class _AdvancedPrivacyScreenState extends State<AdvancedPrivacyScreen> {
  final PrivacySecurityService _privacy = PrivacySecurityService.instance;

  AccountSettings _settings = const AccountSettings();
  PrivacySettings? _privacyData;
  bool _loading = true;
  bool _saving = false;
  bool _privacyLoading = true;
  String? _busyField;
  String? _error;
  String? _privacyError;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrivacy();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await AccountService.instance.fetchSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar suas preferências: $e';
      });
    }
  }

  Future<void> _loadPrivacy() async {
    setState(() {
      _privacyLoading = true;
      _privacyError = null;
    });
    try {
      final data = await _privacy.fetchPrivacySettings();
      if (!mounted) return;
      setState(() {
        _privacyData = data;
        _privacyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _privacyData = null;
        _privacyLoading = false;
        _privacyError =
            'Não foi possível carregar o bloco de privacidade do servidor. '
            '${_privacy.lastCode ?? e}';
      });
    }
  }

  Future<void> _update(AccountSettings Function(AccountSettings) change) async {
    final previous = _settings;
    final next = change(previous);
    setState(() {
      _settings = next;
      _saving = true;
      _error = null;
    });
    try {
      await AccountService.instance.saveSettings(next);
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _saving = false;
        _error =
            'Não foi possível salvar. Sua configuração anterior foi '
            'restaurada: $e';
      });
    }
  }

  Future<void> _save(
    String field,
    String label,
    Future<PrivacySettings> Function() save,
  ) async {
    if (_busyField != null) return;
    setState(() {
      _busyField = field;
      _privacyError = null;
    });
    try {
      final saved = await save();
      if (!mounted) return;
      setState(() {
        _privacyData = saved;
        _busyField = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyField = null;
        _privacyError =
            'Não foi possível salvar "$label". Nada foi alterado. '
            '${_privacy.lastCode ?? e}';
      });
    }
  }

  String get _commentScope {
    if (!_settings.allowComments) return 'none';
    return _settings.accountPrivate ? 'followers' : 'all';
  }

  String? _labelOf(List<(String, String)> options, String value) {
    for (final o in options) {
      if (o.$1 == value) return o.$2;
    }
    return null;
  }

  List<Widget> _privacySections() {
    if (_privacyLoading) {
      return [
        const SizedBox(height: 24),
        _header('Controles do servidor'),
        _statusCard(
          icon: Icons.cloud_sync_rounded,
          title: 'Carregando',
          message: 'Buscando o bloco de privacidade no servidor.',
          loading: true,
        ),
      ];
    }
    final data = _privacyData;
    if (data == null) {
      return [
        const SizedBox(height: 24),
        _header('Controles do servidor'),
        _statusCard(
          icon: Icons.cloud_off_rounded,
          title: 'Indisponível',
          message:
              _privacyError ??
              'O servidor não devolveu o bloco de privacidade. Nenhum valor '
                  'é mostrado aqui para não fingir que existe.',
          onRetry: _loadPrivacy,
        ),
      ];
    }
    final scopes = [for (final s in InteractionScope.all) (s.id, s.label)];
    return [
      const SizedBox(height: 24),
      _header('Quem pode interagir com você'),
      _scopeRow(
        icon: Icons.alternate_email_rounded,
        title: 'Quem pode mencionar',
        hint: 'Quem pode escrever @seu_usuário ou citar seu nome.',
        field: 'allowMentions',
        value: data.allowMentions,
        scopes: scopes,
        onChanged: (v) => _save(
          'allowMentions',
          'Quem pode mencionar',
          () => _privacy.savePrivacySettings(allowMentions: v),
        ),
      ),
      _scopeRow(
        icon: Icons.tag_rounded,
        title: 'Quem pode marcar',
        hint: 'Quem pode marcar sua conta em fotos, vídeos e posts.',
        field: 'allowTags',
        value: data.allowTags,
        scopes: scopes,
        onChanged: (v) => _save(
          'allowTags',
          'Quem pode marcar',
          () => _privacy.savePrivacySettings(allowTags: v),
        ),
      ),
      _scopeRow(
        icon: Icons.share_rounded,
        title: 'Quem pode compartilhar',
        hint: 'Quem pode compartilhar os seus posts e vídeos.',
        field: 'allowShares',
        value: data.allowShares,
        scopes: scopes,
        onChanged: (v) => _save(
          'allowShares',
          'Quem pode compartilhar',
          () => _privacy.savePrivacySettings(allowShares: v),
        ),
      ),
      _scopeRow(
        icon: Icons.group_add_rounded,
        title: 'Quem pode seguir',
        hint: 'Quem pode seguir a sua conta.',
        field: 'allowFollows',
        value: data.allowFollows,
        scopes: scopes,
        onChanged: (v) => _save(
          'allowFollows',
          'Quem pode seguir',
          () => _privacy.savePrivacySettings(allowFollows: v),
        ),
      ),
      const SizedBox(height: 24),
      _header('Downloads e status'),
      _switchRow(
        icon: Icons.download_rounded,
        title: 'Downloads dos vídeos',
        subtitle: 'Desligado, o app deixa de oferecer o download dos vídeos.',
        field: 'allowVideoDownloads',
        value: data.allowVideoDownloads,
        onChanged: (v) => _save(
          'allowVideoDownloads',
          'Downloads dos vídeos',
          () => _privacy.savePrivacySettings(allowVideoDownloads: v),
        ),
      ),
      _switchRow(
        icon: Icons.circle_rounded,
        title: 'Status online',
        subtitle: 'Desligado, sua conta deixa de exibir quando está online.',
        field: 'showOnlineStatus',
        value: data.showOnlineStatus,
        onChanged: (v) => _save(
          'showOnlineStatus',
          'Status online',
          () => _privacy.savePrivacySettings(showOnlineStatus: v),
        ),
      ),
      _switchRow(
        icon: Icons.visibility_rounded,
        title: 'Histórico de visualização',
        subtitle:
            'Desligado, o app não registra nem mostra o que você assistiu.',
        field: 'viewHistoryEnabled',
        value: data.viewHistoryEnabled,
        onChanged: (v) => _save(
          'viewHistoryEnabled',
          'Histórico de visualização',
          () => _privacy.savePrivacySettings(viewHistoryEnabled: v),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Estes valores são gravados e validados pelo servidor. O que cada '
        'tela do app faz com eles depende de cada tela consultar o serviço de '
        'privacidade.',
        style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 24),
      _header('Filtro de conteúdo'),
      _BlockedWordsEditor(words: data.blockedWords),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'PRIVACIDADE AVANÇADA',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Defina quem pode ver e interagir com você. As alterações '
                  'são salvas no seu perfil.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Aviso: $_error',
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: _danger,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                if (_privacyError != null && _privacyData != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Aviso: $_privacyError',
                    child: Text(
                      _privacyError!,
                      style: const TextStyle(
                        color: _danger,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _header('Conta'),
                Semantics(
                  label:
                      'Conta privada. Só quem você aprova consegue ver suas '
                      'publicações e lista de seguidores.',
                  child: Card(
                    color: _card,
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      value: _settings.accountPrivate,
                      activeThumbColor: _accent,
                      title: const Text(
                        'Conta privada',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _settings.accountPrivate
                            ? 'Sua conta está privada'
                            : 'Sua conta está pública',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      onChanged: _saving
                          ? null
                          : (v) =>
                                _update((s) => s.copyWith(accountPrivate: v)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _header('Quem pode comentar'),
                _chips(
                  const [
                    ('all', 'Todos'),
                    ('followers', 'Somente seguidores'),
                    ('none', 'Ninguém'),
                  ],
                  _commentScope,
                  (v) => _update(
                    (s) => s.copyWith(
                      allowComments: v != 'none',
                      accountPrivate: v == 'followers',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O banco de dados aceita apenas permitir ou bloquear '
                  'comentários. Por isso "Todos" torna a conta pública e '
                  '"Somente seguidores" torna a conta privada.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _header('Quem pode enviar mensagens'),
                _chips(
                  _messageScopes,
                  _settings.allowMessages,
                  (v) => _update((s) => s.copyWith(allowMessages: v)),
                ),
                if (_labelOf(_messageScopes, _settings.allowMessages) ==
                    null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'O servidor gravou "${_settings.allowMessages}" como valor '
                    'atual. Essa opção é ajustada em Configurações, no controle '
                    'de mensagens.',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                ..._privacySections(),
                const SizedBox(height: 24),
                _header('Bloqueios'),
                _navTile(
                  Icons.person_off_rounded,
                  'Usuários bloqueados',
                  'Quem não consegue mais interagir com você',
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _BlockedUsersScreen(),
                    ),
                  ),
                ),
                if (_saving) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
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

  Widget _chips(
    List<(String, String)> options,
    String selected,
    ValueChanged<String> onChanged, {
    bool? busy,
  }) {
    final disabled = busy ?? _saving;
    final label = _labelOf(options, selected);
    return Semantics(
      label:
          'Opções: ${options.map((o) => o.$2).join(', ')}. '
          'Selecionado: ${label ?? 'o servidor respondeu "$selected"'}',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(
                o.$2,
                style: TextStyle(
                  color: o.$1 == selected ? Colors.white : Colors.white60,
                  fontSize: 13,
                ),
              ),
              selected: o.$1 == selected,
              selectedColor: _accent,
              backgroundColor: const Color(0xFF222032),
              onSelected: disabled
                  ? null
                  : (v) {
                      if (v) onChanged(o.$1);
                    },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _scopeRow({
    required IconData icon,
    required String title,
    required String hint,
    required String field,
    required String value,
    required List<(String, String)> scopes,
    required ValueChanged<String> onChanged,
  }) {
    final busy = _busyField == field;
    final known = _labelOf(scopes, value) != null;
    return Semantics(
      label:
          '$title. ${_labelOf(scopes, value) ?? 'O servidor respondeu "$value"'}',
      container: true,
      child: Card(
        color: _card,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              _chips(scopes, value, onChanged, busy: busy),
              if (!known) ...[
                const SizedBox(height: 8),
                Text(
                  'Valor atual do backend: $value',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String field,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final busy = _busyField == field;
    return Semantics(
      label: '$title. ${value ? 'Ligado' : 'Desligado'}',
      toggled: value,
      container: true,
      child: Card(
        color: _card,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          value: value,
          activeThumbColor: _accent,
          secondary: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  ),
                )
              : Icon(icon, color: _accent),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          onChanged: _busyField != null ? null : onChanged,
        ),
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String message,
    bool loading = false,
    VoidCallback? onRetry,
  }) => Semantics(
    label: '$title. $message',
    container: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: loading
              ? _accent.withValues(alpha: 0.4)
              : _danger.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: loading ? _accent : _danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: loading ? Colors.white : _danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Tentar de novo',
                        style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
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
}

class _BlockedWordsEditor extends StatefulWidget {
  const _BlockedWordsEditor({required this.words});

  final List<String> words;

  @override
  State<_BlockedWordsEditor> createState() => _BlockedWordsEditorState();
}

class _BlockedWordsEditorState extends State<_BlockedWordsEditor> {
  final PrivacySecurityService _svc = PrivacySecurityService.instance;
  final TextEditingController _controller = TextEditingController();

  List<String> _words = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _words = List<String>.of(widget.words);
  }

  @override
  void didUpdateWidget(covariant _BlockedWordsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_busy) return;
    _words = List<String>.of(widget.words);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final word = _controller.text.trim().toLowerCase();
    if (word.isEmpty) {
      setState(() => _error = 'Escreva uma palavra antes de adicionar.');
      return;
    }
    if (word.length > 40) {
      setState(() => _error = 'Use no máximo 40 caracteres por palavra.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final words = await _svc.addBlockedWords([word]);
      if (words.isEmpty) {
        throw StateError(
          'O servidor não devolveu a lista atualizada de palavras.',
        );
      }
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _words = words;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível adicionar "$word". ${_svc.lastCode ?? e}';
      });
    }
  }

  Future<void> _remove(String word) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final words = await _svc.removeBlockedWords([word]);
      if (words.contains(word)) {
        throw StateError('O servidor não confirmou a remoção.');
      }
      if (!mounted) return;
      setState(() {
        _words = words;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível remover "$word". ${_svc.lastCode ?? e}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Palavras bloqueadas. ${_words.length} cadastradas.',
      container: true,
      child: Card(
        color: _card,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.filter_alt_rounded,
                    color: _accent,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Palavras bloqueadas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'O servidor esconde e sinaliza, para você, textos com estas '
                'palavras. A lista é gravada no seu perfil e nada é filtrado '
                'fora do servidor.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Palavra a bloquear',
                      textField: true,
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        cursorColor: _accent,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _add(),
                        decoration: InputDecoration(
                          hintText: 'Palavra a bloquear',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF141220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2A2740),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2A2740),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: IconButton.filled(
                      onPressed: _busy ? null : _add,
                      icon: const Icon(Icons.add_rounded, size: 22),
                      tooltip: 'Adicionar palavra bloqueada',
                      style: IconButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF2A2740),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  label: 'Erro: $_error',
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: _danger,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_words.isEmpty)
                const Text(
                  'Nenhuma palavra bloqueada. Escreva uma acima para o servidor '
                  'filtrar os textos com esse termo.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.4,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final w in _words)
                      Semantics(
                        label: 'Palavra bloqueada $w. Remover esta palavra.',
                        button: true,
                        child: InputChip(
                          label: Text(
                            w,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          backgroundColor: const Color(0xFF222032),
                          deleteIcon: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                          deleteButtonTooltipMessage: 'Remover "$w"',
                          onDeleted: _busy ? null : () => _remove(w),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedUsersScreen extends StatefulWidget {
  const _BlockedUsersScreen();

  @override
  State<_BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<_BlockedUsersScreen> {
  final AccountService _svc = AccountService.instance;
  List<PostAuthor> _items = const [];
  bool _loading = true;
  String _busyId = '';
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
    setState(() => _busyId = user.id);
    try {
      await _svc.unblockUser(user.id);
      if (!mounted) return;
      setState(() => _items = _items.where((u) => u.id != user.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível desbloquear: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'USUÁRIOS BLOQUEADOS',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
            )
          : _error != null
          ? _empty(_error!, Icons.error_outline_rounded)
          : _items.isEmpty
          ? _empty(
              'Nenhum usuário bloqueado no momento.',
              Icons.person_off_rounded,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final u = _items[i];
                final avatar = u.avatarUrl ?? '';
                final busy = _busyId == u.id;
                return Semantics(
                  label:
                      '${u.name}. Toque em desbloquear para remover o bloqueio.',
                  child: Card(
                    color: _card,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                        onPressed: busy ? null : () => _unblock(u),
                        child: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _accent,
                                ),
                              )
                            : const Text(
                                'Desbloquear',
                                style: TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _empty(String message, IconData icon) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white38, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
