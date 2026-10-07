import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/event_models.dart';
import '../services/event_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';
import '../l10n/app_localizations.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Eventos públicos do KLAY K: descoberta (categorias + busca), cards com
/// data/participantes e botão de presença (RSVP) com dados reais.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final _debounce = KlaykDebouncer(const Duration(milliseconds: 350));
  List<KlayKEvent> _all = [];
  List<KlayKEvent> _mine = [];
  List<KlayKEventCategory> _categories = [];
  String? _selectedCategory;
  bool _loading = true;
  bool _loadFailed = false;
  final Set<String> _goingBusy = {};

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
      final events = await EventService.instance.fetchEvents(
        query: _searchCtrl.text,
        category: category,
      );
      final categories = await EventService.instance.fetchCategories();
      final mine = await EventService.instance.fetchMyEvents();
      final goingIds = mine.map((e) => e.id).toSet();
      if (!mounted) return;
      setState(() {
        _all = [
          for (final e in events) e.copyWith(iAmGoing: goingIds.contains(e.id)),
        ];
        _mine = mine;
        _categories = categories;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _mine = [];
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

  Future<void> _toggleGoing(KlayKEvent e) async {
    if (_goingBusy.contains(e.id)) return;
    setState(() => _goingBusy.add(e.id));
    final next = await EventService.instance.toggleGoing(e.id);
    if (!mounted) return;
    setState(() {
      _goingBusy.remove(e.id);
      final delta = next ? 1 : -1;
      _all = [
        for (final x in _all)
          if (x.id == e.id)
            x.copyWith(
              iAmGoing: next,
              participantCount: (x.participantCount + delta).clamp(0, 1 << 30),
            )
          else
            x,
      ];
    });
    _load(category: _selectedCategory);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.events,
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
          Expanded(
            child: _loading ? const KlaykListSkeleton(rows: 6) : _buildBody(),
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
        hintText: AppLocalizations.of(context)!.searchEventsHint,
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
    final l10n = AppLocalizations.of(context)!;
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
              label: l10n.exploreAll,
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

  void _selectCategory(String? category) {
    if (mounted) setState(() => _selectedCategory = category);
    _load(category: category);
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: l10n.errorLoading,
        message: l10n.eventsLoadFail,
        actionLabel: l10n.retry,
        actionIcon: Icons.refresh_rounded,
        onAction: () => _load(category: _selectedCategory),
      );
    }
    if (_all.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.event_outlined,
        title: l10n.eventsEmptyTitle,
        message: l10n.eventsEmptyBody,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(category: _selectedCategory),
      color: _kAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_mine.isNotEmpty) ...[
            _sectionHeader(
              l10n.yourRSVPs,
              icon: Icons.check_circle_outline_rounded,
            ),
            ..._mine.map((e) => _eventCard(e)),
            const SizedBox(height: 14),
          ],
          _sectionHeader(
            l10n.upcomingEvents,
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 4),
          ..._all.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _eventCard(e),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: _kAccent, size: 18),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(KlayKEvent e) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final busy = _goingBusy.contains(e.id);
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A2350), Color(0xFF161026)],
                  ),
                  border: Border.all(color: const Color(0xFF2A2540)),
                ),
                alignment: Alignment.center,
                child: Text(e.icon, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.whenLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.location.isEmpty
                          ? (e.category.isEmpty
                                ? l10n.everywhereInApp
                                : e.category)
                          : e.location,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: busy ? null : () => _toggleGoing(e),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: e.iAmGoing ? const Color(0xFF2A2350) : _kAccent,
                    border: Border.all(
                      color: e.iAmGoing ? const Color(0xFF8B5CF6) : _kAccent,
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          e.iAmGoing ? l10n.goingActive : l10n.goingAction,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (e.description.isNotEmpty) ...[
            Text(
              e.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(
                Icons.people_outline_rounded,
                color: colors.primarySoft,
                size: 15,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.participantsConfirm(e.participantCount),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
