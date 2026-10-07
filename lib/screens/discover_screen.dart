import 'dart:async';

import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/klayk_ux.dart';
import '../widgets/verified_badge.dart';
import '../l10n/app_localizations.dart';
import 'profile/user_profile_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

const List<String> _kScopes = ['all', 'user', 'post', 'hashtag', 'live'];

/// Descobrir & Tendências do KLAY K: busca real, tendências de hashtags e
/// recentes, alimentados pelo backend (sem dados inventados).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final _debounce = KlaykDebouncer(const Duration(milliseconds: 350));

  List<HashtagTrend> _trends = [];
  List<String> _recents = [];
  List<SearchResult> _results = [];
  String _scope = 'all';
  String _query = '';
  bool _loadingHome = true;
  bool _homeFailed = false;
  bool _searching = false;
  bool _searchFailed = false;
  bool _hasSearched = false;
  List<AdCreative> _ads = [];

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  @override
  void dispose() {
    _debounce.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAds() async {
    final ads = await AdsService.instance.fetchApprovedAds(limit: 4);
    if (!mounted) return;
    setState(() => _ads = ads);
  }

  void _removeAd(String adId) {
    setState(() {
      _ads = List.of(_ads.where((a) => a.id != adId));
    });
  }

  bool get _isConfigured => SupabaseService.instance.isConfigured;

  Future<void> _loadHome() async {
    if (mounted) {
      setState(() {
        _loadingHome = true;
        _homeFailed = false;
      });
    }
    try {
      if (!_isConfigured) throw Exception('Supabase não configurado');
      final results = await Future.wait<Object>([
        SocialService.instance.trendingHashtags(limit: 20),
        SocialService.instance.fetchSearchHistory(limit: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _trends = (results[0] as List).cast<HashtagTrend>();
        _recents = (results[1] as List).cast<String>();
        _loadingHome = false;
      });
      _loadAds();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _trends = [];
        _recents = [];
        _loadingHome = false;
        _homeFailed = true;
      });
    }
  }

  void _onSearchText(String text) {
    _debounce.run(() {
      if (!mounted) return;
      final q = text.trim();
      if (q.isEmpty) {
        setState(() {
          _query = '';
          _results = [];
          _hasSearched = false;
          _searching = false;
          _searchFailed = false;
        });
        return;
      }
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q, {bool record = true}) async {
    if (mounted) {
      setState(() {
        _query = q;
        _searching = true;
        _searchFailed = false;
      });
    }
    try {
      if (!_isConfigured) throw Exception('Supabase não configurado');
      if (record) {
        SocialService.instance.recordSearch(q, resultType: _scope);
      }
      final results = await SocialService.instance.search(q, scope: _scope);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        _hasSearched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
        _searchFailed = true;
        _hasSearched = true;
      });
    }
  }

  void _selectScope(String value) {
    _scope = value;
    final q = _searchCtrl.text.trim();
    if (q.isNotEmpty) {
      _runSearch(q);
    } else {
      setState(() {});
    }
  }

  void _applyHashtag(String tag) {
    final withHash = tag.startsWith('#') ? tag : '#$tag';
    _searchCtrl.text = withHash;
    _runSearch(withHash);
  }

  void _applyRecent(String term) {
    _searchCtrl.text = term;
    _runSearch(term);
  }

  Future<void> _clearRecents() async {
    try {
      await SocialService.instance.clearSearchHistory();
      if (mounted) setState(() => _recents = []);
    } catch (_) {
      // best effort
    }
  }

  void _openAuthor(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.discoverTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white70,
              size: 20,
            ),
            label: Text(
              l10n.close,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: _searchField(colors),
          ),
          _scopeStrip(),
          const SizedBox(height: 4),
          Expanded(child: _body(colors)),
        ],
      ),
    );
  }

  Widget _searchField(KlaykColors colors) {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchText,
      onSubmitted: (v) {
        final q = v.trim();
        if (q.isNotEmpty) _runSearch(q);
      },
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.searchEverythingHint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        suffixIcon: _searchCtrl.text.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchText('');
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

  Widget _scopeStrip() {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _kScopes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (context, i) {
          final value = _kScopes[i];
          return KlayKChip(
            label: _scopeLabel(l10n, value),
            selected: _scope == value,
            onTap: () => _selectScope(value),
          );
        },
      ),
    );
  }

  String _scopeLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'user':
        return l10n.searchScopePeople;
      case 'post':
        return l10n.videos;
      case 'hashtag':
        return l10n.searchScopeHashtags;
      case 'live':
        return l10n.searchScopeLives;
      default:
        return l10n.searchScopeAll;
    }
  }

  Widget _body(KlaykColors colors) {
    // Página inicial (vazio) mostra tendências + recentes.
    if (!_hasSearched && !_searching) {
      return _loadingHome
          ? const KlaykListSkeleton(rows: 6)
          : _homeFailed
          ? _errorState(colors)
          : _homeContent(colors);
    }

    // Modo de busca ativa.
    if (_searching) {
      return const KlaykListSkeleton(rows: 6);
    }
    if (_searchFailed) {
      return _errorState(colors);
    }
    if (_results.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.search_off_rounded,
        title: AppLocalizations.of(context)!.noResults,
        message: AppLocalizations.of(context)!.noResultsQuery(_query.trim()),
      );
    }
    return _resultsList(colors);
  }

  Widget _errorState(KlaykColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: Colors.white38,
              size: 40,
            ),
            const SizedBox(height: 14),
            Text(
              l10n.errorLoading,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.discoverLoadFail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.4),
            ),
            const SizedBox(height: 18),
            KlayKButton(
              label: l10n.retry,
              icon: Icons.refresh_rounded,
              onPressed: _hasSearched ? _retrySearch : _loadHome,
            ),
          ],
        ),
      ),
    );
  }

  void _retrySearch() {
    final q = _searchCtrl.text.trim();
    if (q.isNotEmpty) {
      _runSearch(q, record: false);
    } else {
      _loadHome();
    }
  }

  Widget _homeContent(KlaykColors colors) {
    final l10n = AppLocalizations.of(context)!;
    final hasRecents = _recents.isNotEmpty;
    final hasTrends = _trends.isNotEmpty;
    if (!hasRecents && !hasTrends) {
      return KlaykEmptyState(
        icon: Icons.explore_outlined,
        title: l10n.exploreStart,
        message: l10n.exploreStartBody,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (hasRecents) ...[
          _sectionHeader(l10n.recentSearches, onClear: _clearRecents),
          _recentsList(),
          const SizedBox(height: 18),
        ],
        if (hasTrends) ...[
          _sectionHeader(l10n.trendingNow, icon: Icons.trending_up_rounded),
          _trendsList(),
        ],
        if (_ads.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionHeader(l10n.advertisements, icon: Icons.campaign_rounded),
          const SizedBox(height: 10),
          ..._ads.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdCard(ad: a, onHidden: () => _removeAd(a.id)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.approvedAdsNote,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onClear, IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: _kAccent, size: 20),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        if (onClear != null)
          TextButton(
            onPressed: onClear,
            child: Text(
              AppLocalizations.of(context)!.clear,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _recentsList() {
    return Column(
      children: _recents.map((term) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.history_rounded,
            color: Colors.white38,
            size: 22,
          ),
          title: Text(
            term,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: const Icon(
            Icons.north_west_rounded,
            color: Colors.white24,
            size: 16,
          ),
          onTap: () => _applyRecent(term),
        );
      }).toList(),
    );
  }

  Widget _trendsList() {
    return Column(
      children: List.generate(_trends.length, (i) {
        final t = _trends[i];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 34,
            alignment: Alignment.center,
            child: Text(
              '${i + 1}',
              style: TextStyle(
                color: i < 3 ? _kAccent : Colors.white38,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '#${t.tag}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            AppLocalizations.of(context)!.hashtagPostCount(t.count),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          onTap: () => _applyHashtag(t.tag),
        );
      }),
    );
  }

  Widget _resultsList(KlaykColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _resultCard(_results[i]),
    );
  }

  Widget _resultCard(SearchResult r) {
    final IconData typeIcon = switch (r.type) {
      'user' => Icons.person_rounded,
      'post' => Icons.play_circle_outline_rounded,
      'hashtag' => Icons.tag_rounded,
      'live' => Icons.sensors_rounded,
      _ => Icons.search,
    };
    return KlayKCard(
      onTap: () {
        switch (r.type) {
          case 'user':
            _openAuthor(r.id);
            break;
          case 'hashtag':
            _applyHashtag(r.subtitle.isNotEmpty ? r.subtitle : r.title);
            break;
          default:
            break;
        }
      },
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1E1B2E),
            backgroundImage: r.avatarUrl != null && r.avatarUrl!.isNotEmpty
                ? NetworkImage(r.avatarUrl!)
                : null,
            child:
                (r.type == 'user' &&
                    (r.avatarUrl == null || r.avatarUrl!.isEmpty))
                ? const Icon(
                    Icons.person_rounded,
                    color: Color(0xFFB28DFF),
                    size: 20,
                  )
                : Icon(typeIcon, color: const Color(0xFFB28DFF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.subtitle.isEmpty ? r.type.toUpperCase() : '@${r.subtitle}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (r.isVerified) const SizedBox(width: 6),
          if (r.isVerified) const VerifiedBadge(size: 14),
        ],
      ),
    );
  }
}
