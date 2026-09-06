import 'package:flutter/material.dart';

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
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('Explique por que você merece o selo de verificação.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final req = await AccountService.instance.submitVerificationRequest(reason);
      if (!mounted) return;
      setState(() {
        _request = req;
        _submitting = false;
      });
      _snack('Solicitação enviada! Fique atento à resposta.');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      final msg = e.toString().contains('23505')
          ? 'Você já tem uma solicitação em andamento.'
          : 'Erro ao enviar: $e';
      _snack(msg);
      _load();
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Verificação de perfil',
            style: TextStyle(fontWeight: FontWeight.w800)),
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
                  _bodyHeader(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _bodyText(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 24),
                if (_verified)
                  const Center(
                    child: Text('Seu perfil é verificado. Obrigado!',
                        style: TextStyle(color: Colors.white54)),
                  )
                else if (_request != null)
                  _statusCard(_request!)
                else ...[
                  TextField(
                    controller: _reasonCtrl,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText:
                          'Explique por que devemos verificar seu perfil (ex.: '
                          'artista, marca ou figura pública)...',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1B1A26),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFF3A3550)),
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
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Solicitar verificação',
                            style:
                                TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'A aprovação é feita pela equipe do KLAY K. Não é possível '
                  'comprar ou solicitar aprovação instantânea.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
    );
  }

  String _bodyHeader() {
    if (_verified) return 'Perfil verificado';
    if (_request != null) {
      return switch (_request!.status) {
        'approved' => 'Verificação aprovada',
        'rejected' => 'Solicitação recusada',
        _ => 'Solicitação em análise',
      };
    }
    return 'Solicite seu selo de verificação';
  }

  String _bodyText() {
    if (_verified) {
      return 'Seu perfil possui o selo de verificação oficial do KLAY K.';
    }
    if (_request != null) {
      return switch (_request!.status) {
        'approved' =>
          'Parabéns! Sua conta agora exibe o selo de verificação oficial.',
        'rejected' =>
          'Infelizmente sua solicitação não foi aprovada neste momento. '
              'Você pode tentar novamente mais tarde.',
        _ =>
          'Recebemos sua solicitação. Nossa equipe está avaliando e você será '
              'notificado assim que houver uma resposta.',
      };
    }
    return 'Destaque sua autenticidade com o selo oficial do KLAY K. Envie sua '
        'solicitação e a equipe irá analisá-la.';
  }

  Widget _statusCard(VerificationRequest req) {
    final (icon, color, title, sub) = switch (req.status) {
      'approved' => (
          Icons.check_circle,
          Colors.greenAccent,
          'Aprovado',
          'Selo concedido à sua conta.'
        ),
      'rejected' => (
          Icons.cancel,
          const Color(0xFFFF4D6A),
          'Recusado',
          req.adminNote.isNotEmpty ? req.adminNote : 'Tente novamente mais tarde.'
        ),
      _ => (
          Icons.hourglass_top,
          Colors.orangeAccent,
          'Em análise',
          'Você será avisado assim que houver um veredito.'
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
