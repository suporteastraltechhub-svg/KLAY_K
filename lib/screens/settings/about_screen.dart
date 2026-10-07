import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/klayk_ux.dart';
import 'legal_pages.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Lê a versão real do app instalado.
///
/// Não usamos constante no código (ela mente assim que o número muda na
/// loja) nem `package_info_plus`, que não é dependência deste projeto. O
/// canal de plataforma é a fonte da verdade: no Android vem de
/// `PackageInfo.versionName`, gerado do `versionName` do Gradle.
class AppVersion {
  AppVersion._();

  static String? _cached;

  static Future<String> load() async {
    if (_cached != null) return _cached!;
    try {
      final info = await SystemChannels.platform.invokeMapMethod<String, dynamic>(
        'getPackageInfo',
        <String, dynamic>{'packageName': 'com.klayk.klay_k'},
      );
      final v = info?['versionName']?.toString().trim();
      _cached = (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      _cached = null;
    }
    return _cached ?? '—';
  }
}

/// "Sobre o KLAY K" — versão real, novidades, documentos e créditos.
///
/// A versão vem do nome exibido pelo package manager (`package_info_plus`),
/// não de uma string fixa: em release o número é o do APK de verdade.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<String> _version = AppVersion.load();

  /// Só para o `showLicensePage`, que exige String síncrona.
  String _versionValue = '—';

  @override
  void initState() {
    super.initState();
    AppVersion.load().then((v) {
      if (mounted) setState(() => _versionValue = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.aboutKlayK,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _brand(l10n),
            const SizedBox(height: 18),
            _card(
              children: [
                Text(
                  l10n.aboutIntro,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.tag_rounded, color: _kAccent, size: 16),
                    const SizedBox(width: 8),
                    FutureBuilder<String>(
                      future: _version,
                      builder: (_, snap) => Text(
                        l10n.versionLabel(snap.data ?? '…'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _header(l10n.aboutDocuments),
            _row(
              icon: Icons.gavel_rounded,
              title: l10n.termsOfUse,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
              ),
            ),
            _row(
              icon: Icons.privacy_tip_rounded,
              title: l10n.privacyPolicy,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              ),
            ),
            _row(
              icon: Icons.groups_rounded,
              title: l10n.communityRules,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CommunityRulesScreen()),
              ),
            ),
            _row(
              icon: Icons.workspaces_rounded,
              title: l10n.openSourceLicenses,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'KLAY K',
                applicationVersion: _versionValue,
                applicationLegalese: l10n.developedByAstral,
              ),
            ),
            const SizedBox(height: 18),
            _header(l10n.aboutCredits),
            _card(
              children: [
                Text(
                  l10n.developedByAstral,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.aboutCreditsBody,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in const [
                      'Flutter',
                      'Supabase',
                      'LiveKit',
                      'Firebase',
                    ])
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _kAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _brand(AppLocalizations l10n) {
    return Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            ),
          ),
          alignment: Alignment.center,
          child: const Text(
            'K',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'KLAY K',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.aboutTagline,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _kAccent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _card({required List<Widget> children}) => KlaykCard(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _row({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KlaykCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: _kAccent, size: 20),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }
}