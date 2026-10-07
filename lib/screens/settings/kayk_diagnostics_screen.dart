import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/settings_diagnostics_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1B1A26);
const Color _kOk = Color(0xFF34D399);
const Color _kWarn = Color(0xFFFBBF24);
const Color _kFail = Color(0xFFFF4D6A);
const Color _kMuted = Color(0xFF9A94AD);

class _ProbeView {
  final String label;
  final Color color;
  final IconData icon;

  const _ProbeView(this.label, this.color, this.icon);
}

_ProbeView _probeView(ProbeState state) => switch (state) {
  ProbeState.ok => const _ProbeView(
    'Funcionando',
    _kOk,
    Icons.check_circle_rounded,
  ),
  ProbeState.checking => const _ProbeView(
    'Verificando',
    _kWarn,
    Icons.hourglass_top_rounded,
  ),
  ProbeState.warning => const _ProbeView(
    'Atenção',
    _kWarn,
    Icons.warning_amber_rounded,
  ),
  ProbeState.failed => const _ProbeView('Falhou', _kFail, Icons.cancel_rounded),
  ProbeState.unavailable => const _ProbeView(
    'Indisponível',
    _kMuted,
    Icons.block_rounded,
  ),
  ProbeState.pending => const _ProbeView(
    'Pendente',
    _kMuted,
    Icons.more_horiz_rounded,
  ),
};

String _probeDetail(ServiceProbe probe) {
  if (probe.detail.isNotEmpty) return probe.detail;
  if (probe.state == ProbeState.unavailable) {
    return 'Não foi possível verificar.';
  }
  return '';
}

String _timestamp(DateTime value) =>
    DateFormat('dd/MM/yyyy HH:mm:ss').format(value);

class KaykDiagnosticsScreen extends StatefulWidget {
  const KaykDiagnosticsScreen({super.key});

  @override
  State<KaykDiagnosticsScreen> createState() => _KaykDiagnosticsScreenState();
}

class _KaykDiagnosticsScreenState extends State<KaykDiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  final SettingsDiagnosticsService _svc = SettingsDiagnosticsService.instance;

  late final TabController _tabs;
  DiagnosticsReport? _report;
  bool _running = false;
  bool _requested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.index == 1 && !_requested) _run();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _requested = true;
    });
    try {
      final report = await _svc.runServiceDiagnostics();
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'Não foi possível executar o diagnóstico. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Diagnóstico KLAY K',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Semantics(
            label: 'Atualizar diagnóstico',
            button: true,
            child: IconButton(
              onPressed: _running ? null : _run,
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: TabBar(
            controller: _tabs,
            indicatorColor: _kAccent,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            tabs: const [
              Tab(text: 'Diagnóstico'),
              Tab(text: 'Status dos serviços'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildDiagnosticsTab(), _buildStatusTab()],
      ),
    );
  }

  Widget _buildDiagnosticsTab() {
    final report = _report;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const Text(
          'RELATÓRIO DE SERVIÇOS',
          style: TextStyle(
            color: _kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        _runCard(report),
        if (_running) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Executando verificações nos serviços',
            child: const LinearProgressIndicator(
              color: _kAccent,
              backgroundColor: Color(0xFF2A2740),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Executando verificações reais nos serviços...',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorCard(_error!),
        ],
        if (report != null) ...[
          const SizedBox(height: 12),
          _summaryCard(report),
          const SizedBox(height: 20),
          const Text(
            'VERIFICAÇÕES',
            style: TextStyle(
              color: _kAccent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          ...report.probes.map(_probeCard),
        ] else if (!_running && _error == null) ...[
          const SizedBox(height: 16),
          const Text(
            'Nenhuma verificação executada ainda. Toque em EXECUTAR DIAGNÓSTICO '
            'para testar os serviços agora — nada é verificado em segundo plano.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusTab() {
    final report = _report;
    if (_running) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Semantics(
            label: 'Verificando serviços',
            child: const LinearProgressIndicator(
              color: _kAccent,
              backgroundColor: Color(0xFF2A2740),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Verificando serviços...',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [_errorCard(_error!)],
      );
    }
    if (report == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: const [
          Text(
            'O status dos serviços ainda não foi verificado.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          '${report.okCount} de ${report.probes.length} funcionando',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'Verificado em ${_timestamp(report.ranAt)}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Card(
          color: _kCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (var i = 0; i < report.probes.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFF2A2740)),
                _statusRow(report.probes[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _runCard(DiagnosticsReport? report) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Teste real de todos os serviços do app',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cada linha só fica verde depois que a chamada real volta. Sem '
            'resultado real, a tela mostra o estado honesto (indisponível, '
            'falhou ou pendente).',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'Executar diagnóstico de todos os serviços',
            button: true,
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                _running ? 'EXECUTANDO...' : 'EXECUTAR DIAGNÓSTICO',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          if (report != null) ...[
            const SizedBox(height: 10),
            Text(
              'Última execução: ${_timestamp(report.ranAt)}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(DiagnosticsReport report) {
    final total = report.probes.length;
    final failed = report.probes
        .where((p) => p.state == ProbeState.failed)
        .length;
    final unavailable = report.probes
        .where((p) => p.state == ProbeState.unavailable)
        .length;
    final headline = '${report.okCount} de $total funcionando';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Semantics(
        label:
            'Resumo: $headline. $failed com falha e $unavailable indisponíveis.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.hasFailure
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_rounded,
                  color: report.hasFailure ? _kWarn : _kOk,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Verificado em ${_timestamp(report.ranAt)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (failed > 0) '$failed falhando',
                if (unavailable > 0) '$unavailable indisponíveis',
              ].join(' · '),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kFail.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _kFail, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _probeCard(ServiceProbe probe) {
    final view = _probeView(probe.state);
    final detail = _probeDetail(probe);
    return Semantics(
      label: '${probe.label}: ${view.label}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(view.icon, color: view.color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          probe.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        view.label,
                        style: TextStyle(
                          color: view.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(ServiceProbe probe) {
    final view = _probeView(probe.state);
    final detail = _probeDetail(probe);
    return Semantics(
      label: '${probe.label}: ${view.label}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    probe.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: view.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: view.color.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(view.icon, color: view.color, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    view.label,
                    style: TextStyle(
                      color: view.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
