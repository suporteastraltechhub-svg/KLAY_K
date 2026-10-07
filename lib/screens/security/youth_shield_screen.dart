import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setWorking(bool v) {
    if (mounted) setState(() => _saving = v);
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );

  Future<void> _pickBirthDate() async {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final initial = _profile.birthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - 16, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: l10n.youthShieldBirthDateHelp,
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
      _snack(l10n.youthShieldBirthDateSaved);
    } catch (e) {
      _snack(e.toString());
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _clearBirthDate() async {
    final l10n = AppLocalizations.of(context)!;
    _setWorking(true);
    try {
      await _svc.setBirthDate(null);
      await _load();
      _snack(l10n.youthShieldBirthDateRemoved);
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
    final l10n = AppLocalizations.of(context)!;
    if (on && _profile.isProvenMinor) {
      _snack(l10n.youthShieldMinorBlocked);
      return;
    }
    final ok = await _confirmDialog(
      on ? l10n.youthShieldAdultOnTitle : l10n.youthShieldAdultOffTitle,
      on ? l10n.youthShieldAdultOnBody : l10n.youthShieldAdultOffBody,
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
    final l10n = AppLocalizations.of(context)!;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.confirm,
              style: const TextStyle(
                color: _kAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.youthShieldTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statusBanner(l10n),
                const SizedBox(height: 24),
                _sectionHeader(l10n.youthShieldBirthHeader),
                _birthCard(l10n),
                const SizedBox(height: 24),
                _sectionHeader(l10n.youthShieldPrefsHeader),
                _prefsCard(l10n),
                const SizedBox(height: 16),
                Text(
                  l10n.youthShieldRestrictionsNote,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _statusBanner(AppLocalizations l10n) {
    final String title;
    final String body;
    final Color color;
    if (_profile.isProvenMinor) {
      title = l10n.youthShieldMinorTitle;
      body = l10n.youthShieldMinorBody;
      color = Colors.orange;
    } else if (_profile.hasProvenAge) {
      title = l10n.youthShieldAgeProven(_profile.age!);
      body = l10n.youthShieldAgeProvenBody;
      color = _kSafe;
    } else {
      title = l10n.youthShieldNoAgeTitle;
      body = l10n.youthShieldNoAgeBody;
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
              Icon(
                _profile.isProvenMinor
                    ? Icons.warning_amber_rounded
                    : Icons.shield_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _birthCard(AppLocalizations l10n) {
    final bd = _profile.birthDate;
    final formatted = bd == null
        ? '—'
        : '${bd.day.toString().padLeft(2, '0')}/'
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
                child: Text(
                  formatted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_profile.age != null)
                Text(
                  l10n.youthShieldAgeYears(_profile.age!),
                  style: const TextStyle(color: Colors.white38),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickBirthDate,
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: Text(l10n.youthShieldSetDate),
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
                  child: Text(l10n.youthShieldRemove),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _prefsCard(AppLocalizations l10n) {
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
            title: Text(
              l10n.youthShieldYouthMode,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            subtitle: Text(
              l10n.youthShieldYouthModeSub,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          SwitchListTile(
            value: _profile.adultContentOk,
            onChanged: _saving ? null : _setAdultContentOk,
            activeThumbColor: _kAccent,
            title: Text(
              l10n.youthShieldAdultContent,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            subtitle: Text(
              _profile.isProvenMinor
                  ? l10n.youthShieldAdultBlockedSub
                  : l10n.youthShieldAdultAllowedSub,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
