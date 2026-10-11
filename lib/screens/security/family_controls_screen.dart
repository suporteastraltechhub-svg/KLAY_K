import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/privacy_security_service.dart';
import '../../services/family_service.dart';
import 'family_control_screens.dart';
import 'security_center_screen.dart';
import 'youth_shield_screen.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _bg = Color(0xFF0A0812);
const Color _card = Color(0xFF1B1A26);
const Color _chipBg = Color(0xFF222032);
const Color _ok = Color(0xFF34D399);
const Color _warn = Color(0xFFFFB020);
const Color _bad = Color(0xFFFF4D6A);

const List<(String, String)> _scopes = [
  ('everyone', 'Todos'),
  ('followers', 'Pessoas que sigo'),
  ('friends', 'Amigos'),
  ('none', 'Ninguém'),
];

const List<(String, String)> _relationships = [
  ('responsavel', 'Responsável'),
  ('pai_mae', 'Pai ou mãe'),
  ('tutor', 'Tutor'),
];

class FamilyControlsScreen extends StatefulWidget {
  const FamilyControlsScreen({super.key});

  @override
  State<FamilyControlsScreen> createState() => _FamilyControlsScreenState();
}

class _FamilyControlsScreenState extends State<FamilyControlsScreen> {
  final PrivacySecurityService _svc = PrivacySecurityService.instance;

