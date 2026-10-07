import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/rising_creator_models.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import 'profile/user_profile_screen.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Criadores em Ascensão do KLAY K: ranking de criadores com maior momentum
/// (não magnitude) nos últimos 7 dias, derivado de dados reais do backend.
class RisingCreatorsScreen extends StatefulWidget {
  const RisingCreatorsScreen({super.key});

  @override
  State<RisingCreatorsScreen> createState() => _RisingCreatorsScreenState();
}

class _RisingCreatorsScreenState extends State<RisingCreatorsScreen> {
  List<RisingCreator> _creators = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      if (!SupabaseService.instance.isConfigured) {
        throw Exception('Supabase não configurado');
      }
      final creators = await SocialService.instance.fetchRisingCreators();
      if (!mounted) return;
      setState(() {
        _creators = creators;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _openCreator(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.risingCreatorsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: l10n.risingCreatorsRefresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: _loading ? const KlaykListSkeleton(rows: 6) : _buildBody(),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_loadFailed) {
      return KlaykEmptyState(
        icon: Icons.cloud_off_outlined,
        title: l10n.playlistsLoadFailTitle,
        message: l10n.risingCreatorsLoadFailMsg,
        actionLabel: l10n.retry,
        actionIcon: Icons.refresh_rounded,
        onAction: _load,
      );
    }
    if (_creators.isEmpty) {
      return KlaykEmptyState(
        icon: Icons.trending_up_rounded,
        title: l10n.risingCreatorsEmptyTitle,
        message: l10n.risingCreatorsEmptyMsg,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _creators.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _creatorCard(_creators[i], i + 1),
      ),
    );
  }

  Widget _creatorCard(RisingCreator c, int rank) {
    final l10n = AppLocalizations.of(context)!;
    final colors = kc(context);
    return KlayKCard(
      onTap: () => _openCreator(c.creatorId),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rank <= 3 ? _kAccent : const Color(0xFF2A2350),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          KlayKAvatar(imageUrl: c.avatarUrl, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (c.isVerified) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified_rounded,
                        color: _kAccent,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                if (c.handle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    c.handle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2350),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.momentumLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                Icons.trending_up_rounded,
                color: colors.primarySoft,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.risingCreatorsLast7Days,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
