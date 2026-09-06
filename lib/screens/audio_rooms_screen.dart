import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/audio_room_models.dart';
import '../services/audio_room_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/ad_spot.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/klayk_ux.dart';
import 'voice_room_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Salas de voz do KLAY K: descoberta (categorias + busca) e criação de
/// salas reais via LiveKit (só áudio).
///
/// Quando [autoCreate] está ativo, a tela abre direto no fluxo de criar uma
/// sala multi-falante (usado pelo card "Amigos" da Central de Lives), em vez
/// de listar a descoberta. [friendsMode] ajusta o texto para "Live com
/// amigos".
class AudioRoomsScreen extends StatefulWidget {
  final bool autoCreate;
  final bool friendsMode;

  const AudioRoomsScreen({
    super.key,
    this.autoCreate = false,
    this.friendsMode = false,
  });

  @override
  State<AudioRoomsScreen> createState() => _AudioRoomsScreenState();
}

class _AudioRoomsScreenState extends State<AudioRoomsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final _debounce = KlaykDebouncer(const Duration(milliseconds: 350));
  final AdSpot _ads = AdSpot();
  List<AudioRoom> _rooms = [];
  List<AudioRoomCategory> _categories = [];
  String? _selectedCategory;
  bool _loading = true;
  bool _loadFailed = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _ads.load(limit: 4);
    _load();
    if (widget.autoCreate) {
      Future<void>.microtask(_openCreateDialog);
    }
  }

  @override
  void dispose() {
    _debounce.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? category}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      if (!SupabaseService.instance.isConfigured) {
        throw Exception('Supabase não configurado');
      }
      final rooms = await AudioRoomService.instance.fetchRooms(
        query: _searchCtrl.text,
        category: category,
      );
      final categories = await AudioRoomService.instance.fetchCategories();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _categories = categories;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rooms = [];
        _categories = [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _onSearch(String text) {
    _debounce.run(() {
      if (!mounted) return;
      _load(category: _selectedCategory);
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _onSearch('');
  }

  void _selectCategory(String? category) {
    if (mounted) setState(() => _selectedCategory = category);
    _load(category: category);
  }

  Future<void> _openCreateDialog() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _CreateRoomDialog(friendsMode: widget.friendsMode),
    );
    if (title == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final created = await AudioRoomService.instance.createAndJoin(
        title: title,
        joinWithMic: true,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VoiceRoomScreen(
            room: created,
            joinWithMic: true,
            isOwner: true,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.friendsMode
                ? 'Não foi possível iniciar a Live com amigos.'
                : 'Não foi possível criar a sala de voz.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
    _load();
  }

  Future<void> _openRoom(AudioRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceRoomScreen(
          room: room,
          joinWithMic: false,
          isOwner: room.iOwnIt,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          widget.friendsMode ? 'Amigos' : 'Áudio',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _searchField(),
          ),
          _categoryStrip(),
          const SizedBox(height: 4),
          Expanded(child: _loading ? const KlaykListSkeleton(rows: 6) : _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        onPressed: _creating ? null : _openCreateDialog,
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.mic_rounded),
        label: Text(_creating ? 'Criando…' : 'Criar sala'),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearch,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Buscar salas de voz…',
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        suffixIcon: _searchCtrl.text.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: _clearSearch,
              ),
        filled: true,
        fillColor: const Color(0xFF17141F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2540)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2540)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent),
        ),
      ),
    );
  }

  Widget _categoryStrip() {
    final cats = [..._categories];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: cats.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (context, i) {
          if (i == 0) {
            return KlayKChip(
              label: 'Todas',
              selected: _selectedCategory == null,
              onTap: () => _selectCategory(null),
            );
          }
          final c = cats[i - 1];
          return KlayKChip(
            label: c.name,
            selected: _selectedCategory == c.name,
            onTap: () => _selectCategory(c.name),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Erro ao carregar',
        message: 'Não conseguimos carregar as salas de voz. Tentar novamente.',
        actionLabel: 'Tentar novamente',
        actionIcon: Icons.refresh_rounded,
        onAction: () => _load(category: _selectedCategory),
      );
    }
    if (_rooms.isEmpty) {
      return const KlaykEmptyState(
        icon: Icons.mic_none_rounded,
        title: 'Nenhuma sala ao vivo',
        message:
            'Quando alguém abrir uma sala de voz, ela aparece aqui. Toque em "Criar sala" para começar a sua.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(category: _selectedCategory),
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.waves_rounded, color: _kAccent, size: 18),
                SizedBox(width: 6),
                Text(
                  'Ao vivo agora',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
          ),
          ..._rooms.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _roomCard(r),
              )),
          for (var i = 0; i < _rooms.length; i++)
            if ((i + 1) % 4 == 0 && _ads.ads.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AdCard(
                  ad: _ads.ads[i ~/ 4 % _ads.ads.length],
                  onHidden: () => setState(() {
                    final adId = _ads.ads[i ~/ 4 % _ads.ads.length].id;
                    _ads.remove(adId);
                  }),
                ),
              ),
        ],
      ),
    );
  }

  Widget _roomCard(AudioRoom r) {
    final colors = kcolors(context);
    return GestureDetector(
      onTap: () => _openRoom(r),
      child: KlayKCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2350), Color(0xFF161026)],
                ),
                border: Border.all(color: const Color(0xFF2A2540)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.graphic_eq_rounded, color: _kAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2350),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                            SizedBox(width: 4),
                            Text('AO VIVO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    r.description.isEmpty ? r.category : r.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: r.ownerAvatarUrl == null || r.ownerAvatarUrl!.isEmpty
                            ? Container(
                                width: 20,
                                height: 20,
                                color: const Color(0xFF2A2540),
                                alignment: Alignment.center,
                                child: const Text('🎙️', style: TextStyle(fontSize: 11)),
                              )
                            : Image.network(
                                r.ownerAvatarUrl!,
                                width: 20,
                                height: 20,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 20,
                                  height: 20,
                                  color: const Color(0xFF2A2540),
                                  alignment: Alignment.center,
                                  child: const Text('🎙️', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        r.ownerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Icon(Icons.people_outline_rounded, color: colors.primarySoft, size: 15),
                      const SizedBox(width: 3),
                      Text(
                        '${r.participantCount}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  final bool friendsMode;
  const _CreateRoomDialog({this.friendsMode = false});

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final TextEditingController _titleCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _titleCtrl.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF17141F),
      title: Text(
        widget.friendsMode ? 'Live com amigos' : 'Criar sala de voz',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            onSubmitted: (_) => _submit(),
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Nome da sala…',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.waves_rounded, color: Color(0xFF8B5CF6), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.friendsMode
                      ? 'Você será o anfitrião: seus amigos podem entrar para falar com você.'
                      : 'Você será o dono e poderá falar assim que entrar.',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
          onPressed: _submit,
          child: const Text('Criar e entrar'),
        ),
      ],
    );
  }
}