/// Modelos do Sistema Oficial de Anúncios (KLAY K).
/// Mapeiam o schema `public.ad_creatives`/`ad_campaigns`/`advertisers`,
/// sempre seguindo RLS (o app nunca decide APPROVED/VERIFIED — só o backend).
library;

/// Status de um anúncio/campanha (controlado pelo backend).
enum AdStatus {
  draft,
  pendingReview,
  approved,
  rejected,
  paused,
  expired,
  blocked;

  static AdStatus fromRaw(String? raw) {
    switch ((raw ?? 'DRAFT').toUpperCase()) {
      case 'PENDING_REVIEW':
        return AdStatus.pendingReview;
      case 'APPROVED':
        return AdStatus.approved;
      case 'REJECTED':
        return AdStatus.rejected;
      case 'PAUSED':
        return AdStatus.paused;
      case 'EXPIRED':
        return AdStatus.expired;
      case 'BLOCKED':
        return AdStatus.blocked;
      default:
        return AdStatus.draft;
    }
  }
}

/// Reportar categorias de denúncia (fluxo "Denunciar anúncio").
const List<String> kAdReportCategories = [
  'Golpe ou fraude',
  'Conteúdo enganoso',
  'Link suspeito',
  'Spam',
  'Falsa identidade',
  'Oferta enganosa',
  'Conteúdo inadequado',
  'Outro',
];

/// Um anúncio pronto para exibição (apenas APPROVED chega aqui via RLS).
class AdCreative {
  final String id;
  final String campaignId;
  final String campaignName;
  final String title;
  final String description;
  final String mediaUrl;
  final String mediaType;
  final String ctaLabel;
  final String ctaUrl;
  final String ctaType;
  final AdStatus status;
  final String advertiserName;
  final String advertiserLogo;
  final String advertiserCategory;
  final bool verified;
  final int impressions;
  final int clicks;

  const AdCreative({
    required this.id,
    required this.campaignId,
    this.campaignName = '',
    required this.title,
    this.description = '',
    this.mediaUrl = '',
    this.mediaType = 'image',
    this.ctaLabel = 'Saiba mais',
    this.ctaUrl = '',
    this.ctaType = 'link',
    this.status = AdStatus.approved,
    this.advertiserName = '',
    this.advertiserLogo = '',
    this.advertiserCategory = '',
    this.verified = false,
    this.impressions = 0,
    this.clicks = 0,
  });

  factory AdCreative.fromJson(Map<String, dynamic> json) {
    final campaign = _asMap(json['campaign']);
    final advert = _asMap(json['advertiser']);
    final metrics = _asMap(json['metrics']);
    return AdCreative(
      id: json['id']?.toString() ?? '',
      campaignId:
          campaign['id']?.toString() ?? json['campaign_id']?.toString() ?? '',
      campaignName: campaign['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      mediaUrl: json['media_url']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'image',
      ctaLabel: json['cta_label']?.toString() ?? 'Saiba mais',
      ctaUrl: json['cta_url']?.toString() ?? '',
      ctaType: json['cta_type']?.toString() ?? 'link',
      status: AdStatus.fromRaw(json['status']?.toString()),
      advertiserName: advert['business_name']?.toString() ?? '',
      advertiserLogo: advert['business_logo']?.toString() ?? '',
      advertiserCategory: advert['category']?.toString() ?? '',
      verified: advert['is_verified'] as bool? ?? false,
      impressions:
          (metrics['impressions'] as num?)?.toInt() ??
          json['impressions'] as int? ??
          0,
      clicks:
          (metrics['clicks'] as num?)?.toInt() ?? json['clicks'] as int? ?? 0,
    );
  }

  bool get isApproved => status == AdStatus.approved;

  /// Um CTA real precisa ser do tipo `link`, com rótulo e URL http/https.
  /// Anúncio SEM CTA válido nunca renderiza botão (regra §35/§62).
  bool get hasValidCta =>
      ctaType == 'link' &&
      ctaLabel.trim().isNotEmpty &&
      ctaUrl.trim().isNotEmpty;

  /// Parse da RPC pública `ads_public_approved` (colunas achatadas, display-safe).
  factory AdCreative.fromPublicJson(Map<String, dynamic> json) {
    return AdCreative(
      id: json['creative_id']?.toString() ?? '',
      campaignId: json['campaign_id']?.toString() ?? '',
      campaignName: json['campaign_name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      mediaUrl: json['media_url']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'image',
      ctaLabel: json['cta_label']?.toString() ?? 'Saiba mais',
      ctaUrl: json['cta_url']?.toString() ?? '',
      ctaType: json['cta_type']?.toString() ?? 'link',
      status: AdStatus.approved,
      advertiserName: json['business_name']?.toString() ?? '',
      advertiserLogo: json['business_logo']?.toString() ?? '',
      advertiserCategory: json['advertiser_category']?.toString() ?? '',
      verified: json['verified'] as bool? ?? false,
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      clicks: (json['clicks'] as num?)?.toInt() ?? 0,
    );
  }

  double get ctr => impressions == 0 ? 0 : (clicks / impressions * 100);

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((k, e) => MapEntry(k.toString(), e)),
      );
    }
    return const {};
  }
}

