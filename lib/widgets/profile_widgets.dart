import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../services/link_guard_service.dart';
import 'verified_badge.dart';

const Color kProfileAccent = Color(0xFF8B5CF6);

/// Formata um número de forma compacta (estilo redes sociais), respeitando
/// o idioma ativo (ex.: 1,2 mi em pt · 1.2K em en).
String formatCount(BuildContext context, int n) {
  final l10n = AppLocalizations.of(context)!;
  return NumberFormat.compact(locale: l10n.localeName).format(n);
}

/// Cabeçalho de perfil reutilizável — layout moderno centralizado:
/// avatar circular com borda roxa, @username, nome de exibição, badges,
/// bio, metadados e ações. Segue a ordem: avatar → @username → nome →
/// bio → ação principal → stats.
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final List<Widget> actions;
  final VoidCallback? onNameTap;

  /// Quando `true`, exibe a capa (banner) acima do avatar. O perfil moderno
  /// por padrão é limpo (sem capa) — quem quiser a capa ativa explicitamente.
  final bool showBanner;

  const ProfileHeader({
    super.key,
    required this.profile,
    this.actions = const [],
    this.onNameTap,
    this.showBanner = false,
  });

  Future<void> _openWebsite(BuildContext context) async {
    final url = profile.website;
    if (url == null || url.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final opened = await LinkGuard.instance.openExternal(context, url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.linkOpenFail)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasBanner =
        showBanner &&
        profile.bannerUrl != null &&
        profile.bannerUrl!.isNotEmpty;

    // Mostra o nome de exibição apenas quando ele difere do @username.
    final showDisplayName =
        profile.displayName != null &&
        profile.displayName!.trim().isNotEmpty &&
        profile.displayName!.trim() != (profile.username ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------- Capa (opcional) ----------
        if (hasBanner)
          ClipRRect(
            borderRadius: BorderRadius.circular(0),
            child: SizedBox(
              height: 140,
              child: Image.network(
                profile.bannerUrl!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _bannerFallback(context),
              ),
            ),
          ),

        Padding(
          padding: EdgeInsets.fromLTRB(20, hasBanner ? 18 : 26, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------- Avatar (centralizado, borda roxa + glow) ----------
              Center(child: _avatar(context)),
              const SizedBox(height: 14),

              // ---------- @username ----------
              Semantics(
                header: true,
                child: GestureDetector(
                  onTap: onNameTap,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          profile.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!profile.isFounderOrAdmin &&
                          profile.hasVerifiedBadge) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(size: 18, color: kProfileAccent),
                      ],
                    ],
                  ),
                ),
              ),

              // ---------- Nome de exibição ----------
              if (showDisplayName) ...[
                const SizedBox(height: 4),
                Text(
                  profile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13.5),
                ),
              ],

              // ---------- Badges (fundador / admin / verificado) ----------
              if (profile.isFounderOrAdmin) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (profile.isFounder) const FounderBadge(),
                    if (profile.isAdmin || profile.isFounder)
                      const AdminBadge(),
                    if (profile.isFounder || profile.isVerified)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const VerifiedBadge(size: 15),
                          const SizedBox(width: 4),
                          Text(
                            l10n.verifiedAccountNote,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],

              // ---------- Profissão ----------
              if ((profile.profession ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.work_outline,
                      color: Colors.white38,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        profile.profession!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // ---------- Bio ----------
              if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  profile.bio!.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],

              // ---------- Metadados (local / pronomes / link) ----------
              ..._metaRow(context),

              // ---------- Ações principais ----------
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(children: actions),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasAvatar =
        profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    return Semantics(
      label: l10n.profilePhoto,
      image: true,
      child: Container(
        width: 96,
        height: 96,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB794FF), Color(0xFF6D28D9)],
          ),
          boxShadow: [
            BoxShadow(
              color: kProfileAccent.withValues(alpha: 0.32),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipOval(
          child: hasAvatar
              ? Image.network(
                  profile.avatarUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _avatarFallback(),
                )
              : _avatarFallback(),
        ),
      ),
    );
  }

  List<Widget> _metaRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <Widget>[];

    if (profile.location != null && profile.location!.trim().isNotEmpty) {
      parts.add(_metaItem(Icons.place_outlined, profile.location!.trim()));
    }
    if (profile.pronouns != null && profile.pronouns!.trim().isNotEmpty) {
      parts.add(_metaItem(Icons.tag, profile.pronouns!.trim()));
    }
    if (profile.website != null && profile.website!.trim().isNotEmpty) {
      parts.add(
        _metaItem(
          Icons.link,
          l10n.directLink,
          onTap: () => _openWebsite(context),
          accent: true,
        ),
      );
    }

    if (parts.isEmpty) return const [];
    return <Widget>[
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 6,
        children: parts,
      ),
    ];
  }

  Widget _metaItem(
    IconData icon,
    String text, {
    VoidCallback? onTap,
    bool accent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent ? kProfileAccent : Colors.white38, size: 15),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              text,
              maxLines: 1,
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
    );
  }

  Widget _bannerFallback(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2A63), Color(0xFF1E1B2E)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.palette_outlined, color: Colors.white12, size: 46),
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFF2A2740),
      child: const Icon(Icons.person, color: Colors.white54, size: 40),
    );
  }
}

/// Linha de métricas compacta do perfil: Seguidores / Seguindo / Curtidas.
/// Seguidores e Seguindo ficam clicáveis (listas reais) com destaque em roxo.
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
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _stat(
            context,
            formatCount(context, profile.followersCount),
            l10n.followers,
            onTap: onFollowersTap,
          ),
          _stat(
            context,
            formatCount(context, profile.followingCount),
            l10n.following,
            onTap: onFollowingTap,
          ),
          _stat(
            context,
            formatCount(context, profile.totalLikes),
            l10n.likesLabel,
            onTap: null,
          ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String value,
    String label, {
    required VoidCallback? onTap,
  }) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: onTap != null ? kProfileAccent : Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: onTap != null ? Colors.white60 : Colors.white54,
            fontSize: 11.5,
          ),
        ),
      ],
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        child: child,
      ),
    );
  }
}

/// Botão de ação principal do perfil (Seguir / Seguindo / Editar perfil).
/// Preserva a mesma API — apenas a aparência foi reformulada.
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
    final l10n = AppLocalizations.of(context)!;
    if (isSelf) {
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF2A2540)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: Text(l10n.editProfile),
        ),
      );
    }
    return Expanded(
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isFollowing
              ? const Color(0xFF241F33)
              : kProfileAccent,
          foregroundColor: Colors.white,
          side: isFollowing ? const BorderSide(color: Color(0xFF4C3F7A)) : null,
          elevation: isFollowing ? 0 : 4,
          shadowColor: kProfileAccent.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                isFollowing
                    ? Icons.check_rounded
                    : Icons.person_add_alt_1_rounded,
                size: 19,
              ),
        label: Text(
          isFollowing ? l10n.following : l10n.follow,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
