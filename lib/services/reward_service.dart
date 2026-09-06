import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Resultado da RPC `claim_watch_cycle_reward` (dados vindos do servidor).
///
/// O cliente apenas solicita a recompensa; o backend decide `ok`, `reward`
/// (sempre 15) e `balance` (saldo real após a concessão). Nunca enviamos
/// user_id nem quantidade para o servidor.
class RewardClaimResult {
  final bool ok;
  final int reward;
  final int balance;
  final DateTime? nextAvailableAt;
  final String? error;

  const RewardClaimResult({
    required this.ok,
    this.reward = 0,
    this.balance = 0,
    this.nextAvailableAt,
    this.error,
  });

  factory RewardClaimResult.fromRpc(dynamic raw) {
    final map = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    final ok = map['ok'] == true;
    final reward = (map['reward'] as num?)?.toInt() ?? 0;
    final balance = (map['balance'] as num?)?.toInt() ?? 0;
    DateTime? next;
    final nextStr = map['next_available_at']?.toString();
    if (nextStr != null && nextStr.isNotEmpty) {
      next = DateTime.tryParse(nextStr);
    }
    // Erro/código podem vir como PostgrestException (não-JSON). Tratamos aqui
    // de forma segura, sem expor stacks ao usuário.
    return RewardClaimResult(
      ok: ok,
      reward: reward,
      balance: balance,
      nextAvailableAt: next,
      error: map['error']?.toString(),
    );
  }

  factory RewardClaimResult.failure(String error) =>
      RewardClaimResult(ok: false, error: error);
}

/// Camada de recompensas do feed.
///
/// A fonte da verdade é o backend: o cliente chama a RPC e nunca atualiza
/// saldo diretamente. Caso a RPC ainda não exista no projeto (PGRST202 /
/// função inexistente), reportamos um erro amigável sem quebrar o app.
class RewardService {
  RewardService._();

  static final RewardService instance = RewardService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  /// Solicita a recompensa válida do ciclo assistido (15 moedas), se o
  /// cooldown de 20s do backend já tiver expirado.
  Future<RewardClaimResult> claimWatchCycleReward() async {
    try {
      final raw = await _db.rpc('claim_watch_cycle_reward');
      return RewardClaimResult.fromRpc(raw);
    } on PostgrestException catch (e) {
      // Função inexistente / sem grant ainda aplicado.
      if (e.code == 'PGRST202' ||
          e.message.toString().contains('404') ||
          e.message.contains('function')) {
        return RewardClaimResult.failure('Recompensa indisponível no momento.');
      }
      return RewardClaimResult.failure(_friendly(e.message.toString()));
    } on Exception {
      return RewardClaimResult.failure('Não foi possível solicitar agora.');
    }
  }

  String _friendly(String raw) {
    if (raw.isEmpty) return 'Recompensa ainda em cooldown.';
    final trimmed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.length > 90) return 'Recompensa ainda em cooldown.';
    return trimmed;
  }

  /// Sincroniza o saldo real (moedas) da carteira direto do servidor.
  Future<int?> fetchCreditsBalance() async {
    try {
      final r = await _db.rpc('my_wallet');
      final map = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
      return (map['credits'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }
}

/// Controlador reutilizável do ciclo de recompensa por tempo assistido.
///
/// - Ciclo de exatamente 20s (avanço fino e suave).
/// - Pausa quando o app/feed não está ativo ou nenhum vídeo reproduz.
/// - Impede duas recompensas simultâneas (lock interno de `_claiming`).
/// - Ao completar, solicita a recompensa ao backend; o resultado é entregue
///   via [onClaimed]. O servidor decide tudo (ok, reward, balance).
/// - Faz dispose correto do timer.
class RewardTimerController extends ChangeNotifier {
  static const int cycleMilliseconds = 20000;
  static const int tickMilliseconds = 200;
  static const int ticksPerCycle = cycleMilliseconds ~/ tickMilliseconds; // 100

  final void Function(RewardClaimResult result)? onClaimed;

  Timer? _timer;
  int _tick = 0;
  bool _active = false;
  bool _claiming = false;

  RewardTimerController({this.onClaimed});

  /// Progresso do ciclo, de 0.0 a 1.0.
  double get progress {
    if (_claiming) return 1.0;
    return (_tick / ticksPerCycle).clamp(0.0, 1.0);
  }

  bool get isRunning =>
      _timer != null && _timer!.isActive && !_claiming;

  bool get isClaiming => _claiming;

  bool get isActive => _active;

  /// Liga/desliga o ciclo. Use `false` quando o feed sair de foco, o app for
  /// para background, não houver vídeo reproduzindo etc.
  void setActive(bool active) {
    if (active == _active) return;
    _active = active;
    if (active) {
      _resumeIfReady();
    } else {
      _pause();
    }
    notifyListeners();
  }

  /// Força o ciclo a parar (ex.: tela destruída). [setActive(false)] já cobre.
  void stop() {
    _active = false;
    _pause();
    notifyListeners();
  }

  /// Reinicia o progresso para 0 (ex.: para resincronizar após erro do
  /// servidor indicar cooldown vigente).
  void resetProgress() {
    _tick = 0;
    notifyListeners();
  }

  void _start() {
    _pause();
    _timer = Timer.periodic(
      const Duration(milliseconds: tickMilliseconds),
      (_) => _onTick(),
    );
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  void _resumeIfReady() {
    if (_claiming) return;
    _start();
  }

  void _onTick() {
    if (_claiming) return;
    _tick++;
    if (_tick >= ticksPerCycle) {
      _tick = ticksPerCycle;
      _pause();
      _fireClaim();
    } else {
      notifyListeners();
    }
  }

  Future<void> _fireClaim() async {
    if (_claiming) return;
    _claiming = true;
    notifyListeners();

    final result = await RewardService.instance.claimWatchCycleReward();

    _claiming = false;
    _tick = 0;
    notifyListeners();

    // Repassa o resultado do servidor para a UI (animação "+15", atualizar
    // saldo real, snackbars, resync etc.).
    onClaimed?.call(result);

    // Reinicia o ciclo, se ainda estivermos ativos e não houver claim em curso.
    if (_active && !_claiming) {
      _start();
    }
  }

  @override
  void dispose() {
    _pause();
    super.dispose();
  }
}
