/// Modelos da Central de Marketing (KLAY K).
///
/// Camada administrativa offline-first que roda sobre o sistema de anúncios
/// existente. Os dados gerados aqui vêm de regras/templates locais — nunca de
/// APIs externas — e as métricas exibidas são sempre reais (RPCs do backend).
library;

/// Objetivo de uma campanha.
class MarketingObjective {
  final String id;
  final String label;
  final String emoji;

  const MarketingObjective(this.id, this.label, this.emoji);

  static const List<MarketingObjective> values = [
    MarketingObjective('aquisicao', 'Aquisição', '🎯'),
    MarketingObjective('engajamento', 'Engajamento', '💬'),
    MarketingObjective('retencao', 'Retenção', '🔁'),
    MarketingObjective('lancamento', 'Lançamento', '🚀'),
    MarketingObjective('awareness', 'Conhecimento', '👀'),
    MarketingObjective('livestream', 'LIVE', '🔴'),
    MarketingObjective('jogos', 'Jogos', '🎮'),
    MarketingObjective('promocao', 'Promoção', '🏷️'),
    MarketingObjective('divulgacao', 'Divulgação', '📣'),
  ];

  static MarketingObjective byId(String? id) {
    return values.firstWhere(
      (o) => o.id == id,
      orElse: () => const MarketingObjective('divulgacao', 'Divulgação', '📣'),
    );
  }
}

/// Formato de veiculação.
class MarketingFormat {
  final String id;
  final String label;
  final String emoji;

  const MarketingFormat(this.id, this.label, this.emoji);

  static const List<MarketingFormat> values = [
    MarketingFormat('video_curto', 'Vídeo curto', '📱'),
    MarketingFormat('video_long', 'Vídeo longo', '🎬'),
    MarketingFormat('imagem', 'Imagem', '🖼️'),
    MarketingFormat('story', 'Story', '⚡'),
    MarketingFormat('carrossel', 'Carrossel', '🎠'),
  ];

  static MarketingFormat byId(String? id) {
    return values.firstWhere((f) => f.id == id, orElse: () => values.first);
  }
}

/// Tom de comunicação.
class MarketingTone {
  final String id;
  final String label;
  final String emoji;

  const MarketingTone(this.id, this.label, this.emoji);

  static const List<MarketingTone> values = [
    MarketingTone('amigavel', 'Amigável', '😊'),
    MarketingTone('profissional', 'Profissional', '💼'),
    MarketingTone('ousado', 'Ousado', '🔥'),
    MarketingTone('inspirador', 'Inspirador', '✨'),
    MarketingTone('urgente', 'Urgente', '⏳'),
    MarketingTone('divertido', 'Divertido', '🎉'),
  ];

  static MarketingTone byId(String? id) {
    return values.firstWhere((t) => t.id == id, orElse: () => values.first);
  }
}

/// Uma variação de anúncio (A/B/C/D/E) gerada pelo Agente.
class MarketingVariation {
  final String label;
  final String title;
  final String description;
  final String cta;

  const MarketingVariation({
    required this.label,
    required this.title,
    required this.description,
    required this.cta,
  });

  String get tagline => title;

  Map<String, dynamic> toJson() => {
    'label': label,
    'title': title,
    'description': description,
    'cta': cta,
  };

  factory MarketingVariation.fromJson(Map<String, dynamic> json) {
    return MarketingVariation(
      label: json['label']?.toString() ?? 'A',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      cta: json['cta']?.toString() ?? '',
    );
  }
}

/// Seção de um roteiro (GANCHO → PROBLEMA → APRESENTAÇÃO → DIFERENCIAL → CTA).
class MarketingScriptSection {
  final String step;
  final String text;

  const MarketingScriptSection({required this.step, required this.text});
}

/// Roteiro de divulgação gerado localmente.
class MarketingScript {
  final String category;
  final List<MarketingScriptSection> sections;
  final int estimatedSeconds;

  const MarketingScript({
    required this.category,
    required this.sections,
    required this.estimatedSeconds,
  });

