import 'dart:math';

import '../../models/marketing_models.dart';

/// Agente KLAY K — motor local de marketing.
///
/// Gera títulos, descrições, CTAs, campanhas, roteiros e briefings a partir de
/// regras e templates. É 100% offline e determinístico (seeded): NÃO chama
/// APIs externas, não gasta créditos e não depende de rede. Dados reais de
/// desempenho vêm exclusivamente das RPCs do backend (ver `MarketingService`).
class MarketingEngine {
  MarketingEngine._();

  // ---------------------------------------------------------------------------
  // Sanitização
  // ---------------------------------------------------------------------------

  /// Normaliza texto livre: remove caracteres de controle, espaços duplos e
  /// quebras exageradas. Nunca falha com entrada vazia.
  static String clean(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  /// Normaliza lista de palavras-chave (remove `#`, minúsculas, dedupe).
  static List<String> cleanKeywords(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final k in raw) {
      final cleaned = clean(k).replaceAll('#', '').toLowerCase();
      if (cleaned.isEmpty) continue;
      if (seen.add(cleaned)) out.add(cleaned);
    }
    return out;
  }

  /// Produto com fallback genérico para entrada vazia.
  static String productFallback(String product) {
    final cleaned = clean(product);
    return cleaned.isEmpty ? 'nossa novidade' : cleaned;
  }

  // ---------------------------------------------------------------------------
  // Determinação de audiência
  // ---------------------------------------------------------------------------

  static String suggestAudience(String objectiveId, String product) {
    final p = productFallback(product);
    switch (objectiveId) {
      case 'aquisicao':
        return 'Usuários novos no KLAY K interessados em $p';
      case 'engajamento':
        return 'Usuários ativos que curtem $p';
      case 'retencao':
        return 'Usuários que já interagiram com $p';
      case 'lancamento':
        return 'Fãs e primeiros adotantes de $p';
      case 'livestream':
        return 'Quem acompanha LIVES e bate-papos sobre $p';
      case 'jogos':
        return 'Gamers e players que jogam $p';
      case 'promocao':
        return 'Público sensível a ofertas de $p';
      case 'awareness':
      default:
        return 'Público geral do KLAY K que busca $p';
    }
  }

  // ---------------------------------------------------------------------------
  // Geração da campanha
  // ---------------------------------------------------------------------------

  static MarketingCampaign generateCampaign({
    required String objectiveId,
    required String product,
    String audience = '',
    String formatId = 'video_curto',
    String toneId = 'amigavel',
    List<String> keywords = const [],
  }) {
    final productClean = productFallback(product);
    final kw = cleanKeywords(keywords);
    final objective = MarketingObjective.byId(objectiveId);
    final audienceFinal = clean(audience).isEmpty
        ? suggestAudience(objectiveId, productClean)
        : clean(audience);

    final seed = _hashSeed(
      '$objectiveId|$productClean|$toneId|${kw.join(',')}',
    );
    final rng = Random(seed);

    final variations = _generateVariations(
      objectiveId: objectiveId,
      productClean: productClean,
      toneId: toneId,
      keywords: kw,
      rng: rng,
      count: 5,
    );
    final main = variations.isNotEmpty ? variations.first : null;
    final script = _scriptFor(
      objectiveId: objectiveId,
      productClean: productClean,
      formatId: formatId,
      keywords: kw,
      rng: rng,
    );

    return MarketingCampaign(
      name:
          '${objective.emoji} ${objective.label} — ${_titleCase(productClean)}',
      objectiveId: objectiveId,
      audience: audienceFinal,
      formatId: formatId,
      toneId: toneId,
      keywords: kw,
      title: main?.title ?? 'Conheça $productClean',
      description: main?.description ?? 'Saiba mais sobre $productClean.',
      cta: main?.cta ?? 'Saiba mais',
      script: script,
      checklist: _defaultChecklist(),
      variations: variations,
      createdAt: DateTime.now(),
      status: 'draft',
      localOnly: true,
    );
  }

