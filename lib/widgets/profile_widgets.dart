import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_profile.dart';
import 'verified_badge.dart';

const Color kProfileAccent = Color(0xFF8B5CF6);

/// Formata um número de forma compacta (estilo redes sociais).
String formatCount(int n) {
  if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1).replaceAll('.0', '')} bi';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')} mi';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')} mil';
  return '$n';
}

/// Cabeçalho de perfil reutilizável (cap, avatar, nome, bio e metadados).
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final List<Widget> actions;
  final VoidCallback? onNameTap;

  /// Quando `false`, remove a imagem/capa de fundo e sobe o conteúdo do
  /// perfil (perfil compacto). Padrão `true` preserva as outras telas.
  final bool showBanner;

  const ProfileHeader({
    super.key,
    required this.profile,
    this.actions = const [],
    this.onNameTap,
    this.showBanner = true,
  });

  Future<void> _openWebsite(BuildContext context) async {
    final url = profile.website;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBanner = profile.bannerUrl != null && profile.bannerUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------- Capa (opcional) ----------
        if (showBanner)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                SizedBox(
                  height: 170,
                  child: hasBanner
                      ? Image.network(
                          profile.bannerUrl!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => _bannerFallback(context),
                        )
                      : _bannerFallback(context),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ---------- Avatar / identidade ----------
        Transform.translate(
          offset: showBanner ? const Offset(0, -34) : Offset.zero,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, showBanner ? 0 : 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                    ),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(
                    child: profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty
                        ? Image.network(
                            profile.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatarFallback(),
                          )
                        : _avatarFallback(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                profile.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (profile.isFounder) ...[
                              const SizedBox(width: 5),
                              const FounderBadge(compact: true),
                            ] else if (profile.isVerified) ...[
                              const SizedBox(width: 5),
                              const VerifiedBadge(size: 19, color: kProfileAccent),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile.handle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        if (profile.isFounderOrAdmin) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (profile.isFounder) const FounderBadge(),
                              if (profile.isAdmin || profile.isFounder)
                                const AdminBadge(),
                              if (profile.isFounder || profile.isVerified)
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    VerifiedBadge(size: 16),
                                    SizedBox(width: 4),
                                    Text('Conta verificada oficialmente',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11)),
                                  ],
                                ),
                            ],
                          ),
                        ],
                        if ((profile.profession ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.work_outline,
                                  color: Colors.white38, size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  profile.profession!,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ---------- Ações ----------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (actions.isNotEmpty) ...[
                Row(children: actions),
                const SizedBox(height: 12),
              ],
              if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                Text(
                  profile.bio!.trim(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _metaRow(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaRow(BuildContext context) {
    final parts = <InlineSpan>[];

    if (profile.location != null && profile.location!.trim().isNotEmpty) {
      parts.add(_metaItem(Icons.place_outlined, profile.location!.trim()));
    }
    if (profile.pronouns != null && profile.pronouns!.trim().isNotEmpty) {
      parts.add(_metaItem(Icons.tag, profile.pronouns!.trim()));
    }
    if (profile.website != null && profile.website!.trim().isNotEmpty) {
      parts.add(_metaItem(
        Icons.link,
        'Link direto',
        onTap: () => _openWebsite(context),
        accent: true,
      ));
    }

    if (parts.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: parts),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
    );
  }

  WidgetSpan _metaItem(
    IconData icon,
    String text, {
    VoidCallback? onTap,
    bool accent = false,
  }) {
    return WidgetSpan(
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: accent ? kProfileAccent : Colors.white38, size: 15),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent ? kProfileAccent : Colors.white70,
                  fontSize: 13,
                  fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
                  decoration: accent ? TextDecoration.underline : null,
                  decorationColor: accent ? kProfileAccent : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerFallback(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3B2A63),
            Color(0xFF1E1B2E),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.palette_outlined,
            color: Colors.white12, size: 46),
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFF2A2740),
      child: const Icon(Icons.person, color: Colors.white54, size: 34),
    );
  }
}

/// Linha de métricas do perfil (Seguidores / Seguindo / Vídeos / Curtidas).
/// Seguidores e Seguindo são clicáveis.
class ProfileStats extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  const ProfileStats({
    super.key,
    required this.profile,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              context,
              formatCount(profile.followersCount),
              'Seguidores',
              onTap: onFollowersTap,
              highlighted: onFollowersTap != null,
            ),
          ),
          _verticalDivider(),
          Expanded(
            child: _stat(
              context,
              formatCount(profile.followingCount),
              'Seguindo',
              onTap: onFollowingTap,
              highlighted: onFollowingTap != null,
            ),
          ),
          _verticalDivider(),
          Expanded(
            child: _stat(
              context,
              formatCount(profile.postsCount),
              'Vídeos',
              onTap: null,
              highlighted: false,
            ),
          ),
          _verticalDivider(),
          Expanded(
            child: _stat(
              context,
              formatCount(profile.totalLikes),
              'Curtidas',
              onTap: null,
              highlighted: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() => Container(
        width: 1,
        height: 30,
        color: Colors.white10,
      );

  Widget _stat(
    BuildContext context,
    String value,
    String label, {
    required VoidCallback? onTap,
    required bool highlighted,
  }) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlighted ? Colors.white : Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: highlighted ? Colors.white60 : Colors.white38,
            fontSize: 11,
          ),
        ),
      ],
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}

/// Botão de ação principal do perfil (Seguir / Seguindo / Editar perfil).
class ProfileActionButton extends StatelessWidget {
  final bool isSelf;
  final bool isFollowing;
  final bool busy;
  final VoidCallback? onPressed;

  const ProfileActionButton({
    super.key,
    required this.isSelf,
    required this.isFollowing,
    this.busy = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isSelf) {
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF3A3550)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Editar perfil'),
        ),
      );
    }
    return Expanded(
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isFollowing
              ? const Color(0xFF242233)
              : kProfileAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                isFollowing ? 'Seguindo' : 'Seguir',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}