import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ad_models.dart';
import 'supabase_service.dart';

/// Resultado de uma ação de gerenciamento de campanha.
///
/// [unavailable] significa que a função ainda não existe no servidor — a
/// migration `20260927120000_ads_campaign_management` não foi aplicada. A UI
/// usa esse estado para avisar o anunciante em vez de fingir que a ação
/// funcionou.
enum AdOpResult { ok, unavailable, failed }

/// Posicionamentos de anúncio aceitos pelo servidor
/// (constraint `ad_campaigns_placements_valid`).
const List<String> kAdPlacements = [
  'for_you',
  'between_videos',
  'highlights',
  'discovery',
];

/// Camada de dados do Sistema Oficial de Anúncios (KLAY K).
///
/// Decisões de status/curadoria/verificação NUNCA são tomadas aqui: tudo é
/// validado no backend via RPCs `security definer` + RLS. O app apenas lê o
/// que a política permite (público → só anúncios aprovados; anunciante → suas
/// próprias campanhas/métricas; admin → moderação).
class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  bool get isConfigured => SupabaseService.instance.isConfigured;

  // ---------------------------------------------------------------------------
  // Público: anúncios aprovados + preferências de "ocultar"
  // ---------------------------------------------------------------------------

  /// Anúncios aprovados prontos para exibição no feed, sem os que o usuário
  /// ocultou e sem dados privados (usa a RPC pública `security definer` que
  /// expõe apenas colunas seguras para display).
  Future<List<AdCreative>> fetchApprovedAds({int limit = 10}) async {
    if (!isConfigured) return const [];
    final hidden = await _myHiddenCreativeIds();
    try {
      final r = await _db.rpc(
        'ads_public_approved',
        params: {'p_limit': limit},
      );
      if (r is! List) return const [];
      return r
          .whereType<Map>()
          .map((e) => AdCreative.fromPublicJson(Map<String, dynamic>.from(e)))
          .where((a) => a.isApproved && !hidden.contains(a.id))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Set<String>> _myHiddenCreativeIds() async {
    final user = _db.auth.currentUser;
    if (user == null) return const {};
    try {
      final res = await _db
          .from('ad_user_preferences')
          .select('creative_id')
          .eq('user_id', user.id)
          .eq('hidden', true);
      return (res as List)
          .whereType<Map>()
          .map((e) => e['creative_id']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> hideCreative(String creativeId) async {
    if (!isConfigured) return;
    try {
      await _db.rpc('ads_hide_creative', params: {'p_creative_id': creativeId});
    } catch (_) {}
  }

  Future<void> reportCreative(
    String creativeId,
    String category, {
    String description = '',
  }) async {
    if (!isConfigured) return;
    await _db.rpc(
      'ads_report_creative',
      params: {
        'p_creative_id': creativeId,
        'p_category': category,
        'p_description': description,
      },
    );
  }

  Future<void> trackEvent(String creativeId, String type) async {
    if (!isConfigured) return;
    try {
      await _db.rpc(
        'ads_track_event',
        params: {'p_creative_id': creativeId, 'p_event_type': type},
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Anunciante: perfil, campaigns e creatives
  // ---------------------------------------------------------------------------

  Future<String> upsertAdvertiser({
    String businessName = '',
    String category = '',
    String about = '',
    String website = '',
    String contact = '',
  }) async {
    final r = await _db.rpc(
      'ads_upsert_advertiser',
      params: {
        'p_business_name': businessName,
        'p_category': category,
        'p_about': about,
        'p_website': website,
        'p_contact': contact,
      },
    );
    return r?.toString() ?? '';
  }

  Future<String> createCampaign({
    required String name,
    String objective = 'reach',
    double budget = 0,
    String audience = '',
    String interests = '',
    String region = '',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final r = await _db.rpc(
      'ads_create_campaign',
      params: {
        'p_name': name,
        'p_objective': objective,
        'p_budget': budget,
        'p_audience': audience,
        'p_interests': interests,
        'p_region': region,
        'p_start_date': startDate?.toUtc().toIso8601String(),
        'p_end_date': endDate?.toUtc().toIso8601String(),
      },
    );
    return r?.toString() ?? '';
  }

  Future<String> createCreative({
    required String campaignId,
    required String title,
    String description = '',
    String mediaUrl = '',
    String mediaType = 'image',
    String ctaLabel = 'Saiba mais',
    String ctaUrl = '',
    String ctaType = 'link',
    bool submit = true,
  }) async {
    final r = await _db.rpc(
      'ads_create_creative',
      params: {
        'p_campaign_id': campaignId,
        'p_title': title,
        'p_description': description,
        'p_media_url': mediaUrl,
        'p_media_type': mediaType,
        'p_cta_label': ctaLabel,
        'p_cta_url': ctaUrl,
        'p_cta_type': ctaType,
        'p_submit': submit,
      },
    );
    return r?.toString() ?? '';
  }

  /// O servidor ainda não tem a função pedida (migration não aplicada).
  static bool _isMissingRpc(Object e) {
    if (e is! PostgrestException) return false;
    if (e.code == 'PGRST202' || e.code == '42883') return true;
    final msg = '${e.message} ${e.details}';
    return msg.contains('does not exist') ||
        msg.contains('Could not find the function') ||
        msg.contains('function public.ads_');
  }

  /// Invoca uma RPC nova de gerenciamento mapeando o erro para [AdOpResult].
  Future<AdOpResult> _manage(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    if (!isConfigured) return AdOpResult.failed;
    try {
      await _db.rpc(rpc, params: params);
      return AdOpResult.ok;
    } on PostgrestException catch (e) {
      if (_isMissingRpc(e)) return AdOpResult.unavailable;
      // not_owner / invalid_budget / invalid_status → recusa legítima.
      return AdOpResult.failed;
    } catch (_) {
      return AdOpResult.failed;
    }
  }

  /// Pausa, retoma ou encerra a campanha. `action` ∈ pause|resume|end.
  Future<AdOpResult> setCampaignStatus(
    String campaignId,
    String action,
  ) => _manage('ads_set_campaign_status', {
    'p_campaign_id': campaignId,
    'p_action': action,
  });

  /// Exclui um rascunho. O servidor só aceita criativo DRAFT do próprio
  /// anunciante (o app também pede confirmação antes).
  Future<AdOpResult> deleteDraft(String creativeId) =>
      _manage('ads_delete_draft', {'p_creative_id': creativeId});

  /// Reenvia para análise um criativo DRAFT ou REJECTED.
  Future<AdOpResult> resubmitCreative(String creativeId) =>
      _manage('ads_resubmit_creative', {'p_creative_id': creativeId});

  /// Salva orçamento diário, limite e posicionamento da campanha.
  Future<AdOpResult> updateCampaign({
    required String campaignId,
    required String name,
    double? budget,
    double? dailyBudget,
    double? spendCap,
    List<String>? placements,
  }) => _manage('ads_update_campaign', {
    'p_campaign_id': campaignId,
    'p_name': name,
    'p_budget': budget,
    'p_daily_budget': dailyBudget,
    'p_spend_cap': spendCap,
    'p_placements': placements,
  });

  /// Duplica a campanha como rascunho, num único passo transacional.
  /// Cai para o caminho via [duplicateCampaign] se a RPC ainda não existir.
  Future<AdOpResult> duplicateCampaignFast(AdCampaignRow source) async {
    final viaRpc = await _manage('ads_duplicate_campaign', {
      'p_campaign_id': source.campaignId,
    });
    if (viaRpc != AdOpResult.unavailable) return viaRpc;
    return await duplicateCampaign(source)
        ? AdOpResult.ok
        : AdOpResult.failed;
  }

  /// Cria uma cópia de uma campanha existente como **rascunho**.
  ///
  /// Reutiliza apenas RPCs já existentes: cria uma campanha nova com os
  /// mesmos parâmetros e um criativo em DRAFT (`p_submit = false`), para o
  /// anunciante ajustar antes de reenviar. Não apaga nem altera a original.
  Future<bool> duplicateCampaign(AdCampaignRow source) async {
    if (!isConfigured) return false;
    try {
      final newCampaignId = await createCampaign(
        name: source.campaignName.isEmpty
            ? source.title
            : source.campaignName,
        budget: source.budget,
        startDate: source.createdAt,
        endDate: source.approvedAt,
      );
      if (newCampaignId.isEmpty) return false;
      await createCreative(
        campaignId: newCampaignId,
        title: source.title,
        mediaUrl: source.media,
        ctaLabel: source.cta.isEmpty ? 'Saiba mais' : source.cta,
        ctaUrl: source.ctaUrl,
        submit: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `ads_my_list` usa RLS/security definer e nunca expõe dados privados.
  Future<List<AdCampaignRow>> myCampaigns() async {
    if (!isConfigured) return const [];
    try {
      final r = await _db.rpc('ads_my_list');
      if (r is! List) return const [];
      return r
          .whereType<Map>()
          .map((e) => AdCampaignRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<AdMetrics> myMetrics() async {
    if (!isConfigured) return const AdMetrics();
    try {
      final r = await _db.rpc('ads_my_metrics');
      if (r is! Map) return const AdMetrics();
      return AdMetrics.fromJson(Map<String, dynamic>.from(r));
    } catch (_) {
      return const AdMetrics();
    }
  }

  // ---------------------------------------------------------------------------
  // Admin / moderação
  // ---------------------------------------------------------------------------

  Future<bool> isAdAdmin() async {
    if (!isConfigured) return false;
    try {
      return await _db.rpc('ad_is_admin') == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<AdminAdRow>> adminList({
    String status = '',
    String advertiser = '',
    String category = '',
  }) async {
    if (!isConfigured) return const [];
    try {
      final r = await _db.rpc(
        'admin_ads_list',
        params: {
          'p_status': status,
          'p_advertiser_name': advertiser,
          'p_category': category,
        },
      );
      if (r is! List) return const [];
      return r
          .whereType<Map>()
          .map((e) => AdminAdRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AdReport>> adminReports() async {
    if (!isConfigured) return const [];
    try {
      final r = await _db.rpc('admin_ads_reports');
      if (r is! List) return const [];
      return r
          .whereType<Map>()
          .map((e) => AdReport.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> adminApprove(String creativeId, {String reason = ''}) async {
    await _db.rpc(
      'admin_ads_approve',
      params: {'p_creative_id': creativeId, 'p_reason': reason},
    );
  }

  Future<void> adminReject(String creativeId, String reason) async {
    await _db.rpc(
      'admin_ads_reject',
      params: {'p_creative_id': creativeId, 'p_reason': reason},
    );
  }

  Future<void> adminRequestChanges(String creativeId, String reason) async {
    await _db.rpc(
      'admin_ads_request_changes',
      params: {'p_creative_id': creativeId, 'p_reason': reason},
    );
  }

  Future<void> adminPause(String creativeId) async {
    await _db.rpc('admin_ads_pause', params: {'p_creative_id': creativeId});
  }

  Future<void> adminBlock(String creativeId, String reason) async {
    await _db.rpc(
      'admin_ads_block',
      params: {'p_creative_id': creativeId, 'p_reason': reason},
    );
  }

  // ---------------------------------------------------------------------------
  // Upload de mídia do anúncio (bucket `ad-media`). Retorna URL pública.
  // ---------------------------------------------------------------------------

  /// Sobe a [file] (imagem/vídeo) ao bucket `ad-media` e retorna a URL pública.
  Future<String?> uploadAdMedia(
    File file,
    String fileName, {
    String? mimeType,
  }) async {
    if (!isConfigured) return null;
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final mime = mimeType ?? 'application/octet-stream';
    try {
      final path =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}-$fileName';
      await _db.storage
          .from('ad-media')
          .upload(
            path,
            file,
            fileOptions: FileOptions(
              cacheControl: '3600',
              contentType: mime,
              upsert: false,
            ),
          );
      return _db.storage.from('ad-media').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureAdMediaBucket() async {
    if (!isConfigured) return;
    try {
      await _db.storage.listBuckets();
    } catch (_) {}
  }
}
