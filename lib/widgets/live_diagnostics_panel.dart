import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef LiveDiagnosticsSnapshotBuilder =
    FutureOr<List<LiveDiagnosticItem>> Function();

enum LiveDiagnosticStatus { healthy, warning, error, info }

class LiveDiagnosticItem {
  const LiveDiagnosticItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.status,
  });

  final String label;
  final String value;
  final IconData icon;
  final LiveDiagnosticStatus status;
}

class LiveDiagnosticQuickTest {
  const LiveDiagnosticQuickTest({
    required this.label,
    required this.callback,
    this.icon = Icons.play_arrow_rounded,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() callback;
}

class LiveDiagnosticsPanel extends StatefulWidget {
  const LiveDiagnosticsPanel({
    super.key,
    required this.snapshotBuilder,
    this.recentEvents,
    this.quickTests = const [],
    this.refreshInterval = const Duration(seconds: 2),
  }) : assert(kDebugMode, 'LiveDiagnosticsPanel is debug-only.'),
       assert(
         refreshInterval > Duration.zero,
         'refreshInterval must be positive.',
       );

  final LiveDiagnosticsSnapshotBuilder snapshotBuilder;
  final List<String>? recentEvents;
  final List<LiveDiagnosticQuickTest> quickTests;
  final Duration refreshInterval;

  @override
  State<LiveDiagnosticsPanel> createState() => _LiveDiagnosticsPanelState();
}

class _LiveDiagnosticsPanelState extends State<LiveDiagnosticsPanel> {
  static const _background = Color(0xFF0B0A10);
  static const _accent = Color(0xFF9B7BFF);

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: _accent,
        onPrimary: Colors.white,
        surface: _background,
        onSurface: Colors.white,
        surfaceContainerLowest: const Color(0xFF08070C),
        surfaceContainerLow: const Color(0xFF12111A),
        surfaceContainer: const Color(0xFF181622),
        surfaceContainerHigh: const Color(0xFF211E2D),
        outline: const Color(0xFF5A526D),
        outlineVariant: const Color(0xFF302B3D),
        error: const Color(0xFFFF6B7A),
        onError: Colors.white,
      );

  Timer? _timer;
  List<LiveDiagnosticItem> _items = const [];
  bool _hasSnapshot = false;
  bool _refreshing = false;
  String? _snapshotError;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh(force: true));
      });
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant LiveDiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotBuilder != widget.snapshotBuilder ||
        oldWidget.refreshInterval != widget.refreshInterval) {
      if (oldWidget.refreshInterval != widget.refreshInterval) {
        _startTimer();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh(force: true));
      });
    }
  }

  @override
  void dispose() {
    _requestId++;
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!kDebugMode || widget.refreshInterval <= Duration.zero) return;
    _timer = Timer.periodic(widget.refreshInterval, (_) {
      unawaited(_refresh());
    });
  }

  Future<void> _refresh({bool force = false}) async {
    if (!kDebugMode || !mounted || (_refreshing && !force)) return;

    final requestId = ++_requestId;
    _refreshing = true;
    setState(() {});

    try {
      final snapshot = await widget.snapshotBuilder();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = List<LiveDiagnosticItem>.unmodifiable(snapshot);
        _hasSnapshot = true;
        _snapshotError = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _snapshotError = error.toString();
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: _darkScheme,
      scaffoldBackgroundColor: _background,
      textTheme: Theme.of(context).textTheme,
    );

    return Theme(
      data: theme,
      child: Material(
        type: MaterialType.card,
        color: _background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: _darkScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              if (_refreshing) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_snapshotError != null) ...[
                const SizedBox(height: 14),
                _buildSnapshotError(context, _snapshotError!),
              ],
              const SizedBox(height: 18),
              _buildDiagnostics(context),
              if (widget.recentEvents != null) ...[
                const SizedBox(height: 22),
                _buildRecentEvents(context),
              ],
              if (widget.quickTests.isNotEmpty) ...[
                const SizedBox(height: 22),
                _buildQuickTests(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _darkScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _darkScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          child: const Icon(
            Icons.monitor_heart_rounded,
            color: _accent,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'KLAY K LIVE DIAGNOSTICS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.35,
            ),
          ),
        ),
        if (_refreshing)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            tooltip: 'Refresh diagnostics',
            onPressed: () => unawaited(_refresh(force: true)),
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }

  Widget _buildSnapshotError(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _darkScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _darkScheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_rounded, color: _darkScheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Snapshot failed',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_refresh(force: true)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnostics(BuildContext context) {
    if (!_hasSnapshot && _refreshing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasSnapshot) {
      return _buildEmptyState(
        icon: Icons.sensors_rounded,
        message: 'Waiting for the first diagnostic snapshot.',
      );
    }
    if (_items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inbox_rounded,
        message: 'No diagnostic items reported.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          title: 'Snapshot items',
          icon: Icons.checklist_rounded,
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _items.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _DiagnosticRow(item: _items[index]),
        ],
      ],
    );
  }

  Widget _buildRecentEvents(BuildContext context) {
    final events = widget.recentEvents ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(title: 'Recent events', icon: Icons.history_rounded),
        const SizedBox(height: 10),
        if (events.isEmpty)
          Text(
            'No recent events.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 13,
            ),
          )
        else
          for (var index = 0; index < events.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _EventRow(message: events[index]),
          ],
      ],
    );
  }

  Widget _buildQuickTests(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(title: 'Quick tests', icon: Icons.science_rounded),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (var index = 0; index < widget.quickTests.length; index++)
              _QuickTestButton(
                key: ValueKey<int>(index),
                test: widget.quickTests[index],
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle({required String title, required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: _darkScheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      decoration: BoxDecoration(
        color: _darkScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _darkScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, color: _darkScheme.primary, size: 28),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.item});

  final LiveDiagnosticItem item;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _LiveDiagnosticsPanelState._darkScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _LiveDiagnosticsPanelState._darkScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(status: item.status, color: color),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.color});

  final LiveDiagnosticStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            _statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _LiveDiagnosticsPanelState._darkScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.bolt_rounded,
            color: _LiveDiagnosticsPanelState._darkScheme.primary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTestButton extends StatefulWidget {
  const _QuickTestButton({super.key, required this.test});

  final LiveDiagnosticQuickTest test;

  @override
  State<_QuickTestButton> createState() => _QuickTestButtonState();
}

