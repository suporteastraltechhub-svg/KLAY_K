import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../design/klayk_design.dart';
import '../l10n/app_localizations.dart';
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
  final TextEditingController _dailyBudget = TextEditingController();
  final TextEditingController _spendCap = TextEditingController();

  /// Posicionamentos marcados (constraint do servidor: for_you, between_videos,
  /// highlights, discovery). Vazio = padrão do KLAY K.
  final Set<String> _placements = <String>{};
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
    // Reavalia _canNext() a cada digitação: sem onChanged, os botões de
    // navegação ficariam "travados" no estado do último build.
    for (final c in [_title, _ctaUrl, _campaignName, _businessName]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_title, _ctaUrl, _campaignName, _businessName]) {
      c.removeListener(_onFieldChanged);
    }
    _title.dispose();
    _desc.dispose();
    _mediaUrlCtrl.dispose();
    _ctaUrl.dispose();
    _campaignName.dispose();
    _budget.dispose();
    _dailyBudget.dispose();
    _spendCap.dispose();
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

  /// Valida tudo antes de enviar. O servidor continua sendo a autoridade:
  /// isto só evita ida-e-volta e dá mensagens claras em português.
  ///
  /// [relaxed] = rascunho: exige só o mínimo para retomar a edição depois
  /// (título e campanha). Mídia e destino só são exigidos no envio real.
  List<String> _validate({bool relaxed = false}) {
    final l10n = AppLocalizations.of(context)!;
    final errors = <String>[];

    if (_title.text.trim().isEmpty) errors.add(l10n.adErrTitleRequired);
    if (_campaignName.text.trim().isEmpty) {
      errors.add(l10n.adErrNameRequired);
    }
    if (!relaxed && _businessName.text.trim().isEmpty) {
      errors.add(l10n.adErrBusinessNameRequired);
    }

    final ctaUrl = _ctaUrl.text.trim();
    if (ctaUrl.isNotEmpty && !_isValidUrl(ctaUrl)) {
      errors.add(l10n.adErrCtaUrlInvalid);
    }

    if (!relaxed && _mediaUrl.isEmpty) errors.add(l10n.adErrMediaRequired);

    final budgetRaw = _budget.text.trim();
    if (budgetRaw.isEmpty) {
      errors.add(l10n.adErrBudgetRequired);
    } else {
      final budget = double.tryParse(budgetRaw.replaceAll(',', '.'));
      if (budget == null || budget <= 0) {
        errors.add(l10n.adErrBudgetPositive);
      }
    }

    if (!relaxed && (_start == null || _end == null)) {
      errors.add(l10n.adErrDatesRequired);
    } else if (_start != null && _end != null) {
      final today = DateTime.now();
      final startDay = DateTime(_start!.year, _start!.month, _start!.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      if (startDay.isBefore(todayDay) || !_end!.isAfter(_start!)) {
        errors.add(l10n.adErrDateOrder);
      }
    }
    return errors;
  }

  static bool _isValidUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return uri.host.isNotEmpty;
  }

  void _showErrors(List<String> errors) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.adCreateFixErrorsTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            ...errors.map(
              (e) => Text('• $e', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  /// Persiste a campanha/criativo. [submit] = false salva como rascunho
  /// (`ads_create_creative` aceita `p_submit`), true envia para análise.
  ///
  /// Orçamento diário, limite e posicionamento vivem em colunas novas
  /// (migration 20260927120000). Se o servidor ainda não as tem, o anúncio é
  /// enviado assim mesmo e devolvemos [false] para a UI avisar — nada some
  /// silenciosamente.
  Future<bool> _persist({required bool submit}) async {
    final budget =
        double.tryParse(_budget.text.trim().replaceAll(',', '.')) ?? 0;
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
      submit: submit,
    );

    final daily =
        double.tryParse(_dailyBudget.text.trim().replaceAll(',', '.'));
    final cap = double.tryParse(_spendCap.text.trim().replaceAll(',', '.'));
    final hasExtras =
        daily != null || cap != null || _placements.isNotEmpty;
    if (!hasExtras) return true;

    final r = await AdsService.instance.updateCampaign(
      campaignId: campaignId,
      name: _campaignName.text.trim(),
      dailyBudget: daily,
      spendCap: cap,
      placements: _placements.isEmpty ? null : (_placements.toList()..sort()),
    );
    return r == AdOpResult.ok;
  }

  Future<void> _submit() async {
    if (!_configured) return;
    final l10n = AppLocalizations.of(context)!;
    final errors = _validate();
    if (errors.isNotEmpty) {
      _showErrors(errors);
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final full = await _persist(submit: true);
      if (!mounted) return;
      navigator.pop(true);
      if (!full) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.adSavePendingBackend)),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adCreateSubmitFailed)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// "Salvar rascunho" aceita um formulário menos completo que o envio:
  /// rascunho é para retomar depois, não para passar por análise.
  Future<void> _saveDraft() async {
    if (!_configured) return;
    final errors = _validate(relaxed: true);
    if (errors.isNotEmpty) {
      _showErrors(errors);
      return;
    }
    setState(() => _submitting = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _persist(submit: false);
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adCreateDraftSaved)),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adCreateDraftSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickMedia(AppLocalizations l10n) async {
    if (_uploadingMedia) return;
    final fromCamera = await showModalBottomSheet<ImageSource>(
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l10n.adCreateSheetUploadTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  l10n.adCreateSheetUploadSubtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              _mediaPickTile(
                sheetCtx,
                l10n,
                Icons.camera_alt_outlined,
                _mediaType == 'video'
                    ? l10n.adCreateRecordVideo
                    : l10n.adCreateTakePhoto,
                () => ImageSource.camera,
              ),
              _mediaPickTile(
                sheetCtx,
                l10n,
                Icons.photo_library_outlined,
                _mediaType == 'video'
                    ? l10n.adCreateVideoGallery
                    : l10n.adCreateGallery,
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.adCreateMediaFailed)));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.adCreateMediaFailed)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingMedia = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adCreateMediaFailed)));
    }
  }

  Widget _mediaPickTile(
    BuildContext ctx,
    AppLocalizations l10n,
    IconData icon,
    String label,
    ImageSource Function() source,
  ) {
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
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Colors.white54,
        size: 20,
      ),
      onTap: () => Navigator.of(ctx).pop(source()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          _stepLabel(l10n),
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
              _stepper(l10n),
              const SizedBox(height: 16),
              if (!_configured) ...[
                KlaykEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: l10n.adsBackendNotConfigured,
                  message: l10n.adsBackendNotConfiguredBody,
                ),
                const SizedBox(height: 16),
              ],
              if (_step == 1) _stepContent(l10n),
              if (_step == 2) _stepCampaign(l10n),
              if (_step == 3) _stepReview(l10n),
              const SizedBox(height: 24),
              _navButtons(l10n),
            ],
          ),
        ),
      ),
    );
  }

  String _stepLabel(AppLocalizations l10n) {
    switch (_step) {
      case 2:
        return l10n.adCreateStepCampaign;
      case 3:
        return l10n.adCreateStepReview;
      default:
        return l10n.adCreateStepContent;
    }
  }

  Widget _stepper(AppLocalizations l10n) {
    final labels = [
      l10n.adCreateStepContent,
      l10n.adCreateStepCampaign,
      l10n.adCreateStepReview,
    ];
    return Row(
      children: List.generate(labels.length * 2 - 1, (i) {
        // Separador flexível apenas no Row externo (com largura limitada).
        // O Expanded nunca pode viver num Row aninhado com mainAxisSize.min:
        // um Row horizontal dentro de outro Row horizontal recebe largura
        // ilimitada e o flex estoura ("black screen" de toda a página).
        if (i.isOdd) {
          return const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Divider(thickness: 2, color: Color(0xFF2A2540)),
            ),
          );
        }
        final n = i ~/ 2 + 1;
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
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 16,
                    )
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
              labels[n - 1],
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _navButtons(AppLocalizations l10n) {
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
          label: Text(l10n.continueAction),
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
            label: Text(l10n.adCreateSubmit),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _submitting ? null : _saveDraft,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: const BorderSide(color: Color(0xFF3A3355)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(l10n.adCreateSaveDraft),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: Text(
            l10n.adCreateBackEdit,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      ],
    );
  }

  bool _showAdvertiserForm() => _businessName.text.trim().isNotEmpty;

  Widget _stepContent(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(l10n.adCreateFieldAdTitle),
        TextField(
          controller: _title,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintWhatAbout),
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.descriptionLabel),
        TextField(
          controller: _desc,
          maxLines: 4,
          maxLength: 300,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintShortDescription),
        ),
        const SizedBox(height: 12),
        _mediaField(l10n),
        const SizedBox(height: 12),
        _ctaField(l10n),
      ],
    );
  }

  Widget _mediaField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(l10n.adCreateFieldMedia),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _mediaChip(
                l10n,
                'image',
                l10n.adCreateMediaImage,
                Icons.image_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _mediaChip(
                l10n,
                'video',
                l10n.videoLabel,
                Icons.videocam_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mediaUrlCtrl,
          maxLength: 255,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintMediaUrl),
          onChanged: (t) => setState(() => _mediaUrl = t.trim()),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _uploadingMedia ? null : () => _pickMedia(l10n),
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
              _uploadingMedia
                  ? l10n.adCreateUploading
                  : l10n.adCreateSendDevice,
            ),
          ),
        ),
        if (_mediaUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.greenAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _mediaType == 'image'
                        ? l10n.adCreateMediaSetImage
                        : l10n.adCreateMediaSetVideo,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mediaChip(
    AppLocalizations l10n,
    String type,
    String label,
    IconData icon,
  ) {
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
            Icon(
              icon,
              color: sel ? const Color(0xFF8B5CF6) : Colors.white38,
              size: 18,
            ),
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

  Widget _ctaField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(l10n.adCreateFieldCta),
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
          decoration: _decoration(l10n.adCreateHintCtaUrl),
        ),
      ],
    );
  }

  Widget _stepCampaign(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(l10n.adCreateFieldCampaignName),
        TextField(
          controller: _campaignName,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintCampaignName),
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.adCreateFieldObjective),
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
        _fieldLabel(l10n.adCreateFieldBudget),
        TextField(
          controller: _budget,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('0'),
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.adFieldDailyBudget),
        TextField(
          controller: _dailyBudget,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adPlacementDefault),
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.adFieldSpendCap),
        TextField(
          controller: _spendCap,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adPlacementDefault),
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.adFieldPlacement),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in kAdPlacements)
              KlayKChip(
                label: _placementLabel(l10n, p),
                selected: _placements.contains(p),
                onTap: () => setState(() {
                  if (!_placements.remove(p)) _placements.add(p);
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.adCreateFieldPeriod),
        Row(
          children: [
            Expanded(
              child: _dateChip(
                l10n.adCreateDateStart,
                _start,
                (d) => _start = d,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateChip(l10n.adCreateDateEnd, _end, (d) => _end = d),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _fieldLabel(l10n.adCreateFieldAudience),
        TextField(
          controller: _audience,
          maxLength: 120,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintAudience),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _interests,
          maxLength: 120,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintInterests),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _region,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintRegion),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.adCreatePrivacyNote,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _placementLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'for_you' => l10n.adPlacementForYou,
      'between_videos' => l10n.adPlacementBetweenVideos,
      'highlights' => l10n.adPlacementHighlights,
      _ => l10n.adPlacementDiscovery,
    };
  }

  Widget _dateChip(
    String label,
    DateTime? value,
    void Function(DateTime?) onSet,
  ) {
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

  Widget _stepReview(AppLocalizations l10n) {
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
        Text(
          l10n.adCreateReviewTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.adCreateReviewBody,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 14),
        AdCard(ad: preview, preview: true),
        const SizedBox(height: 16),
        _summaryCard(l10n),
        const SizedBox(height: 16),
        _advertiserSection(l10n),
      ],
    );
  }

  /// Resumo do que será enviado: público, posicionamento, orçamento, período,
  /// mídia e destino. Só mostra campos que o app realmente vai persistir.
  Widget _summaryCard(AppLocalizations l10n) {
    final budget =
        double.tryParse(_budget.text.trim().replaceAll(',', '.')) ?? 0;
    final period = (_start == null || _end == null)
        ? '—'
        : '${_fmtDate(_start!)} → ${_fmtDate(_end!)}';
    return KlayKCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.adReviewSummaryTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(l10n.adReviewAudience, _audience.text.trim()),
          _summaryRow(
            l10n.adReviewPlacement,
            _placements.isEmpty
                ? l10n.adPlacementDefault
                : (_placements.toList()..sort())
                      .map((p) => _placementLabel(l10n, p))
                      .join(' · '),
          ),
          _summaryRow(l10n.adsBudgetLabel, budget.toStringAsFixed(0)),
          _summaryRow(l10n.adReviewPeriod, period),
          _summaryRow(
            l10n.adCreateFieldMedia,
            _mediaUrl.isEmpty
                ? '—'
                : (_mediaType == 'video'
                      ? l10n.videoLabel
                      : l10n.adCreateMediaImage),
          ),
          _summaryRow(l10n.adReviewDestination, _ctaUrl.text.trim()),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _advertiserSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(l10n.adCreateFieldAdvertiser),
        TextField(
          controller: _businessName,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintAdvertiserName),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _businessCategory,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.categoryLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _businessAbout,
          maxLines: 3,
          maxLength: 200,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(l10n.adCreateHintAdvertiserAbout),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user, color: Color(0xFFD4AF37), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.adCreateVerificationNote,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.4,
                ),
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
