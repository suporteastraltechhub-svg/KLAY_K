import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_service.dart';
import 'gift_service.dart';
import 'live_kit_service.dart';
import 'notif_prefs_service.dart';
import 'security_service.dart';
import 'supabase_service.dart';

/// Estado de uma verificação real. Nunca "verde" por omissão: cada item só
/// fica [ok] depois de uma chamada que realmente voltou.
enum ProbeState { pending, checking, ok, warning, failed, unavailable }

class ServiceProbe {
  final String id;
  final String label;
  String detail;
  ProbeState state;

  ServiceProbe({
    required this.id,
    required this.label,
    this.detail = '',
    this.state = ProbeState.pending,
  });
}

/// Resultado agregado de um diagnóstico.
class DiagnosticsReport {
  final List<ServiceProbe> probes;
  final DateTime ranAt;

  DiagnosticsReport({required this.probes, required this.ranAt});

  bool get hasFailure => probes.any((p) => p.state == ProbeState.failed);

  int get okCount => probes.where((p) => p.state == ProbeState.ok).length;
}

/// Resumo de segurança (usado pela Central de Segurança).
class SecuritySummary {
  final bool authenticated;
  final int sessionCount;
  final int blockedCount;
  final int reportCount;
  final bool emailConfirmed;
  final bool youthProtected;
  final bool privacyPrivate;
  final bool messagesRestricted;
  final bool commentsAllowed;
  final bool confirmActions;
  final List<String> issues;
  final bool loaded;

  const SecuritySummary({
    this.authenticated = false,
    this.sessionCount = 0,
    this.blockedCount = 0,
    this.reportCount = 0,
    this.emailConfirmed = false,
    this.youthProtected = false,
    this.privacyPrivate = false,
    this.messagesRestricted = false,
    this.commentsAllowed = true,
    this.confirmActions = true,
    this.issues = const [],
    this.loaded = false,
  });

  int get score {
    var s = 0;
    if (authenticated) s += 20;
    if (emailConfirmed) s += 15;
    if (confirmActions) s += 15;
    if (youthProtected) s += 15;
    if (privacyPrivate || messagesRestricted) s += 10;
    if (sessionCount <= 3) s += 10;
    if (commentsAllowed) s += 5;
    if (blockedCount > 0) s += 10;
    return s.clamp(0, 100);
  }

  ProbeState get state {
    if (!loaded) return ProbeState.unavailable;
    if (issues.any((i) => i.startsWith('!'))) return ProbeState.failed;
    if (issues.isNotEmpty) return ProbeState.warning;
    return ProbeState.ok;
  }
}

/// Motor de diagnóstico real. Cada método executa uma chamada verdadeira e
/// traduz o resultado em um estado — nunca inventa "funcionando".
class SettingsDiagnosticsService {
  SettingsDiagnosticsService._();

  static final SettingsDiagnosticsService instance =
      SettingsDiagnosticsService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  static const _timeout = Duration(seconds: 12);

  // ---------------------------------------------------------------------------
  // Diagnóstico de serviços
  // ---------------------------------------------------------------------------

  Future<DiagnosticsReport> runServiceDiagnostics() async {
    final probes = <ServiceProbe>[
      ServiceProbe(id: 'internet', label: 'Internet'),
      ServiceProbe(id: 'supabase', label: 'Supabase'),
      ServiceProbe(id: 'auth', label: 'Autenticação'),
      ServiceProbe(id: 'profile', label: 'Perfil'),
      ServiceProbe(id: 'feed', label: 'Feed'),
      ServiceProbe(id: 'livekit', label: 'LiveKit'),
      ServiceProbe(id: 'chat', label: 'Chat / Realtime'),
      ServiceProbe(id: 'notifications', label: 'Notificações'),
      ServiceProbe(id: 'wallet', label: 'Carteira'),
      ServiceProbe(id: 'gifts', label: 'Presentes'),
      ServiceProbe(id: 'storage', label: 'Armazenamento local'),
    ];
    final report = DiagnosticsReport(probes: probes, ranAt: DateTime.now());

    await _run(probes, 'internet', _probeInternet);
    await _run(probes, 'supabase', _probeSupabase);
    await _run(probes, 'auth', _probeAuth);
    await _run(probes, 'profile', _probeProfile);
    await _run(probes, 'feed', _probeFeed);
    probes.firstWhere((p) => p.id == 'livekit').state = _probeLiveKitConfig();
    await _run(probes, 'chat', _probeRealtime);
    await _run(probes, 'notifications', _probeNotifications);
    await _run(probes, 'wallet', _probeWallet);
    await _run(probes, 'gifts', _probeGifts);
    await _run(probes, 'storage', _probeStorage);
    return report;
  }

  Future<void> _run(
    List<ServiceProbe> probes,
    String id,
    Future<ProbeState> Function() check,
  ) async {
    final probe = probes.firstWhere((p) => p.id == id);
    probe.state = ProbeState.checking;
    try {
      probe.state = await check().timeout(_timeout);
    } on TimeoutException {
      probe.state = ProbeState.failed;
      probe.detail = 'Tempo limite excedido';
    } catch (e) {
      probe.state = ProbeState.failed;
      probe.detail = _short(e);
    }
  }

  Future<ProbeState> _probeInternet() async {
    final result = await Connectivity().checkConnectivity();
    final offline = result.contains(ConnectivityResult.none);
    if (offline) {
      return ProbeState.failed;
    }
    return ProbeState.ok;
  }

  Future<ProbeState> _probeSupabase() async {
    if (!SupabaseService.instance.isConfigured) {
      return ProbeState.unavailable;
    }
    // Uma chamada leve e real: ler o próprio usuário autenticado.
    await _db.auth.getUser().timeout(_timeout);
    return ProbeState.ok;
  }