  bool _loading = true;
  String? _error;
  List<FamilyLink> _links = const [];
  String? _busyLink;
  bool _requesting = false;
  int _pedidosPendentes = 0;
  String _relationship = 'responsavel';
  final TextEditingController _memberId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _carregarPedidos();
  }

  @override
  void dispose() {
    _memberId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await _svc.fetchFamilyLinks();
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _links = const [];
        _loading = false;
        _error = _linkMessage(e, 'Não foi possível carregar seus vínculos.');
      });
    }
  }

  String _linkMessage(Object error, String fallback) {
    final code = error is PostgrestException ? error.message.trim() : '';
    return switch (code) {
      'auth_required' =>
        'Você precisa entrar na conta para usar vínculos familiares.',
      'bad_member' =>
        'O servidor recusou esse perfil. Confira o ID e tente de novo.',
      'bad_relationship' => 'O servidor recusou esse tipo de relação.',
      'link_not_found' => 'Esse vínculo não existe mais ou já foi encerrado.',
      'forbidden' => 'Você não tem permissão para ajustar estas preferências.',
      'bad_scope' => 'O servidor recusou essa opção de privacidade.',
      _ => fallback,
    };
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _shortId(String id) {
    if (id.isEmpty) return '—';
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }

  String _relationshipLabel(String value) {
    for (final r in _relationships) {
      if (r.$1 == value) return r.$2;
    }
    return value;
  }

  String _statusLabel(FamilyLink link) => switch (link.status) {
    'active' => 'Ativo',
    'pending' =>
      link.isGuardian
          ? 'Aguardando o titular aceitar'
          : 'Aguardando sua decisão',
    _ => 'Encerrado',
  };

  Color _statusColor(FamilyLink link) => switch (link.status) {
    'active' => _ok,
    'pending' => _warn,
    _ => Colors.white38,
  };

  Future<void> _request() async {
    final memberId = _memberId.text.trim();
    if (memberId.isEmpty) {
      _snack(
        'Informe o ID de usuário (uuid) do perfil que você quer proteger.',
      );
      return;
    }
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      await _svc.requestFamilyLink(memberId, relationship: _relationship);
      if (!mounted) return;
      _memberId.clear();
      setState(() => _requesting = false);
      _snack('Pedido enviado. Só vale depois que o titular do perfil aceitar.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _requesting = false);
      _snack(_linkMessage(e, 'Não foi possível enviar o pedido de vínculo.'));
    }
  }

  Future<void> _respond(FamilyLink link, bool accept) async {
    setState(() {
      _busyLink = link.id;
      _error = null;
    });
    try {
      await _svc.respondFamilyLink(link.id, accept);
      if (!mounted) return;
      setState(() => _busyLink = null);
      _snack(
        accept
            ? 'Vínculo aceito. O responsável pode ajustar só as preferências de segurança.'
            : 'Pedido recusado.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLink = null);
      _snack(_linkMessage(e, 'Não foi possível responder ao pedido.'));
    }
  }

  Future<void> _revoke(FamilyLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Revogar vínculo',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          link.isGuardian
              ? 'Você deixa de acompanhar as preferências de segurança deste '
                    'perfil. As preferências que você mudou continuam salvas.'
              : 'O responsável perde o acesso às preferências de segurança deste '
                    'perfil. Nenhuma mensagem ou publicação é envolvida.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Revogar',
              style: TextStyle(color: _bad, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busyLink = link.id;
      _error = null;
    });
    try {
      await _svc.revokeFamilyLink(link.id);
      if (!mounted) return;
      setState(() => _busyLink = null);
      _snack('Vínculo revogado.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLink = null);
      _snack(_linkMessage(e, 'Não foi possível revogar o vínculo.'));
    }
  }

  Future<void> _openSafety(FamilyLink link) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SafetySheet(link: link),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'CONTROLES FAMILIARES',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ferramentas para ajudar a manter crianças e adolescentes mais '
            'protegidos no KLAY K.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          _privacyNote(),
          const SizedBox(height: 24),
          _header('Vínculos familiares'),
          _linksSection(),
          const SizedBox(height: 24),
          _header('Pedir vínculo de responsável'),
          _requestCard(),
          const SizedBox(height: 24),
          _header('O que já existe hoje'),
          _tile(
            Icons.shield_rounded,
            'Proteção para menores',
            'Data de nascimento, Modo Jovem e conteúdo adulto. As decisões são '
                'validadas no servidor.',
            () => _open(const YouthShieldScreen()),
          ),
          _tile(
            Icons.verified_user_rounded,
            'Central de Segurança',
            'Verificação real da sua conta, sessões e denúncias.',
            () => _open(const SecurityCenterScreen()),
          ),
          const SizedBox(height: 24),
          _header('Controles da família'),
          const Text(
            'Estes três recursos já têm suporte no servidor. Cada um valida, '
            'no banco, se quem age é o próprio membro ou um responsável ativo.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          _tileTempo(),
          _tileRelatorio(),
          _tileAprovacao(),
          const SizedBox(height: 24),
          const Text(
            'Enquanto isso, a melhor proteção continua sendo: conta privada, '
            'idade provada nas Configurações e revisão periódica do '
            'Account Guard.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// Quem este usuário pode proteger? Só vínculos ATIVOS e com
  /// `canManageSafety`. A lista vem de `family_links`; a autorização de
  /// verdade é refeita no servidor a cada chamada.
  List<FamilyLink> get _gerenciados {
    if (_cargoAtual != 'responsavel') return const [];
    return _links
        .where((l) => l.status == 'active' && l.canManageSafety)
        .toList();
  }

  String get _cargoAtual => _relationship;

  // ---------------------------------------------------------------------------
  // 1) Limite de tempo definido por um responsável
  // ---------------------------------------------------------------------------
  Widget _tileTempo() {
    final podeVer = _gerenciados.isNotEmpty;
    return _tileFam(
      icone: Icons.timer_outlined,
      titulo: 'Limite de tempo definido por um responsável',
      subtitulo: podeVer
          ? 'Defina quantos minutos por dia cada membro pode usar o app.'
          : 'Vincule um responsável ativo para definir limites.',
      acao: podeVer ? _abrirLimite : null,
    );
  }

  Future<void> _abrirLimite() async {
    if (_gerenciados.isEmpty) return;
    final alvo = _gerenciados.first;
    _open(
      FamilyTimeLimitScreen(
        memberId: alvo.otherId,
        memberLabel: alvo.otherId.isEmpty ? 'Membro' : alvo.otherId.substring(0, 8),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2) Relatório de atividade para responsáveis
  // ---------------------------------------------------------------------------
  Widget _tileRelatorio() {
    final podeVer = _gerenciados.isNotEmpty;
    return _tileFam(
      icone: Icons.insights_outlined,
      titulo: 'Relatório de atividade para responsáveis',
      subtitulo: podeVer
          ? 'Veja o uso real do app de quem está sob sua responsabilidade.'
          : 'Disponível para responsáveis ativos.',
      acao: podeVer ? _abrirRelatorio : null,
    );
  }

  Future<void> _abrirRelatorio() async {
    if (_gerenciados.isEmpty) return;
    final alvo = _gerenciados.first;
    _open(
      FamilyReportScreen(
        memberId: alvo.otherId,
        memberLabel: alvo.otherId.isEmpty ? 'Membro' : alvo.otherId.substring(0, 8),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3) Aprovação de novos seguidores
  // ---------------------------------------------------------------------------
  Widget _tileAprovacao() {
    return _tileFam(
      icone: Icons.person_add_alt_outlined,
      titulo: 'Aprovação de novos seguidores',
      subtitulo:
          'Exija aprovação antes de aceitar quem te seguir. Você decide.',
      acao: _abrirAprovacao,
      badge: _pedidosPendentes,
    );
  }

  Future<void> _abrirAprovacao() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FollowApprovalScreen()),
    );
    if (mounted) _carregarPedidos();
  }

  Future<void> _carregarPedidos() async {
    try {
      final l = await FamilyService.instance.myIncomingRequests();
      if (!mounted) return;
      setState(() => _pedidosPendentes = l.length);
    } catch (_) {
      // Sem sessão ou sem rede: a tela mostra o próprio estado vazio.
    }
  }

  /// Linha dos três recursos familiares agora implementados.
  Widget _tileFam({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    VoidCallback? acao,
    int badge = 0,
  }) {
    return Card(
      color: _card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icone, color: _accent),
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          subtitulo,
          style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
        ),
        trailing: badge > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: acao,
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _privacyNote() => Semantics(
    label:
        'O responsável ajusta apenas preferências de segurança. Ele nunca lê '
        'mensagens, não vê localização, câmera ou microfone e não acessa '
        'conteúdo privado.',
    container: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_rounded, color: _accent, size: 30),
          SizedBox(height: 12),
          Text(
            'O responsável só mexe no que é segurança',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Ele ajusta quem envia mensagem ao perfil, se os comentários abrem, '
            'quem pode marcar, o filtro de conteúdo sensível e a confirmação de '
            'ações de segurança. Ele nunca lê mensagens, não vê localização, '
            'câmera ou microfone e não acessa conteúdo privado.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
          ),
          SizedBox(height: 10),
          Text(
            'O vínculo só vale depois que o titular do perfil aceitar. Antes '
            'disso o responsável não ajusta nada.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    ),
  );

  Widget _linksSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return _notice(Icons.cloud_off_rounded, _error!, _load);
    }
    if (_links.isEmpty) {
      return _notice(
        Icons.link_off_rounded,
        'Nenhum vínculo familiar na sua conta agora. Você pode pedir um '
        'vínculo abaixo ou responder a um pedido de responsável.',
        null,
      );
    }
    return Column(children: [for (final link in _links) _linkCard(link)]);
  }

  Widget _notice(IconData icon, String message, VoidCallback? onRetry) =>
      Semantics(
        label: message,
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.white38, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text(
                      'Tentar de novo',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _linkCard(FamilyLink link) {
    final busy = _busyLink == link.id;
    final canManage = link.isGuardian && link.isActive && link.canManageSafety;
    final title = link.isGuardian
        ? 'Vínculo de responsabilidade'
        : (link.isPending ? 'Pedido de responsável' : 'Responsável vinculado');
    final subtitle = [
      link.isGuardian
          ? 'Perfil ${_shortId(link.otherId)}'
          : (link.isPending
                ? 'Pedido de ${_shortId(link.otherId)}'
                : 'Responsável ${_shortId(link.otherId)}'),
      _relationshipLabel(link.relationship),
      _statusLabel(link),
    ].join(' · ');

    return Semantics(
      label: '$title. $subtitle',
      container: true,
      child: Card(
        color: _card,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: Padding(
                        padding: EdgeInsets.all(3),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.family_restroom_rounded,
                      color: _statusColor(link),
                    ),
              title: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              trailing: canManage
                  ? const Icon(Icons.tune_rounded, color: _accent)
                  : null,
              onTap: canManage && !busy ? () => _openSafety(link) : null,
            ),
            if (canManage ||
                (!link.isGuardian && (link.isPending || link.isActive)))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
                child: Row(
                  children: [
                    if (canManage)
                      TextButton(
                        onPressed: busy ? null : () => _openSafety(link),
                        child: const Text(
                          'Ajustar preferências',
                          style: TextStyle(
                            color: _accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (link.isPending && !link.isGuardian) ...[
                      TextButton(
                        onPressed: busy ? null : () => _respond(link, false),
                        child: const Text(
                          'Recusar',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _respond(link, true),
                        child: const Text(
                          'Aceitar',
                          style: TextStyle(
                            color: _ok,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ] else if (link.isActive)
                      TextButton(
                        onPressed: busy ? null : () => _revoke(link),
                        child: const Text(
                          'Revogar',
                          style: TextStyle(color: _bad, fontSize: 13),
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

  Widget _requestCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Você pode ser o responsável de um perfil',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Peça à pessoa o ID de usuário (uuid) do perfil. Sem esse ID o '
          'servidor não aceita o pedido.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _memberId,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'ID de usuário (uuid) do perfil',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: _chipBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Relação',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label:
              'Relação: ${_relationships.map((r) => r.$2).join(', ')}. '
              'Selecionado: ${_relationshipLabel(_relationship)}',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _relationships)
                ChoiceChip(
                  label: Text(
                    r.$2,
                    style: TextStyle(
                      color: r.$1 == _relationship
                          ? Colors.white
                          : Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  selected: r.$1 == _relationship,
                  selectedColor: _accent,
                  backgroundColor: _chipBg,
                  onSelected: _requesting
                      ? null
                      : (v) {
                          if (v) setState(() => _relationship = r.$1);
                        },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _requesting ? null : _request,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _accent.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _requesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'ENVIAR PEDIDO',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'O pedido fica pendente até o titular do perfil responder. Nada é '
          'ativado sozinho.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
      ],
    ),
  );

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Card(
    color: _card,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: _accent),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    ),
  );
}

class _SafetySheet extends StatefulWidget {
  const _SafetySheet({required this.link});

  final FamilyLink link;

  @override
  State<_SafetySheet> createState() => _SafetySheetState();
}

class _SafetySheetState extends State<_SafetySheet> {
  final PrivacySecurityService _svc = PrivacySecurityService.instance;

  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  String _name = '';
  String _username = '';
  String _allowMessages = 'everyone';
  bool _allowComments = true;
  String _allowMentions = 'everyone';
  bool _sensitiveFilter = false;
  bool _confirmActions = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _linkMessage(Object error, String fallback) {
    final code = error is PostgrestException ? error.message.trim() : '';
    return switch (code) {
      'auth_required' =>
        'Você precisa entrar na conta para usar vínculos familiares.',
      'link_not_found' => 'Esse vínculo não está ativo.',
      'forbidden' => 'Você não tem permissão para ajustar estas preferências.',
      'bad_scope' => 'O servidor recusou essa opção de privacidade.',
      _ => fallback,
    };
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _scopeLabel(String value) {
    for (final s in _scopes) {
      if (s.$1 == value) return s.$2;
    }
    return value;
  }

  void _apply(Map<String, dynamic> snap) {
    final raw = snap['settings'];
    final s = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _name = snap['display_name']?.toString() ?? '';
    _username = snap['username']?.toString() ?? '';
    _allowMessages = s['allow_messages']?.toString() ?? 'everyone';
    _allowComments = s['allow_comments'] == true;
    _allowMentions = s['allow_mentions']?.toString() ?? 'everyone';
    _sensitiveFilter = s['sensitive_content_filter'] == true;
    _confirmActions = s['security_confirm_actions'] != false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _svc.familySafetySnapshot(widget.link.id);
      if (!mounted) return;
      setState(() {
        _apply(snap);
        _loaded = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _linkMessage(
          e,
          'Não foi possível carregar as preferências deste perfil.',
        );
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _svc.familySetSafetySettings(
        widget.link.id,
        allowMessages: _allowMessages,
        allowComments: _allowComments,
        allowMentions: _allowMentions,
        sensitiveContentFilter: _sensitiveFilter,
        securityConfirmActions: _confirmActions,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _linkMessage(
          e,
          'Não foi possível salvar as preferências de segurança.',
        );
      });
      return;
    }
    try {
      final snap = await _svc.familySafetySnapshot(widget.link.id);
      if (!mounted) return;
      setState(() {
        _apply(snap);
        _saving = false;
      });
      _snack('Preferências de segurança confirmadas pelo servidor.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'As preferências foram enviadas, mas não foi possível reler a '
            'confirmação do servidor. '
            '${_linkMessage(e, 'Tente abrir o vínculo de novo para conferir.')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preferências de segurança',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _name.isEmpty && _username.isEmpty
                  ? 'Perfil sob responsabilidade'
                  : (_name.isEmpty
                        ? '@$_username'
                        : (_username.isEmpty ? _name : '$_name · @$_username')),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Você ajusta apenas estas preferências. Mensagens, localização, '
              'câmera, microfone e conteúdo privado deste perfil não ficam '
              'acessíveis para você.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(
                    color: _accent,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (!_loaded) ...[
              Text(
                _error ?? 'Não foi possível carregar as preferências.',
                style: const TextStyle(
                  color: Color(0xFFFFB020),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _load,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Tentar de novo'),
                ),
              ),
            ] else ...[
              _chips(
                'Quem pode enviar mensagem',
                'Define quem abre a caixa de mensagem deste perfil.',
                _allowMessages,
                (v) => setState(() => _allowMessages = v),
              ),
              _switchRow(
                Icons.mode_comment_rounded,
                'Comentários',
                'Desligado, ninguém comenta nas publicações deste perfil.',
                _allowComments,
                (v) => setState(() => _allowComments = v),
              ),
              _chips(
                'Quem pode marcar',
                'Quem pode escrever @usuário ou citar o nome deste perfil.',
                _allowMentions,
                (v) => setState(() => _allowMentions = v),
              ),
              _switchRow(
                Icons.filter_alt_rounded,
                'Filtro de conteúdo sensível',
                'Corta a exibição de conteúdo sensível no app do titular.',
                _sensitiveFilter,
                (v) => setState(() => _sensitiveFilter = v),
              ),
              _switchRow(
                Icons.verified_user_rounded,
                'Confirmar ações de segurança',
                'O titular confirma trocas de senha e ações sensíveis.',
                _confirmActions,
                (v) => setState(() => _confirmActions = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFFB020),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      : const Text(
                          'SALVAR PREFERÊNCIAS',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chips(
    String title,
    String subtitle,
    String value,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Semantics(
          label:
              'Opções: ${_scopes.map((s) => s.$2).join(', ')}. '
              'Selecionado: ${_scopeLabel(value)}',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _scopes)
                ChoiceChip(
                  label: Text(
                    s.$2,
                    style: TextStyle(
                      color: s.$1 == value ? Colors.white : Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  selected: s.$1 == value,
                  selectedColor: _accent,
                  backgroundColor: _chipBg,
                  onSelected: _saving
                      ? null
                      : (v) {
                          if (v) onChanged(s.$1);
                        },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _switchRow(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Semantics(
    label: '$title. ${value ? 'Ligado' : 'Desligado'}',
    toggled: value,
    container: true,
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      activeThumbColor: _accent,
      secondary: Icon(icon, color: _accent),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      onChanged: _saving ? null : onChanged,
    ),
  );
}

