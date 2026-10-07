import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketing_models.dart';
import 'supabase_service.dart';

/// Acesso negado na Central de Marketing (backend rejeitou / usuário comum).
class MarketingAccessDeniedException implements Exception {
  const MarketingAccessDeniedException();

  @override
  String toString() => 'Acesso restrito à Central de Marketing.';
}

/// Central de Marketing — camada de dados.
///
/// Toda persistência passa por RPCs `security definer` que re-validam
/// `marketing_is_admin()` no backend. Um usuário comum recebe
/// [MarketingAccessDeniedException], mesmo tentando chamar as funções direto.
/// A geração acontece no [MarketingEngine] (100% local/offline).
class MarketingService {
  MarketingService._();

  static final MarketingService instance = MarketingService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  bool get isConfigured => SupabaseService.instance.isConfigured;

  /// RPC com teto de tempo: uma rota instável/backend lento vira exceção
  /// tratável em vez de travar o botão de salvar/carregar indefinidamente.
  Future<dynamic> _rpc(String fn, {Map<String, dynamic>? params}) =>
      _db.rpc(fn, params: params).timeout(SupabaseService.networkTimeout);

  Future<void> _guard() async {
    if (!isConfigured) {
      throw const MarketingAccessDeniedException();
    }
    await SupabaseService.instance.ensureAuthenticated();
  }

  /// Se o usuário atual é administrador (mesma origem do gate do app).
  Future<bool> isAdmin() async {
    if (!isConfigured) return false;
    try {
      await _guard();
      return await _rpc('marketing_is_admin') == true;
    } catch (_) {
      return false;
    }
  }

  /// Persiste uma campanha (e suas variações). Retorna o id no backend.
  Future<String> saveCampaign(
    MarketingCampaign campaign, {
    String status = 'draft',
  }) async {
    await _guard();
    final res = await _rpc(
      'marketing_save_campaign',
      params: {
        'p_name': campaign.name,
        'p_objective': campaign.objectiveId,
        'p_audience': campaign.audience,
        'p_format': campaign.formatId,
        'p_tone': campaign.toneId,
        'p_keywords': campaign.keywords,
        'p_title': campaign.title,
        'p_description': campaign.description,
        'p_cta': campaign.cta,
        'p_script_category': campaign.script?.category ?? '',
        'p_script_text': campaign.script?.fullText ?? '',
        'p_checklist': campaign.checklist.map((i) => i.label).toList(),
        'p_status': status,
        'p_id': campaign.id,
        'p_variants': jsonEncode(
          campaign.variations.map((v) => v.toJson()).toList(),
        ),
      },
    );
    return (res as String?) ?? campaign.id ?? '';
  }

