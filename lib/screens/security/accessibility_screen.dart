import 'package:flutter/material.dart';

import '../../services/experience_settings.dart';
import '../../services/local_prefs_service.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _bg = Color(0xFF0A0812);
const Color _card = Color(0xFF1B1A26);

class AccessibilityScreen extends StatefulWidget {
  const AccessibilityScreen({super.key});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> {
  final LocalPrefsService _local = LocalPrefsService.instance;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadLocal() async {
    if (_local.isLoaded) return;
    await _local.load();
  }

  String _scaleLabel(double scale) => '${(scale * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'ACESSIBILIDADE',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: Semantics(
        label: 'Configurações de acessibilidade',
        container: true,
        child: ValueListenableBuilder<LocalPrefs>(
          valueListenable: _local.prefs,
          builder: (context, prefs, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Ajuste a interface para ficar mais confortável de ler e de '
                'usar.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _header('Leitura'),
              _preview(prefs),
              const SizedBox(height: 12),
              _chips(prefs.textScale),
              const SizedBox(height: 8),
              const Text(
                'O tamanho do texto muda a interface do app inteiro, não só '
                'esta tela. Ele não altera a fonte do sistema do aparelho.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _header('Contraste e movimento'),
              _switch(
                prefs.highContrast,
                'Alto contraste',
                'Aumenta o contraste entre textos e fundo.',
                (v) => _local.update(prefs.copyWith(highContrast: v)),
              ),
              ValueListenableBuilder<KlaykExperience>(
                valueListenable: ExperienceSettings.instance.prefs,
                builder: (context, xp, _) => _switch(
                  xp.reduceAnimations,
                  'Reduzir animações',
                  'Menos transições e menos movimento na interface.',
                  (v) => ExperienceSettings.instance.update(
                    xp.copyWith(reduceAnimations: v),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tamanho do texto e alto contraste valem para a interface do '
                  'KLAY K neste aparelho e ficam salvos localmente. Se você '
                  'trocar de aparelho, será preciso escolher de novo.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _preview(LocalPrefs prefs) => Semantics(
    container: true,
    label:
        'Exemplo de texto em ${_scaleLabel(prefs.textScale)}${prefs.highContrast ? ', com alto contraste' : ''}',
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'O KLAY K é mais confortável quando o texto está no tamanho certo '
        'para você.',
        style: TextStyle(
          color: prefs.highContrast ? Colors.white : Colors.white70,
          fontSize: 14 * prefs.textScale,
          fontWeight: prefs.highContrast ? FontWeight.w700 : FontWeight.w400,
          height: 1.4,
        ),
      ),
    ),
  );

  Widget _chips(double current) => Semantics(
    container: true,
    label: 'Tamanho do texto. Selecionado: ${_scaleLabel(current)}',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final scale in const [0.9, 1.0, 1.15, 1.3])
          ChoiceChip(
            label: Text(
              _scaleLabel(scale),
              style: TextStyle(
                color: scale == current ? Colors.white : Colors.white60,
                fontSize: 13,
              ),
            ),
            selected: scale == current,
            selectedColor: _accent,
            backgroundColor: const Color(0xFF222032),
            onSelected: (v) {
              if (v) {
                _local.update(_local.prefs.value.copyWith(textScale: scale));
              }
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    ),
  );

  Widget _switch(
    bool value,
    String title,
    String subtitle,
    ValueChanged<bool> onChanged,
  ) => Semantics(
    container: true,
    label: '$title. $subtitle',
    child: Card(
      color: _card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        value: value,
        activeThumbColor: _accent,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        onChanged: onChanged,
      ),
    ),
  );
}
