import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/klayk_ux.dart';

const Color _kAccent = Color(0xFF8B5CF6);


/// Página de conteúdo legal/institucional do KLAY K.
///
/// Recebe o corpo já pronto em [body] para que Termos, Privacidade e Regras
/// compartilhem a mesma moldura visual.
class KlaykLegalPage extends StatelessWidget {
  final String title;
  final IconData icon;

  /// Se true, mostra "voltamos para Configurações" ao final.
  final bool showBackToSettings;

  /// Corpo introdutório (texto já traduzido).
  final String body;

  /// Parágrafos já traduzidos.
  final List<String> paragraphs;

  /// Tópicos com título + linhas.
  final List<(String, List<String>)> topics;

  const KlaykLegalPage({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    this.showBackToSettings = false,
    this.paragraphs = const [],
    this.topics = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(
              children: [
                Icon(icon, color: _kAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            KlaykCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            for (final t in topics) ...[
              const SizedBox(height: 14),
              _SectionTitle(t.$1),
              const SizedBox(height: 6),
              KlaykCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in t.$2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• $line',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (showBackToSettings) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccent,
                  side: const BorderSide(color: Color(0xFF3A3355)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: Text(l10n.settingsTitle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _kAccent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// Termos de Uso.
class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KlaykLegalPage(
      title: l10n.termsOfUse,
      icon: Icons.gavel_rounded,
      showBackToSettings: true,
      body: l10n.legalTermsBody,
      topics: [
        (l10n.legalAccountTopic, [l10n.legalAccount1, l10n.legalAccount2]),
        (l10n.legalContentTopic, [
          l10n.legalContent1,
          l10n.legalContent2,
          l10n.legalContent3,
        ]),
        (l10n.legalConductTopic, [l10n.legalConduct1, l10n.legalConduct2]),
        (l10n.legalPaymentsTopic, [l10n.legalPayments1, l10n.legalPayments2]),
      ],
    );
  }
}

/// Política de Privacidade.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KlaykLegalPage(
      title: l10n.privacyPolicy,
      icon: Icons.privacy_tip_rounded,
      showBackToSettings: true,
      body: l10n.legalPrivacyBody,
      topics: [
        (l10n.legalDataTopic, [l10n.legalData1, l10n.legalData2]),
        (l10n.legalUsageTopic, [l10n.legalUsage1, l10n.legalUsage2]),
        (l10n.legalRightsTopic, [
          l10n.legalRights1,
          l10n.legalRights2,
          l10n.legalRights3,
        ]),
      ],
    );
  }
}

/// Regras da Comunidade.
class CommunityRulesScreen extends StatelessWidget {
  const CommunityRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KlaykLegalPage(
      title: l10n.communityRules,
      icon: Icons.groups_rounded,
      showBackToSettings: true,
      body: l10n.legalRulesBody,
      topics: [
        (l10n.legalRespectTopic, [
          l10n.legalRespect1,
          l10n.legalRespect2,
          l10n.legalRespect3,
        ]),
        (l10n.legalSafetyTopic, [
          l10n.legalSafety1,
          l10n.legalSafety2,
          l10n.legalSafety3,
        ]),
        (l10n.legalAdsTopic, [l10n.legalAds1, l10n.legalAds2]),
        (l10n.legalReportTopic, [l10n.legalReport1, l10n.legalReport2]),
      ],
    );
  }
}