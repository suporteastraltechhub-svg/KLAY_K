import 'package:flutter/material.dart';

import '../../services/experience_settings.dart';
import '../../services/local_prefs_service.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _bg = Color(0xFF0A0812);
const Color _card = Color(0xFF1B1A26);
const Color _ok = Color(0xFF34D399);
const Color _warn = Color(0xFFFFB020);

class DigitalWellbeingScreen extends StatefulWidget {
  const DigitalWellbeingScreen({super.key});

  @override
  State<DigitalWellbeingScreen> createState() => _DigitalWellbeingScreenState();
}

class _DigitalWellbeingScreenState extends State<DigitalWellbeingScreen> {
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

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  void _save(LocalPrefs next) {
    _local.update(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'BEM-ESTAR DIGITAL',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: ValueListenableBuilder<LocalPrefs>(
        valueListenable: _local.prefs,
        builder: (context, prefs, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Você decide o ritmo. Estes ajustes ficam salvos apenas neste '
              'aparelho.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _header('Hoje'),
            ValueListenableBuilder<int>(
              valueListenable: _local.todayUsageMinutes,
              builder: (context, minutes, _) =>
                  _usageCard(minutes, prefs.dailyLimitMinutes),
            ),
            const SizedBox(height: 24),
            _header('Lembrete de pausa'),
            _chips(
              const [
                (0, 'Desligado'),
                (15, '15 min'),
                (30, '30 min'),
                (60, '60 min'),
              ],
              prefs.pauseReminderMinutes,
              (v) => _save(prefs.copyWith(pauseReminderMinutes: v)),
              'Lembrete de pausa',
            ),
            const SizedBox(height: 8),
            const Text(
              'Intervalo de uso contínuo que você quer se lembrar de fazer '
              'uma pausa.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _header('Tempo de uso diário'),
            _chips(
              const [(0, 'Sem limite'), (60, '1h'), (120, '2h'), (240, '4h')],
              prefs.dailyLimitMinutes,
              (v) => _save(prefs.copyWith(dailyLimitMinutes: v)),
              'Tempo de uso diário',
            ),
            const SizedBox(height: 8),
            const Text(
              'O app apenas avisa quando você passa do limite. Ele não bloqueia '
              'o acesso a nada.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _header('Notificações'),
            _switch(
              prefs.reduceNotificationsDimmer,
              'Reduzir notificações',
              'Silencia o escurecimento da tela quando uma notificação chega.',
              (v) => _save(prefs.copyWith(reduceNotificationsDimmer: v)),
            ),
            const SizedBox(height: 24),
            _header('Reprodução e dados'),
            ValueListenableBuilder<KlaykExperience>(
              valueListenable: ExperienceSettings.instance.prefs,
              builder: (context, xp, _) => Column(
                children: [
                  _switch(
                    xp.autoPlay,
                    'Reprodução automática',
                    'Vídeos começam sozinhos quando você rola o feed.',
                    (v) => ExperienceSettings.instance.update(
                      xp.copyWith(autoPlay: v),
                    ),
                  ),
                  _switch(
                    xp.wifiOnly,
                    'Somente no Wi-Fi',
                    'Evita usar dados móveis para carregar vídeos e áudios.',
                    (v) => ExperienceSettings.instance.update(
                      xp.copyWith(wifiOnly: v),
                    ),
                  ),
                  _switch(
                    xp.saveData,
                    'Economia de dados',
                    'Carrega a qualidade mais baixa para economizar internet.',
                    (v) => ExperienceSettings.instance.update(
                      xp.copyWith(saveData: v),
                    ),
                  ),
                  _switch(
                    xp.reduceAnimations,
                    'Reduzir animações',
                    'Menos transições e menos movimento na interface.',
                    (v) => ExperienceSettings.instance.update(
                      xp.copyWith(reduceAnimations: v),
                    ),
                  ),
                ],
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
                'Como este número é medido: o KLAY K marca o início e o fim '
                'de cada sessão do próprio app e soma os minutos em primeiro '
                'plano. Não é o tempo de tela do sistema, e não é enviado para '
                'o servidor.',
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
    );
  }

  Widget _usageCard(int minutes, int limit) {
    final over = limit > 0 && minutes > limit;
    return Semantics(
      label: over
          ? 'Tempo de hoje ${_formatMinutes(minutes)}. Você ultrapassou o '
                'limite de ${_formatMinutes(limit)}.'
          : 'Tempo de hoje ${_formatMinutes(minutes)}'
                '${limit > 0 ? '. Limite de ${_formatMinutes(limit)}' : ''}',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: over ? Border.all(color: _warn) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timelapse_rounded, color: over ? _warn : _accent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tempo com o app em primeiro plano',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _formatMinutes(minutes),
              style: TextStyle(
                color: over ? _warn : _ok,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              limit > 0
                  ? 'Seu limite diário é ${_formatMinutes(limit)}.'
                  : 'Você não definiu um limite diário.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (over) ...[
              const SizedBox(height: 12),
              const Text(
                'Você passou do limite que escolheu. Que tal uma pausa?',
                style: TextStyle(
                  color: _warn,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
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

  Widget _chips(
    List<(int, String)> options,
    int selected,
    ValueChanged<int> onChanged,
    String group,
  ) => Semantics(
    label:
        '$group. Selecionado: ${options.firstWhere((o) => o.$1 == selected, orElse: () => options.first).$2}',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(
              o.$2,
              style: TextStyle(
                color: o.$1 == selected ? Colors.white : Colors.white60,
                fontSize: 13,
              ),
            ),
            selected: o.$1 == selected,
            selectedColor: _accent,
            backgroundColor: const Color(0xFF222032),
            onSelected: (v) {
              if (v) onChanged(o.$1);
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
