import 'package:flutter/material.dart';

import '../models/ad_models.dart';
import '../services/ads_service.dart';

/// Bottom sheet "Denunciar anúncio". Categorias fixas + descrição opcional.
/// Registra no backend via RPC (limite anti-spam de 3 denúncias abertas).
class AdReportSheet extends StatefulWidget {
  final String creativeId;
  const AdReportSheet({super.key, required this.creativeId});

  @override
  State<AdReportSheet> createState() => _AdReportSheetState();
}

class _AdReportSheetState extends State<AdReportSheet> {
  String? _category;
  final TextEditingController _desc = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cat = _category;
    if (cat == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AdsService.instance
          .reportCreative(widget.creativeId, cat, description: _desc.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denúncia registrada. Obrigado!')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Já registrei muitas denúncias abertas. Aguarde a análise.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3355),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Denunciar anúncio',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'O que você quer reportar?',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...List.generate(kAdReportCategories.length, (i) {
              final c = kAdReportCategories[i];
              final selected = _category == c;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _category = c),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x228B5CF6)
                          : const Color(0xFF17141F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF8B5CF6)
                            : const Color(0xFF2A2540),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? const Color(0xFF8B5CF6)
                              : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          c,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
            TextField(
              controller: _desc,
              maxLines: 3,
              maxLength: 300,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Descrição opcional…',
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
                  borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: _category == null || _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                    : const Text('Enviar denúncia'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}