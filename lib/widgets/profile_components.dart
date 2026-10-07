import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
import '../models/post_models.dart';
import '../models/user_profile.dart';
import '../screens/profile/video_preview_screen.dart';
import 'klayk_ux.dart';
import 'profile_widgets.dart';
import 'verified_badge.dart';

/// ============================================================================
/// KLAY K — Componentes prontos para a ETAPA 2 do Perfil (rede social).
///
/// Não alteram a tela atual: são blocos reutilizáveis, orientados a dados
/// reais (UserProfile / FeedPost) e à identidade visual premium do KLAY K.
/// Os cards administrativos (Carteira, Conquistas, Missões...) continuarão
/// aninhados dentro de "Meu KLAY K" na próxima etapa, fora daqui.
/// ============================================================================

/// Barra de ações do topo do perfil: voltar + compartilhar + menu (⋮).
///
/// Componentes são opcionais (onShare/onMenu nulos ocultam o item), feito
/// para telas estreitas (360px) sem overflow: usa [Flexible] no título.
class KlaykProfileTopBar extends StatelessWidget {
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onMenu;

  const KlaykProfileTopBar({
    super.key,
    this.title,
    this.onBack,
    this.onShare,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = <Widget>[
      _roundButton(context, Icons.arrow_back_rounded, l10n.back, onBack),
      const Spacer(),
      if (title != null)
        Flexible(
          child: Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      const Spacer(),
      if (onShare != null)
        _roundButton(context, Icons.ios_share_rounded, l10n.share, onShare),
      if (onMenu != null)
        _roundButton(
          context,
          Icons.more_vert_rounded,
          l10n.moreOptionsTooltip,
          onMenu,
        ),
    ];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12) +
            const EdgeInsets.only(top: 8),
        child: Row(children: items),
      ),
    );
  }

  Widget _roundButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) {
    return Semantics(
      label: label,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kc(context).surface.withValues(alpha: 0.8),
            border: Border.all(color: kc(context).border),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Cabeçalho do perfil: avatar + nome + @username + selo + bio + links reais.
/// Organizado para caber em 360px (avatar reduz, linhas com ellipsis).
class KlaykProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final int followers;
  final int following;
  final int likes;

  const KlaykProfileHeader({
    super.key,
    required this.profile,
    this.followers = 0,
    this.following = 0,
    this.likes = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KlayKAvatar(imageUrl: '', size: 92, following: false),
              const SizedBox(width: 28),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (profile.isVerified) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge(size: 17),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        profile.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.primarySoft,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      KlaykProfileStatsRow(
                        followers: followers,
                        following: following,
                        likes: likes,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              profile.bio!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (profile.website != null && profile.website!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              profile.website!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: colors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Linha de estatísticas do perfil (Seguidores / Seguindo / Curtidas).
/// Números vêm de dados reais (nunca inventados).
class KlaykProfileStatsRow extends StatelessWidget {
  final int followers;
  final int following;
  final int likes;

  const KlaykProfileStatsRow({
    super.key,
    required this.followers,
    required this.following,
    required this.likes,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stat(context, l10n.followers, followers),
        const SizedBox(width: 22),
        _stat(context, l10n.following, following),
        const SizedBox(width: 22),
        _stat(context, l10n.likesLabel, likes),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatCount(context, value),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

/// Ações principais do perfil: Seguir (estado real) / Mensagem / Compartilhar.
/// Botões responsivos: linhas encolhem com Expanded em telas estreitas.
class KlaykProfileActionsRow extends StatelessWidget {
  final bool following;
  final VoidCallback? onFollow;
  final VoidCallback? onMessage;
  final VoidCallback? onShare;

  const KlaykProfileActionsRow({
    super.key,
    required this.following,
    this.onFollow,
    this.onMessage,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: KlayKButton(
              icon: following ? Icons.check_rounded : Icons.person_add_rounded,
              label: following ? l10n.following : l10n.follow,
              onPressed: onFollow,
            ),
          ),
          const SizedBox(width: 10),
          if (onMessage != null)
            Expanded(
              flex: 3,
              child: KlayKSecondaryButton(
                icon: Icons.chat_bubble_rounded,
                label: l10n.messageAction,
                onPressed: onMessage,
              ),
            ),
          const SizedBox(width: 10),
          if (onShare != null)
            Expanded(
              flex: 3,
              child: KlayKSecondaryButton(
                icon: Icons.ios_share_rounded,
                label: l10n.share,
                onPressed: onShare,
              ),
            ),
        ],
      ),
    );
  }
}

/// Abas do perfil (Vídeos / Curtidos / Salvos). A aba selecionada ganha um
/// indicador roxo neon deslizante abaixo do texto, animado com
/// [AnimatedAlign] — identificável também por ícone e cor (não só cor).
class KlaykProfileTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const KlaykProfileTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = kc(context);
    final tabs = <(IconData, String)>[
      (Icons.videocam_rounded, l10n.videos),
      (Icons.favorite_border_rounded, l10n.likedVideos),
      (Icons.bookmark_border_rounded, l10n.savedVideos),
    ];
    final n = tabs.length;
    final selectedX = selected * 2 / (n - 1) - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / n;
          return SizedBox(
            height: 52,
            child: Stack(
              children: [
                // Indicador roxo deslizante.
                AnimatedAlign(
                  alignment: Alignment(selectedX, 1),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: itemWidth * 0.42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.45),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(n, (i) {
                    final sel = selected == i;
                    final color = sel ? colors.primarySoft : Colors.white54;
                    return Expanded(
                      child: Semantics(
                        selected: sel,
                        button: true,
                        label: tabs[i].$2,
                        child: InkWell(
                          onTap: () => onChanged(i),
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(tabs[i].$1, size: 19, color: color),
                              const SizedBox(height: 4),
                              Text(
                                tabs[i].$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: sel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: sel ? Colors.white : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tile de vídeo do perfil: miniatura REAL via `cover_url` (nunca gradiente
/// fake), placeholder neutro grafite enquanto carrega/erro, indicador de
/// reprodução discreto e abertura da prévia existente ([VideoPreviewScreen]).
class KlaykProfileVideoTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback? onDeleted;

  const KlaykProfileVideoTile({super.key, required this.post, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    final hasCover = post.coverUrl != null && post.coverUrl!.isNotEmpty;
    return GestureDetector(
      onTap: () async {
        final deleted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => VideoPreviewScreen(post: post)),
        );
        if (deleted == true) onDeleted?.call();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.surfaceAlt),
            if (hasCover)
              Image.network(
                post.coverUrl!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: imageDecodeWidth(context, 140),
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : _placeholder(context, loading: true),
                errorBuilder: (_, __, ___) =>
                    _placeholder(context, loading: false),
              )
            else
              _placeholder(context, loading: false),
            // Indicador de reprodução discreto.
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Placeholder neutro (grafite) com loading discreto ou ícone de vídeo —
  /// usado para carregando, erro de imagem e posts sem capa. Uma falha de
  /// imagem NUNCA quebra a grade.
  Widget _placeholder(BuildContext context, {required bool loading}) {
    final colors = kc(context);
    return ColoredBox(
      color: colors.surfaceAlt,
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white24,
                ),
              )
            : const Icon(
                Icons.videocam_outlined,
                color: Colors.white24,
                size: 24,
              ),
      ),
    );
  }
}

/// Grade de vídeos reais do usuário (abre a prévia de reprodução).
/// Grid fixo de 3 colunas com proporção vertical e miniatura real via
/// `cover_url` ([KlaykProfileVideoTile]).
class KlaykProfileVideoGrid extends StatelessWidget {
  final List<FeedPost> videos;
  final VoidCallback? onEmpty;
  final VoidCallback? onDeleted;

  const KlaykProfileVideoGrid({
    super.key,
    required this.videos,
    this.onEmpty,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
        child: Column(
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white38,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.noVideosYet,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.noVideosYetBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            if (onEmpty != null) ...[
              const SizedBox(height: 16),
              KlayKButton(
                icon: Icons.add_rounded,
                label: l10n.createVideo,
                onPressed: onEmpty,
              ),
            ],
          ],
        ),
      );
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) =>
          KlaykProfileVideoTile(post: videos[index], onDeleted: onDeleted),
    );
  }
}
