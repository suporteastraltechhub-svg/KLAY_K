import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Jogo do catálogo (read from `games`).
class GameInfo {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final String category;
  final String status;
  final Map<String, dynamic> rules;
  final int maxScore;
  final int sortOrder;

  const GameInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.category,
    required this.status,
    this.rules = const {},
    this.maxScore = 100,
    this.sortOrder = 0,
  });

  bool get isActive => status == 'active';
  bool get isSoon => status == 'soon';

  factory GameInfo.fromMap(Map<String, dynamic> json) {
    final rulesRaw = json['rules'];
    return GameInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '🎮',
      category: json['category']?.toString() ?? 'arcade',
      status: json['status']?.toString() ?? 'soon',
      rules: rulesRaw is Map
          ? rulesRaw.map((k, v) => MapEntry(k.toString(), v))
          : const {},
      maxScore: (json['max_score'] as num?)?.toInt() ?? 100,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Entrada de ranking de um jogo.
class GameRankEntry {
  final int rank;
  final String userId;
  final String displayName;
  final String username;
  final String avatarUrl;
  final int bestScore;
  final int durationSeconds;
  final bool isVerified;

  const GameRankEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl = '',
    required this.bestScore,
    this.durationSeconds = 0,
    this.isVerified = false,
  });

  factory GameRankEntry.fromMap(Map<String, dynamic> json) => GameRankEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: json['user_id']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString() ?? '',
        bestScore: (json['best_score'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        isVerified: json['is_verified'] == true,
      );
}

/// Resultado da submissão de pontuação (retorno do backend).
class GameSubmitResult {
  final int score;
  final int reward;
  final bool improved;
  final int bestScore;

  const GameSubmitResult({
    required this.score,
    this.reward = 0,
    this.improved = false,
    this.bestScore = 0,
  });

  factory GameSubmitResult.fromMap(Map<String, dynamic> json) => GameSubmitResult(
        score: (json['score'] as num?)?.toInt() ?? 0,
        reward: (json['reward'] as num?)?.toInt() ?? 0,
        improved: json['improved'] as bool? ?? false,
        bestScore: (json['best_score'] as num?)?.toInt() ?? 0,
      );
}

/// Serviço da aba Jogos. Sessão/ranking/recompensa são validados no backend
/// (RPCs security definer); o cliente nunca define saldos ou pontuações finais.
class GameService {
  GameService._();

  static final GameService instance = GameService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------------

  Future<List<GameInfo>> catalog() async {
    try {
      final res = await _db
          .from('games')
          .select()
          .order('sort_order', ascending: true);
      return (res as List)
          .whereType<Map>()
          .map((m) => GameInfo.fromMap(_stringMap(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Meus recordes por jogo (id → best_score). Fallback vazio em demo.
  Future<Map<String, int>> myRecords() async {
    try {
      final r = await _rpc('my_game_records');
      if (r is! List) return const {};
      final out = <String, int>{};
      for (final e in r.whereType<Map>()) {
        final m = _stringMap(e);
        out[m['game_id']?.toString() ?? ''] =
            (m['best_score'] as num?)?.toInt() ?? 0;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // Sessão e pontuação (rodeios: o backend decide tudo)
  // ---------------------------------------------------------------------------

  /// Abre uma partida. Retorna o id da sessão ou lança EstadoErro com motivo.
  Future<String> startSession(String gameId) async {
    try {
      final r = await _rpc('game_start_session', {'p_game_id': gameId});
      if (r == null) throw StateError('Não foi possível iniciar a partida.');
      return r.toString();
    } catch (_) {
      throw StateError('Não foi possível iniciar a partida.');
    }
  }

  /// Submete a pontuação de uma sessão; recebe recompensa se melhorar recorde.
  Future<GameSubmitResult> submitScore({
    required String sessionId,
    required int score,
    int durationSeconds = 0,
  }) async {
    final r = await _rpc('game_submit_score', {
      'p_session_id': sessionId,
      'p_score': score,
      'p_duration_seconds': durationSeconds,
    });
    if (r is! Map) {
      return GameSubmitResult(score: score);
    }
    return GameSubmitResult.fromMap(_stringMap(r));
  }

  // ---------------------------------------------------------------------------
  // Ranking
  // ---------------------------------------------------------------------------

  Future<List<GameRankEntry>> leaderboard(String gameId) async {
    try {
      final r = await _rpc('game_leaderboard', {'p_game_id': gameId});
      if (r is! List) return const [];
      return r
          .whereType<Map>()
          .map((m) => GameRankEntry.fromMap(_stringMap(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<dynamic> _rpc(String name, [Map<String, dynamic> params = const {}]) {
    return _db.rpc(name, params: params);
  }

  Map<String, dynamic> _stringMap(Map<dynamic, dynamic> m) => m.map(
        (k, v) => MapEntry(k.toString(), v),
      );
}