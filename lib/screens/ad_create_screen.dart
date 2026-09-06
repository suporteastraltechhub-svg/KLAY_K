import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../design/klayk_design.dart';
import '../models/ad_models.dart';
import '../services/ads_service.dart';
import '../services/supabase_service.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/klayk_ux.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Fluxo en etapas de criação de un anuncio.
/// 1. Contenido (título, descripción, media, CTA, destino).
/// 2. Campaña (nombre, período, presupuesto, público).
/// 3. Revisar (vista previa tal como se mostrará) + "Sobre este anunciante".
///
/// Los datos sólo se persisten al final: se crea campaña DRAFT y creative
/// PENDING_REVIEW (jamás APPROVED por el cliente).
class AdCreateScreen extends StatefulWidget {
  const AdCreateScreen({super.key});

  @override
  State<AdCreateScreen> createState() => _AdCreateScreenState();
}

const List<String> _kCtaOptions = [
  'Saiba mais',
  'Ver agora',
  'Conhecer',
  'Comprar',
  'Baixar',
  'Participar',
];

const List<String> _kObjectives = [
  'Alcance',
  'Tráfico',
  'Engagement',
  'Conhecimento de marca',
];

class _AdCreateScreenState extends State<AdCreateScreen> {
  int _step = 1;

  // ETAPA 1 — contenido
  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _mediaUrlCtrl = TextEditingController();
  String _mediaUrl = '';
  String _mediaType = 'image';
  String _cta = 'Saiba mais';
  final TextEditingController _ctaUrl = TextEditingController();

  // ETAPA 2 — campaña / público
  final TextEditingController _campaignName = TextEditingController();
  String _objective = 'Alcance';
  final TextEditingController _budget = TextEditingController(text: '0');
  final TextEditingController _audience = TextEditingController();
  final TextEditingController _interests = TextEditingController();
  final TextEditingController _region = TextEditingController();
  DateTime? _start;
  DateTime? _end;

  // ETAPA 3 — anunciante (Sobre este anunciante)
  final TextEditingController _businessName = TextEditingController();
  final TextEditingController _businessCategory = TextEditingController();
  final TextEditingController _businessAbout = TextEditingController();

