import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/post_models.dart';
import '../../models/user_profile.dart';
import '../../services/content_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/klayk_ux.dart';
import '../../widgets/profile_components.dart';
import '../../widgets/profile_widgets.dart';
import '../settings_screen.dart';
import 'edit_profile_screen.dart';
import 'profile_lists_screen.dart';

/// Aba "Perfil" do usuário autenticado.
///
/// Perfil limpo no estilo rede social: cabeçalho de verdade (avatar, nome,
/// selo, bio), métricas reais (seguidores/seguindo/curtidas), ações
/// (Editar perfil / Compartilhar) e abas Vídeos / Curtidos / Salvos com
/// conteúdo real. Os itens administrativos (Carteira, Loja, Conquistas…) não
/// foram apagados — foram movidos para as Configurações.
class ProfileScreen extends StatefulWidget {
  /// Ação "Criar vídeo" quando o usuário não tem vídeos publicados. Quando
  /// nula, o estado vazio não mostra o botão. Convenção: abrir o fluxo de
  /// upload já existente (`UploadScreen`), injetado pela raiz do app.
  final Future<void> Function()? onCreateVideo;

  const ProfileScreen({super.key, this.onCreateVideo});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<FeedPost> _videos = const [];
  List<FeedPost> _liked = const [];
  List<FeedPost> _saved = const [];
  bool _loading = true;
  bool _tabLoading = false;
  int _tab = 0;

  UserProfile? get _p => _profile;

  bool get _real => SupabaseService.instance.isConfigured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_real) {
      if (mounted) {
        setState(() {
          _profile = ProfileService.instance.offlineProfile('');
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final profile = await ProfileService.instance.fetchMyProfile();
      final user = SupabaseService.instance.currentUser;
      final posts = user != null
          ? await ContentService.instance.fetchFeed(userId: user.id, limit: 9)
          : const <FeedPost>[];
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _videos = posts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) => _load());
  }

  void _openEdit() async {
    final p = _p;
    if (p == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p)),
    );
    if (changed == true) _load();
  }

  Future<void> _openFollowers() async {
    final uid = ProfileService.instance.myId;
    if (uid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileListsScreen(userId: uid, following: false),
      ),
    );
  }

  Future<void> _openFollowing() async {
    final uid = ProfileService.instance.myId;
    if (uid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileListsScreen(userId: uid, following: true),
      ),
    );
  }

  Future<void> _share() async {
    final p = _p;
    if (p == null) return;
    final l10n = AppLocalizations.of(context)!;
    final handle = p.handle.replaceAll('@', '').trim();
    try {
      await Share.share(
        p.handle.isEmpty
            ? l10n.profileShareMsg
            : l10n.profileShareMsgLink('https://klayk.app/u/$handle'),
      );
    } catch (_) {}
  }

  void _changeTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    _loadTab(index);
  }

  /// Carrega Curtidos/Salvos do backend real, uma única vez por seção
  /// (sem consultas duplicadas) e nunca inventa conteúdo §4/§9.
  Future<void> _loadTab(int index) async {
    if (index == 0 || !_real || _tabLoading) return;
    if (index == 1 && _liked.isNotEmpty) return;
    if (index == 2 && _saved.isNotEmpty) return;
    setState(() => _tabLoading = true);
    try {
      if (index == 1) {
        final posts = await ContentService.instance.fetchLikedPosts();
        if (mounted) setState(() => _liked = posts);
      } else {
        final posts = await ContentService.instance.fetchSavedPosts();
        if (mounted) setState(() => _saved = posts);
      }
    } catch (_) {
      // Sem resposta do backend a seção fica vazia — nunca dados falsos.
    } finally {
      if (mounted) setState(() => _tabLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.profileTab,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 6, withAvatar: true)
          : p == null
          ? KlaykErrorState(message: l10n.profileLoadFail, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              color: kProfileAccent,
              backgroundColor: const Color(0xFF1B1A26),
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  ProfileHeader(
                    profile: p,
                    showBanner: false,
                    actions: [
                      ProfileActionButton(
                        isSelf: true,
                        isFollowing: false,
                        onPressed: _openEdit,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _share,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF2A2540)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.share_outlined, size: 17),
                          label: Text(l10n.share),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ProfileStats(
                    profile: p,
                    onFollowersTap: _openFollowers,
                    onFollowingTap: _openFollowing,
                  ),
                  KlaykProfileTabs(selected: _tab, onChanged: _changeTab),
                  const SizedBox(height: 8),
                  _buildTabContent(),
                ],
              ),
            ),
    );
  }

  Widget _buildTabContent() {
    final l10n = AppLocalizations.of(context)!;
    if (_tab == 0) {
      return KlaykProfileVideoGrid(
        videos: _videos,
        onDeleted: _load,
        onEmpty: widget.onCreateVideo == null ? null : _createFromEmpty,
      );
    }
    final posts = _tab == 1 ? _liked : _saved;
    if (_tabLoading && posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: KlaykListSkeleton(rows: 4, withAvatar: false),
      );
    }
    if (posts.isEmpty) {
      final isLiked = _tab == 1;
      return KlaykEmptyState(
        icon: isLiked
            ? Icons.favorite_border_rounded
            : Icons.bookmark_border_rounded,
        title: isLiked
            ? l10n.profileLikedEmptyTitle
            : l10n.profileSavedEmptyTitle,
        message: isLiked
            ? l10n.profileLikedEmptyMsg
            : l10n.profileSavedEmptyMsg,
      );
    }
    return KlaykProfileVideoGrid(videos: posts);
  }

  /// Abre o fluxo de criação de vídeo injetado pela raiz do app e recarrega a
  /// aba Vídeos quando o usuário voltar.
  Future<void> _createFromEmpty() async {
    final create = widget.onCreateVideo;
    if (create == null) return;
    await create();
    _load();
  }
}
