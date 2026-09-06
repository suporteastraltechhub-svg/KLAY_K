import 'package:flutter/material.dart';

/// Componentes reutilizáveis da Central de Lives do KLAY K.
///
/// Mantêm a identidade visual escura/premium (preto profundo, grafite, roxo
/// neon) e são usados em [lib/screens/...] tanto na aba dentro do feed quanto
/// em telas dedicadas da Central de Lives.

const Color kkLiveBg = Color(0xFF0E0C16);
const Color kkLiveSurface = Color(0xFF17141F);
const Color kkLiveCard = Color(0xFF1B1A26);
const Color kkLiveBorder = Color(0xFF2A2540);
const Color kkLivePurple = Color(0xFF8B5CF6);
const Color kkLiveMagenta = Color(0xFFEC4899);
const Color kkLiveRed = Color(0xFFFF2E4D);

/// Um dos cinco formatos de Live da Central.
class LiveFormat {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;

  const LiveFormat({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });
}

/// Card de um formato de Live (Vídeo/Áudio/Amigos/Filmes/Jogos).
class LiveTypeCard extends StatelessWidget {
  final LiveFormat format;
  final VoidCallback onTap;

  const LiveTypeCard({
    super.key,
    required this.format,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: format.title,
      child: _PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                format.accent.withValues(alpha: 0.22),
                kkLiveCard,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: format.accent.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: format.accent.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: format.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: format.accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Icon(format.icon, color: format.accent, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                format.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                format.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card compacto de uma live ao vivo (real) para as seções "Ao vivo agora" e
/// "Em alta".
class LiveNowCard extends StatelessWidget {
  final String coverUrl;
  final bool hasCover;
  final String title;
  final String streamerName;
  final int viewers;
  final String category;
  final bool verified;
  final VoidCallback onTap;

  const LiveNowCard({
    super.key,
    this.coverUrl = '',
    this.hasCover = false,
    required this.title,
    required this.streamerName,
    required this.viewers,
    required this.category,
    this.verified = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGame = category.toLowerCase().contains('jogo');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF251A45), Color(0xFF14142B)],
          ),
          border: Border.all(color: kkLivePurple.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: kkLivePurple.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (hasCover && coverUrl.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (hasCover && coverUrl.isNotEmpty)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kkLivePurple.withValues(alpha: 0.16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kkLiveRed,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: kkLiveRed.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 7),
                            SizedBox(width: 4),
                            Text('AO VIVO',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isGame
                            ? Icons.sports_esports_rounded
                            : Icons.videocam_rounded,
                        color: kkLivePurple,
                        size: 18,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.remove_red_eye_rounded,
                            color: Colors.white70, size: 13),
                        const SizedBox(width: 4),
                        Text('$viewers',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.person_rounded,
                          color: Colors.white54, size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          streamerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            color: kkLivePurple, size: 13),
                      ],
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

/// Nome sugerido no destaque "🔥 Em alta" (reuso de card de live).
class TrendingLiveCard extends StatelessWidget {
  final String title;
  final String meta;
  final int viewers;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const TrendingLiveCard({
    super.key,
    required this.title,
    required this.meta,
    required this.viewers,
    this.icon = Icons.local_fire_department_rounded,
    this.accent = kkLivePurple,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.20), kkLiveCard],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 22),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.remove_red_eye_rounded,
                          color: Colors.white70, size: 12),
                      const SizedBox(width: 3),
                      Text('$viewers',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de categoria para "Explorar Lives".
class LiveCategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const LiveCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? kkLivePurple.withValues(alpha: 0.85)
                : kkLiveCard,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? kkLivePurple : kkLiveBorder,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: kkLivePurple.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Título de seção com ênfase.
class LiveSectionTitle extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? accent;

  const LiveSectionTitle({
    super.key,
    required this.label,
    this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final col = accent ?? kkLivePurple;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: col, size: 18),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
            shadows: [Shadow(color: col.withValues(alpha: 0.5), blurRadius: 12)],
          ),
        ),
      ],
    );
  }
}

/// Envolve conteúdo com um leve feedback de escala ao tocar (sem bloquear o
/// gesto de scroll do progenitor).
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressableScale({required this.child, required this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}