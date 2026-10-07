import 'package:flutter/material.dart';

import '../models/ad_models.dart';
import '../services/ads_service.dart';
import 'ad_widgets.dart';

/// Placements suportados pelo KLAY K (only estes recebem anúncios; as demais
/// áreas são proibidas por padrão — mensagens, perfil, carteira, Game Live…).
const List<String> kAdPlacements = ['feed', 'live_hub', 'games', 'discover'];

/// Proteção local simples contra spam visual (§33): o backend NÃO expõe
/// frequency cap/placement/prioridade na RPC pública `ads_public_approved`
/// (retorna só APPROVED, ordenado por updated_at). Então o app limita o
/// número máximo de anúncios mantidos em memória por contexto de exibição —
/// cada posição sempre mantém o MESMO conjunto fixo durante a sessão (o feed
/// em PageView nunca encolhe em runtime, evitando quebrar a navegação).
const int kAdMaxPerSession = 12;

/// Lote de anúncios aprovados para um contexto de exibição (ex.: Jogos,
/// Central de Lives, salas de Áudio). Centraliza carregamento + intercalação
/// para não duplicar lógica em cada tela. Nunca decide status no cliente:
/// usa a RPC pública `ads_public_approved` (só APPROVED chega aqui).
class AdSpot {
  List<AdCreative> ads = const [];

  /// Carrega até [limit] anúncios aprovados (limitado por [kAdMaxPerSession]).
  /// Falha silenciosa: sem anúncios, a tela segue normal (publicidade é
  /// opcional e NUNCA bloqueia o conteúdo — §37/§38).
  Future<void> load({int limit = 4}) async {
    if (!AdsService.instance.isConfigured) return;
    final fromBackend = await AdsService.instance.fetchApprovedAds(
      limit: limit,
    );
    ads = fromBackend.length > kAdMaxPerSession
        ? fromBackend.take(kAdMaxPerSession).toList()
        : fromBackend;
  }

  /// Remove um anúncio localmente (após "Ocultar este anúncio").
  void remove(String adId) {
    ads = List.of(ads.where((a) => a.id != adId));
  }

  /// Intercala `AdCard` (com badge ANÚNCIO, selo e CTA) entre os widgets de
  /// conteúdo [mains], a cada [everyN] itens, aplicando [gap] de espaçamento.
  /// Usa [onHidden] para remoção imediata quando o usuário ocultar o anúncio.
  List<Widget> interleave(
    List<Widget> mains, {
    int everyN = 4,
    double gap = 12,
    void Function(String adId)? onHidden,
  }) {
    if (ads.isEmpty) return mains;
    final out = <Widget>[];
    for (var i = 0; i < mains.length; i++) {
      out.add(mains[i]);
      if ((i + 1) % everyN == 0) {
        final ad = ads[i ~/ everyN % ads.length];
        out.add(
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: AdCard(
              ad: ad,
              onHidden: onHidden == null ? null : () => onHidden(ad.id),
            ),
          ),
        );
      }
    }
    return out;
  }
}