enum _QuickTestState { idle, running, success, failure }

class _QuickTestButtonState extends State<_QuickTestButton> {
  _QuickTestState _state = _QuickTestState.idle;
  bool _running = false;
  String _message = '';

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _state = _QuickTestState.running;
      _message = 'Running...';
    });

    try {
      await widget.test.callback();
      if (!mounted) return;
      setState(() {
        _running = false;
        _state = _QuickTestState.success;
        _message = 'Passed';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _state = _QuickTestState.failure;
        _message = 'Failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _LiveDiagnosticsPanelState._darkScheme;
    final stateColor = _stateColor(scheme);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 156),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _running ? null : () => unawaited(_run()),
            icon: _running
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                : Icon(widget.test.icon, size: 18),
            label: Text(
              widget.test.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              backgroundColor: scheme.surfaceContainerLow,
              side: BorderSide(color: scheme.outlineVariant),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_state != _QuickTestState.idle) ...[
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_stateIcon(), color: stateColor, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _stateColor(ColorScheme scheme) {
    switch (_state) {
      case _QuickTestState.success:
        return const Color(0xFF54D69A);
      case _QuickTestState.failure:
        return scheme.error;
      case _QuickTestState.running:
        return scheme.primary;
      case _QuickTestState.idle:
        return scheme.onSurfaceVariant;
    }
  }

  IconData _stateIcon() {
    switch (_state) {
      case _QuickTestState.success:
        return Icons.check_circle_rounded;
      case _QuickTestState.failure:
        return Icons.error_rounded;
      case _QuickTestState.running:
        return Icons.hourglass_top_rounded;
      case _QuickTestState.idle:
        return Icons.remove_circle_outline_rounded;
    }
  }
}

Color _statusColor(LiveDiagnosticStatus status) {
  switch (status) {
    case LiveDiagnosticStatus.healthy:
      return const Color(0xFF54D69A);
    case LiveDiagnosticStatus.warning:
      return const Color(0xFFFFC857);
    case LiveDiagnosticStatus.error:
      return const Color(0xFFFF6B7A);
    case LiveDiagnosticStatus.info:
      return const Color(0xFF6BCBFF);
  }
}

IconData _statusIcon(LiveDiagnosticStatus status) {
  switch (status) {
    case LiveDiagnosticStatus.healthy:
      return Icons.check_circle_rounded;
    case LiveDiagnosticStatus.warning:
      return Icons.warning_amber_rounded;
    case LiveDiagnosticStatus.error:
      return Icons.error_rounded;
    case LiveDiagnosticStatus.info:
      return Icons.info_rounded;
  }
}

String _statusLabel(LiveDiagnosticStatus status) {
  switch (status) {
    case LiveDiagnosticStatus.healthy:
      return 'OK';
    case LiveDiagnosticStatus.warning:
      return 'WARN';
    case LiveDiagnosticStatus.error:
      return 'ERROR';
    case LiveDiagnosticStatus.info:
      return 'INFO';
  }
}
