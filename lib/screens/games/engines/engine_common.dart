import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/game_service.dart';
import '../../../theme/klayk_theme.dart';

/// ============================================================================
/// Infraestrutura das engines de mini‑jogos do KLAY K.
///
/// Cada engine é UMA tela reutilizável que lê a configuração do jogo
/// (`rules.engine_config` do backend). O placar/recompensa SEMPRE passa pelo
/// backend (game_start_session + game_submit_score — security definer); o
/// cliente nunca define saldo. O ponto de virada para "mais 1000 jogos" é
/// adicionar linhas na tabela `games`, não criar telas.
/// ============================================================================

/// Lê um int da configuração da engine com fallback.
int cfgInt(GameInfo game, String key, int def) =>
    (game.engineConfig[key] as num?)?.toInt() ?? def;

/// Lê um double da configuração da engine com fallback.
double cfgDouble(GameInfo game, String key, double def) =>
    (game.engineConfig[key] as num?)?.toDouble() ?? def;

/// Lê um bool da configuração da engine com fallback.
bool cfgBool(GameInfo game, String key, bool def) =>
    game.engineConfig[key] as bool? ?? def;

/// Lê uma string da configuração da engine com fallback.
String cfgStr(GameInfo game, String key, String def) =>
    game.engineConfig[key]?.toString() ?? def;

/// Cor do tema configurada pelo backend (hex `#RRGGBB`) com fallback.
Color engineColor(GameInfo game, {Color? fallback}) {
  final fallbackColor = fallback ?? const Color(0xFF8B5CF6);
  final raw = cfgStr(game, 'tint', '');
  if (raw.isEmpty) return fallbackColor;
  final cleaned = raw.replaceFirst('#', '').trim();
  if (cleaned.length != 6) return fallbackColor;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return fallbackColor;
  return Color(0xFF000000 | value);
}

/// Submete o resultado da partida ao backend (autenticidade total no server).
/// Retorna `null` se a sincronização falhar (a UI informa, sem quebrar a sessão).
Future<GameSubmitResult?> submitMatch(
  GameInfo game, {
  required int score,
  required int elapsedSeconds,
}) async {
  final svc = GameService.instance;
  final safe = score.clamp(0, game.maxScore);
  try {
    final sessionId = await svc.startSession(game.id);
    return await svc.submitScore(
      sessionId: sessionId,
      score: safe,
      durationSeconds: elapsedSeconds,
    );
  } catch (_) {
    return null;
  }
}

/// Painel premium de resultado da partida — usado por todas as engines.
class EngineResultPanel extends StatelessWidget {
  const EngineResultPanel({
    super.key,
    required this.emoji,
    required this.score,
    required this.maxScore,
    this.result,
    required this.onReplay,
    required this.onClose,
    this.title,
    this.subtitle,
    this.accentColor,
  });

  final String emoji;
  final int score;
  final int maxScore;
  final GameSubmitResult? result;
  final VoidCallback onReplay;
  final VoidCallback onClose;
  final String? title;
  final String? subtitle;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final r = result;
    final rewardLine = r != null
        ? (r.improved ? l10n.engineReward(r.reward) : l10n.engineRewardAlready)
        : l10n.engineSyncFailed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 14),
            Text(
              title ?? l10n.engineMatchComplete,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle ?? l10n.engineYouScored(score, maxScore),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              rewardLine,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.primarySoft,
              ),
            ),
            const SizedBox(height: 24),
            // Ações do resultado: Wrap responsivo — em telas estreitas o
            // segundo botão quebra para a linha seguinte em vez de estourar
            // o layout (RIGHT OVERFLOWED). Sem larguras fixas.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: colors.border),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(l10n.engineClose),
                ),
                FilledButton.icon(
                  onPressed: onReplay,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor ?? colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: Text(l10n.enginePlayAgain),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cabeçalho padrão das telas de engine: título + pontuação em tempo real.
class EngineHeader extends StatelessWidget {
  const EngineHeader({
    super.key,
    required this.title,
    required this.leftLabel,
    this.rightLabel,
    this.tint,
  });

  final String title;
  final String leftLabel;
  final String? rightLabel;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (rightLabel != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (tint ?? colors.primary).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (tint ?? colors.primary).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                rightLabel!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