  /// Gera pelo menos [count] variações distintas (A, B, C, ...).
  static List<MarketingVariation> generateVariations({
    required String objectiveId,
    required String product,
    String toneId = 'amigavel',
    List<String> keywords = const [],
    int count = 5,
  }) {
    final productClean = productFallback(product);
    final kw = cleanKeywords(keywords);
    final seed = _hashSeed(
      '$objectiveId|$productClean|$toneId|${kw.join(',')}',
    );
    return _generateVariations(
      objectiveId: objectiveId,
      productClean: productClean,
      toneId: toneId,
      keywords: kw,
      rng: Random(seed),
      count: count,
    );
  }

  static List<MarketingVariation> _generateVariations({
    required String objectiveId,
    required String productClean,
    required String toneId,
    required List<String> keywords,
    required Random rng,
    required int count,
  }) {
    final titles = _titlesFor(objectiveId, productClean, keywords, rng);
    final descriptions = _descriptionsFor(
      objectiveId,
      productClean,
      toneId,
      rng,
    );
    final ctas = _ctasFor(objectiveId);

    final seen = <String>{};
    final variations = <MarketingVariation>[];
    var attempts = 0;
    while (variations.length < count && attempts < 120) {
      attempts++;
      final ti = rng.nextInt(titles.length);
      final di = rng.nextInt(descriptions.length);
      final ci = rng.nextInt(ctas.length);
      final title = titles[ti];
      final description = descriptions[di];
      final cta = ctas[ci];
      final key = '$title#$description#$cta';
      if (!seen.add(key)) continue;
      variations.add(
        MarketingVariation(
          label: _letterFor(variations.length),
          title: title,
          description: description,
          cta: cta,
        ),
      );
    }
    return variations;
  }

