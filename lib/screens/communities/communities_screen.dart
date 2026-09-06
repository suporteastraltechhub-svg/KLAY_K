import 'package:flutter/material.dart';

import '../../design/klayk_design.dart';
import '../../models/community_models.dart';
import '../../services/community_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import 'community_detail_screen.dart';
import 'create_community_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Exploração de Comunidades do KLAY K: busca, categorias e comunidades
/// populares. Idêntico em identidade ao restante do app.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final _debounce = KlaykDebouncer(const Duration(milliseconds: 350));
  List<Community> _all = [];
  List<CommunityCategory> _categories = [];
  String? _selectedCategory;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      final communities = await CommunityService.instance.fetchCommunities(
        query: _searchCtrl.text,
        category: category,
      );
      final categories = await CommunityService.instance.fetchCategories();
      if (!mounted) return;
      setState(() {
        _all = communities;
        _categories = categories;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _all = [];
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

  Future<void> _openDetail(Community c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CommunityDetailScreen(community: c)),
    );
    _load(category: _selectedCategory);
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
    );
    _load(category: _selectedCategory);
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: const Text(
          'Comunidades',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          KlayKIconButton(
            icon: Icons.add_rounded,
            onTap: _openCreate,
            glow: true,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _searchField(),
          ),
          _categoryStrip(),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const KlaykListSkeleton(rows: 6)
                : _buildBody(colors),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearch,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Buscar comunidades…',
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        suffixIcon: _searchCtrl.text.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearch('');
                },
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
              onTap: _selectCategory,
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

  void _selectCategory([String? category]) {
    if (mounted) setState(() => _selectedCategory = category);
    _load(category: category);
  }

  Widget _buildBody(KlaykColors colors) {
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Erro ao carregar',
        message: 'Não conseguimos carregar as comunidades. Tentar novamente.',
        actionLabel: 'Tentar novamente',
        actionIcon: Icons.refresh_rounded,
        onAction: () => _load(category: _selectedCategory),
      );
    }
    if (_all.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.groups_outlined,
        title: 'Nenhuma comunidade',
        message:
            'Crie a primeira comunidade do KLAY K ou tente outra busca.',
        actionLabel: 'Criar comunidade',
        actionIcon: Icons.add_rounded,
        onAction: _openCreate,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _all.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _communityCard(_all[i]),
    );
  }

  Widget _communityCard(Community c) {
    final colors = kcolors(context);
    return KlayKCard(
      onTap: () => _openDetail(c),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: colors.primary.withValues(alpha: 0.14),
              border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Text(
              c.icon.isNotEmpty ? c.icon : c.categoryIcon,
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  c.description.isEmpty
                      ? '${c.memberCount} membros · ${c.categoryIcon} ${c.category}'
                      : c.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.groups_rounded,
                        size: 14, color: colors.primarySoft),
                    const SizedBox(width: 4),
                    Text(
                      '${c.memberCount} membros',
                      style:
                          TextStyle(color: colors.primarySoft, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        ],
      ),
    );
  }
}