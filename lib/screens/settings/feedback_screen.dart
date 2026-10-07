import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/founder_service.dart';
import '../../design/klayk_design.dart';
import '../../widgets/klayk_ux.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Categorias aceitas por `submit_feedback` na migration
/// `20260915000000_feedback_system.sql` — o app não inventa categoria nova.
enum _FeedbackKind { suggestion, bug, praise, other }

/// Feedback do usuário para a equipe do KLAY K.
///
/// O backend já existia (`app_feedback` + RPC `submit_feedback`); o que
/// faltava era esta tela. Não há sistema de votação no servidor, então a tela
/// **não** oferece "votar em ideias" — isso seria um botão falso.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  _FeedbackKind _kind = _FeedbackKind.suggestion;
  int _rating = 4;
  final TextEditingController _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String _kindLabel(AppLocalizations l10n, _FeedbackKind k) => switch (k) {
    _FeedbackKind.suggestion => l10n.feedbackSuggestion,
    _FeedbackKind.bug => l10n.feedbackBug,
    _FeedbackKind.praise => l10n.feedbackPraise,
    _FeedbackKind.other => l10n.feedbackOther,
  };

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context)!;
    final text = _message.text.trim();
    if (text.length < 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.feedbackTooShort)));
      return;
    }
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    // A RPC devolve a linha criada; null = recusa do servidor.
    final res = await FounderService.instance.submitFeedback(
      category: _kind.name,
      rating: _rating,
      message: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    final ok = res.isNotEmpty;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? l10n.feedbackSent : l10n.feedbackFailed)),
    );
    if (ok) _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.feedbackTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            KlaykCard(
              padding: const EdgeInsets.all(14),
              child: Text(
                l10n.feedbackIntro,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _header(l10n.feedbackCategory),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in _FeedbackKind.values)
                  KlayKChip(
                    label: _kindLabel(l10n, k),
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _header(l10n.feedbackRating),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i <= _rating ? const Color(0xFFD4AF37) : _kAccent,
                      size: 28,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _header(l10n.feedbackMessage),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLines: 6,
              maxLength: 1000,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.feedbackMessageHint,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF17141F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2540)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2A2540)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kAccent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(l10n.feedbackSend),
              ),
            ),
            const SizedBox(height: 18),
            _header(l10n.feedbackTrackTitle),
            const SizedBox(height: 8),
            KlaykCard(
              padding: const EdgeInsets.all(14),
              child: Text(
                l10n.feedbackTrackBody,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
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
}