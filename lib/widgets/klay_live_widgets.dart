import 'package:flutter/material.dart';

import '../design/klayk_design.dart';
import '../models/gift_models.dart';
import '../models/message_models.dart';
import '../models/post_models.dart';
import '../services/gift_service.dart';
import 'verified_badge.dart';

/// ============================================================================
/// KLAY K — Componentes da Experiência de Live + Mensagens
///
/// Identidade visual do redesign: fundo preto `#000000`, superfícies grafite
/// `#111/#171/#1D`, roxo de marca `#8B5CF6` e acento `#A78BFA`. Roxo aparece
/// SOMENTE em botões, indicadores, badges, seleção e detalhes — nunca como cor
/// dominante da interface.
///
/// Todos os componentes aqui consuem DADOS REAIS do backend (presentes,
/// conversas, notificações, espectadores). Nenhum dado é inventado.
/// ============================================================================

const Color kkBg = Color(0xFF000000);
const Color kkSurface = Color(0xFF171717);
const Color kkSurfaceAlt = Color(0xFF1D1D1D);
const Color kkNeon = Color(0xFF8B5CF6);
const Color kkAccent = Color(0xFF8B5CF6);
const Color kkLiveRed = Color(0xFFFF2E4D);
const Color kkTextSecondary = Color(0xFF9CA3AF);

/// ---------------------------------------------------------------------------
/// BOTTOM SHEET PADRÃO DA LIVE
/// ---------------------------------------------------------------------------

/// Wrapper das bottom sheets da experiência de Live: superfície `#161616`,
/// topo arredondado 22 e drag-handle. Reaproveitada por presentes, "mais" e
/// anúncios — evita repetir estilo em cada sheet.
class KlayLiveBottomSheet {
  KlayLiveBottomSheet._();

  static Future<T?> show<T>(BuildContext context, {required Widget child}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(child: child),
    );
  }

  static Widget handle() => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// ---------------------------------------------------------------------------
/// TOPO DA LIVE
/// ---------------------------------------------------------------------------

