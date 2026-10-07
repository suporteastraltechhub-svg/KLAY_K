import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import '../l10n/app_localizations_es.dart';
import '../l10n/app_localizations_ko.dart';
import '../l10n/app_localizations_pt.dart';
import '../services/invite_service.dart';
import '../services/locale_controller.dart';
import '../services/supabase_service.dart';

/// Login e Cadastro com Supabase Auth real (e-mail/senha) + Google quando o
/// provedor estiver configurado. Validações claras, erros reais e
/// persistência de sessão via supabase_flutter.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.inviteChecker});

  /// Validação do código de convite (opcional, injetável nos testes). Quando
  /// ausente usa o backend real via [InviteService.validateStatus]; o backend
  /// permanece a fonte da verdade.
  final InviteChecker? inviteChecker;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

/// Assinatura da verificação de um código de convite (estado: válido,
/// inválido/inexistente ou verificação indisponível).
typedef InviteChecker = Future<InviteCheck> Function(String code);

enum _InviteStatus { idle, checking, valid, invalid, unreachable }

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _inviteController = TextEditingController();

  AppLocalizations? _l10n;

  // Idioma da TELA DE LOGIN apenas. Não altera o idioma global do app (nem o
  // AppLanguageController nem o SharedPreferences): o seletor filho reusa o
  // mesmo banco de traduções ARB, mas a troca vale só para esta tela.
  String _loginLocaleCode = 'pt';

  bool _signup = false;
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  /// Idiomas oferecidos no seletor discreto da tela de login.
  static const List<({String flag, String code, String name})> _loginLanguages =
      [
        (flag: '🇧🇷', code: 'pt', name: 'Português'),
        (flag: '🇰🇷', code: 'ko', name: '한국어'),
        (flag: '🇺🇸', code: 'en', name: 'English'),
        (flag: '🇪🇸', code: 'es', name: 'Español'),
      ];

  @override
  void initState() {
    super.initState();
    final current = AppLanguageController.instance.locale.languageCode;
    if (_loginLanguages.any((l) => l.code == current)) {
      _loginLocaleCode = current;
    }
  }

  /// Strings da tela de login no idioma escolhido (reusa o ARB existente).
  AppLocalizations get _loginStrings {
    switch (_loginLocaleCode) {
      case 'ko':
        return AppLocalizationsKo();
      case 'en':
        return AppLocalizationsEn();
      case 'es':
        return AppLocalizationsEs();
      default:
        return AppLocalizationsPt();
    }
  }

  // Estado da validação do código de convite (feedback claro, sem bloquear o
  // cadastro além do necessário — o backend permanece a validação definitiva).
  _InviteStatus _inviteStatus = _InviteStatus.idle;
  InviteValidation? _inviteInfo;
  String? _inviteMessage;
  Timer? _inviteDebounce;

  @override
  void dispose() {
    _inviteDebounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // No modo login as strings seguem o seletor de idioma DESTA tela; no
    // cadastro permanece o idioma global do app.
    final l10n = _signup ? AppLocalizations.of(context)! : _loginStrings;
    final db = SupabaseService.instance;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!_signup) {
      if (email.isEmpty || password.isEmpty) {
        setState(() => _error = l10n.authFillEmailPassword);
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final user = await db.signInWithEmail(email, password);
        kAppIdentity.displayName =
            user.userMetadata?['full_name'] as String? ??
            kAppIdentity.displayName;
        kAppIdentity.username =
            '@${user.userMetadata?['username'] ?? kAppIdentity.username.replaceFirst('@', '')}';
      } on AuthException catch (e) {
        if (!mounted) return;
        setState(() => _error = _friendlyAuthError(e.message, l10n));
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = l10n.authConnectionFail);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      // A troca de tela (Login -> Home) é feita pelo AppGate ao escutar
      // onAuthStateChange.
      return;
    }

    // ---------- Cadastro ----------
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final confirm = _confirmController.text;

    if (name.isEmpty) return _err(l10n.authNameRequired);
    final uname = username.replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(uname)) {
      return _err(l10n.authUsernameRules);
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return _err(l10n.authEmailInvalid);
    }
    if (password.length < 6) {
      return _err(l10n.authPasswordMinLength);
    }
    if (password != confirm) {
      return _err(l10n.authPasswordsMismatch);
    }

    // ---- Convite: confirmação do backend ANTES de finalizar o cadastro ----
    final inviteCode = _inviteController.text.trim().toUpperCase();
    if (inviteCode.isNotEmpty) {
      _inviteDebounce?.cancel();
      final check = await _checkInviteCode(inviteCode);
      if (!mounted) return;
      if (check.isValid) {
        _inviteStatus = _InviteStatus.valid;
        _inviteInfo = check.validation;
        _inviteMessage = null;
      } else if (check.isUnknown) {
        // Verificação indisponível: não trava o cadastro (uma falha de rede
        // não deve impedir a conta). O backend segue sendo a validação
        // definitiva no momento do redeem.
        _inviteStatus = _InviteStatus.unreachable;
        _inviteMessage = l10n.inviteCheckFailed;
      } else {
        setState(() {
          _inviteStatus = _InviteStatus.invalid;
          _inviteMessage = l10n.inviteCodeInvalid;
        });
        return _err(l10n.inviteCodeInvalid);
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await db.signUp(
        email: email,
        password: password,
        displayName: name,
        username: uname,
        inviteCode: inviteCode,
      );
      if (!mounted) return;
      if (res.session != null) {
        kAppIdentity.displayName =
            res.user?.userMetadata?['full_name'] as String? ?? name;
        kAppIdentity.username = '@$uname';
        // Registra o convite no backend assim que a sessão existe.
        if (inviteCode.isNotEmpty) {
          await _redeemInvite(inviteCode);
        }
      } else {
        // Confirmação de e-mail exigida pelo projeto.
        setState(() => _signup = false);
        _emailController.clear();
        _passwordController.clear();
        _confirmController.clear();
        _error = l10n.authAccountCreated;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.authCheckInbox),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e.message, l10n));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.authSignupFail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Registra o convite depois que o usuário tem sessão (backend valida tudo).
  Future<void> _redeemInvite(String code) async {
    try {
      await InviteService.instance.redeem(code);
    } catch (_) {}
  }

  /// Ao digitar o convite, verifica com debounce para dar feedback claro.
  void _onInviteChanged(String raw) {
    _inviteDebounce?.cancel();
    final code = raw.trim();
    if (code.isEmpty || code.length < 6) {
      setState(() {
        _inviteStatus = _InviteStatus.idle;
        _inviteInfo = null;
        _inviteMessage = null;
      });
      return;
    }
    setState(() {
      _inviteStatus = _InviteStatus.checking;
      _inviteMessage = null;
    });
    _inviteDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _checkInvite(code.toUpperCase()),
    );
  }

  Future<InviteCheck> _checkInviteCode(String code) {
    final checker = widget.inviteChecker;
    if (checker != null) return checker(code);
    return InviteService.instance.validateStatus(code);
  }

  Future<void> _checkInvite(String code) async {
    final check = await _checkInviteCode(code);
    if (!mounted) return;
    final l10n = _l10n ?? AppLocalizations.of(context)!;
    setState(() {
      if (check.isValid) {
        _inviteStatus = _InviteStatus.valid;
        _inviteInfo = check.validation;
        _inviteMessage = null;
      } else if (check.isUnknown) {
        _inviteStatus = _InviteStatus.unreachable;
        _inviteInfo = null;
        _inviteMessage = l10n.inviteCheckFailed;
      } else {
        _inviteStatus = _InviteStatus.invalid;
        _inviteInfo = null;
        _inviteMessage = l10n.inviteCodeInvalid;
      }
    });
  }

  void _err(String message) => setState(() => _error = message);

  String _friendlyAuthError(String message, AppLocalizations l10n) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return l10n.authBadCredentials;
    }
    if (lower.contains('already registered')) {
      return l10n.authEmailTaken;
    }
    if (lower.contains('not confirmed')) {
      return l10n.authEmailNotConfirmed;
    }
    if (lower.contains('access_denied') ||
        lower.contains('access denied') ||
        lower.contains('cancelled') ||
        lower.contains('canceled')) {
      return l10n.authGoogleDenied;
    }
    return message;
  }

  Future<void> _google() async {
    final l10n = _loginStrings;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.signInWithGoogle();
      // O retorno do navegador dispara o deep link klayk://callback; o
      // AppGate escuta onAuthStateChange e redireciona para a Home.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e.message, l10n));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.authGoogleStartFail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _github() async {
    final l10n = _loginStrings;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.signInWithGitHub();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e.message, l10n));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.authGithubStartFail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final l10n = _loginStrings;
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _err(l10n.authEmailForgotHint);
      return;
    }
    setState(() => _loading = true);
    try {
      await SupabaseService.instance.resetPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.authRecoveryEmailSent)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.authRecoverySendFail('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _visitor() async {
    final l10n = _loginStrings;
    setState(() => _loading = true);
    try {
      await SupabaseService.instance.ensureAnonymous();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.authGuestUnavailable);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: Stack(
        children: [
          // Brilho roxo sútil ao fundo (identidade premium, sem poluir a leitura).
          Positioned(
            top: -140,
            right: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B5CF6).withValues(alpha: 0.28),
                    const Color(0xFF8B5CF6).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _BrandHeader(strings: _loginStrings),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _signup ? _buildSignup() : _buildLogin(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Seletor de idioma discreto (só afeta esta tela).
                Positioned(top: 8, right: 16, child: _buildLanguageSelector()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    final l10n = _loginStrings;
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          key: const ValueKey('auth_email'),
          controller: _emailController,
          hint: l10n.authEmail,
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        _passwordField(l10n),
        if (_error != null) _errorBox(),
        const SizedBox(height: 14),
        // Brilho neon roxo sútil em torno do botão principal (ativação real).
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _loading
                ? const []
                : [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.32),
                      blurRadius: 26,
                      spreadRadius: -2,
                    ),
                  ],
          ),
          child: FilledButton(
            onPressed: _loading ? null : _submit,
            style: _primaryButtonStyle(),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.authLogin, style: _btnText),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading ? null : _forgotPassword,
            child: Text(
              l10n.authForgotPassword,
              style: const TextStyle(color: Color(0xFFB7A3E8), fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.white10)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l10n.authOr,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider(color: Colors.white10)),
          ],
        ),
        const SizedBox(height: 8),
        _socialButton(
          label: l10n.authGoogleLogin,
          icon: const _GoogleLogo(size: 20),
          onPressed: _loading ? null : _google,
        ),
        const SizedBox(height: 10),
        _socialButton(
          label: l10n.authGithubLogin,
          icon: const _GitHubLogo(size: 19),
          onPressed: _loading ? null : _github,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                l10n.authNoAccountYet,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _signup = true;
                _error = null;
              }),
              child: Text(
                l10n.authCreateAccount,
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _loading ? null : _visitor,
          child: Text(
            l10n.authGuestLogin,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSignup() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          controller: _nameController,
          hint: l10n.authDisplayName,
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _usernameController,
          hint: l10n.authUsername,
          icon: Icons.alternate_email,
          helper: l10n.authUsernameHelper,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _emailController,
          hint: l10n.authEmail,
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _passwordField(),
        const SizedBox(height: 12),
        _field(
          controller: _confirmController,
          hint: l10n.authConfirmPassword,
          icon: Icons.lock_outline,
          obscure: _hidePassword,
          suffix: _obscureToggle(),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('auth_invite_code'),
          controller: _inviteController,
          hint: l10n.authInviteCodeHint,
          icon: Icons.card_giftcard_outlined,
          helper: switch (_inviteStatus) {
            _InviteStatus.valid => l10n.authInviteValid(
              _inviteInfo?.username ?? '',
            ),
            _InviteStatus.checking => l10n.authInviteChecking,
            _InviteStatus.idle => l10n.authInviteFieldHint,
            _InviteStatus.invalid || _InviteStatus.unreachable => null,
          },
          errorText:
              (_inviteStatus == _InviteStatus.invalid ||
                  _inviteStatus == _InviteStatus.unreachable)
              ? _inviteMessage
              : null,
          suffix: switch (_inviteStatus) {
            _InviteStatus.valid => const Icon(
              Icons.check_circle,
              color: Color(0xFF34D399),
              size: 20,
            ),
            _InviteStatus.invalid => const Icon(
              Icons.cancel,
              color: Color(0xFFFF5C7A),
              size: 20,
            ),
            _InviteStatus.checking => const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            _InviteStatus.idle || _InviteStatus.unreachable => null,
          },
          textInputAction: TextInputAction.done,
          onChanged: _onInviteChanged,
          onSubmitted: _submit,
        ),
        if (_error != null) _errorBox(),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: _primaryButtonStyle(),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(l10n.authCreateAccount, style: _btnText),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.authAlreadyHaveAccount,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _signup = false;
                _error = null;
              }),
              child: Text(
                l10n.authLogin,
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _passwordField([AppLocalizations? strings]) => _field(
    controller: _passwordController,
    hint: (strings ?? AppLocalizations.of(context)!).authPassword,
    icon: Icons.lock_outline,
    obscure: _hidePassword,
    suffix: _obscureToggle(),
    textInputAction: TextInputAction.done,
    onSubmitted: _submit,
  );

  Widget _obscureToggle() => IconButton(
    icon: Icon(
      _hidePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      color: Colors.white38,
    ),
    onPressed: () => setState(() => _hidePassword = !_hidePassword),
  );

  Widget _errorBox() => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFE4183C).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE4183C).withValues(alpha: 0.4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFFF5C7A), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _error!,
            style: const TextStyle(color: Color(0xFFFFA0B2), fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _field({
    Key? key,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    VoidCallback? onSubmitted,
    ValueChanged<String>? onChanged,
    String? helper,
    String? errorText,
  }) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: (_) => onSubmitted?.call(),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFF8B5CF6),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        helperText: helper,
        helperStyle: const TextStyle(color: Colors.white30, fontSize: 11),
        errorText: errorText,
        errorStyle: const TextStyle(color: Color(0xFFFFA0B2), fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF15131E),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE4183C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE4183C)),
        ),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
    backgroundColor: const Color(0xFF8B5CF6),
    disabledBackgroundColor: const Color(0xFF3B3163),
    padding: const EdgeInsets.symmetric(vertical: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );

  /// Botão social escuro e elegante, com borda e brilho roxo sútil. O logo
  /// (Google/GitHub) mantém o vetor oficial — nada de recolorir a marca.
  Widget _socialButton({
    required String label,
    required Widget icon,
    required VoidCallback? onPressed,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.13),
            blurRadius: 24,
            spreadRadius: -3,
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF12101A),
            disabledBackgroundColor: const Color(
              0xFF12101A,
            ).withValues(alpha: 0.55),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _kAccent.withValues(alpha: 0.38)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 36, height: 22, child: icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Espaçador espelho do logo: mantém o label perfeitamente
              // centralizado nos dois botões sociais.
              const SizedBox(width: 46),
            ],
          ),
        ),
      ),
    );
  }

  /// Seletor de idioma discreto (canto superior direito), limitado a esta
  /// tela. Não toca no idioma global do app.
  Widget _buildLanguageSelector() {
    final current = _loginLanguages.firstWhere(
      (l) => l.code == _loginLocaleCode,
      orElse: () => _loginLanguages.first,
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12101A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: _kAccent.withValues(alpha: 0.18), blurRadius: 18),
        ],
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Idioma',
        position: PopupMenuPosition.under,
        color: const Color(0xFF15131E),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (code) => setState(() {
          _loginLocaleCode = code;
          _error = null; // evita texto de erro num idioma antigo.
        }),
        itemBuilder: (ctx) => [
          for (final lang in _loginLanguages)
            PopupMenuItem<String>(
              value: lang.code,
              height: 46,
              child: Row(
                children: [
                  Text(lang.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lang.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  if (lang.code == _loginLocaleCode)
                    const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 18,
                    ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.language_rounded,
                color: Color(0xFFB7A3E8),
                size: 17,
              ),
              const SizedBox(width: 6),
              Text(
                current.flag,
                style: const TextStyle(fontSize: 14, height: 1),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more_rounded,
                color: Colors.white38,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.strings});

  /// Strings do idioma selecionado nesta tela; quando nulo usa o app.
  final AppLocalizations? strings;

  @override
  Widget build(BuildContext context) {
    final l10n = strings ?? AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8B5CF6), Color(0xFF4C1D95)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
                blurRadius: 36,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'k',
              style: TextStyle(
                fontSize: 40,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFC084F0), Color(0xFF8B5CF6), Color(0xFF6D28D9)],
          ).createShader(bounds),
          child: const Text(
            'KLAY K',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 5,
              height: 1.1,
              shadows: [Shadow(color: Color(0xFF8B5CF6), blurRadius: 24)],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.authTagline,
          style: const TextStyle(
            color: Color(0xFFB7A3E8),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

const TextStyle _btnText = TextStyle(fontSize: 16, fontWeight: FontWeight.w800);

const Color _kAccent = Color(0xFF8B5CF6);

/// Vetor oficial do "G" multicolor do Google (paths reais do asset de marca).
/// Mantém as 4 cores oficiais — o neon roxo fica no botão e no brilho.
const String _kGoogleLogo =
    '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>'
    '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>'
    '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>'
    '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>'
    '</svg>';

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_kGoogleLogo, width: size, height: size);
}

/// Vetor oficial do Mark do GitHub (octocat) — branco sobre fundo escuro,
/// como no padrão da própria marca.
const String _kGitHubLogo =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#FFFFFF" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/>'
    '</svg>';

class _GitHubLogo extends StatelessWidget {
  const _GitHubLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_kGitHubLogo, width: size, height: size);
}
