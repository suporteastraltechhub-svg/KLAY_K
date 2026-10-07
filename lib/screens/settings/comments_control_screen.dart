import 'package:flutter/material.dart';

import '../../models/security_models.dart';
import '../../services/account_service.dart';
import '../../services/privacy_security_service.dart';
import '../../services/security_service.dart';
import 'spam_protection_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1B1A26);
const Color _kOk = Color(0xFF34D399);
const Color _kMuted = Color(0xFF9A94AD);
const Color _kDanger = Color(0xFFFF4D6A);

class _CheckResultView {
  final String label;
  final Color color;
  final IconData icon;

  const _CheckResultView(this.label, this.color, this.icon);
}

_CheckResultView _checkView(SpamScanResult result) {
  if (result.action.toLowerCase() == 'ok' ||
      result.action.toLowerCase() == 'allow') {
    return const _CheckResultView(
      'Nada bloqueado neste texto',
      _kOk,
      Icons.check_circle_rounded,
    );
  }
  if (result.blocked) {
    return const _CheckResultView(
      'Texto bloqueado pelo filtro do backend',
      Color(0xFFFF4D6A),
      Icons.block_rounded,
    );
  }
  if (result.flagged) {
    return const _CheckResultView(
      'Texto sinalizado para revisão',
      Color(0xFFFBBF24),
      Icons.flag_rounded,
    );
  }
  return _CheckResultView(
    'Resposta do backend: ${result.action}',
    _kMuted,
    Icons.help_outline_rounded,
  );
}

class CommentsControlScreen extends StatefulWidget {
  const CommentsControlScreen({super.key});

  @override
  State<CommentsControlScreen> createState() => _CommentsControlScreenState();
}

class _CommentsControlScreenState extends State<CommentsControlScreen> {
  final AccountService _account = AccountService.instance;
  final SecurityService _security = SecurityService.instance;
  final PrivacySecurityService _privacy = PrivacySecurityService.instance;
  final TextEditingController _controller = TextEditingController();