  static String _letterFor(int index) {
    const letters = 'ABCDEFGHIJ';
    return letters[index % letters.length].toString();
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  // ---------------------------------------------------------------------------
  // Template pools
  // ---------------------------------------------------------------------------

  static List<String> _titlesFor(
    String objectiveId,
    String p,
    List<String> keywords,
    Random rng,
  ) {
    final k = keywords.isNotEmpty ? keywords[rng.nextInt(keywords.length)] : p;
    switch (objectiveId) {
      case 'aquisicao':
        return [
          'Conheça $p',
          'Comece com $p agora',
          '$p é para você',
          'Entre na festa: $p',
          'Seu próximo passo: $p',
          'Experimente $p hoje',
        ];
      case 'engajamento':
        return [
          'Participe: $p',
          'O que você acha de $p?',
          'A galera está falando de $p',
          '$p chegou pra ficar',
          'Mostre seu lado com $p',
        ];
      case 'retencao':
        return [
          'Volte para $p',
          'Não perca $p',
          '$p fica ainda melhor',
          'Você vai querer repetir: $p',
          'Mais $p, do seu jeito',
        ];
      case 'lancamento':
        return [
          '$p acaba de lançar',
          'O lançamento: $p',
          'Primeiro a ver $p',
          '$p está no ar',
          'Bem-vindo ao $p',
        ];
      case 'livestream':
        return [
          'LIVE agora com $p',
          'Ao vivo: $p',
          'Assista nossa live sobre $p',
          'Bate-papo ao vivo: $p',
        ];
      case 'jogos':
        return [
          'Jogue $p agora',
          'Partida aberta: $p',
          'Desafie seus amigos em $p',
          '$p — a próxima partida',
          'Venha jogar $p',
        ];
      case 'promocao':
        return [
          'Aproveite a oferta de $p',
          '$p com condição especial',
          'Só agora: $p',
          'Oferta relâmpago: $p',
        ];
      case 'awareness':
      default:
        return [
          'Descubra $p',
          'Você já ouviu falar de $p?',
          '$p está por toda parte',
          'A novidade é $p',
          'Por dentro de $p',
          'Tudo sobre $k e $p',
        ];
    }
  }

  static List<String> _descriptionsFor(
    String objectiveId,
    String p,
    String toneId,
    Random rng,
  ) {
    final objective = MarketingObjective.byId(objectiveId);
    final hooks = <String>[];
    switch (objectiveId) {
      case 'aquisicao':
        hooks.addAll([
          '$p chegou no KLAY K.',
          'Buscando algo novo?',
          'Quer entrar de vez em $p?',
        ]);
      case 'engajamento':
        hooks.addAll([
          'A comunidade do KLAY K está toda falando de $p.',
          'Chegou a sua hora de dar uma opinião.',
        ]);
      case 'retencao':
        hooks.addAll([
          'Quem já conhece $p sabe: vale voltar sempre.',
          'Não deixe $p pra trás.',
        ]);
      case 'lancamento':
        hooks.addAll([
          'O grande dia chegou.',
          'Depois de muita expectativa, $p está no ar.',
        ]);
      case 'livestream':
        hooks.addAll([
          'A live sobre $p já vai começar.',
          'Só hoje: conversa ao vivo sobre $p.',
        ]);
      case 'jogos':
        hooks.addAll([
          'Partida boa se joga com quem curte.',
          '$p está com a galera reunida agora.',
        ]);
      case 'promocao':
        hooks.addAll([
          'Atenção: promoção de $p por tempo limitado.',
          'Condição especial apareceu pra você.',
        ]);
      default:
        hooks.addAll([
          'Você precisa conhecer $p.',
          'Tem novidade boa no KLAY K.',
        ]);
    }
    final benefits = switch (objectiveId) {
      'engajamento' => [
        'Todo mundo pode participar — é só tocar em um botão.',
        'Sua opinião muda o rumo do que acontece.',
      ],
      'retencao' => [
        'Cada visita rende uma experiência nova.',
        'O conteúdo é sempre fresquinho.',
      ],
      'livestream' => [
        'O chat fica aberto e você participa ao vivo.',
        'Quem chega cedo tem lugar garantido.',
      ],
      'jogos' => [
        'Você entra na partida direto pelo KLAY K.',
        'Sem enrolação: é só começar a jogar.',
      ],
      'promocao' => [
        'Oferta com desconto por tempo limitado.',
        'Basta tocar no botão e aproveitar.',
      ],
      'aquisicao' => [
        'Começar é rápido e sem complicação.',
        'Você começa a usar em poucos segundos.',
      ],
      'lancamento' => [
        'Quem vê primeiro sai na frente.',
        'A novidade já está disponível pra todo mundo.',
      ],
      'awareness' => [
        '$p já faz parte do dia a dia do KLAY K.',
        'Quanto mais você conhece, melhor fica.',
      ],
      _ => [
        'Tudo acontece dentro do KLAY K.',
        'É rápido, simples e bem feito.',
      ],
    };
    final ctas = switch (objectiveId) {
      'engajamento' => ['Toque para participar e deixar seu comentário.'],
      'retencao' => ['Volte hoje e veja o que mudou.'],
      'livestream' => ['Abra a live agora e entre no chat.'],
      'jogos' => ['Tente a sorte: toque e entre na partida.'],
      'promocao' => ['Toque agora para aproveitar antes que acabe.'],
      'aquisicao' => ['Comece agora, sem burocracia.'],
      'lancamento' => ['Seja o primeiro a experimentar.'],
      'awareness' => ['Descubra em poucos segundos.'],
      _ => ['Toque para saber mais.'],
    };

    final sentences = <String>[
      hooks[rng.nextInt(hooks.length)],
      benefits[0],
      benefits[1],
      ctas[0],
    ];
    // Embaralha de forma determinística conforme o seed (rng) para variar as
    // combinações entre variações sem repetir frases exatas.
    final start = rng.nextInt(sentences.length);
    final joined = <String>[];
    for (var i = 0; i < sentences.length; i++) {
      joined.add(sentences[(start + i) % sentences.length]);
    }
    final text = joined.join(' ');
    return [text, '$text ${objective.label} em pauta.', text];
  }

  static List<String> _ctasFor(String objectiveId) {
    switch (objectiveId) {
      case 'aquisicao':
        return ['Começar agora', 'Quero participar', 'Saiba mais', 'Começar'];
      case 'engajamento':
        return ['Participar', 'Deixar comentário', 'Curtir', 'Entrar'];
      case 'retencao':
        return ['Voltar agora', 'Seguir ouvindo', 'Salvar', 'Ativar lembretes'];
      case 'lancamento':
        return ['Garantir vaga', 'Ver lançamento', 'Ser avisado', 'Saber mais'];
      case 'awareness':
        return ['Descobrir', 'Explorar', 'Conhecer', 'Ver novidade'];
      case 'livestream':
        return ['Ver ao vivo', 'Assistir LIVE', 'Entrar no chat', 'Abrir live'];
      case 'jogos':
        return ['Jogar agora', 'Entrar na partida', 'Desafiar amigos', 'Jogar'];
      case 'promocao':
        return ['Aproveitar agora', 'Garantir desconto', 'Resgatar', 'Quero'];
      case 'divulgacao':
      default:
        return ['Saiba mais', 'Conhecer', 'Ver mais', 'Abrir'];
    }
  }

  // ---------------------------------------------------------------------------
  // Roteiro
  // ---------------------------------------------------------------------------

  static MarketingScript generateScript({
    required String category,
    required String product,
    String formatId = 'video_curto',
    String toneId = 'amigavel',
  }) {
    final p = productFallback(product);
    final rng = Random(_hashSeed('script|$category|$p|$toneId'));
    // Formato de imagem/carrossel não gera roteiro: força vídeo neste método.
    final effectiveFormat = (formatId == 'imagem' || formatId == 'carrossel')
        ? 'video_curto'
        : formatId;
    return _scriptFor(
      objectiveId: category,
      productClean: p,
      formatId: effectiveFormat,
      keywords: const [],
      rng: rng,
    )!;
  }

  static final List<({String id, String label})> scriptCategories = [
    (id: 'institucional', label: 'Institucional'),
    (id: 'jogos', label: 'Jogos'),
    (id: 'livestream', label: 'LIVE'),
    (id: 'videos', label: 'Vídeos'),
    (id: 'lancamento', label: 'Lançamento'),
    (id: 'divulgacao', label: 'Divulgação'),
    (id: 'novidade', label: 'Novidade'),
  ];

  static MarketingScript? _scriptFor({
    required String objectiveId,
    required String productClean,
    required String formatId,
    required List<String> keywords,
    required Random rng,
  }) {
    final format = MarketingFormat.byId(formatId);
    if (format.id == 'imagem' || format.id == 'carrossel') return null;

    final category = _mapCategory(objectiveId);
    final seconds = switch (format.id) {
      'video_long' => 45 + rng.nextInt(16),
      'story' => 15,
      _ => 20 + rng.nextInt(11),
    };

    final hook = _hookFor(objectiveId, productClean, rng);
    final problem = _problemFor(objectiveId, rng);
    final intro = _introFor(objectiveId, productClean, rng);
    final differential = _differentialFor(rng);
    final cta = _scriptCtaFor(productClean, rng);

    return MarketingScript(
      category: category,
      estimatedSeconds: seconds,
      sections: [
        MarketingScriptSection(
          step: 'GANCHO',
          text:
              '$hook '
              '(cenas: abertura com energia, foco em $productClean.)',
        ),
        MarketingScriptSection(step: 'PROBLEMA', text: problem),
        MarketingScriptSection(step: 'APRESENTAÇÃO', text: intro),
        MarketingScriptSection(step: 'DIFERENCIAL', text: differential),
        MarketingScriptSection(step: 'CTA', text: cta),
      ],
    );
  }

  static String _mapCategory(String objectiveId) {
    switch (objectiveId) {
      case 'jogos':
        return 'Jogos';
      case 'livestream':
        return 'LIVE';
      case 'lancamento':
        return 'Lançamento';
      case 'videos':
        return 'Vídeos';
      case 'institucional':
        return 'Institucional';
      case 'novidade':
      case 'awareness':
        return 'Novidade';
      case 'divulgacao':
      default:
        return 'Divulgação';
    }
  }

  static String _hookFor(String objectiveId, String p, Random rng) {
    final options = switch (objectiveId) {
      'jogos' => [
        'Você nunca jogou nada assim antes — e vai sair disso para a próxima partida.',
        'Nove entre dez players já estão dentro de $p.',
      ],
      'livestream' => [
        'Pare o que você está fazendo: isso está acontecendo ao vivo agora.',
        'Você já viu uma live que muda sua opinião em minutos?',
      ],
      'lancamento' => [
        'Hoje é o dia que todo mundo esperava.',
        'Se você ainda não ouviu isso, sente-se.',
      ],
      'institucional' => [
        'Existe um jeito certo de construir uma marca — e a gente escolheu fazer isso todos os dias.',
        'Toda grande história começa com um propósito.',
      ],
      'videos' => [
        'Três minutos que valem mais do que uma hora de rolagem.',
        'Este vídeo vai prender a sua atenção até o final.',
      ],
      'promocao' => [
        'Se você demorar, a condição especial de $p pode não estar mais lá.',
        'Cuidado: ofertas assim acabam rápido.',
      ],
      'divulgacao' => [
        'O KLAY K está mudando o jogo — e $p faz parte disso.',
        'Você precisa ver isso antes de todo mundo.',
      ],
      _ => [
        'Atenção para quem busca novidade: $p.',
        'Tem uma novidade que vai chamar a sua atenção.',
      ],
    };
    return options[rng.nextInt(options.length)];
  }

  static String _problemFor(String objectiveId, Random rng) {
    final options = <String>[
      'O problema: a maioria das pessoas descobre coisas boas tarde demais.',
      'Parece familiar? Você passa horas procurando e nunca acha o que quer.',
      'Todo mundo perde tempo com conteúdo ruim — ninguém deveria precisar disso.',
    ];
    return options[rng.nextInt(options.length)];
  }

  static String _introFor(String objectiveId, String p, Random rng) {
    final options = [
      'É exatamente aí que entra $p: simples, direto e feito pra você.',
      'A resposta é $p — construído para ser insubstituível dentro do KLAY K.',
      '$p resolve isso na prática e sem enrolação.',
    ];
    return options[rng.nextInt(options.length)];
  }

  static String _differentialFor(Random rng) {
    const options = <String>[
      'O diferencial: tudo acontece dentro do KLAY K, na mesma comunidade onde você já vive.',
      'O que separa isso de tudo mais é a experiência: rápida, bonita e com gente de verdade.',
      'Nada de volta ao mundo: aqui você encontrará tudo no mesmo lugar.',
    ];
    return options[rng.nextInt(options.length)];
  }

  static String _scriptCtaFor(String p, Random rng) {
    final options = <String>[
      'Finalize dizendo o próximo passo: toque no botão abaixo e confira agora.',
      'Feche com convite claro: encontre $p e faça parte agora mesmo.',
      'Termine gerando ação: o CTA do anúncio leva direto ao destino.',
    ];
    return options[rng.nextInt(options.length)];
  }

  // ---------------------------------------------------------------------------
  // Briefing
  // ---------------------------------------------------------------------------

  static MarketingBrief generateBrief({
    required String formatId,
    required String product,
    String objectiveId = 'divulgacao',
    String audience = '',
  }) {
    final p = productFallback(product);
    final format = MarketingFormat.byId(formatId);
    final rng = Random(_hashSeed('brief|$formatId|$p'));
    final a = clean(audience).isEmpty
        ? suggestAudience(objectiveId, p)
        : clean(audience);

    final specs = switch (format.id) {
      'video_curto' => [
        'Proporção 9:16 (vertical)',
        'Duração: 15–35 s',
        'Som e legenda obrigatórios',
        'Identidade KLAY K: roxo neon sobre fundo escuro',
      ],
      'video_long' => [
        'Proporção 16:9 (horizontal)',
        'Duração: 45–60 s',
        'Ritmo crescente com pausa para o produto',
        'Cena de encerramento com CTA visível',
      ],
      'imagem' => [
        'Proporção 1:1 (quadrada)',
        'Texto ≤ 80 caracteres',
        'Product hero em destaque',
        'Link/CTA fora da arte (botão real do anúncio)',
      ],
      'story' => [
        'Proporção 9:16 (vertical)',
        'Primeiros 3 s decisivos (GANCHO)',
        'Sticker/URL apenas se o sistema de mídia suportar',
        'Sem texto abaixo da zona segura',
      ],
      'carrossel' => [
        'Proporção 1:1 ou 4:5',
        '3–5 telas: gancho → problema → produto → prova → CTA',
        'Hierarquia de texto consistente entre telas',
        'Última tela sempre com CTA claro',
      ],
      _ => [
        'Proporção alinhada ao formato escolhido.',
        'Identidade KLAY K: roxo neon sobre fundo escuro.',
      ],
    };

    final scenes = <BriefScene>[
      BriefScene(
        step: 'Cena 1 · Gancho',
        description: _sceneHook(objectiveId, p, rng),
      ),
      const BriefScene(
        step: 'Cena 2 · Contexto',
        description:
            'Mostra o problema anunciado no roteiro (visualização cotidiana).',
      ),
      BriefScene(
        step: 'Cena 3 · Produto',
        description: '$p em destaque com assinatura visual KLAY K.',
      ),
      const BriefScene(
        step: 'Cena 4 · Diferencial',
        description:
            'Uma prova de valor: comunidade, rapidez ou exclusividade.',
      ),
      const BriefScene(
        step: 'Cena 5 · CTA',
        description: 'Botão/CTA real do anúncio com rótulo final.',
      ),
    ];

    return MarketingBrief(
      format: format.label,
      product: p,
      objective: MarketingObjective.byId(objectiveId).label,
      audience: a,
      specs: specs,
      scenes: scenes,
      doItems: const [
        'Usar a identidade KLAY K (roxo neon sobre escuro).',
        'CTA real com link http(s) válido e rótulo de ação.',
        'Cumprir o checklist de publicação antes de aprovar.',
      ],
      dontItems: const [
        'Não prometer prêmio/benefício que não existe.',
        'Não usar roteiro acima do tempo definido no formato.',
        'Não aplicar texto cortado ou CTA sem destino.',
        'Não publicar automaticamente: sempre revisão do CEO.',
      ],
    );
  }

  static String _sceneHook(String objectiveId, String p, Random rng) {
    final options = <String>[
      'Primeiros 3 s com $p em movimento ou destaque imediato.',
      'Pergunta direta para o público antes de revelar $p.',
      'Contraste visual (antes/depois) para fisgar a atenção.',
    ];
    return options[rng.nextInt(options.length)];
  }

  // ---------------------------------------------------------------------------
  // Checklist
  // ---------------------------------------------------------------------------

  static List<MarketingChecklistItem> _defaultChecklist() => const [
    MarketingChecklistItem(label: 'Roteiro/briefing revisado pelo CEO'),
    MarketingChecklistItem(label: 'CTA válido (veto dissociado — link)'),
    MarketingChecklistItem(label: 'Público-alvo definido'),
    MarketingChecklistItem(label: 'Formato e mídia alinhados ao objetivo'),
    MarketingChecklistItem(label: 'Sem promessas que a experiência não cumpre'),
  ];

  /// Checklist padrão de publicação (exposto para testes/UI).
  static List<MarketingChecklistItem> get checklistDefault =>
      _defaultChecklist();

  // ---------------------------------------------------------------------------
  // Seeds determinísticos
  // ---------------------------------------------------------------------------

  static int _hashSeed(String input) {
    var hash = 5381;
    for (var i = 0; i < input.length; i++) {
      // ignore: avoid_dynamic_var
      var code = input.codeUnitAt(i);
      hash = ((hash << 5) + hash) ^ code;
    }
    return hash & 0x7FFFFFFF;
  }
}