/// Avatar miniatura com fallback do KLAY K (inicial quando não há foto).
class _KlayMiniAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initial;
  final double size;

  const _KlayMiniAvatar({
    required this.imageUrl,
    required this.initial,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kkSurfaceAlt,
        border: Border.all(color: Colors.black87, width: 1.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
    child: Text(
      initial.isEmpty ? 'K' : initial.characters.first.toUpperCase(),
      style: TextStyle(
        color: Colors.white70,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Cabeçalho da sala: fechar, pill AO VIVO, contador real de espectadores com
/// avatares sobrepostos (host real + convidados reais do LiveKit), categoria
/// real e botão "mais" (abre [KlayMoreSheet]).
class KlayLiveHeader extends StatelessWidget {
  final int viewers;
  final String? hostAvatar;
  final List<String> participants;
  final String category;
  final VoidCallback onClose;
  final VoidCallback onMore;
  final bool showFullscreen;
  final VoidCallback? onFullscreen;

  const KlayLiveHeader({
    super.key,
    required this.viewers,
    this.hostAvatar,
    this.participants = const [],
    this.category = '',
    required this.onClose,
    required this.onMore,
    this.showFullscreen = false,
    this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        KlayKIconButton(
          icon: Icons.close_rounded,
          onTap: onClose,
          color: Colors.white,
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: kkLiveRed,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: kkLiveRed.withValues(alpha: 0.25),
                blurRadius: 6,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: Colors.white, size: 8),
              SizedBox(width: 4),
              Text(
                'AO VIVO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: _viewerPill()),
        if (category.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kkAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kkAccent.withValues(alpha: 0.35)),
              ),
              child: Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
        const SizedBox(width: 4),
        if (showFullscreen && onFullscreen != null)
          KlayKIconButton(
            icon: Icons.fullscreen_rounded,
            onTap: onFullscreen,
            color: Colors.white,
          ),
        const SizedBox(width: 4),
        KlayKIconButton(
          icon: Icons.more_horiz_rounded,
          onTap: onMore,
          color: Colors.white,
        ),
      ],
    );
  }

  Widget _viewerPill() {
    final avatars = <Widget>[
      if (hostAvatar != null && hostAvatar!.isNotEmpty)
        _KlayMiniAvatar(imageUrl: hostAvatar, initial: 'K', size: 22),
      for (final p in participants.take(2))
        _KlayMiniAvatar(imageUrl: null, initial: p, size: 22),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (avatars.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < avatars.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i == avatars.length - 1 ? 6 : 0,
                    ),
                    child: Transform.translate(
                      offset: Offset(-(i * 7.0), 0),
                      child: avatars[i],
                    ),
                  ),
              ],
            )
          else
            const Icon(Icons.group_rounded, color: Colors.white, size: 15),
          Text(
            viewers == 1 ? '1 espectador' : '$viewers espectadores',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// AÇÕES LATERAIS DA LIVE
/// ---------------------------------------------------------------------------

/// Botão circular translúcido com rótulo (curtir, comentar, presente, top...).
/// Sempre ligado a uma função real da sala.
class KlayLiveActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color activeColor;
  final bool active;

  const KlayLiveActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = Colors.white,
    this.activeColor = kkAccent,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? activeColor : color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.5),
                border: Border.all(
                  color: active ? c.withValues(alpha: 0.6) : Colors.white24,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: c.withValues(alpha: 0.25),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: c, size: 24),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// SHEET "MAIS"
/// ---------------------------------------------------------------------------

class KlayMoreItem {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;

  const KlayMoreItem({
    required this.label,
    this.icon,
    this.color = Colors.white,
    this.onTap,
  });
}

class KlayMoreToggle {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const KlayMoreToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
}

/// Menu "mais" da live: itens de ação reais (compartilhar, denunciar,
/// configurar...) + interruptores (efeitos, som, imagem...). Nada aqui é
/// decorativo — cada linha executa uma função real da sala.
class KlayMoreSheet {
  KlayMoreSheet._();

  static Future<void> show(
    BuildContext context, {
    required List<KlayMoreItem> items,
    List<KlayMoreToggle> toggles = const [],
  }) {
    final shown = <bool>[...toggles.map((t) => t.value)];
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: kkSurface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.86,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KlayLiveBottomSheet.handle(),
                  const SizedBox(height: 8),
                  for (final item in items) _row(ctx, item),
                  if (toggles.isNotEmpty) ...[
                    const Divider(color: Color(0x14FFFFFF), height: 1),
                    for (var i = 0; i < toggles.length; i++)
                      SwitchListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        activeThumbColor: kkAccent,
                        activeTrackColor: kkAccent.withValues(alpha: 0.35),
                        title: Text(
                          toggles[i].label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        value: shown[i],
                        onChanged: (v) {
                          setSheetState(() => shown[i] = v);
                          toggles[i].onChanged(v);
                        },
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _row(BuildContext ctx, KlayMoreItem item) {
    return InkWell(
      onTap: () {
        Navigator.of(ctx).pop();
        item.onTap?.call();
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            if (item.icon != null)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (item.color).withValues(alpha: 0.14),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
            if (item.icon != null) const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: item.color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white30,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// PAINEL DE PRESENTES (REAIS)
/// ---------------------------------------------------------------------------

class KlayGiftPick {
  final Gift gift;
  final int amount;

  const KlayGiftPick(this.gift, this.amount);
}

/// Seletor de presentes reais da live: categorias reais (`gift_categories`),
/// grade com paginação real, saldo real (💎) e envio pelo fluxo seguro
/// existente (Edge Function `send-gift` — nada de moeda fictícia).
class KlayGiftSheet extends StatefulWidget {
  final int wallet;
  final Future<int> Function() onRefreshWallet;

  const KlayGiftSheet({
    super.key,
    required this.wallet,
    required this.onRefreshWallet,
  });

  static Future<KlayGiftPick?> show(
    BuildContext context, {
    required int wallet,
    required Future<int> Function() onRefreshWallet,
  }) {
    return KlayLiveBottomSheet.show<KlayGiftPick>(
      context,
      child: KlayGiftSheet(wallet: wallet, onRefreshWallet: onRefreshWallet),
    );
  }

  @override
  State<KlayGiftSheet> createState() => _KlayGiftSheetState();
}

class _KlayGiftSheetState extends State<KlayGiftSheet> {
  final List<GiftCategory> _categories = [];
  final List<Gift> _items = [];
  final _scroll = ScrollController();
  late int _wallet;
  String? _catId;
  Gift? _selected;
  int _amount = 1;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _refreshingWallet = false;
  String? _error;

  static const _pageSize = 40;
  static const _amounts = [1, 5, 10, 66, 99];

  @override
  void initState() {
    super.initState();
    _wallet = widget.wallet;
    _scroll.addListener(_onScroll);
    _loadCategories();
    _loadGifts(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240 &&
        _hasMore) {
      _loadGifts(reset: false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final list = await GiftService.instance.fetchCategories();
      if (!mounted) return;
      setState(() => _categories.addAll(list));
    } catch (_) {
      // Sem backend: a aba "Todos" continua funcionando (estado honesto).
    }
  }

  Future<void> _loadGifts({required bool reset}) async {
    if (_loadingMore) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      setState(() {
        _items.clear();
        _loading = true;
        _error = null;
      });
    } else {
      _page += 1;
      setState(() => _loadingMore = true);
    }
    try {
      final newItems = await GiftService.instance.fetchGifts(
        categoryId: _catId,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(newItems);
        _loading = false;
        _loadingMore = false;
        _hasMore = newItems.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = e.toString();
      });
    }
  }

  Future<void> _refreshWallet() async {
    if (_refreshingWallet) return;
    setState(() => _refreshingWallet = true);
    try {
      final w = await widget.onRefreshWallet();
      if (!mounted) return;
      setState(() => _wallet = w);
    } finally {
      if (mounted) setState(() => _refreshingWallet = false);
    }
  }

  void _pickCategory(String? id) {
    if (_catId == id) return;
    setState(() {
      _catId = id;
      _selected = null;
    });
    _loadGifts(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.68;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(child: KlayLiveBottomSheet.handle()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Presentes',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildBalancePill(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildCategoryTabs(),
          const SizedBox(height: 8),
          Expanded(child: _buildGrid()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          KlayCategoryTab(
            label: 'Todos',
            selected: _catId == null,
            onTap: () => _pickCategory(null),
          ),
          for (final c in _categories) ...[
            const SizedBox(width: 8),
            KlayCategoryTab(
              label: c.name,
              selected: _catId == c.id,
              onTap: () => _pickCategory(c.id),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível carregar os presentes.\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: kkNeon));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum presente disponível.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        childAspectRatio: 0.62,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: kkNeon),
            ),
          );
        }
        final g = _items[index];
        final afford = _wallet >= g.credits;
        return KlayGiftCard(
          gift: g,
          afford: afford,
          selected: _selected?.id == g.id,
          onTap: () => _onTapGift(g, afford),
        );
      },
    );
  }

  void _onTapGift(Gift g, bool afford) {
    if (!afford) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saldo insuficiente para este presente.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _selected = g);
  }

  Widget _buildBalancePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: kkSurfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💎', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            'Saldo: $_wallet',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: _refreshWallet,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _refreshingWallet
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kkAccent,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white54,
                      size: 15,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final gift = _selected;
    final total = gift == null ? 0 : gift.credits * _amount;
    final canSend = gift != null && total <= _wallet;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: kkSurfaceAlt,
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  itemCount: _amounts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final n = _amounts[i];
                    final ok = gift != null && n * gift.credits <= _wallet;
                    return _amountChip(n, selected: _amount == n, ok: ok);
                  },
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: canSend
                    ? () =>
                          Navigator.of(context).pop(KlayGiftPick(gift, _amount))
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: kkNeon,
                  disabledBackgroundColor: kkSurface,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white24,
                  minimumSize: const Size(84, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Enviar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 18,
            child: Text(
              gift == null
                  ? 'Toque num presente para enviar'
                  : canSend
                  ? '${gift.icon} ${gift.name} × $_amount · '
                        '$total 💎'
                  : 'Saldo insuficiente para ${gift.name} × $_amount.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountChip(int n, {required bool selected, required bool ok}) {
    return GestureDetector(
      onTap: ok ? () => setState(() => _amount = n) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? kkNeon : kkSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? kkAccent : Colors.white12),
        ),
        child: Text(
          'x$n',
          style: TextStyle(
            color: ok ? Colors.white : Colors.white24,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// CARD DE PRESENTE
/// ---------------------------------------------------------------------------

/// Item de presente real na grade: ícone, nome, preço e seleção com borda
/// roxa FINA (sem glow dominante). Presentes exclusivos ganham destaque
/// subtil (borda), seguindo o backend.
class KlayGiftCard extends StatelessWidget {
  final Gift gift;
  final bool afford;
  final bool selected;
  final VoidCallback onTap;

  const KlayGiftCard({
    super.key,
    required this.gift,
    required this.afford,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? kkAccent
                : gift.isExclusive
                ? const Color(0x6600E5FF)
                : const Color(0xFF2E2E2E),
            width: selected ? 1.3 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kkAccent.withValues(alpha: 0.14),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: afford ? 1 : 0.45,
              child: Text(gift.icon, style: const TextStyle(fontSize: 30)),
            ),
            const SizedBox(height: 5),
            Text(
              gift.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
            const SizedBox(height: 3),
            Text(
              '💎 ${gift.credits}',
              style: TextStyle(
                color: afford
                    ? const Color(0xFFE9D502)
                    : const Color(0xFFFF5252),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// ABA DE CATEGORIA
/// ---------------------------------------------------------------------------

/// Aba horizontal (categorias de presentes, abas de Mensagens...) com seleção
/// roxa suave (fundo roxo fraco + borda fina) e badge opcional de contagem.
class KlayCategoryTab extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? badge;

  const KlayCategoryTab({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kkAccent.withValues(alpha: 0.16) : kkSurfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? kkAccent.withValues(alpha: 0.65)
                : const Color(0xFF2E2E2E),
            width: selected ? 1.2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kkAccent.withValues(alpha: 0.14),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: selected ? Colors.white : Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 7), badge!],
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// CARD DE EVENTO (KLAY K BÔNUS — apresentação)
/// ---------------------------------------------------------------------------

/// Card de apresentação do KLAY K Bônus (apenas visual: não inventa saldo,
/// prêmio ou transação). Tocar abre uma sheet informativa honesta.
class KlayLiveEventCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const KlayLiveEventCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 224,
        height: 82,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B0F4E), kkSurface],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kkNeon.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: kkNeon.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [kkNeon, kkAccent]),
                boxShadow: [
                  BoxShadow(
                    color: kkNeon.withValues(alpha: 0.5),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'KLAY K Bônus',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kkNeon, kkAccent]),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Ver detalhes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// BANNER HORIZONTAL (DADO REAL)
/// ---------------------------------------------------------------------------

/// Banner horizontal da live usando a capa real (`cover_url`) do criador com
/// título/categoria reais. Não inventa conteúdo.
class KlayLiveBanner extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String? category;

  const KlayLiveBanner({
    super.key,
    required this.imageUrl,
    required this.title,
    this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 82,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: kkSurface,
              child: const Icon(Icons.live_tv_rounded, color: kkNeon, size: 26),
            ),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    color: kkSurface,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kkNeon,
                        ),
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          if (category != null && category!.isNotEmpty)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kkNeon.withValues(alpha: 0.5)),
                ),
                child: Text(
                  category!,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// TILE DE CONVERSA (DM REAL)
/// ---------------------------------------------------------------------------

/// Conversa real do `Bate-papos`: avatar, nome verificado, última mensagem,
/// horário e badge de não lidos. Usado na aba BATE-PAPOS.
class KlayMessageTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const KlayMessageTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
    final hasAvatar = c.peerAvatar != null && c.peerAvatar!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: kkSurfaceAlt,
                  backgroundImage: hasAvatar
                      ? NetworkImage(c.peerAvatar!)
                      : null,
                  child: hasAvatar
                      ? null
                      : const Icon(Icons.person, color: Colors.white38),
                ),
                if (unread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: KlayKBadge(count: c.unread),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.peerName ?? 'Usuário',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: unread
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (c.peerVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.lastMessage.isNotEmpty ? c.lastMessage : 'Nova conversa',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread ? Colors.white : kkTextSecondary,
                      fontSize: 13,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _time(c.lastMessageAt),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays == 1) return 'ontem';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }
}

/// ---------------------------------------------------------------------------
/// TILE DE NOTIFICAÇÃO (REAL)
/// ---------------------------------------------------------------------------

/// Notificação real da central: avatar do autor com selo do tipo, título com
/// verificação e selo de não lida.
class KlayNotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const KlayNotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.read;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: unread ? kkAccent.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: kkSurfaceAlt,
                  backgroundImage:
                      n.actor?.avatarUrl != null &&
                          n.actor!.avatarUrl!.isNotEmpty
                      ? NetworkImage(n.actor!.avatarUrl!)
                      : null,
                  child:
                      n.actor?.avatarUrl == null || n.actor!.avatarUrl!.isEmpty
                      ? const Icon(Icons.person, color: Colors.white54)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _colorFor(n.type),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(n.type),
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(n, unread),
                  const SizedBox(height: 3),
                  Text(
                    _timeAgo(n.createdAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: kkAccent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _titleFor(AppNotification n) {
    final name = n.actor?.name ?? 'Alguém';
    switch (n.type) {
      case 'like':
        return '$name curtiu seu vídeo';
      case 'comment':
        return '$name comentou: ${n.message.isNotEmpty ? n.message : 'no seu vídeo'}';
      case 'follow':
        return '$name começou a seguir você';
      case 'live':
        return '$name entrou ao vivo';
      case 'mention':
        return '$name mencionou você';
      case 'verification':
        return n.message.isNotEmpty ? n.message : 'Seu perfil de verificação';
      default:
        return n.message.isNotEmpty ? n.message : name;
    }
  }

  Widget _title(AppNotification n, bool unread) {
    final base = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
    );
    final text = _titleFor(n);
    final actor = n.actor;
    if (actor == null || !actor.isVerified) return Text(text, style: base);
    if (!text.startsWith(actor.name)) return Text(text, style: base);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: actor.name),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: 3),
              child: VerifiedBadge(size: 12),
            ),
          ),
          if (text.length > actor.name.length)
            TextSpan(text: text.substring(actor.name.length)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays < 7) return 'há ${diff.inDays} d';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.comment_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      case 'live':
        return Icons.sensors_rounded;
      case 'mention':
        return Icons.alternate_email_rounded;
      case 'verification':
        return Icons.verified_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'like':
        return kkLiveRed;
      case 'comment':
        return Colors.cyanAccent;
      case 'follow':
        return const Color(0xFF4CAF50);
      case 'live':
        return const Color(0xFFFF5722);
      case 'verification':
        return kkAccent;
      default:
        return Colors.amberAccent;
    }
  }
}