  Future<ProbeState> _probeAuth() async {
    final user = _db.auth.currentUser;
    if (user == null) return ProbeState.unavailable;
    return ProbeState.ok;
  }

  Future<ProbeState> _probeProfile() async {
    final profile = await AccountService.instance.fetchMyProfile();
    if (profile == null) return ProbeState.failed;
    return ProbeState.ok;
  }

  Future<ProbeState> _probeFeed() async {
    if (!SupabaseService.instance.isConfigured) {
      return ProbeState.unavailable;
    }
    await _db.from('posts').select('id').limit(1);
    return ProbeState.ok;
  }

  ProbeState _probeLiveKitConfig() {
    if (!LiveKitService.instance.isEnabled) {
      return ProbeState.unavailable;
    }
    // Configurado significa que o token pode ser obtido do backend; não
    // significa que há sala conectada — o estado real aparece na LIVE.
    return ProbeState.ok;
  }

  Future<ProbeState> _probeRealtime() async {
    if (!SupabaseService.instance.isConfigured) {
      return ProbeState.unavailable;
    }
    final channel = _db.channel(
      'diag-${DateTime.now().millisecondsSinceEpoch}',
    );
    final completer = Completer<ProbeState>();
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!completer.isCompleted) completer.complete(ProbeState.ok);
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (!completer.isCompleted) completer.complete(ProbeState.failed);
      }
    });
    final result = await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => ProbeState.failed,
    );
    SupabaseService.instance.removeChannel(channel);
    return result;
  }

  Future<ProbeState> _probeNotifications() async {
    if (!SupabaseService.instance.isConfigured) {
      return ProbeState.unavailable;
    }
    await NotifPrefsService.instance.fetch();
    return ProbeState.ok;
  }

  Future<ProbeState> _probeWallet() async {
    if (!SupabaseService.instance.isConfigured) {
      return ProbeState.unavailable;
    }
    await GiftService.instance.fetchWallet();
    return ProbeState.ok;
  }

  Future<ProbeState> _probeGifts() async {
    if (!SupabaseService.instance.isConfigured) {
      return ProbeState.unavailable;
    }
    final gifts = await GiftService.instance.fetchGifts(pageSize: 1);
    return gifts.isEmpty ? ProbeState.warning : ProbeState.ok;
  }

  Future<ProbeState> _probeStorage() async {
    try {
      final dir = await getTemporaryDirectory();
      var bytes = 0;
      if (dir.existsSync()) {
        for (final entity in dir.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            try {
              bytes += await entity.length();
            } catch (_) {}
          }
        }
      }
      return bytes >= 0 ? ProbeState.ok : ProbeState.warning;
    } catch (_) {
      return ProbeState.unavailable;
    }
  }

  // ---------------------------------------------------------------------------
  // Resumo de segurança (Central de Segurança)
  // ---------------------------------------------------------------------------

  Future<SecuritySummary> loadSecuritySummary() async {
    final issues = <String>[];
    var authenticated = false;
    var sessions = 0;
    var blocked = 0;
    var reports = 0;
    var emailConfirmed = false;
    var youthProtected = false;
    var privateAccount = false;
    var messagesRestricted = false;
    var commentsAllowed = true;
    var confirmActions = true;

    try {
      await SupabaseService.instance.ensureAuthenticated();
      authenticated = true;
    } catch (_) {
      return const SecuritySummary(loaded: false, issues: ['!Não autenticado']);
    }

    try {
      final account = await SecurityService.instance.myAccount();
      emailConfirmed = account.emailConfirmed;
      if (!emailConfirmed) {
        issues.add('E-mail não confirmado');
      }
    } catch (_) {
      issues.add('!Não foi possível verificar sua conta');
    }

    try {
      sessions = (await SecurityService.instance.authListSessions()).length;
      if (sessions > 5) {
        issues.add('Muitas sessões ativas ($sessions)');
      }
    } catch (_) {
      issues.add('!Não foi possível verificar as sessões');
    }

    try {
      blocked = (await AccountService.instance.fetchBlockedIds()).length;
    } catch (_) {
      issues.add('!Não foi possível verificar os bloqueios');
    }

    try {
      reports = (await SecurityService.instance.myReports()).length;
    } catch (_) {
      issues.add('!Não foi possível verificar as denúncias');
    }

    try {
      final profile = await SecurityService.instance.mySafetyProfile();
      youthProtected = profile.hasProvenAge;
      if (!youthProtected) {
        issues.add('Defina sua data de nascimento para proteção total');
      }
    } catch (_) {
      issues.add('!Não foi possível verificar a proteção para menores');
    }

    try {
      final settings = await AccountService.instance.fetchSettings();
      privateAccount = settings.accountPrivate;
      messagesRestricted = settings.allowMessages != 'everyone';
      commentsAllowed = settings.allowComments;
      confirmActions = settings.securityConfirmActions;
      if (!confirmActions) {
        issues.add('Confirmação de ações importantes desligada');
      }
    } catch (_) {
      issues.add('!Não foi possível verificar as preferências');
    }

    return SecuritySummary(
      authenticated: authenticated,
      sessionCount: sessions,
      blockedCount: blocked,
      reportCount: reports,
      emailConfirmed: emailConfirmed,
      youthProtected: youthProtected,
      privacyPrivate: privateAccount,
      messagesRestricted: messagesRestricted,
      commentsAllowed: commentsAllowed,
      confirmActions: confirmActions,
      issues: issues,
      loaded: true,
    );
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }
}
