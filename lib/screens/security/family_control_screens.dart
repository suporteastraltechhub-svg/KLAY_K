import 'package:flutter/material.dart';

import '../../services/family_service.dart';

/// Telas dos três recursos familiares que antes apareciam como
/// "Aguardando backend".
///
/// Todas leem e escrevem por [FamilyService], que chama funções
/// `security definer`. Nenhuma delas calcula autorização localmente: quem é
/// responsável, se o vínculo está ativo e se o dado pertence a quem pediu são
/// respondidos pelo servidor.
class _FamPaleta {
  static const accent = Color(0xFF8B5CF6);
  static const card = Color(0xFF171717);
}

// ===========================================================================
// 1) LIMITE DE TEMPO DEFINIDO POR UM RESPONSÁVEL
// ===========================================================================

class FamilyTimeLimitScreen extends StatefulWidget {
  const FamilyTimeLimitScreen({
    super.key,
    required this.memberId,
    required this.memberLabel,
  });

  final String memberId;
  final String memberLabel;

  @override
  State<FamilyTimeLimitScreen> createState() => _FamilyTimeLimitScreenState();
}

class _FamilyTimeLimitScreenState extends State<FamilyTimeLimitScreen> {
  FamilyTimeLimit? _status;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  int _minutos = 60;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final s = await FamilyService.instance.timeLimitStatus(
        memberId: widget.memberId,
      );
      if (!mounted) return;
      setState(() {
        _status = s;
        if (s.limitado && s.dailyMinutes != null) _minutos = s.dailyMinutes!;
        _carregando = false;
      });
    } on FamilyException catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o limite.';
      });
    }
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await FamilyService.instance.setTimeLimit(
        memberId: widget.memberId,
        dailyMinutes: _minutos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limite salvo')),
      );
      _carregar();
    } on FamilyException catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Limite de tempo')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Membro: ${widget.memberLabel}',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.memberId,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                if (_erro != null)
                  _aviso(_erro!, Icons.error_outline_rounded, const Color(0xFFEF4444)),
                if (_status != null) _cartaoStatus(_status!),
                const SizedBox(height: 22),
                const Text(
                  'Tempo diário permitido',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  '0 significa sem limite diário.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_minutos min',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: _FamPaleta.accent,
                  ),
                ),
                Slider(
                  value: _minutos.toDouble().clamp(0, 720),
                  max: 720,
                  divisions: 24,
                  activeColor: _FamPaleta.accent,
                  label: '$_minutos min',
                  onChanged: (v) => setState(() => _minutos = v.round()),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _preset('30 min', 30),
                      ),
                    const SizedBox(width: 8),
                    Expanded(child: _preset('1 h', 60)),
                    const SizedBox(width: 8),
                    Expanded(child: _preset('2 h', 120)),
                    const SizedBox(width: 8),
                    Expanded(child: _preset('Sem limite', 0)),
                  ],
                ),
                const SizedBox(height: 26),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    style: FilledButton.styleFrom(
                      backgroundColor: _FamPaleta.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar limite'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _preset(String txt, int min) => OutlinedButton(
    onPressed: () => setState(() => _minutos = min),
    style: OutlinedButton.styleFrom(
      foregroundColor: _minutos == min ? Colors.white : Colors.white54,
      side: BorderSide(
        color: _minutos == min ? _FamPaleta.accent : Colors.white12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    child: Text(txt, style: const TextStyle(fontSize: 12)),
  );

  Widget _cartaoStatus(FamilyTimeLimit s) {
    if (!s.limitado) {
      return _aviso(
        'Este membro não tem limite de tempo definido.',
        Icons.timer_off_outlined,
        Colors.white54,
      );
    }
    final pct = (s.ratio * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _FamPaleta.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Uso de hoje',
                style: TextStyle(color: Colors.white54),
              ),
              Text(
                '${s.usedMinutes} / ${s.dailyMinutes} min',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: s.ratio,
              minHeight: 7,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(
                s.exceeded ? const Color(0xFFEF4444) : _FamPaleta.accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.exceeded
                ? 'Limite já atingido hoje.'
                : 'Restam ${s.remainingMinutes} min hoje.',
            style: TextStyle(
              color: s.exceeded ? const Color(0xFFEF4444) : Colors.white70,
              fontSize: 12,
            ),
          ),
          if (pct >= 80 && !s.exceeded)
            Text(
              'Perto do limite ($pct%).',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _aviso(String txt, IconData ic, Color cor) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: cor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(ic, color: cor, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(txt, style: TextStyle(color: cor, fontSize: 13)),
        ),
      ],
    ),
  );
}

// ===========================================================================
// 2) RELATÓRIO DE ATIVIDADE PARA RESPONSÁVEIS
// ===========================================================================

class FamilyReportScreen extends StatefulWidget {
  const FamilyReportScreen({
    super.key,
    required this.memberId,
    required this.memberLabel,
  });

  final String memberId;
  final String memberLabel;

  @override
  State<FamilyReportScreen> createState() => _FamilyReportScreenState();
}

class _FamilyReportScreenState extends State<FamilyReportScreen> {
  FamilyActivityReport? _rel;
  bool _carregando = true;
  String? _erro;
  int _dias = 7;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final r = await FamilyService.instance.activityReport(
        memberId: widget.memberId,
        days: _dias,
      );
      if (!mounted) return;
      setState(() {
        _rel = r;
        _carregando = false;
        _erro = null;
      });
    } on FamilyException catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatório de atividade')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Membro: ${widget.memberLabel}',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [7, 14, 30]
                      .map(
                        (d) => ChoiceChip(
                          label: Text('$d dias'),
                          selected: _dias == d,
                          onSelected: (_) {
                            setState(() => _dias = d);
                            _carregar();
                          },
                          selectedColor: _FamPaleta.accent.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: _dias == d ? Colors.white : Colors.white54,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                if (_erro != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _erro!,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (_rel != null) _grade(_rel!),
                const SizedBox(height: 18),
                const Text(
                  'Os números vêm do que o app realmente registrou no período. '
                  'Conta sem uso aparece com zeros — nada é estimado.',
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
                ),
              ],
            ),
    );
  }

  Widget _grade(FamilyActivityReport r) {
    final itens = [
      ('Publicações', r.posts, Icons.video_library_outlined),
      ('Comentários', r.comments, Icons.chat_bubble_outline_rounded),
      ('Curtidas dadas', r.likesGiven, Icons.favorite_border_rounded),
      ('Lives vistas', r.liveViews, Icons.podcasts_rounded),
      ('Vídeos vistos', r.postViews, Icons.visibility_outlined),
      ('Seguidores novos', r.newFollowers, Icons.person_add_alt_outlined),
      ('Pedidos pendentes', r.pendingFollowRequests, Icons.hourglass_empty_rounded),
    ];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _FamPaleta.accent.withValues(alpha: 0.22),
                _FamPaleta.accent.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'Minutos hoje',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${r.minutesUsedToday}',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: itens
              .map(
                (i) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _FamPaleta.card,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(i.$3, color: Colors.white38, size: 19),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${i.$2}',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              i.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

// ===========================================================================
// 3) APROVAÇÃO DE NOVOS SEGUIDORES
// ===========================================================================

class FollowApprovalScreen extends StatefulWidget {
  const FollowApprovalScreen({super.key});

  @override
  State<FollowApprovalScreen> createState() => _FollowApprovalScreenState();
}

class _FollowApprovalScreenState extends State<FollowApprovalScreen> {
  bool _carregando = true;
  bool _exigir = false;
  String? _erro;
  List<FollowRequest> _pedidos = const [];
  final Set<String> _ocupado = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final p = await FamilyService.instance.myIncomingRequests();
      final ex = await FamilyService.instance.requireFollowApproval();
      if (!mounted) return;
      setState(() {
        _pedidos = p;
        _exigir = ex;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e is FamilyException ? e.message : 'Falha ao carregar.';
      });
    }
  }

  Future<void> _alternar(bool v) async {
    setState(() => _exigir = v);
    try {
      await FamilyService.instance.setRequireFollowApproval(v);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            v
                ? 'Agora você aprova quem te segue.'
                : 'Anyone can follow you again.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exigir = !v);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is FamilyException ? e.message : 'Falhou')),
      );
    }
  }

  Future<void> _responder(FollowRequest r, bool aceitar) async {
    setState(() => _ocupado.add(r.id));
    try {
      await FamilyService.instance.respondRequest(r.id, aceitar);
      if (!mounted) return;
      setState(() {
        _pedidos = _pedidos.where((x) => x.id != r.id).toList();
        _ocupado.remove(r.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado.remove(r.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is FamilyException ? e.message : 'Falhou')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aprovação de seguidores')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _FamPaleta.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Exigir aprovação',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _exigir
                            ? 'Quem te seguir precisa da sua aprovação.'
                            : 'Qualquer pessoa pode te seguir direto.',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _exigir,
                        activeThumbColor: _FamPaleta.accent,
                        onChanged: _alternar,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Pedidos pendentes (${_pedidos.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (_erro != null)
                  Text(
                    _erro!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 13,
                    ),
                  ),
                if (_pedidos.isEmpty && _erro == null)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: _FamPaleta.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          color: Colors.white24,
                          size: 34,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Nenhum pedido esperando.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                for (final r in _pedidos) _linha(r),
              ],
            ),
    );
  }

  Widget _linha(FollowRequest r) {
    final id = r.followerId;
    final busy = _ocupado.contains(r.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _FamPaleta.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFF2A2A2A),
            child: Icon(Icons.person_rounded, size: 18, color: Colors.white54),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id.isEmpty ? 'Usuário' : id.substring(0, 8),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (r.createdAt != null)
                  Text(
                    '${r.createdAt!.day}/${r.createdAt!.month}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              onPressed: () => _responder(r, false),
              icon: const Icon(Icons.close_rounded),
              color: const Color(0xFFEF4444),
              tooltip: 'Rejeitar',
            ),
            IconButton(
              onPressed: () => _responder(r, true),
              icon: const Icon(Icons.check_rounded),
              color: const Color(0xFF22C55E),
              tooltip: 'Aprovar',
            ),
          ],
        ],
      ),
    );
  }
}