  bool _submitting = false;
  bool _uploadingMedia = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _configured = SupabaseService.instance.isConfigured;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _mediaUrlCtrl.dispose();
    _ctaUrl.dispose();
    _campaignName.dispose();
    _budget.dispose();
    _audience.dispose();
    _interests.dispose();
    _region.dispose();
    _businessName.dispose();
    _businessCategory.dispose();
    _businessAbout.dispose();
    super.dispose();
  }

  bool _canNext() {
    if (_step == 1) {
      return _title.text.trim().isNotEmpty &&
          (_ctaUrl.text.trim().isNotEmpty || _cta != 'Saiba mais');
    }
    if (_step == 2) {
      return _campaignName.text.trim().isNotEmpty;
    }
    return _businessName.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_configured) return;
    setState(() => _submitting = true);
    try {
      final budget = double.tryParse(_budget.text.trim()) ?? 0;
      final campaignId = await AdsService.instance.createCampaign(
        name: _campaignName.text.trim(),
        objective: _objective.toLowerCase(),
        budget: budget,
        audience: _audience.text.trim(),
        interests: _interests.text.trim(),
        region: _region.text.trim(),
        startDate: _start,
        endDate: _end,
      );
      await AdsService.instance.upsertAdvertiser(
        businessName: _businessName.text.trim(),
        category: _businessCategory.text.trim(),
        about: _businessAbout.text.trim(),
      );
      await AdsService.instance.createCreative(
        campaignId: campaignId,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        mediaUrl: _mediaUrl,
        mediaType: _mediaType,
        ctaLabel: _cta,
        ctaUrl: _ctaUrl.text.trim(),
        submit: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar o anúncio.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickMedia() async {
    if (_uploadingMedia) return;
    final fromCamera =
        await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enviar arquivo do dispositivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'A mídia vai para o bucket ad-media do KLAY K.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              _mediaPickTile(
                sheetCtx,
                Icons.camera_alt_outlined,
                _mediaType == 'video' ? 'Gravar vídeo' : 'Tirar foto',
                () => ImageSource.camera,
              ),
              _mediaPickTile(
                sheetCtx,
                Icons.photo_library_outlined,
                _mediaType == 'video' ? 'Vídeo da galeria' : 'Galeria',
                () => ImageSource.gallery,
              ),
            ],
          ),
        ),
      ),
    );
    if (fromCamera == null) return;
    try {
      setState(() => _uploadingMedia = true);
      if (_mediaType == 'video') {
        final picked = await ImagePicker().pickVideo(
          source: fromCamera,
          maxDuration: const Duration(minutes: 2),
        );
        if (picked == null) {
          if (mounted) setState(() => _uploadingMedia = false);
          return;
        }
        final url = await AdsService.instance.uploadAdMedia(
          File(picked.path),
          picked.name,
          mimeType: picked.mimeType ?? 'video/mp4',
        );
        if (!mounted) return;
        setState(() {
          _uploadingMedia = false;
          _mediaUrl = url ?? '';
          if (url != null && _mediaUrlCtrl.text != url) {
            _mediaUrlCtrl.text = url;
          }
        });
        if (url == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível enviar a mídia.')),
          );
        }
        return;
      }
      final picked = await ImagePicker().pickImage(
        source: fromCamera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) {
        if (mounted) setState(() => _uploadingMedia = false);
        return;
      }
      final url = await AdsService.instance.uploadAdMedia(
        File(picked.path),
        picked.name,
        mimeType: picked.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploadingMedia = false;
        _mediaType = 'image';
        _mediaUrl = url ?? '';
        if (url != null && _mediaUrlCtrl.text != url) {
          _mediaUrlCtrl.text = url;
        }
      });
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar a mídia.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingMedia = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mídia.')),
      );
    }
  }

  Widget _mediaPickTile(BuildContext ctx, IconData icon, String label,
      ImageSource Function() source) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0x228B5CF6),
        child: Icon(icon, color: const Color(0xFF8B5CF6), size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: Colors.white54, size: 20),
      onTap: () => Navigator.of(ctx).pop(source()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          _stepLabel(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_step > 1) {
              setState(() => _step--);
            } else {
              Navigator.of(context).pop(false);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stepper(),
              const SizedBox(height: 16),
              if (!_configured) ...[
                const KlaykEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Backend no configurado',
                  message:
                      'Conecta Supabase para crear un anuncio en KLAY K.',
                ),
                const SizedBox(height: 16),
              ],
              if (_step == 1) _stepContent(),
              if (_step == 2) _stepCampaign(),
              if (_step == 3) _stepReview(),
              const SizedBox(height: 24),
              _navButtons(),
            ],
          ),
        ),
      ),
    );
  }

  String _stepLabel() {
    switch (_step) {
      case 2:
        return 'Campaña';
      case 3:
        return 'Revisar anuncio';
      default:
        return 'Contenido';
    }
  }

  Widget _stepper() {
    const labels = ['Contenido', 'Campaña', 'Revisar'];
    return Row(
      children: List.generate(labels.length, (i) {
        final n = i + 1;
        final active = n == _step;
        final done = n < _step;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active || done
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFF2A2540),
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(Icons.check_circle, color: Colors.white, size: 16)
                  : Text(
                      '$n',
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              labels[i],
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (i < labels.length - 1) ...[
              const SizedBox(width: 8),
              const Expanded(
                child: Divider(
                  thickness: 2,
                  color: Color(0xFF2A2540),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        );
      }),
    );
  }

  Widget _navButtons() {
    if (_step < 3) {
      return SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _canNext() ? () => setState(() => _step++) : null,
          style: FilledButton.styleFrom(
            backgroundColor: _kAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.arrow_forward_ios_rounded),
          label: const Text('Continuar'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _submitting || !_showAdvertiserForm() ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Enviar para análise'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text(
            'Volver y editar',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      ],
    );
  }

  bool _showAdvertiserForm() => _businessName.text.trim().isNotEmpty;

  Widget _stepContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Título del anuncio'),
        TextField(
          controller: _title,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('¿De qué trata?'),
        ),
        const SizedBox(height: 8),
        _fieldLabel('Descripción'),
        TextField(
          controller: _desc,
          maxLines: 4,
          maxLength: 300,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Descripción breve…'),
        ),
        const SizedBox(height: 12),
        _mediaField(),
        const SizedBox(height: 12),
        _ctaField(),
      ],
    );
  }

  Widget _mediaField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Medios (imagen o vídeo)'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _mediaChip('image', 'Imagen', Icons.image_rounded),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _mediaChip('video', 'Vídeo', Icons.videocam_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mediaUrlCtrl,
          maxLength: 255,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('URL de la imagem ou vídeo…'),
          onChanged: (t) => setState(() => _mediaUrl = t.trim()),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _uploadingMedia ? null : _pickMedia,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              side: const BorderSide(color: Color(0xFF3A3355)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _uploadingMedia
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(
              _uploadingMedia ? 'Enviando…' : 'Enviar do dispositivo',
            ),
          ),
        ),
        if (_mediaUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.greenAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Mídia definida (${_mediaType == 'image' ? 'imagem' : 'vídeo'}).',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mediaChip(String type, String label, IconData icon) {
    final sel = _mediaType == type;
    return InkWell(
      onTap: () => setState(() => _mediaType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0x228B5CF6) : const Color(0xFF17141F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? const Color(0xFF8B5CF6) : const Color(0xFF2A2540),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: sel ? const Color(0xFF8B5CF6) : Colors.white38, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: sel ? Colors.white : Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctaField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Botón / CTA'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: _kCtaOptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _kCtaOptions[i];
              return KlayKChip(
                label: c,
                selected: _cta == c,
                onTap: () => setState(() => _cta = c),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctaUrl,
          maxLength: 255,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Destino del anuncio (URL)'),
        ),
      ],
    );
  }

  Widget _stepCampaign() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Nombre de la campaña'),
        TextField(
          controller: _campaignName,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Ej: Lanzamiento primavera'),
        ),
        const SizedBox(height: 8),
        _fieldLabel('Objetivo'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: _kObjectives.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final o = _kObjectives[i];
              return KlayKChip(
                label: o,
                selected: _objective == o,
                onTap: () => setState(() => _objective = o),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _fieldLabel('Presupuesto (KLAY\$)'),
        TextField(
          controller: _budget,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('0'),
        ),
        const SizedBox(height: 8),
        _fieldLabel('Período de campaña'),
        Row(
          children: [
            Expanded(child: _dateChip('Inicio', _start, (d) => _start = d)),
            const SizedBox(width: 10),
            Expanded(child: _dateChip('Fin', _end, (d) => _end = d)),
          ],
        ),
        const SizedBox(height: 8),
        _fieldLabel('Público e intereses'),
        TextField(
          controller: _audience,
          maxLength: 120,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Público objetivo…'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _interests,
          maxLength: 120,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Intereses (separados por coma)…'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _region,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Región (opcional)'),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, color: Colors.white38, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No usamos segmentación invasiva: no vendemos ni compartimos tus datos personales.',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dateChip(String label, DateTime? value, void Function(DateTime?) onSet) {
    return InkWell(
      onTap: () => onSet(DateTime.now()),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF17141F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2540)),
        ),
        alignment: Alignment.center,
        child: Text(
          value == null ? '…' : value.toString(),
          style: TextStyle(
            color: value == null ? Colors.white38 : Colors.white70,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _stepReview() {
    final preview = AdCreative(
      id: 'preview',
      campaignId: '',
      campaignName: _campaignName.text.trim(),
      title: _title.text.trim(),
      description: _desc.text.trim(),
      mediaUrl: _mediaUrl,
      mediaType: _mediaType,
      ctaLabel: _cta,
      ctaUrl: _ctaUrl.text.trim(),
      advertiserName: _businessName.text.trim(),
      advertiserCategory: _businessCategory.text.trim(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Así verán tu anuncio',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pré-visualização: ainda não publicado. O sello oficial só aparece '
          'se o anúncio for aprovado pela equipe do KLAY K.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 14),
        AdCard(ad: preview, preview: true),
        const SizedBox(height: 16),
        _advertiserSection(),
      ],
    );
  }

  Widget _advertiserSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Sobre este anunciante'),
        TextField(
          controller: _businessName,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Nombre del anunciante'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _businessCategory,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Categoría'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _businessAbout,
          maxLines: 3,
          maxLength: 200,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Sobre el anunciante…'),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user, color: Color(0xFFD4AF37), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'La verificación la decide el KLAY K. El sello oficial es controlado por el sistema, no por el anunciante.',
                style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
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
    );
  }
}