  String get fullText {
    final buffer = StringBuffer();
    buffer.writeln('Roteiro — $category ($estimatedSeconds s)');
    for (final section in sections) {
      buffer.writeln('');
      buffer.writeln(section.step.toUpperCase());
      buffer.writeln(section.text);
    }
    return buffer.toString();
  }
}

/// Cena de um briefing de criativo (sem geração de imagens — texto + specs).
class BriefScene {
  final String step;
  final String description;

  const BriefScene({required this.step, required this.description});
}

/// Briefing de criativo pronto para copiar.
class MarketingBrief {
  final String format;
  final String product;
  final String objective;
  final String audience;
  final List<String> specs;
  final List<BriefScene> scenes;
  final List<String> doItems;
  final List<String> dontItems;

  const MarketingBrief({
    required this.format,
    required this.product,
    required this.objective,
    required this.audience,
    required this.specs,
    required this.scenes,
    required this.doItems,
    required this.dontItems,
  });

  String get fullText {
    final buffer = StringBuffer();
    buffer.writeln('BRIEFING DE CRIATIVO');
    buffer.writeln('');
    buffer.writeln('Formato: $format');
    buffer.writeln('Produto: $product');
    buffer.writeln('Objetivo: $objective');
    buffer.writeln('Público: $audience');
    buffer.writeln('');
    buffer.writeln('ESPECIFICAÇÕES');
    for (final spec in specs) {
      buffer.writeln('- $spec');
    }
    buffer.writeln('');
    buffer.writeln('CENAS');
    for (final scene in scenes) {
      buffer.writeln('- ${scene.step}: ${scene.description}');
    }
    buffer.writeln('');
    buffer.writeln('FAZER');
    for (final item in doItems) {
      buffer.writeln('- $item');
    }
    buffer.writeln('');
    buffer.writeln('EVITAR');
    for (final item in dontItems) {
      buffer.writeln('- $item');
    }
    return buffer.toString();
  }
}

/// Item do checklist de publicação.
class MarketingChecklistItem {
  final String label;
  final bool checked;

  const MarketingChecklistItem({required this.label, this.checked = false});

  MarketingChecklistItem copyWith({bool? checked}) =>
      MarketingChecklistItem(label: label, checked: checked ?? this.checked);
}

/// Campanha de marketing gerada pelo Agente KLAY K.
class MarketingCampaign {
  final String? id;
  String name;
  String objectiveId;
  String audience;
  String formatId;
  String toneId;
  List<String> keywords;
  String title;
  String description;
  String cta;
  MarketingScript? script;
  List<MarketingChecklistItem> checklist;
  List<MarketingVariation> variations;
  DateTime createdAt;
  DateTime? approvedAt;
  String status; // draft | approved | archived
  final bool localOnly; // ainda não persistida (modo offline)

  MarketingCampaign({
    this.id,
    required this.name,
    required this.objectiveId,
    required this.audience,
    required this.formatId,
    required this.toneId,
    required this.keywords,
    required this.title,
    required this.description,
    required this.cta,
    this.script,
    required this.checklist,
    required this.variations,
    required this.createdAt,
    this.approvedAt,
    required this.status,
    this.localOnly = true,
  });

  MarketingObjective get objective => MarketingObjective.byId(objectiveId);
  MarketingFormat get format => MarketingFormat.byId(formatId);
  MarketingTone get tone => MarketingTone.byId(toneId);

  bool get isApproved => status == 'approved';
  bool get isArchived => status == 'archived';

  int get variantA => variations.isEmpty ? 0 : variations.length;

