import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_config.dart';
import '../services/content_service.dart';
import '../services/live_kit_service.dart';
import '../services/supabase_service.dart';
import 'live_room_screen.dart';

/// Seletor de capa injetável (o app usa [ImagePicker]; testes injetam um fake
/// para não depender do plugin de plataforma).
typedef CoverFilePicker = Future<XFile?> Function(ImageSource source);

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1C1C26);

const List<String> _kCategories = [
  'Jogos',
  'Filmes',
  'Música',
  'Bate-papo',
  'Comédia',
  'Educativo',
];

/// Modo de transmissão escolhido antes de iniciar a live.
enum LiveMode {
  /// Câmera frontal do celular, transmissão tradicional em tela cheia.
  camera,

  /// Captura de tela (jogos); o app é minimizado e uma bolinha flutuante
  /// controla a transmissão (igual ao Kwai).
  screen,
}

/// Configuração de uma nova transmissão ao vivo (real, via Supabase + LiveKit).
class StartLiveScreen extends StatefulWidget {
  const StartLiveScreen({
    super.key,
    this.coverPicker,
    this.forceGame = false,
    this.initialCategory,
    this.title,
  });

  /// Seletor de imagem da capa. Quando nulo, usa [ImagePicker] de verdade.
  final CoverFilePicker? coverPicker;

  /// Quando verdadeiro, pré-seleciona a categoria "Jogos" e abre a sala como
  /// uma Live de Jogo (com captura de tela) ao iniciar.
  final bool forceGame;

  /// Pré-seleciona a categoria (ex.: "Filmes") ao abrir a configuração.
  final String? initialCategory;

  /// Título do app bar quando vindo de um formato específico.
  final String? title;

  @override
  State<StartLiveScreen> createState() => _StartLiveScreenState();
}