  /// Lista campanhas persistidas (rascunho/arquivadas/aprovadas).
  Future<List<MarketingCampaign>> listCampaigns({String status = ''}) async {
    await _guard();
    final res = await _rpc(
      'marketing_list_campaigns',
      params: {'p_status': status},
    );
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => MarketingCampaign.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<MarketingCampaign?> getCampaign(String id) async {
    await _guard();
    final res = await _rpc('marketing_get_campaign', params: {'p_id': id});
    if (res is! Map) return null;
    return MarketingCampaign.fromJson(Map<String, dynamic>.from(res));
  }

  /// Aprova (revisão de CEO) ou arquiva. Retorna `false` se nada mudou.
  Future<bool> setStatus(String id, String status) async {
    await _guard();
    final res = await _rpc(
      'marketing_set_status',
      params: {'p_id': id, 'p_status': status},
    );
    return res == true;
  }

  /// Duplica uma campanha salva. Retorna o id da cópia ou `null`.
  Future<String?> duplicate(String id) async {
    await _guard();
    final res = await _rpc(
      'marketing_duplicate_campaign',
      params: {'p_id': id},
    );
    return (res as String?) == null || (res as dynamic) == false
        ? null
        : res.toString();
  }

  /// Exclui campanha (apenas rascunho/arquivada — aprovada arquiva antes).
  Future<bool> delete(String id) async {
    await _guard();
    final res = await _rpc('marketing_delete_campaign', params: {'p_id': id});
    return res == true;
  }

  // ---------------------------------------------------------------------------
  // Briefings
  // ---------------------------------------------------------------------------

  Future<String> saveBrief({
    required String title,
    required String format,
    required String product,
    required String briefText,
    String? id,
  }) async {
    await _guard();
    final res = await _rpc(
      'marketing_save_brief',
      params: {
        'p_title': title,
        'p_format': format,
        'p_product': product,
        'p_brief_text': briefText,
        'p_id': id,
      },
    );
    return (res as String?) ?? id ?? '';
  }

  Future<List<Map<String, dynamic>>> listBriefs() async {
    await _guard();
    final res = await _rpc('marketing_list_briefs');
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<bool> deleteBrief(String id) async {
    await _guard();
    final res = await _rpc('marketing_delete_brief', params: {'p_id': id});
    return res == true;
  }

  // ---------------------------------------------------------------------------
  // Métricas reais (nunca inventadas) — agrega os dados do sistema de anúncios.
  // Retorna null quando não há dados suficientes para calcular.
  // ---------------------------------------------------------------------------

  /// Agregado de desempenho de anúncios para o dashboard da Central.
  /// `null` = não é admin ou backend não configurado.
  Future<MarketingSummary?> adminMetrics() async {
    if (!isConfigured) return null;
    try {
      final rows = await _rpc(
        'admin_ads_list',
        params: {'p_status': '', 'p_advertiser_name': '', 'p_category': ''},
      );
      return MarketingSummary.fromRows(rows);
    } catch (_) {
      return null;
    }
  }
}

/// Resumo agregado de métricas reais de anúncios (dashboard da Central).
///
/// Caso de "Dados insuficientes" (sem impressões): [hasData] é `false` e a UI
/// mostra "Dados insuficientes para calcular." — nunca inventamos números.
class MarketingSummary {
  final int impressions;
  final int clicks;
  final int approved;
  final int rejected;
  final int paused;
  final int blocked;
  final int advertisers;

  const MarketingSummary({
    required this.impressions,
    required this.clicks,
    required this.approved,
    required this.rejected,
    required this.paused,
    required this.blocked,
    required this.advertisers,
  });

  bool get hasData => impressions > 0;

  String? get ctrText {
    if (!hasData) return null;
    final ctr = clicks / impressions * 100;
    return '${ctr.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  static const MarketingSummary empty = MarketingSummary(
    impressions: 0,
    clicks: 0,
    approved: 0,
    rejected: 0,
    paused: 0,
    blocked: 0,
    advertisers: 0,
  );

  factory MarketingSummary.fromRows(dynamic r) {
    if (r is! List) return MarketingSummary.empty;
    var impressions = 0;
    var clicks = 0;
    var approved = 0;
    var rejected = 0;
    var paused = 0;
    var blocked = 0;
    final advertisers = <String>{};

    for (final row in r.whereType<Map>()) {
      final imp = (row['impressions'] as num?)?.toInt() ?? 0;
      final clk = (row['clicks'] as num?)?.toInt() ?? 0;
      impressions += imp;
      clicks += clk;
      final status = (row['creative_status'] ?? row['status'] ?? '')
          .toString()
          .toUpperCase();
      switch (status) {
        case 'APPROVED':
          approved++;
        case 'REJECTED':
          rejected++;
        case 'PAUSED':
          paused++;
        case 'BLOCKED':
          blocked++;
      }
      final name = row['business_name']?.toString() ?? '';
      if (name.isNotEmpty) advertisers.add(name);
    }

    return MarketingSummary(
      impressions: impressions,
      clicks: clicks,
      approved: approved,
      rejected: rejected,
      paused: paused,
      blocked: blocked,
      advertisers: advertisers.length,
    );
  }
}
