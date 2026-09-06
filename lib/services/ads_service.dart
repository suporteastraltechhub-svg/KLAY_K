import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ad_models.dart';
import 'supabase_service.dart';

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
      final r = await _db.rpc('ads_public_approved', params: {'p_limit': limit});
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
    await _db.rpc('ads_report_creative', params: {
      'p_creative_id': creativeId,
      'p_category': category,
      'p_description': description,
    });
  }

  Future<void> trackEvent(String creativeId, String type) async {
    if (!isConfigured) return;
    try {
      await _db.rpc('ads_track_event', params: {
        'p_creative_id': creativeId,
        'p_event_type': type,
      });
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
    final r = await _db.rpc('ads_upsert_advertiser', params: {
      'p_business_name': businessName,
      'p_category': category,
      'p_about': about,
      'p_website': website,
      'p_contact': contact,
    });
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
    final r = await _db.rpc('ads_create_campaign', params: {
      'p_name': name,
      'p_objective': objective,
      'p_budget': budget,
      'p_audience': audience,
      'p_interests': interests,
      'p_region': region,
      'p_start_date': startDate?.toUtc().toIso8601String(),
      'p_end_date': endDate?.toUtc().toIso8601String(),
    });
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
    final r = await _db.rpc('ads_create_creative', params: {
      'p_campaign_id': campaignId,
      'p_title': title,
      'p_description': description,
      'p_media_url': mediaUrl,
      'p_media_type': mediaType,
      'p_cta_label': ctaLabel,
      'p_cta_url': ctaUrl,
      'p_cta_type': ctaType,
      'p_submit': submit,
    });
    return r?.toString() ?? '';
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
      final r = await _db.rpc('admin_ads_list', params: {
        'p_status': status,
        'p_advertiser_name': advertiser,
        'p_category': category,
      });
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
    await _db.rpc('admin_ads_approve', params: {
      'p_creative_id': creativeId,
      'p_reason': reason,
    });
  }

  Future<void> adminReject(String creativeId, String reason) async {
    await _db.rpc('admin_ads_reject', params: {
      'p_creative_id': creativeId,
      'p_reason': reason,
    });
  }

  Future<void> adminRequestChanges(String creativeId, String reason) async {
    await _db.rpc('admin_ads_request_changes', params: {
      'p_creative_id': creativeId,
      'p_reason': reason,
    });
  }

  Future<void> adminPause(String creativeId) async {
    await _db.rpc('admin_ads_pause', params: {'p_creative_id': creativeId});
  }

  Future<void> adminBlock(String creativeId, String reason) async {
    await _db.rpc('admin_ads_block', params: {
      'p_creative_id': creativeId,
      'p_reason': reason,
    });
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
      final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}-$fileName';
      await _db.storage.from('ad-media').upload(
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