class _StartLiveScreenState extends State<StartLiveScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _gameNameController = TextEditingController();

  String _category = _kCategories.first;
  String _privacy = 'public';
  bool _adultOnly = false;
  bool _saving = false;

  /// Modo de transmissão. Quando ainda não escolhido (`null`), a tela abre o
  /// seletor de modo (câmera vs. jogos) antes de permitir iniciar a live.
  LiveMode? _liveMode;
  bool get _modeChosen => _liveMode != null;
  bool get _isScreenMode => _liveMode == LiveMode.screen;

  @override
  void initState() {
    super.initState();
    if (widget.forceGame) {
      _liveMode = LiveMode.screen;
      _category = 'Jogos';
      _gameNameController.text = 'Meu Jogo';
    } else if (widget.initialCategory != null &&
        _kCategories.contains(widget.initialCategory)) {
      _category = widget.initialCategory!;
    }
  }

  File? _coverFile;
  String? _coverExtension;
  String? _coverError;
  bool _uploadingCover = false;

  static const int _maxTitle = 80;
  static const int _maxTags = 10;
  static const int _maxTagLength = 30;
  static const int _maxCoverBytes = 10 * 1024 * 1024; // mesmo cap do storage-init
  static const List<String> _allowedCoverExt = ['png', 'jpg', 'jpeg', 'webp'];

  List<String> get _tags {
    final parts = _tagsController.text
        .split(RegExp(r'[,\s]+'))
        .map((t) => t.replaceAll('#', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return parts;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _gameNameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_modeChosen) {
      await _showModePicker();
      if (!mounted || !_modeChosen) return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _snack('Digite um título para a live.');
      return;
    }
    if (title.length > _maxTitle) {
      _snack('O título deve ter até $_maxTitle caracteres.');
      return;
    }
    final tags = _tags;
    if (tags.length > _maxTags) {
      _snack('Use no máximo $_maxTags hashtags.');
      return;
    }
    if (tags.any((t) => t.length > _maxTagLength)) {
      _snack('Cada hashtag deve ter até $_maxTagLength caracteres.');
      return;
    }
    final isGame = _isScreenMode;
    if (isGame) _category = 'Jogos';
    final gameName = isGame ? _gameNameController.text.trim() : null;
    if (isGame && (gameName == null || gameName.isEmpty)) {
      _snack('Digite o nome do jogo.');
      return;
    }

    if (!AppConfig.isSupabaseConfigured) {
      _snack('Configure o Supabase para iniciar uma live real.');
      return;
    }

    setState(() => _saving = true);
    try {
      final db = SupabaseService.instance;
      await db.ensureAuthenticated();

      // Upload real da capa (antes de criar o registro) + limpeza best-effort
      // do objeto caso a criação da live falhe.
      String? coverUrl;
      if (_coverFile != null) {
        setState(() => _uploadingCover = true);
        try {
          coverUrl = await ContentService.instance.uploadCover(
            _coverFile!,
            coverExtension: _coverExtension,
          );
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _uploadingCover = false;
            _saving = false;
          });
          _snack('Não foi possível enviar a capa. Tente novamente.');
          return;
        }
        if (!mounted) return;
        setState(() => _uploadingCover = false);
      }

      final live = await db.createLive(
        title: title,
        description: _descriptionController.text.trim(),
        category: _category,
        hashtags: tags,
        privacy: _privacy,
        gameName: gameName,
        coverUrl: coverUrl,
        ageRestricted: _adultOnly,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LiveRoomScreen(
            live: live,
            role: LiveRole.streamer,
            isGameLive: _isScreenMode,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e is SupabaseAuthUnavailableException) {
        _snack(e.message);
        return;
      }
      _snack('Não foi possível iniciar a live. Tente novamente.');
    }
  }

  Future<void> _pickCover() async {
    if (_uploadingCover) return;
    final pick = widget.coverPicker ??
        (ImageSource source) =>
            ImagePicker().pickImage(
              source: source,
              maxWidth: 1440,
              imageQuality: 85,
            );
    final XFile? picked;
    try {
      picked = await pick(ImageSource.gallery);
    } catch (_) {
      _snack('Não foi possível abrir a galeria.');
      return;
    }
    if (!mounted || picked == null) return;

    // Validação de formato e tamanho ANTES de qualquer upload.
    final ext = _extensionOfName(picked.name);
    if (!_allowedCoverExt.contains(ext)) {
      setState(() {
        _coverError = 'Formato não suportado. Use PNG, JPG ou WEBP.';
      });
      return;
    }
    final bytes = await picked.length();
    if (bytes <= 0 || bytes > _maxCoverBytes) {
      setState(() {
        _coverError = 'Imagem muito grande (máx. 10 MB). Escolha outra.';
      });
      return;
    }

    final path = picked.path;
    setState(() {
      _coverFile = File(path);
      _coverExtension = ext;
      _coverError = null;
    });
  }

  void _removeCover() {
    if (_uploadingCover) return;
    setState(() {
      _coverFile = null;
      _coverExtension = null;
      _coverError = null;
    });
  }

  static String _extensionOfName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  Future<void> _showModePicker() async {
    final picked = await showModalBottomSheet<LiveMode>(
      context: context,
      backgroundColor: const Color(0xFF151430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Como você quer transmitir?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Escolha o modo da sua live antes de começar.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _modeCard(
                ctx: ctx,
                mode: LiveMode.camera,
                icon: Icons.videocam_rounded,
                title: 'Modo Câmera (Rosto)',
                subtitle: 'Transmissão tradicional com a câmera frontal.',
              ),
              const SizedBox(height: 12),
              _modeCard(
                ctx: ctx,
                mode: LiveMode.screen,
                icon: Icons.sports_esports_rounded,
                title: 'Modo Jogos (Tela)',
                subtitle: 'Captura de tela em tempo real (bolinha flutuante).',
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _liveMode = picked);
      if (picked == LiveMode.screen) {
        _category = 'Jogos';
        if (_gameNameController.text.isEmpty) {
          _gameNameController.text = 'Meu Jogo';
        }
      }
    }
  }

  Widget _modeCard({
    required BuildContext ctx,
    required LiveMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isCam = mode == LiveMode.camera;
    return GestureDetector(
      onTap: () => Navigator.of(ctx).pop(mode),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCam
                ? _kAccent.withValues(alpha: 0.6)
                : _kAccent.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _kAccent, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 24),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.title ?? 'Criar live ao vivo',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('Título'),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              maxLength: _maxTitle,
              style: const TextStyle(color: Colors.white),
              cursorColor: _kAccent,
              decoration: _inputDec('O que você vai mostrar?'),
            ),
            const SizedBox(height: 12),
            _sectionTitle('Categoria'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _kCategories)
                  ChoiceChip(
                    label: Text(c,
                        style: const TextStyle(color: Colors.white)),
                    selected: _category == c,
                    backgroundColor: _kCard,
                    selectedColor: _kAccent.withValues(alpha: 0.85),
                    side: BorderSide(
                      color: _category == c
                          ? _kAccent
                          : Colors.white10,
                    ),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (_category == 'Jogos') ...[
              const SizedBox(height: 12),
              _sectionTitle('Jogo'),
              const SizedBox(height: 8),
              TextField(
                controller: _gameNameController,
                maxLength: 60,
                style: const TextStyle(color: Colors.white),
                cursorColor: _kAccent,
                decoration: _inputDec('Qual jogo você vai jogar?'),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle('Hashtags'),
            const SizedBox(height: 4),
            const Text(
              'Separe por espaço ou vírgula (até $_maxTags).',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tagsController,
              style: const TextStyle(color: Colors.white),
              cursorColor: _kAccent,
              decoration: _inputDec('ex: klayk ecossistema'),
              onChanged: (_) => setState(() {}),
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _kAccent.withValues(alpha: 0.6)),
                      ),
                      child: Text('#$t',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle('Descrição'),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 200,
              style: const TextStyle(color: Colors.white),
              cursorColor: _kAccent,
              decoration: _inputDec('Detalhes da transmissão (opcional)'),
            ),
            const SizedBox(height: 8),
            _sectionTitle('Capa'),
            const SizedBox(height: 8),
            if (_coverError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _coverError!,
                  style: const TextStyle(color: Color(0xFFFF5A7A), fontSize: 12),
                ),
              ),
            _buildCoverPicker(),
            const SizedBox(height: 20),
            _sectionTitle('Privacidade'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _privacyOption('Pública', 'public',
                        Icons.public_rounded),
                  ),
                  Expanded(
                    child: _privacyOption('Privada', 'private',
                        Icons.lock_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile(
                value: _adultOnly,
                onChanged: (v) => setState(() => _adultOnly = v),
                activeThumbColor: _kAccent,
                title: const Text('Live para maiores de 18',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
                subtitle: const Text(
                  'Espectadores só entram com idade provada de 18+ '
                  '(verificada no backend).',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sensors_rounded),
              label: Text(
                _uploadingCover
                    ? 'Enviando capa…'
                    : _saving
                        ? 'Iniciando...'
                        : 'Iniciar Live',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPicker() {
    final hasCover = _coverFile != null;
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        height: 140,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1B4D), Color(0xFF14142B)],
          ),
          border: Border.all(color: _kAccent.withValues(alpha: 0.5)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              Image.file(
                _coverFile!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF14142B),
                ),
              ),
            if (hasCover)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x99000000),
                    ],
                  ),
                ),
              ),
            if (hasCover)
              Positioned(
                right: 6,
                top: 6,
                child: Tooltip(
                  message: 'Remover capa',
                  child: IconButton(
                    onPressed: _uploadingCover ? null : _removeCover,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xA6000000),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: hasCover
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cached_rounded,
                                color: Colors.white70, size: 18),
                            SizedBox(width: 6),
                            Text('Trocar capa',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded,
                                color: _kAccent, size: 24),
                            SizedBox(width: 8),
                            Text('Adicionar capa (opcional)',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                ),
              ),
            ),
            if (_uploadingCover)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: _kAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: _kCard,
        counterStyle: const TextStyle(color: Colors.white30),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccent),
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _privacyOption(String label, String value, IconData icon) {
    final selected = _privacy == value;
    return GestureDetector(
      onTap: () => setState(() => _privacy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withValues(alpha: 0.85) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? Colors.white : Colors.white54, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                )),
          ],
        ),
      ),
    );
  }
}