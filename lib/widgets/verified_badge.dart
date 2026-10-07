import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Selo de verificado usando o asset PNG oficial `assets/ic_verificado.png`,
/// com fallback para ícone Material caso o asset não carregue. Tamanho
/// responsivo (padrão 16) para não quebrar o layout em linhas de nome.
class VerifiedBadge extends StatelessWidget {
  final double size;
  final Color? color;

  const VerifiedBadge({super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/ic_verificado.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.verified_rounded,
        size: size,
        color: color ?? const Color(0xFF8B5CF6),
      ),
    );
  }
}

/// Selo especial 👑 FUNDADOR OFICIAL — mostrado apenas para o fundador (role
/// vinda do banco, nunca fabricada no cliente).
class FounderBadge extends StatelessWidget {
  final bool compact;

  const FounderBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (compact) {
      return Tooltip(
        message: l10n.founderOfficialBadge,
        child: const Text('👑', style: TextStyle(fontSize: 16)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD4AF37), Color(0xFFB8860B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👑', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            l10n.founderOfficialLabel,
            style: const TextStyle(
              color: Color(0xFF1B1A26),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Selo de admin (super_admin/admin) — tom roxo premium.
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🛡️', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            l10n.adminMasterLabel,
            style: const TextStyle(
              color: Color(0xFFC4B5FD),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
