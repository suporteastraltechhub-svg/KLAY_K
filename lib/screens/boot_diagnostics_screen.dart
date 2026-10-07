// Tela de diagnóstico de BOOT.
//
// Aparece quando o app falhou ao abrir: mostra a exceção e o stack trace já
// redigidos (sem token, chave ou e-mail), o ponto exato do boot onde falhou e
// o relatório da abertura ANTERIOR — que é o que permite ver a causa mesmo
// quando o processo morre antes de desenhar o primeiro frame.
//
// Não substitui o app: o botão "Continuar" abre o KLAY K normalmente.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/boot_diagnostics.dart';
import '../services/boot_trace.dart';
import '../theme/klayk_theme.dart';

class BootDiagnosticsScreen extends StatefulWidget {
  const BootDiagnosticsScreen({super.key, this.onContinue});

  /// Quando nulo, o botão "Continuar" apenas fecha a tela.
  final VoidCallback? onContinue;

  @override
  State<BootDiagnosticsScreen> createState() => _BootDiagnosticsScreenState();
}

class _BootDiagnosticsScreenState extends State<BootDiagnosticsScreen> {
  late BootDiagnostics _diag;

  @override
  void initState() {
    super.initState();
    _diag = BootDiagnostics.instance;
  }

  void _continue() {
    // Navega PRIMEIRO: segurar o usuário esperando I/O de disco seria um
    // defeito. A limpeza do relatório roda em segundo plano.
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
    // O relatório só é apagado quando o usuário segue para o app, para não
    // perder a prova de uma falha que ainda pode reaparecer.
    unawaited(_diag.clearPersisted());
  }

  @override
  Widget build(BuildContext context) {
    final d = _diag;
    final current = d.current;
    final previous = d.previous;
    final groups = d.grouped();
    // Falhas repetidas da mesma causa não são N problemas: são 1.
    final totalCauses = groups.length;
    final totalEvents = current.length + previous.length;

    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1A26),
        foregroundColor: Colors.white,
        title: const Text('Diagnóstico de abertura'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _header(totalCauses, totalEvents),
            const SizedBox(height: 16),
            _traceCard(),
            const SizedBox(height: 16),
            if (groups.isNotEmpty) ...[
              _sectionTitle('Causas agrupadas'),
              Text(
                'Ocorrências da mesma causa foram agrupadas: '
                'um problema pode se repetir dezenas de vezes.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ...groups.map(_groupCard),
              const SizedBox(height: 16),
            ],
            if (current.isEmpty && previous.isEmpty)
              const Text('Nenhuma falha registrada.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _continue,
              style: FilledButton.styleFrom(
                backgroundColor: KlaykColors.dark.accent,
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Continuar para o app'),
            ),
          ],
        ),
      ),
    );
  }

  /// Trilha do startup. É a resposta direta a "em qual etapa parou?".
  Widget _traceCard() {
    final t = BootTrace.instance;
    final linhas = t.previous;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3550)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trilha do startup',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Abertura atual: #${t.open}'
            '${t.appendFailed ? ' · AVISO: sem escrita em disco' : ''}',
            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (linhas.isEmpty)
            const Text(
              'A abertura anterior não deixou nenhuma etapa registrada. '
              'Se o app fecha sozinho antes de mostrar esta tela, o processo '
              'morreu ANTES do Dart — ou nenhum passo foi gravado.',
              style: TextStyle(color: Color(0xFFFFC46B), fontSize: 12),
            )
          else ...[
            Text(
              'Abertura anterior — ${linhas.length} etapa(s), '
              'última concluída: ${t.previousLastStep ?? "?"}',
              style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _ultimas(linhas, 60).join("\n"),
                  style: const TextStyle(
                    color: Color(0xFFB9F6CA),
                    fontSize: 9,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
          if (t.nativeMarkers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Marcadores nativos: ${t.nativeMarkers.length}',
              style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _ultimas(t.nativeMarkers, 20).join("\n"),
                  style: const TextStyle(
                    color: Color(0xFF80CBC4),
                    fontSize: 9,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(int totalCauses, int totalEvents) {
    final d = _diag;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF241E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6B3FA0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            totalCauses == 0
                ? 'Nenhum problema registrado ao abrir.'
                : '$totalCauses causa(s) em $totalEvents ocorrência(s).',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Última etapa alcançada agora: ${d.phase}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          if (d.previousPhase != null) ...[
            const SizedBox(height: 4),
            Text(
              'A abertura ANTERIOR parou em: ${d.previousPhase}',
              style: const TextStyle(
                color: Color(0xFFFFC46B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Segredos (tokens, chaves, e-mails) foram removidos.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(BootFailureGroup g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: g.count > 1
              ? const Color(0xFFFFC46B)
              : const Color(0xFF3A3550),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _chip(g.phase),
              const SizedBox(width: 6),
              _chip('origem: ${g.from}'),
              const SizedBox(width: 6),
              if (g.count > 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A3410),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'x${g.count} ocorrências',
                    style: const TextStyle(
                      color: Color(0xFFFFC46B),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            g.error,
            style: const TextStyle(
              color: Color(0xFFFF8A80),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'visto de ${_hhmm(g.firstSeen)} até ${_hhmm(g.lastSeen)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              title: const Text(
                'Stack trace',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    g.stack,
                    style: const TextStyle(
                      color: Color(0xFFB9F6CA),
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text:
                              '[${g.phase} / ${g.from} / x${g.count}]\n'
                              '${g.error}\n${g.stack}',
                        ),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Diagnóstico copiado')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 14,
      ),
    ),
  );

  Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF2E2A44),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10)),
  );

  /// Últimas [n] linhas (lista simples, sem extensão de coleção).
  List<String> _ultimas(List<String> xs, int n) =>
      xs.length <= n ? xs : xs.sublist(xs.length - n);
}
