import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/invite_service.dart';
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

  bool _signup = false;
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

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
    final db = SupabaseService.instance;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!_signup) {
      if (email.isEmpty || password.isEmpty) {
        setState(() => _error = 'Preencha e-mail e senha.');
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final user = await db.signInWithEmail(email, password);
        kAppIdentity.displayName = user.userMetadata?['full_name'] as String? ?? kAppIdentity.displayName;
        kAppIdentity.username = '@${user.userMetadata?['username'] ?? kAppIdentity.username.replaceFirst('@', '')}';
      } on AuthException catch (e) {
        if (!mounted) return;
        setState(() => _error = _friendlyAuthError(e.message));
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = 'Não foi possível entrar. Verifique sua conexão.');
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

    if (name.isEmpty) return _err('Informe seu nome de exibição.');
    final uname = username.replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(uname)) {
      return _err('Usuário: 3 a 20 caracteres (letras, números e _).');
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return _err('Digite um e-mail válido.');
    }
    if (password.length < 6) {
      return _err('A senha deve ter pelo menos 6 caracteres.');
    }
    if (password != confirm) {
      return _err('As senhas não coincidem.');
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
        _inviteMessage = 'Não foi possível verificar o código agora.';
      } else {
        setState(() {
          _inviteStatus = _InviteStatus.invalid;
          _inviteMessage =
              'Código de convite inválido. Confira com quem te convidou.';
        });
        return _err('Código de convite inválido. Confira com quem te convidou.');
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
        _error = 'Conta criada! Confirme seu e-mail para entrar.';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verifique sua caixa de entrada para confirmar.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível criar a conta. Tente novamente.');
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
    setState(() {
      if (check.isValid) {
        _inviteStatus = _InviteStatus.valid;
        _inviteInfo = check.validation;
        _inviteMessage = null;
      } else if (check.isUnknown) {
        _inviteStatus = _InviteStatus.unreachable;
        _inviteInfo = null;
        _inviteMessage = 'Não foi possível verificar o código agora.';
      } else {
        _inviteStatus = _InviteStatus.invalid;
        _inviteInfo = null;
        _inviteMessage =
            'Código de convite inválido. Confira com quem te convidou.';
      }
    });
  }

  void _err(String message) => setState(() => _error = message);

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (lower.contains('already registered')) {
      return 'Este e-mail já está cadastrado. Faça login.';
    }
    if (lower.contains('not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (lower.contains('access_denied') ||
        lower.contains('access denied') ||
        lower.contains('cancelled') ||
        lower.contains('canceled')) {
      return 'Login com Google cancelado ou negado. Tente novamente.';
    }
    return message;
  }

  Future<void> _google() async {
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
      setState(() => _error = _friendlyAuthError(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Não foi possível iniciar o Google. Verifique o provedor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _github() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.signInWithGitHub();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Não foi possível iniciar o GitHub. Verifique o provedor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _err('Digite o e-mail da conta para resetar a senha.');
      return;
    }
    setState(() => _loading = true);
    try {
      await SupabaseService.instance.resetPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail de recuperação enviado!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível enviar a recuperação: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _visitor() async {
    setState(() => _loading = true);
    try {
      await SupabaseService.instance.ensureAnonymous();
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Modo visitante indisponível (login anônimo desativado).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
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
          ),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          key: const ValueKey('auth_email'),
          controller: _emailController,
          hint: 'E-mail',
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        _passwordField(),
        if (_error != null) _errorBox(),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: _primaryButtonStyle(),
          child: _loading
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Entrar', style: _btnText),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading ? null : _forgotPassword,
            child: const Text(
              'Esqueceu a senha?',
              style: TextStyle(color: Color(0xFFB7A3E8), fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white10)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('ou', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(child: Divider(color: Colors.white10)),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loading ? null : _google,
          style: _outlineButtonStyle(),
          icon: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          label: const Text('Entrar com Google', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loading ? null : _github,
          style: _outlineButtonStyle(),
          icon: const Icon(Icons.code_rounded, color: Colors.white, size: 20),
          label: const Text('Entrar com GitHub', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Flexible(
              child: Text("Ainda não tem uma conta? ",
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _signup = true;
                _error = null;
              }),
              child: const Text('Criar conta',
                  style: TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  )),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _loading ? null : _visitor,
          child: const Text(
            'Entrar sem conta agora (visitante)',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSignup() {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          controller: _nameController,
          hint: 'Nome de exibição',
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _usernameController,
          hint: 'Nome de usuário',
          icon: Icons.alternate_email,
          helper: '@ letras, números e _ (3 a 20)',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _emailController,
          hint: 'E-mail',
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _passwordField(),
        const SizedBox(height: 12),
        _field(
          controller: _confirmController,
          hint: 'Confirmar senha',
          icon: Icons.lock_outline,
          obscure: _hidePassword,
          suffix: _obscureToggle(),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('auth_invite_code'),
          controller: _inviteController,
          hint: 'Código de convite (opcional)',
          icon: Icons.card_giftcard_outlined,
          helper: switch (_inviteStatus) {
            _InviteStatus.valid => 'Convite válido de @${_inviteInfo?.username ?? ''}',
            _InviteStatus.checking => 'Verificando convite...',
            _InviteStatus.idle =>
              'Código do amigo que te convidou, ex.: KLAYK-AB12CD',
            _InviteStatus.invalid || _InviteStatus.unreachable => null,
          },
          errorText: (_inviteStatus == _InviteStatus.invalid ||
                  _inviteStatus == _InviteStatus.unreachable)
              ? _inviteMessage
              : null,
          suffix: switch (_inviteStatus) {
            _InviteStatus.valid => const Icon(Icons.check_circle,
                color: Color(0xFF34D399), size: 20),
            _InviteStatus.invalid => const Icon(Icons.cancel,
                color: Color(0xFFFF5C7A), size: 20),
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
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Criar conta', style: _btnText),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Já tem uma conta? ',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            GestureDetector(
              onTap: () => setState(() {
                _signup = false;
                _error = null;
              }),
              child: const Text('Entrar',
                  style: TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  )),
            ),
          ],
        ),
      ],
    );
  }

  Widget _passwordField() => _field(
        controller: _passwordController,
        hint: 'Senha',
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
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFFFA0B2), fontSize: 13)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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

  ButtonStyle _outlineButtonStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
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
            child: Text('k', style: TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.w900)),
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
        const Text(
          'Conecte. Crie. Brilhe. 💜',
          style: TextStyle(color: Color(0xFFB7A3E8), fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

const TextStyle _btnText = TextStyle(fontSize: 16, fontWeight: FontWeight.w800);