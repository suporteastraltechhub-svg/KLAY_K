import 'package:flutter/material.dart';

import '../../models/security_models.dart';
import '../../services/security_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kSafe = Color(0xFF34D399);

/// Youth Shield — idade provada, Modo Jovem e consentimento para conteúdo
/// adulto. As decisões de acesso (especialmente em gate de lives) são tomadas
/// no backend com precedência real: menor com idade provada é NEGADO mesmo com
/// o consentimento ligado — o app apenas mostra isso honestamente.
class YouthShieldScreen extends StatefulWidget {
  const YouthShieldScreen({super.key});

  @override
  State<YouthShieldScreen> createState() => _YouthShieldScreenState();
}

class _YouthShieldScreenState extends State<YouthShieldScreen> {
  final SecurityService _svc = SecurityService.instance;

  bool _loading = true;
  bool _saving = false;
  SafetyProfile _profile = const SafetyProfile();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _svc.mySafetyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setWorking(bool v) {
    if (mounted) setState(() => _saving = v);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _profile.birthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - 16, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Data de nascimento',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _kAccent,
            surface: Color(0xFF1B1A26),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    _setWorking(true);
    try {
      await _svc.setBirthDate(picked);
      await _load();
      _snack('Data de nascimento salva.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _clearBirthDate() async {
    _setWorking(true);
    try {
      await _svc.setBirthDate(null);
      await _load();
      _snack('Data de nascimento removida.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _setYouthMode(bool on) async {
    if (_saving) return;
    _setWorking(true);
    try {
      await _svc.setYouthMode(on);
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _setAdultContentOk(bool on) async {
    if (_saving) return;
    if (on && _profile.isProvenMinor) {
      _snack('Menor de idade com data provada: o backend recusa conteúdo '
          'adulto mesmo com este consentimento.');
      return;
    }
    final ok = await _confirmDialog(
      on
          ? 'Permitir conteúdo adulto?'
          : 'Desativar conteúdo adulto?',
      on
          ? 'Se você for maior de idade, o backend permitirá conteúdo adulto. '
              'Você pode desativar a qualquer momento.'
          : 'Conteúdo adulto ficará oculto.',
    );
    if (!ok) return;
    _setWorking(true);
    try {
      await _svc.setAdultContentOk(on);
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<bool> _confirmDialog(String title, String body) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar',
                style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Modo Jovem e segurança',
            style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statusBanner(),
                const SizedBox(height: 24),
                _sectionHeader('DATA DE NASCIMENTO'),
                _birthCard(),
                const SizedBox(height: 24),
                _sectionHeader('PREFERÊNCIAS'),
                _prefsCard(),
                const SizedBox(height: 16),
                const Text(
                  'As restrições são aplicadas no backend: lives para maiores '
                  'exigem idade provada de 18+ e o Modo Jovem restringe '
                  'interações para menor de idade mesmo com consentimento.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1)),
      );

  Widget _statusBanner() {
    final String title;
    final String body;
    final Color color;
    if (_profile.isProvenMinor) {
      title = 'Conta identificada como menor de 18 anos';
      body = 'Conteúdo e lives para maiores são bloqueados no backend. '
          'O consentimento abaixo não altera esse bloqueio.';
      color = Colors.orange;
    } else if (_profile.hasProvenAge) {
      title = 'Idade provada: ${_profile.age} anos';
      body = 'Os gates de conteúdo usam essa idade de forma honesta.';
      color = _kSafe;
    } else {
      title = 'Idade ainda não informada';
      body = 'Devido a algum consentimento, conteúdo adulto pode ser '
          'liberado, mas lives para maiores ficam bloqueadas até '
          'informar a data de nascimento.';
      color = _kAccent;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_profile.isProvenMinor ? Icons.warning_amber_rounded
                  : Icons.shield_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _birthCard() {
    final bd = _profile.birthDate;
    final formatted =
        bd == null ? '—' : '${bd.day.toString().padLeft(2, '0')}/'
            '${bd.month.toString().padLeft(2, '0')}/${bd.year}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cake_rounded, color: _kAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(formatted,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              if (_profile.age != null)
                Text('${_profile.age} anos',
                    style: const TextStyle(color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickBirthDate,
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: const Text('Informar data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kAccent,
                    side: const BorderSide(color: _kAccent),
                  ),
                ),
              ),
              if (bd != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _saving ? null : _clearBirthDate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Remover'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _prefsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16151F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _profile.youthMode,
            onChanged: _saving ? null : _setYouthMode,
            activeThumbColor: _kSafe,
            title: const Text('Modo Jovem',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: const Text(
              'Restringe interações e conteúdo sensível.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          SwitchListTile(
            value: _profile.adultContentOk,
            onChanged: _saving ? null : _setAdultContentOk,
            activeThumbColor: _kAccent,
            title: const Text('Permitir conteúdo adulto',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: Text(
              _profile.isProvenMinor
                  ? 'Bloqueado para menor de idade (idade provada).'
                  : 'Libera conteúdo adulto. Sujeito a verificação de idade.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}