/// Linha da "Central de Anúncios" (campanha + creative) do anunciante logado.
class AdCampaignRow {
  final String campaignId;
  final String campaignName;
  final AdStatus campaignStatus;
  final double budget;

  /// Orçamento diário (KLAY$). Vem de `ads_campaigns.daily_budget`, coluna
  /// criada em 20260927120000. Continua vazio enquanto a migration não for
  /// aplicada — a UI trata como "não definido".
  final double? dailyBudget;

  /// Teto de gasto (KLAY$), mesma migration.
  final double? spendCap;

  /// Posicionamentos marcados: for_you, between_videos, highlights, discovery.
  final List<String> placements;

  /// Contagem de cliques, não dinheiro. Ver `ads_my_list()`: a cobrança ainda
  /// não é calculada no servidor, então este campo nunca aparece como moeda.
  final int spent;
  final String creativeId;
  final String title;
  final AdStatus creativeStatus;
  final String media;
  final String cta;
  final String ctaUrl;
  final int impressions;
  final int clicks;
  final String rejectionReason;
  final DateTime createdAt;
  final DateTime? approvedAt;

  const AdCampaignRow({
    required this.campaignId,
    required this.campaignName,
    required this.campaignStatus,
    this.budget = 0,
    this.dailyBudget,
    this.spendCap,
    this.placements = const [],
    this.spent = 0,
    required this.creativeId,
    required this.title,
    required this.creativeStatus,
    this.media = '',
    this.cta = '',
    this.ctaUrl = '',
    this.impressions = 0,
    this.clicks = 0,
    this.rejectionReason = '',
    required this.createdAt,
    this.approvedAt,
  });

  factory AdCampaignRow.fromJson(Map<String, dynamic> json) {
    return AdCampaignRow(
      campaignId: json['campaign_id']?.toString() ?? '',
      campaignName: json['campaign_name']?.toString() ?? '',
      campaignStatus: AdStatus.fromRaw(json['campaign_status']?.toString()),
      budget: (json['budget'] as num?)?.toDouble() ?? 0,
      dailyBudget: (json['daily_budget'] as num?)?.toDouble(),
      spendCap: (json['spend_cap'] as num?)?.toDouble(),
      placements: switch (json['placements']) {
        final List<dynamic> l => l.map((e) => e.toString()).toList(),
        final String s when s.isNotEmpty && s != '{}' =>
          s.replaceAll(RegExp(r'[\[\]{}"]'), '')
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        _ => const <String>[],
      },
      spent: (json['spent'] as num?)?.toInt() ?? 0,
      creativeId: json['creative_id']?.toString() ?? '',
      title: json['creative_title']?.toString() ?? '',
      creativeStatus: AdStatus.fromRaw(json['creative_status']?.toString()),
      media: json['creative_media']?.toString() ?? '',
      cta: json['creative_cta']?.toString() ?? '',
      ctaUrl: json['creative_url']?.toString() ?? '',
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      clicks: (json['clicks'] as num?)?.toInt() ?? 0,
      rejectionReason: json['rejection_reason']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      approvedAt: DateTime.tryParse(json['approved_at']?.toString() ?? ''),
    );
  }

