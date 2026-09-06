import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/invite_service.dart';
import '../services/supabase_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';

/// Central de Convites: código pessoal, copiar/compartilhar, lista de
/// convidados e reivindicação de cristais por convidados validados.
/// Tudo persistido/válido no backend (RPCs security definer).
class InvitesCenterScreen extends StatefulWidget {
  const InvitesCenterScreen({super.key});

  @override
  State<InvitesCenterScreen> createState() => _InvitesCenterScreenState();
}

class _InvitesCenterScreenState extends State<InvitesCenterScreen> {
  final _svc = InviteService.instance;
  InviteSummary _summary = const InviteSummary();
  List<InviteRecord> _invites = const [];
  bool _loading = true;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await _svc.summary();
    final invites = await _svc.invites();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _invites = invites;
      _loading = false;
    });
  }

  Future<void> _copyCode() async {
    if (_summary.code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _summary.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código copiado!')),
    );
  }

  Future<void> _share() async {
    final text = _svc.shareText(
      _summary.code,
      kAppIdentity.username.replaceFirst('@', ''),
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem de convite copiada!')),
    );
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final result = await _svc.claimRewards();
    if (!mounted) return;
    setState(() => _claiming = false);
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimed > 0
                ? '🎉 +${result.crystals} 🔮 cristais!'
                : 'Nenhuma recompensa pendente no momento.',
          ),
        ),
      );
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível reivindicar agora.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convites')),
      body: KlaykScreenBackground(
        child: _loading
            ? const Center(child: KlaykLoader())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHero(),
                    const SizedBox(height: 20),
                    _buildStats(),
                    const SizedBox(height: 20),
                    _buildInviteList(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHero() {
    final colors = kcolors(context);
    return KlaykCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.primaryFaint, colors.surfaceAlt],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎉 Convide amigos, ganhe cristais',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Compartilhe seu código. Quando alguém se cadastrar com ele, você '
            'ganha 🔮 cristais para usar na loja e nos jogos.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _copyCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _summary.code,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.copy_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _share,
                icon: const Icon(Icons.share_rounded),
                tooltip: 'Copiar convite',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final colors = kcolors(context);
    return Row(
      children: [
        _statCard(colors, '👥', '${_summary.invited}', 'Convidados'),
        const SizedBox(width: 12),
        _statCard(colors, '✅', '${_summary.pendingRewards}', 'Pendentes'),
        const SizedBox(width: 12),
        Expanded(
          child: KlaykCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            onTap: _claim,
            child: Column(
              children: [
                Icon(
                  _claiming ? Icons.hourglass_top : Icons.card_giftcard,
                  color: colors.gold,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Reivindicar',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '🔮 ${_summary.pendingRewards * 5}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(KlaykColors colors, String emoji, String value, String label) {
    return Expanded(
      child: KlaykCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteList() {
    if (_invites.isEmpty) {
      return const KlaykEmptyState(
        icon: Icons.group_add_rounded,
        title: 'Ninguém entrou ainda',
        message: 'Compartilhe seu código para começar a ganhar cristais.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KlaykSectionTitle('Convidados'),
        const SizedBox(height: 8),
        ..._invites.map(
          (inv) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KlaykCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    child: Icon(Icons.person_rounded, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusLabel(inv.status, inv.validatedAt),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  _statusChip(inv.status),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status, DateTime? validatedAt) {
    switch (status) {
      case 'validated':
        return 'Convidado validado';
      case 'rewarded':
        return 'Recompensa liberada 🔮 +5';
      case 'blocked':
        return 'Convite bloqueado';
      default:
        return 'Convite registrado';
    }
  }

  Widget _statusChip(String status) {
    final colors = kcolors(context);
    final (label, bg, fg) = switch (status) {
      'rewarded' => ('+5 🔮', colors.success.withValues(alpha: .15), colors.success),
      'validated' => ('validado', colors.info.withValues(alpha: .15), colors.info),
      'blocked' => ('bloqueado', colors.danger.withValues(alpha: .15), colors.danger),
      _ => ('pendente', colors.warning.withValues(alpha: .15), colors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}