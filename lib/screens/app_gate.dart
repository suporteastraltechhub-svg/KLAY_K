import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/experience_settings.dart';
import '../services/push_service.dart';
import '../services/supabase_service.dart';
import 'auth_screen.dart';
import 'splash_screen.dart';

/// Porta de entrada do KLAY K.
///
/// Plays a Splash animada (~4s) enquanto resolve a sessão de forma silenciosa:
///   - sessão ativa  -> [homeBuilder] (Tela Inicial);
///   - sem sessão    -> Login/Cadastro;
///   - Supabase fora (dev/testes) -> Tela Inicial (modo demo).
/// Também reage a signIn/signOut em tempo real (persistência de sessão).
class AppGate extends StatefulWidget {
  final Widget Function() homeBuilder;

  const AppGate({super.key, required this.homeBuilder});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  /// A resolução de sessão usa `SupabaseService.isConfigured`: em flutter_test
  /// (sem `KLAY_E2E`) o Supabase está desligado e o app segue para a Tela
  /// Inicial em modo demo; com `KLAY_E2E=true` resolve a sessão real.

  bool _splashDone = false;
  bool _sessionKnown = false;
  bool _authed = false;
  bool _demoMode = false;
  bool _ready = false;
  bool _skipScheduled = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _resolveSession();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _resolveSession() async {
    bool authed = false;
    bool demo = false;
    try {
      final db = SupabaseService.instance;
      if (!db.isConfigured) {
        demo = true;
      } else {
        await db.ensureReady();
        authed = db.hasSession;
        if (authed) {
          _syncIdentity(db.currentUser);
        }
        _authSub = db.client.auth.onAuthStateChange.listen(_onAuthState);
      }
    } catch (_) {
      // Sem Supabase disponível (ex.: testes/widgets) → segue para a Tela
      // Inicial em modo demo, preservando o comportamento anterior.
      demo = true;
    }
    if (!mounted) return;
    setState(() {
      _authed = authed;
      _demoMode = demo;
      _sessionKnown = true;
    });
    if (authed) {
      // Carrega preferências de experiência (animações, auto-play etc.) cedo.
      await ExperienceSettings.instance.load();
      // Registra o token de push (FCM) deste dispositivo para a sessão real.
      await PushService.instance.register();
    }
    _maybeReady();
    _scheduleSkipIfFast();
  }

  /// Se a sessão resolver antes do splash de 4s terminar, finaliza a splash em
  /// ~1.1s (marca mostrada, boot mais rápido).
  void _scheduleSkipIfFast() {
    if (_skipScheduled || _splashDone || !mounted) return;
    _skipScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted && !_splashDone) _onSplashFinished();
    });
  }

  void _syncIdentity(User? user) {
    if (user == null) return;
    kAppIdentity.displayName =
        user.userMetadata?['full_name'] as String? ?? kAppIdentity.displayName;
    kAppIdentity.username =
        '@${user.userMetadata?['username'] ?? kAppIdentity.username.replaceFirst('@', '')}';
  }

  void _onAuthState(AuthState state) {
    if (!mounted) return;
    if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession &&
            state.session != null) {
      _syncIdentity(SupabaseService.instance.currentUser);
      setState(() {
        _authed = true;
        _demoMode = false;
        _sessionKnown = true;
      });
      ExperienceSettings.instance.load();
      PushService.instance.register();
    } else if (state.event == AuthChangeEvent.signedOut) {
      // Desassocia tokens de push deste usuário (RPC security definer).
      PushService.instance.logout();
      setState(() {
        _authed = false;
        _demoMode = false;
        _sessionKnown = true;
      });
    }
    _maybeReady();
    _scheduleSkipIfFast();
  }

  void _onSplashFinished() {
    setState(() => _splashDone = true);
    _maybeReady();
  }

  void _maybeReady() {
    if (_splashDone && _sessionKnown && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (!_ready) {
      child = SplashScreen(onFinished: _onSplashFinished);
    } else if (_authed || _demoMode) {
      child = widget.homeBuilder();
    } else {
      child = const AuthScreen();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
  }
}
