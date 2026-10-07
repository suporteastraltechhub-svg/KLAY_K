import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/account_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Central de Ajuda do KLAY K.
/// FAQ estático honesto + suporte por tickets persistidos no Supabase.
/// As respostas de atendimento são feitas por painel administrativo
/// (service role) e aparecem aqui quando foram respondidas.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  bool _loading = true;
  List<SupportTicket> _tickets = [];

  final _categoryIds = [
    'conta',
    'video',
    'live',
    'pagamento',
    'privacidade',
    'outro',
  ];

  String _categoryLabel(String id, AppLocalizations l10n) {
    return switch (id) {
      'conta' => l10n.ticketCategoryAccount,
      'video' => l10n.ticketCategoryVideo,
      'live' => l10n.ticketCategoryLive,
      'pagamento' => l10n.ticketCategoryPayment,
      'privacidade' => l10n.ticketCategoryPrivacy,
      _ => l10n.ticketCategoryOther,
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tickets = await AccountService.instance.fetchMyTickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewTicket() async {
    final l10n = AppLocalizations.of(context)!;
    final category = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF17151F),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _categoryIds
              .map(
                (id) => ListTile(
                  leading: const Icon(Icons.category_outlined, color: _kAccent),
                  title: Text(
                    _categoryLabel(id, AppLocalizations.of(ctx)!),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(ctx, id),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (category == null || !mounted) return;

    final subjectCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    final result = await showDialog<_TicketDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(_categoryLabel(category, AppLocalizations.of(ctx)!)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectCtrl,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(ctx)!.contactSubjectHint,
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3550)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(ctx)!.contactMessageHint,
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3550)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              _TicketDraft(subjectCtrl.text.trim(), msgCtrl.text.trim()),
            ),
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (result == null || result.subject.isEmpty || result.message.isEmpty) {
      if (result != null) {
        _snack(l10n.ticketFieldsRequired);
      }
      return;
    }

    try {
      await AccountService.instance.submitTicket(
        category: category,
        subject: result.subject,
        message: result.message,
      );
      _snack(l10n.ticketCreated);
      _load();
    } catch (e) {
      _snack(l10n.ticketCreateError(e.toString()));
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
          l10n.helpCenter,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicket,
        backgroundColor: _kAccent,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(l10n.talkToSupport),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _faqItem(l10n.faqUploadTitle, l10n.faqUploadBody),
          _faqItem(l10n.faqVerificationTitle, l10n.faqVerificationBody),
          _faqItem(l10n.faqContentTitle, l10n.faqContentBody),
          _faqItem(l10n.faqModerationTitle, l10n.faqModerationBody),
          _faqItem(l10n.faqUnblockTitle, l10n.faqUnblockBody),
          const SizedBox(height: 24),
          _sectionHeader(l10n.myTicketsSection),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: _kAccent)),
            )
          else if (_tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  l10n.noTicketsYet,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ..._tickets.map((t) => _ticketCard(t, l10n)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _faqItem(String q, String a) {
    return ExpansionTile(
      leading: const Icon(Icons.help_outline, color: _kAccent),
      title: Text(
        q,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      backgroundColor: const Color(0xFF1B1A26),
      collapsedBackgroundColor: const Color(0xFF1B1A26),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            a,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text) => Padding(
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

  Widget _ticketCard(SupportTicket t, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.subject,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _statusChip(t.status, l10n),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _categoryLabel(t.category, l10n),
            style: const TextStyle(color: _kAccent, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            t.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.ticketSentOn(_fmt(t.createdAt)),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (t.adminReply.isNotEmpty) ...[
            const Divider(color: Color(0xFF2A2740), height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.support_agent, color: _kAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.adminReply,
                    style: const TextStyle(color: Colors.white70, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status, AppLocalizations l10n) {
    final (label, color) = switch (status) {
      'answered' => (l10n.ticketStatusAnswered, Colors.greenAccent),
      'in_review' => (l10n.statusInProgress, Colors.orangeAccent),
      'closed' => (l10n.statusClosed, Colors.grey),
      _ => (l10n.statusOpen, _kAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _TicketDraft {
  final String subject;
  final String message;
  const _TicketDraft(this.subject, this.message);
}