  double get ctr => impressions == 0 ? 0 : (clicks / impressions * 100);
}

/// Métricas agregadas da Central (reais, do backend).
class AdMetrics {
  final int impressions;
  final int clicks;
  final int activeCampaigns;
  final int pendingCampaigns;
  final double budget;

  const AdMetrics({
    this.impressions = 0,
    this.clicks = 0,
    this.activeCampaigns = 0,
    this.pendingCampaigns = 0,
    this.budget = 0,
  });

  factory AdMetrics.fromJson(Map<String, dynamic> json) {
    return AdMetrics(
      impressions: (json['total_impressions'] as num?)?.toInt() ?? 0,
      clicks: (json['total_clicks'] as num?)?.toInt() ?? 0,
      activeCampaigns: (json['active_campaigns'] as num?)?.toInt() ?? 0,
      pendingCampaigns: (json['pending_campaigns'] as num?)?.toInt() ?? 0,
      budget: (json['budget'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Linha administrativa (moderação) de um anúncio.
class AdminAdRow {
  final String creativeId;
  final String campaignId;
  final String title;
  final String description;
  final String media;
  final String cta;
  final String ctaUrl;
  final AdStatus creativeStatus;
  final String campaignName;
  final AdStatus campaignStatus;
  final String businessName;
  final String category;
  final double budget;
  final int impressions;
  final int clicks;
  final String rejectionReason;
  final DateTime createdAt;
  final DateTime? approvedAt;

  const AdminAdRow({
    required this.creativeId,
    required this.campaignId,
    required this.title,
    this.description = '',
    this.media = '',
    this.cta = '',
    this.ctaUrl = '',
    required this.creativeStatus,
    required this.campaignName,
    required this.campaignStatus,
    this.businessName = '',
    this.category = '',
    this.budget = 0,
    this.impressions = 0,
    this.clicks = 0,
    this.rejectionReason = '',
    required this.createdAt,
    this.approvedAt,
  });

  factory AdminAdRow.fromJson(Map<String, dynamic> json) {
    return AdminAdRow(
      creativeId: json['creative_id']?.toString() ?? '',
      campaignId: json['campaign_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      media: json['media']?.toString() ?? '',
      cta: json['cta']?.toString() ?? '',
      ctaUrl: json['cta_url']?.toString() ?? '',
      creativeStatus: AdStatus.fromRaw(json['creative_status']?.toString()),
      campaignName: json['campaign_name']?.toString() ?? '',
      campaignStatus: AdStatus.fromRaw(json['campaign_status']?.toString()),
      businessName: json['business_name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      budget: (json['budget'] as num?)?.toDouble() ?? 0,
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      clicks: (json['clicks'] as num?)?.toInt() ?? 0,
      rejectionReason: json['rejection_reason']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      approvedAt: DateTime.tryParse(json['approved_at']?.toString() ?? ''),
    );
  }
}

/// Uma denúncia (painel administrativo).
class AdReport {
  final String reportId;
  final String creativeId;
  final String title;
  final String category;
  final String description;
  final String status;
  final String reporterUsername;
  final DateTime createdAt;

  const AdReport({
    required this.reportId,
    required this.creativeId,
    required this.title,
    required this.category,
    this.description = '',
    this.status = 'open',
    this.reporterUsername = '',
    required this.createdAt,
  });

  factory AdReport.fromJson(Map<String, dynamic> json) {
    return AdReport(
      reportId: json['report_id']?.toString() ?? '',
      creativeId: json['creative_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: json['report_status']?.toString() ?? 'open',
      reporterUsername: json['reporter_username']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
