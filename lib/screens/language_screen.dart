import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_controller.dart';
import '../theme/klayk_theme.dart';

/// Tela "Configurações → Idioma e região → Idioma do aplicativo".
/// Permite trocar o idioma da interface em tempo real; a escolha é salva
/// localmente e continua após reabrir o aplicativo.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  static const List<({String code, String flag, IconData? icon})> _languages = [
    (code: 'pt', flag: '🇧🇷', icon: null),
    (code: 'en', flag: '🇺🇸', icon: null),
    (code: 'es', flag: '🇪🇸', icon: null),
    (code: 'fr', flag: '🇫🇷', icon: null),
    (code: 'ja', flag: '🇯🇵', icon: null),
    (code: 'ko', flag: '🇰🇷', icon: null),
    (code: 'zh', flag: '🇨🇳', icon: null),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E16),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white70,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          l10n.languageTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: ListenableBuilder(
        listenable: AppLanguageController.instance,
        builder: (context, _) {
          final controller = AppLanguageController.instance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF17151F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.translate_rounded,
                          color: colors.primarySoft,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.currentLanguage,
                          style: TextStyle(
                            color: colors.primarySoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _displayName(context, controller.locale.languageCode),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.languageSettingsNote,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  l10n.appLanguage,
                  style: TextStyle(
                    color: colors.primarySoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Card(
                color: const Color(0xFF17151F),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final lang in _languages)
                      _LanguageTile(
                        flag: lang.flag,
                        name: _displayName(context, lang.code),
                        selected: controller.locale.languageCode == lang.code,
                        onTap: () {
                          if (controller.locale.languageCode == lang.code) {
                            return;
                          }
                          controller.setLocale(Locale(lang.code));
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(content: Text(l10n.languageChanged)),
                            );
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Nome do idioma na própria língua (autoexplicativo para o usuário).
  String _displayName(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context)!;
    return switch (code) {
      'pt' => l10n.portuguese,
      'en' => l10n.english,
      'es' => l10n.spanish,
      'fr' => l10n.french,
      'ja' => l10n.japanese,
      'ko' => l10n.korean,
      'zh' => l10n.chinese,
      _ => l10n.portuguese,
    };
  }
}

class _LanguageTile extends StatelessWidget {
  final String flag;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.flag,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: kcolors(context).primary)
            else
              const Icon(
                Icons.radio_button_unchecked_rounded,
                color: Colors.white24,
              ),
          ],
        ),
      ),
    );
  }
}
