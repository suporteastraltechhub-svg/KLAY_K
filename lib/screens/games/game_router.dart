import 'package:flutter/material.dart';

import '../../services/game_service.dart';
import '../../widgets/klayk_ux.dart';
import 'engines/arcade_engine_screen.dart';
import 'engines/arcade_engines.dart';
import 'engines/estrategia_engine_screen.dart';
import 'engines/matematica_engine_screen.dart';
import 'engines/memoria_engine_screen.dart';
import 'engines/palavras_engine_screen.dart';
import 'engines/reflex_engine_screen.dart';
import 'engines/trivia_engine_screen.dart';

/// Registro dos minijogos arcade, construído uma única vez.
final Map<String, KlaykArcadeBuilder> _arcadeEngines =
    buildKlaykArcadeEngines();

/// ============================================================================
/// Roteador único de jogos por ENGINE.
///
/// Cada jogo declara `games.engine` no catálogo; UMA tela por engine serve
/// qualquer configuração. Engines futuras = 1 case aqui + 1 coluna no banco —
/// nunca telas por jogo. `trivia` é o fallback seguro (a própria engine tem
/// perguntas padrão), então catálogo novo nunca abre em tela errada.
///
/// Usado tanto pela aba Jogos quanto pela área Jogos da Home (sem duplicar a

/// lógica de roteamento).
/// ============================================================================

/// Retorna a tela da engine do jogo ([GameInfo.engine]).
Widget gameScreenFor(GameInfo game) {
  switch (game.engine) {
    case 'reflexo':
      return ReflexEngineScreen(game: game);
    case 'memoria':
      return MemoriaEngineScreen(game: game);
    case 'matematica':
      return MatematicaEngineScreen(game: game);
    case 'palavras':
      return PalavrasEngineScreen(game: game);
    case 'arcade':
      return ArcadeEngineScreen(game: game);
    case 'estrategia':
      return EstrategiaEngineScreen(game: game);
    default:
      // Minijogos arcade do KLAY K (slot, roda, dados, cartas, mines, crash,
      // baú e cara-ou-coroa). Todos recreativos: só pontuação/XP virtual.
      final arcade = _arcadeEngines[game.engine];
      if (arcade != null) return arcade(game: game);
      return TriviaEngineScreen(game: game);
  }
}

/// Abre o jogo na tela da engine declarada. Completa quando a tela fecha.
Future<void> openGame(BuildContext context, GameInfo game) =>
    KlaykNav.push<void>(context, gameScreenFor(game));
