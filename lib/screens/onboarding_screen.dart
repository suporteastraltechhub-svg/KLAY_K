import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';

/// Guia do iniciante (onboarding). Aparece uma vez para contas novas
/// (gate por `user_settings.onboarding_done` no backend). Ao final, marca
/// como concluído via RPC `set_onboarding_done` e devolve verdadeiro para o
/// MainScreen montar o app completo.
class OnboardingScreen extends StatefulWidget {
  /// Chamado quando o usuário conclui o guia (marca onboarding no backend).
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _saving = false;

  static final List<_OnboardingSlide> _slides = [
    const _OnboardingSlide(
      emoji: '👋',
      title: 'Bem-vindo ao KLAY K',
      text: 'Seu espaço de vídeos curtos, lives e encontros. Explore, '
          'participe da comunidade e acompanhe seus criadores favoritos.',
    ),
    const _OnboardingSlide(
      emoji: '🎬',
      title: 'Assista e crie',
      text: 'Navegue pelo feed, curta, comente e publique seus próprios '
          'vídeos. Tudo pensado para ser leve e rápido.',
    ),
    const _OnboardingSlide(
      emoji: '🔥',
      title: 'Viva e conecte',
      text: 'Participe de lives em tempo real, envie presentes e bata papo '
          'com quem assiste você também.',
    ),
    const _OnboardingSlide(
      emoji: '💎',
      title: 'Ganhe recompensas',
      text: 'Complete missões, abra baús, ganhe conquistas e cristais. Use '
          'nas loja, nos jogos e na central de recompensas.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    await _finish();
  }

  Future<void> _skip() async => _finish();

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AccountService.instance.markOnboardingDone();
    } catch (_) {}
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Scaffold(
      body: Stack(
        children: [
          KlaykScreenBackground(
            child: SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _saving ? null : _skip,
                      child: const Text('Pular'),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) => _slideView(_slides[i]),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? colors.primary
                              : colors.border,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _next,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: colors.primary,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _page == _slides.length - 1
                                    ? 'Começar 🚀'
                                    : 'Continuar',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slideView(_OnboardingSlide slide) {
    final colors = kcolors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primaryFaint, colors.surfaceAlt],
                ),
              ),
              child: Center(
                child: Text(slide.emoji, style: const TextStyle(fontSize: 52)),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              slide.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, height: 1.5, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final String emoji;
  final String title;
  final String text;

  const _OnboardingSlide({
    required this.emoji,
    required this.title,
    required this.text,
  });
}