  String get summary {
    final buffer = StringBuffer();
    buffer.writeln(name);
    buffer.writeln(
      'Objetivo: ${objective.label} · Formato: ${format.label}'
      ' · Tom: ${tone.label}',
    );
    buffer.writeln('Público: $audience');
    if (keywords.isNotEmpty) {
      buffer.writeln('Palavras-chave: ${keywords.join(', ')}');
    }
    buffer.writeln('');
    buffer.writeln('TÍTULO');
    buffer.writeln(title);
    buffer.writeln('');
    buffer.writeln('DESCRIÇÃO');
    buffer.writeln(description);
    buffer.writeln('');
    buffer.writeln('CTA: $cta');
    buffer.writeln('');
    buffer.writeln('VARIAÇÕES (${variations.length})');
    for (final v in variations) {
      buffer.writeln('');
      buffer.writeln('[${v.label}] ${v.title}');
      buffer.writeln(v.description);
      buffer.writeln('CTA: ${v.cta}');
    }
    if (script != null) {
      buffer.writeln('');
      buffer.writeln(script!.fullText);
    }
    buffer.writeln('');
    buffer.writeln('CHECKLIST DE PUBLICAÇÃO');
    for (final item in checklist) {
      buffer.writeln('${item.checked ? '[x]' : '[ ]'} ${item.label}');
    }
    return buffer.toString();
  }

  MarketingCampaign copyWith({
    String? id,
    String? name,
    String? objectiveId,
    String? audience,
    String? formatId,
    String? toneId,
    List<String>? keywords,
    String? title,
    String? description,
    String? cta,
    MarketingScript? script,
    List<MarketingChecklistItem>? checklist,
    List<MarketingVariation>? variations,
    DateTime? approvedAt,
    String? status,
    bool? localOnly,
  }) {
    return MarketingCampaign(
      id: id ?? this.id,
      name: name ?? this.name,
      objectiveId: objectiveId ?? this.objectiveId,
      audience: audience ?? this.audience,
      formatId: formatId ?? this.formatId,
      toneId: toneId ?? this.toneId,
      keywords: keywords ?? this.keywords,
      title: title ?? this.title,
      description: description ?? this.description,
      cta: cta ?? this.cta,
      script: script ?? this.script,
      checklist: checklist ?? this.checklist,
      variations: variations ?? this.variations,
      createdAt: createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
      status: status ?? this.status,
      localOnly: localOnly ?? this.localOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'objective': objectiveId,
    'audience': audience,
    'format': formatId,
    'tone': toneId,
    'keywords': keywords,
    'title': title,
    'description': description,
    'cta': cta,
    'script_category': script?.category ?? '',
    'script_text': script?.fullText ?? '',
    'checklist': checklist.map((i) => i.label).toList(),
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'approved_at': approvedAt?.toIso8601String(),
  };

  factory MarketingCampaign.fromJson(Map<String, dynamic> json) {
    return MarketingCampaign(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? 'Campanha sem nome',
      objectiveId: json['objective']?.toString() ?? 'divulgacao',
      audience: json['audience']?.toString() ?? '',
      formatId: json['format']?.toString() ?? 'video_curto',
      toneId: json['tone']?.toString() ?? 'amigavel',
      keywords:
          (json['keywords'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      cta: json['cta']?.toString() ?? '',
      script: (json['script_text']?.toString() ?? '').isEmpty
          ? null
          : MarketingScript(
              category: json['script_category']?.toString() ?? 'general',
              sections: _scriptSections(json['script_text']?.toString() ?? ''),
              estimatedSeconds: json['script_seconds'] as int? ?? 30,
            ),
      checklist:
          (json['checklist'] as List?)
              ?.map((e) => MarketingChecklistItem(label: e.toString()))
              .toList() ??
          const [],
      variations: _variations(json),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      approvedAt: DateTime.tryParse(json['approved_at']?.toString() ?? ''),
      status: json['status']?.toString() ?? 'draft',
      localOnly: false,
    );
  }

  static List<MarketingVariation> _variations(Map<String, dynamic> json) {
    final variants = json['variants'];
    if (variants is List) {
      return variants
          .whereType<Map>()
          .map((e) => MarketingVariation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  static List<MarketingScriptSection> _scriptSections(String text) {
    final raw = text.split(RegExp(r'\n{2,}'));
    final sections = <MarketingScriptSection>[];
    for (final block in raw) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;
      final step = lines.first.trim().toUpperCase().replaceAll(': ', '');
      final body = lines.skip(1).join(' ').trim();
      if (step.isEmpty) continue;
      sections.add(MarketingScriptSection(step: step, text: body));
    }
    return sections;
  }
}
