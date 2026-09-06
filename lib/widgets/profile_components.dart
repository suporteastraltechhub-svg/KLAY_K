import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/post_models.dart';
import '../models/user_profile.dart';
import '../screens/profile/video_preview_screen.dart';
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
    final items = <Widget>[
      _roundButton(context, Icons.arrow_back_rounded, 'Voltar', onBack),
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
        _roundButton(context, Icons.ios_share_rounded, 'Compartilhar', onShare),
      if (onMenu != null)
        _roundButton(context, Icons.more_vert_rounded, 'Mais opções', onMenu),
    ];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12) +
            const EdgeInsets.only(top: 8),
        child: Row(children: items),
      ),
    );
  }

  Widget _roundButton(BuildContext context, IconData icon, String label,
      VoidCallback? onTap) {
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
                        style:
                            TextStyle(color: colors.primarySoft, fontSize: 13),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stat(context, 'Seguidores', followers),
        const SizedBox(width: 22),
        _stat(context, 'Seguindo', following),
        const SizedBox(width: 22),
        _stat(context, 'Curtidas', likes),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatCount(value),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: KlayKButton(
              icon: following ? Icons.check_rounded : Icons.person_add_rounded,
              label: following ? 'Seguindo' : 'Seguir',
              onPressed: onFollow,
            ),
          ),
          const SizedBox(width: 10),
          if (onMessage != null)
            Expanded(
              flex: 3,
              child: KlayKSecondaryButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Mensagem',
                onPressed: onMessage,
              ),
            ),
          const SizedBox(width: 10),
          if (onShare != null)
            Expanded(
              flex: 3,
              child: KlayKSecondaryButton(
                icon: Icons.ios_share_rounded,
                label: 'Compartilhar',
                onPressed: onShare,
              ),
            ),
        ],
      ),
    );
  }
}

/// Abas do perfil (Vídeos / Curtidos / Salvos). A aba selecionada ganha
/// destaque roxo neon — identificável também por ícone (não só cor).
class KlaykProfileTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const KlaykProfileTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const List<(IconData, String)> _tabs = [
    (Icons.videocam_rounded, 'Vídeos'),
    (Icons.favorite_border_rounded, 'Curtidos'),
    (Icons.bookmark_border_rounded, 'Salvos'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = kc(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final sel = selected == i;
          return Expanded(
            child: Semantics(
              selected: sel,
              button: true,
              label: _tabs[i].$2,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  decoration: BoxDecoration(
                    color: sel
                        ? colors.primary.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: sel
                        ? Border.all(color: colors.primary.withValues(alpha: 0.6))
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _tabs[i].$1,
                        size: 17,
                        color: sel ? colors.primarySoft : Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _tabs[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Grade de vídeos reais do usuário (abre a prévia de reprodução).
class KlaykProfileVideoGrid extends StatelessWidget {
  final List<FeedPost> videos;
  final VoidCallback? onEmpty;

  const KlaykProfileVideoGrid({super.key, required this.videos, this.onEmpty});

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white38, size: 40),
            const SizedBox(height: 10),
            const Text(
              'Nenhum vídeo publicado ainda',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            if (onEmpty != null) ...[
              const SizedBox(height: 14),
              KlayKButton(label: 'Criar vídeo', onPressed: onEmpty),
            ],
          ],
        ),
      );
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width >= 430 ? 3 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final post = videos[index];
        final hasCover = post.coverUrl != null && post.coverUrl!.isNotEmpty;
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VideoPreviewScreen(post: post),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: kc(context).surfaceAlt,
              child: !hasCover
                  ? const Icon(Icons.play_circle_fill_rounded,
                      color: Color(0xFF8B5CF6), size: 36)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          post.coverUrl!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 36,
                          ),
                        ),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 38,
                            shadows: [Shadow(blurRadius: 12)],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}