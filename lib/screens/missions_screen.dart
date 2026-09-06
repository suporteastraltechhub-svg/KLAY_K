import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_service.dart';
import '../services/supabase_service.dart';
import 'chests_screen.dart';

/// Missões do KLAY K: tarefas diárias/semanais com recompensas multi-moeda.
///
/// As recompensas só são creditadas pelo backend (transição para completed).
/// Esta tela é apenas leitura do progresso (my_progress).
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const MissionsScreen(),
    );
  }

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  Map<String, dynamic>? _progress;
  String? _error;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Mantém o progresso razoavelmente fresco enquanto a sheet está aberta.
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!SupabaseService.instance.isConfigured) {
      if (mounted) setState(() => _error = 'Modo demo: conecte-se para ver missões.');
      return;
    }
    try {
      final p = await AdminService.instance.myProgress();
      if (mounted) {
        setState(() {
          _progress = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                '🎯 Missões',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : _progress == null
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF8B5CF6)),
                        )
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                          children: [
                            _levelCard(),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                ChestsScreen.show(context);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFB794FF),
                                side: const BorderSide(color: Color(0xFF8B5CF6)),
                              ),
                              icon: const Icon(Icons.inventory_2_rounded, size: 18),
                              label: const Text('🎁 Abrir meus baús'),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Completa missões e ganha moedas, cristais e baús!',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            ..._missionTiles(),
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _levelCard() {
    final level = (_progress?['level'] as num?)?.toInt() ?? 1;
    final title = _progress?['level_title']?.toString() ?? 'Novato';
    final xpTotal = (_progress?['xp_total'] as num?)?.toInt() ?? 0;
    final xpStart = (_progress?['xp_level_start'] as num?)?.toInt() ?? 0;
    final xpNext = (_progress?['xp_next_level'] as num?)?.toInt();
    final hasNext = xpNext != null && xpNext > 0;
    final ratio = hasNext
        ? (((xpTotal - xpStart) / (xpNext - xpStart)).clamp(0.0, 1.0)).toDouble()
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1B54), Color(0xFF151126)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8B5CF6), Color(0xFFC084F0)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$level',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nível $level • $title',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasNext
                      ? '$xpTotal / $xpNext XP'
                      : '$xpTotal XP • nível máximo',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _missionTiles() {
    final missions = (_progress?['missions'] as List?) ?? const [];
    if (missions.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              'Nenhuma missão disponível agora.',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ),
      ];
    }
    return missions.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return _missionTile(m);
    }).toList();
  }

  Widget _missionTile(Map<String, dynamic> m) {
    final target = (m['target'] as num?)?.toInt() ?? 1;
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final completed = m['completed'] == true;
    final ratio = (progress / target).clamp(0.0, 1.0).toDouble();
    final frequency = m['frequency']?.toString() ?? 'daily';
    final rewards = m['rewards'];
    final awardChest = m['award_chest']?.toString();
    final icon = m['icon']?.toString() ?? '✅';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completed
              ? const Color(0xFF34D399).withValues(alpha: 0.6)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m['title']?.toString() ?? 'Missão',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  frequency == 'weekly' ? 'semanal' : 'diária',
                  style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            m['description']?.toString() ?? '',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completed
                          ? const Color(0xFF34D399)
                          : const Color(0xFF8B5CF6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                completed ? '✓' : '$progress/$target',
                style: TextStyle(
                  color: completed ? const Color(0xFF34D399) : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _rewardChip('+${m['xp_reward']} XP'),
              if (rewards is Map && rewards.isNotEmpty)
                ...rewards.entries.map((e) {
                  final cur = e.key?.toString() ?? '';
                  final amount = e.value?.toString() ?? '0';
                  return _rewardChip('+$amount $cur', premium: _isPremium(cur));
                }),
              if (awardChest != null && awardChest.isNotEmpty)
                _rewardChip('🎁 Baú', premium: true),
            ],
          ),
        ],
      ),
    );
  }

  static const Set<String> _premium = {'diamonds', 'crystals', 'rubies', 'emeralds', 'crystal_rare'};

  bool _isPremium(String cur) => _premium.contains(cur);

  Widget _rewardChip(String label, {bool premium = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: premium
            ? const Color(0xFFD4AF37).withValues(alpha: 0.14)
            : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: premium
            ? Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: premium ? const Color(0xFFD4AF37) : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}