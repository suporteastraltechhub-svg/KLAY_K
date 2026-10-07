import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/account_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Tela de verificação de perfil do KLAY K.
/// Submete uma solicitação `pending` persistida no Supabase. A aprovação é
/// manual e exclusiva da equipe (service role) — o app NUNCA concede o selo
/// sozinho.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _loading = true;
  bool _verified = false;
  VerificationRequest? _request;
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final verified = await AccountService.instance.isVerified();
      final request = await AccountService.instance.fetchVerificationRequest();
      if (!mounted) return;
      setState(() {
        _verified = verified;
        _request = request;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack(l10n.verificationReasonEmpty);
      return;
    }
    setState(() => _submitting = true);
    try {
      final req = await AccountService.instance.submitVerificationRequest(
        reason,
      );
      if (!mounted) return;
      setState(() {
        _request = req;
        _submitting = false;
      });
      _snack(l10n.verificationSubmitted);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      final msg = e.toString().contains('23505')
          ? l10n.verificationPendingDuplicate
          : l10n.verificationSubmitError(e.toString());
      _snack(msg);
      _load();
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.profileVerification,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1B1A26),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _verified
                          ? Icons.verified_rounded
                          : Icons.verified_outlined,
                      color: _kAccent,
                      size: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _bodyHeader(l10n),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _bodyText(l10n),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 24),
                if (_verified)
                  Center(
                    child: Text(
                      l10n.verificationVerifiedThanks,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                else if (_request != null)
                  _statusCard(_request!, l10n)
                else ...[
                  TextField(
                    controller: _reasonCtrl,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText: l10n.verificationReasonHint,
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1B1A26),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3A3550)),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                            l10n.requestVerification,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  l10n.verificationApprovalNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
    );
  }

  String _bodyHeader(AppLocalizations l10n) {
    if (_verified) return l10n.verificationHeaderVerified;
    if (_request != null) {
      return switch (_request!.status) {
        'approved' => l10n.verificationHeaderApproved,
        'rejected' => l10n.verificationHeaderRejected,
        _ => l10n.verificationHeaderPending,
      };
    }
    return l10n.verificationHeaderRequest;
  }

  String _bodyText(AppLocalizations l10n) {
    if (_verified) {
      return l10n.verificationBodyVerified;
    }
    if (_request != null) {
      return switch (_request!.status) {
        'approved' => l10n.verificationBodyApproved,
        'rejected' => l10n.verificationBodyRejected,
        _ => l10n.verificationBodyPending,
      };
    }
    return l10n.verificationBodyRequest;
  }

  Widget _statusCard(VerificationRequest req, AppLocalizations l10n) {
    final (icon, color, title, sub) = switch (req.status) {
      'approved' => (
        Icons.check_circle,
        Colors.greenAccent,
        l10n.verificationBadgeApproved,
        l10n.verificationBadgeApprovedSub,
      ),
      'rejected' => (
        Icons.cancel,
        const Color(0xFFFF4D6A),
        l10n.verificationBadgeRejected,
        req.adminNote.isNotEmpty
            ? req.adminNote
            : l10n.verificationBadgeRejectedSub,
      ),
      _ => (
        Icons.hourglass_top,
        Colors.orangeAccent,
        l10n.statusInProgress,
        l10n.verificationBadgePendingSub,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
