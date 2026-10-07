import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/local_prefs_service.dart';
import '../../services/locale_controller.dart';
import '../../services/maintenance_service.dart';
import '../../widgets/klayk_ux.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Manutenção do aplicativo.
///
/// "Reiniciar configurações" restaura **apenas preferências locais**
/// (idioma, acessibilidade, bem-estar digital). Nunca toca em conta, vídeos,
/// mensagens, moedas ou qualquer dado do servidor — o botão diz isso na tela.
class MaintenanceScreen extends StatefulWidget {
  /// Chamado quando o usuário reinicia as preferências.
  final VoidCallback? onReset;

  /// Abre o diagnóstico real do KLAY K.
  final VoidCallback? onDiagnostics;

  const MaintenanceScreen({
    super.key,
    this.onReset,
    this.onDiagnostics,
  });

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _loading = true;
  bool _cleaning = false;
  int? _cacheBytes;
  int? _tempBytes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final m = await MaintenanceService.instance.measure();
    if (!mounted) return;
    setState(() {
      _cacheBytes = m?.cache;
      _tempBytes = m?.temp;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    if (_cleaning) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _cleaning = true);
    final r = await MaintenanceService.instance.clearCache();
    await _measure();
    if (!mounted) return;
    setState(() => _cleaning = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          r.removedAnything
              ? l10n.maintenanceCacheCleared(
                  MaintenanceService.formatBytes(r.totalBytes),
                )
              : l10n.maintenanceCacheEmpty,
        ),
      ),
    );
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17141F),
        title: Text(l10n.maintenanceResetTitle),
        content: Text(
          l10n.maintenanceResetBody,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.maintenanceResetAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Só preferências locais. Nada de conta, servidor ou mídia.
    await LocalPrefsService.instance.update(
      LocalPrefsService.instance.prefs.value.copyWithReset(),
    );
    await AppLanguageController.instance.setLocale(
      AppLanguageController.defaultLocale,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.maintenanceResetDone)));
    widget.onReset?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.maintenanceTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _header(l10n.maintenanceStorage),
            const SizedBox(height: 8),
            KlaykCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _row(
                    l10n.maintenanceCache,
                    _loading
                        ? '…'
                        : MaintenanceService.formatBytes(_cacheBytes ?? 0),
                  ),
                  const Divider(color: Color(0xFF2A2540), height: 20),
                  _row(
                    l10n.maintenanceTempFiles,
                    _loading
                        ? '…'
                        : MaintenanceService.formatBytes(_tempBytes ?? 0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: _cleaning || _loading ? null : _clear,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _cleaning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(l10n.maintenanceClearCache),
              ),
            ),
            const SizedBox(height: 20),
            _header(l10n.maintenanceCheck),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.science_rounded,
              title: l10n.maintenanceDiagnostics,
              onTap: widget.onDiagnostics,
            ),
            _tile(
              icon: Icons.system_update_rounded,
              title: l10n.maintenanceUpdates,
              subtitle: l10n.maintenanceUpdatesBody,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.maintenanceUpdatesDone)),
              ),
            ),
            const SizedBox(height: 20),
            _header(l10n.maintenanceReset),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.restart_alt_rounded,
              title: l10n.maintenanceResetAction,
              subtitle: l10n.maintenanceResetSubtitle,
              danger: true,
              onTap: _reset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Text(
    text,
    style: const TextStyle(
      color: _kAccent,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    ),
  );

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFFF4D6A) : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KlaykCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: danger ? color : _kAccent, size: 20),
          title: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
        ),
      ),
    );
  }
}