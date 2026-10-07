import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/security_models.dart';
import '../../services/security_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kSafe = Color(0xFF34D399);
const Color _kWarn = Color(0xFFFFB020);
const Color _kDanger = Color(0xFFFF4D6A);

/// Centro de Denúncias — histórico real do próprio usuário (`my_reports`) +
/// nova denúncia via RPC `file_report` (com anti-abuso no backend: dedupe de
/// 24h por alvo e limite de 10/h).
class ReportCenterScreen extends StatefulWidget {
  const ReportCenterScreen({super.key});

  @override
  State<ReportCenterScreen> createState() => _ReportCenterScreenState();
}

class _ReportCenterScreenState extends State<ReportCenterScreen> {
  final SecurityService _svc = SecurityService.instance;

  bool _loading = true;
  List<ReportEntry> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await _svc.myReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
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

  Future<void> _newReport() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16151F),
      builder: (_) => _ReportFormSheet(svc: _svc),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.reportCenterTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : RefreshIndicator(
              onRefresh: _load,
              color: _kAccent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ElevatedButton.icon(
                    onPressed: _newReport,
                    icon: const Icon(Icons.report_gmailerrorred_rounded),
                    label: Text(
                      l10n.reportCenterNewReport,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.reportCenterIntro,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (_reports.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            color: Colors.white24,
                            size: 44,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.reportCenterEmpty,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final r in _reports) _reportTile(r, l10n),
                ],
              ),
            ),
    );
  }

  Widget _reportTile(ReportEntry r, AppLocalizations l10n) {
    final color = _statusColor(r.status);
    return Card(
      color: const Color(0xFF16151F),
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.targetLabel.toUpperCase(),
                    style: const TextStyle(
                      color: _kAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusLabel(l10n, r.status).toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              r.reason,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (r.details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                r.details,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60),
              ),
            ],
            if (r.resolution.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.reportCenterResolution(r.resolution),
                style: const TextStyle(color: _kSafe, fontSize: 13),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${l10n.reportCenterSentAt(_fmt(r.createdAt))}'
              '${r.reviewedAt != null ? l10n.reportCenterReviewedAt(_fmt(r.reviewedAt)) : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return _kSafe;
      case 'dismissed':
        return Colors.blueGrey;
      case 'reviewing':
        return _kWarn;
      default:
        return _kDanger;
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'resolved':
        return l10n.reportStatusResolved;
      case 'dismissed':
        return l10n.reportStatusDismissed;
      case 'reviewing':
        return l10n.reportStatusReviewing;
      default:
        return l10n.reportStatusPending;
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ReportFormSheet extends StatefulWidget {
  final SecurityService svc;
  const _ReportFormSheet({required this.svc});

  @override
  State<_ReportFormSheet> createState() => _ReportFormSheetState();
}

class _ReportFormSheetState extends State<_ReportFormSheet> {
  String _targetType = 'post';
  final TextEditingController _targetId = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _details = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _targetId.dispose();
    _reason.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final targetId = _targetId.text.trim();
    final reason = _reason.text.trim();
    if (targetId.isEmpty) return _snack(l10n.reportTargetIdRequired);
    if (reason.length < 3) {
      return _snack(l10n.reportReasonMinChars);
    }
    setState(() => _submitting = true);
    try {
      await widget.svc.fileReport(
        targetType: _targetType,
        targetId: targetId,
        reason: reason,
        details: _details.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.reportCenterNewReport,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.reportAntiAbuse,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _targetType,
              dropdownColor: const Color(0xFF1B1A26),
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(l10n.reportTargetType),
              items: [
                DropdownMenuItem(value: 'user', child: Text(l10n.user)),
                DropdownMenuItem(
                  value: 'post',
                  child: Text(l10n.reportTargetPost),
                ),
                DropdownMenuItem(value: 'live', child: Text(l10n.live)),
                DropdownMenuItem(
                  value: 'comment',
                  child: Text(l10n.reportTargetComment),
                ),
                DropdownMenuItem(
                  value: 'chat',
                  child: Text(l10n.reportTargetChat),
                ),
              ],
              onChanged: (v) => setState(() => _targetType = v ?? 'post'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _targetId,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(l10n.reportTargetIdHint),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: _decoration(l10n.reportReasonHint),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _details,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: _decoration(l10n.reportDetailsHint),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        l10n.reportSubmit,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: const Color(0xFF1B1A26),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );
}