  AccountSettings _settings = const AccountSettings();
  PrivacySettings? _privacyData;
  SpamScanResult? _result;
  List<String> _userHits = const [];
  String? _scanNote;
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  bool _privacyLoading = true;
  String? _busyField;
  bool _checking = false;
  String? _error;
  String? _checkError;
  String? _privacyError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _privacyError = null;
      _privacyLoading = true;
    });
    try {
      final settings = await _account.fetchSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = false;
        _error = 'Não foi possível carregar suas preferências. $e';
      });
    }
    try {
      final privacy = await _privacy.fetchPrivacySettings();
      if (!mounted) return;
      setState(() {
        _privacyData = privacy;
        _privacyLoading = false;
        _privacyError = null;
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
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _setAllowComments(bool value) async {
    if (_saving || !_loaded) return;
    final previous = _settings;
    setState(() {
      _settings = previous.copyWith(allowComments: value);
      _saving = true;
    });
    try {
      await _account.saveSettings(_settings);
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(value ? 'Comentários permitidos.' : 'Comentários bloqueados.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _saving = false;
      });
      _snack('Não foi possível salvar. A preferência foi revertida. $e');
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

  Future<void> _checkText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _result = null;
        _userHits = const [];
        _scanNote = null;
        _checkError = 'Escreva um texto para verificar.';
      });
      return;
    }
    setState(() {
      _checking = true;
      _checkError = null;
      _result = null;
      _userHits = const [];
      _scanNote = null;
    });
    SpamScanResult? result;
    List<String> userHits = const [];
    String? note;
    try {
      final json = await _privacy.scanUserContent(text, scope: 'comment');
      if (json.isEmpty) {
        throw StateError('O servidor não devolveu a análise do texto.');
      }
      result = SpamScanResult.fromJson(json);
      final hits = json['user_matches'];
      userHits = hits is List
          ? hits.map((e) => e.toString()).toList()
          : const [];
    } catch (e) {
      try {
        result = await _security.scanSpam(text, scope: 'comment');
        note =
            'Suas palavras bloqueadas não entraram nesta verificação. '
            '${_privacy.lastCode ?? e}';
      } catch (e2) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _checkError = 'Não foi possível verificar o texto. $e2';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _userHits = userHits;
      _scanNote = note;
      _checking = false;
    });
  }

  void _openSpamScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SpamProtectionScreen()));
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
          'Comentários',
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
                const _SectionHeader('REGRAS'),
                _allowCommentsTile(),
                const SizedBox(height: 20),
                const _SectionHeader('FILTROS'),
                ..._filtersSection(),
                const SizedBox(height: 20),
                const _SectionHeader('VERIFICAR UM TEXTO'),
                _checkCard(),
                if (_checking) ...[
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
                if (_checkError != null) ...[
                  const SizedBox(height: 12),
                  _errorCard(_checkError!),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  _resultCard(_result!, _userHits),
                ],
                if (_scanNote != null) ...[
                  const SizedBox(height: 12),
                  _noteCard(_scanNote!),
                ],
                const SizedBox(height: 20),
                const _SectionHeader('PROTEÇÃO EXTRA'),
                _spamTile(),
              ],
            ),
    );
  }

  Widget _allowCommentsTile() {
    if (!_loaded) {
      return Semantics(
        label: 'Permitir comentários: indisponível, não foi possível verificar',
        child: Card(
          color: _kCard,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: const ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            title: Text(
              'Permitir comentários',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              'Não foi possível verificar sua preferência agora.',
              style: TextStyle(color: _kMuted, fontSize: 12),
            ),
            trailing: Icon(Icons.block_rounded, color: _kMuted),
          ),
        ),
      );
    }
    return Semantics(
      label: 'Permitir comentários',
      toggled: _settings.allowComments,
      child: Card(
        color: _kCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          value: _settings.allowComments,
          activeThumbColor: _kAccent,
          onChanged: _saving ? null : _setAllowComments,
          title: const Text(
            'Permitir comentários',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Desligado, o backend recusa novos comentários feitos pela sua '
            'conta em posts e lives.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ),
    );
  }

  List<Widget> _filtersSection() {
    if (_privacyLoading) {
      return [
        Semantics(
          label: 'Carregando os filtros de privacidade do servidor',
          container: true,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kAccent,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Carregando os filtros de privacidade do servidor.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    final data = _privacyData;
    if (data == null) {
      return [
        _unavailableCard(
          title: 'Filtros indisponíveis',
          message:
              _privacyError ??
              'O servidor não devolveu o bloco de privacidade. Nenhum valor é '
                  'mostrado aqui para não fingir que existe.',
        ),
      ];
    }
    return [
      _sensitiveFilterTile(data.sensitiveContentFilter),
      _mentionsRow(data.allowMentions),
      _BlockedWordsEditor(words: data.blockedWords),
      if (_privacyError != null) ...[
        const SizedBox(height: 4),
        _errorCard(_privacyError!),
      ],
    ];
  }

  Widget _sensitiveFilterTile(bool value) {
    final busy = _busyField == 'sensitiveContentFilter';
    return Semantics(
      label: 'Filtrar conteúdo ofensivo. ${value ? 'Ligado' : 'Desligado'}',
      toggled: value,
      container: true,
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
          activeThumbColor: _kAccent,
          secondary: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kAccent,
                    ),
                  ),
                )
              : const Icon(Icons.shield_outlined, color: _kAccent),
          title: const Text(
            'Filtrar conteúdo ofensivo',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'O servidor guarda este valor e o devolve na verificação de texto '
            'abaixo. Ele não bloqueia nada por conta própria.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          onChanged: _busyField != null
              ? null
              : (v) => _save(
                  'sensitiveContentFilter',
                  'Filtrar conteúdo ofensivo',
                  () => _privacy.savePrivacySettings(sensitiveContentFilter: v),
                ),
        ),
      ),
    );
  }

  Widget _mentionsRow(String value) {
    final busy = _busyField == 'allowMentions';
    final scopes = [for (final s in InteractionScope.all) (s.id, s.label)];
    String? label;
    for (final s in scopes) {
      if (s.$1 == value) label = s.$2;
    }
    return Semantics(
      label: 'Controle de menções. ${label ?? 'O servidor respondeu "$value"'}',
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.alternate_email_rounded,
                  color: _kAccent,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Controle de menções',
                    style: TextStyle(
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
                      color: _kAccent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Quem pode escrever @seu_usuário ou citar seu nome.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Opções: ${scopes.map((o) => o.$2).join(', ')}. '
                  'Selecionado: ${label ?? 'o servidor respondeu "$value"'}',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in scopes)
                    ChoiceChip(
                      label: Text(
                        o.$2,
                        style: TextStyle(
                          color: o.$1 == value ? Colors.white : Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                      selected: o.$1 == value,
                      selectedColor: _kAccent,
                      backgroundColor: const Color(0xFF222032),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onSelected: _busyField != null
                          ? null
                          : (v) {
                              if (!v) return;
                              _save(
                                'allowMentions',
                                'Controle de menções',
                                () => _privacy.savePrivacySettings(
                                  allowMentions: o.$1,
                                ),
                              );
                            },
                    ),
                ],
              ),
            ),
            if (label == null) ...[
              const SizedBox(height: 8),
              Text(
                'Valor atual do backend: $value',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _unavailableCard({required String title, required String message}) {
    return Semantics(
      label: '$title. $message',
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kDanger.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded, color: _kDanger, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _kDanger,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkCard() {
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
            'A verificação usa a função real de anti-spam do servidor no '
            'escopo de comentário, somando as palavras bloqueadas por você. '
            'Ela mostra a prévia, sem publicar nada.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Comentário para verificar',
            textField: true,
            child: TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: _kAccent,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Escreva ou cole um comentário',
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
          Semantics(
            label: 'Verificar texto do comentário',
            button: true,
            child: FilledButton.icon(
              onPressed: _checking ? null : _checkText,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.policy_rounded, size: 20),
              label: const Text(
                'VERIFICAR TEXTO',
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

  Widget _resultCard(SpamScanResult result, List<String> userHits) {
    final view = _checkView(result);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (result.matches.isEmpty)
              const Text(
                'Nenhuma correspondência encontrada pelo backend.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              )
            else
              ...result.matches.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $m',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            if (userHits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Semantics(
                label:
                    'Suas palavras bloqueadas encontradas: ${userHits.join(', ')}',
                child: Text(
                  'Suas palavras bloqueadas: ${userHits.join(', ')}',
                  style: const TextStyle(
                    color: _kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _spamTile() {
    return Semantics(
      label: 'Abrir proteção contra spam',
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
          leading: const Icon(Icons.shield_rounded, color: _kAccent),
          title: const Text(
            'Proteção contra spam',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Teste comentários e mensagens, e veja as regras anti-spam reais.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: _openSpamScreen,
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

  Widget _noteCard(String message) {
    return Semantics(
      label: message,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: _kMuted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
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
    );
  }
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
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_rounded, color: _kAccent, size: 22),
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
                      color: _kAccent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'O servidor esconde e sinaliza, para você, textos com estas '
              'palavras. Nada é filtrado fora do servidor.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Palavra a bloquear',
                    textField: true,
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      cursorColor: _kAccent,
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
                          borderSide: const BorderSide(color: _kAccent),
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
                      backgroundColor: _kAccent,
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
                    color: _kDanger,
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
