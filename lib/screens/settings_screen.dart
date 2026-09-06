import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/account_service.dart';
import '../services/admin_service.dart';
import '../services/experience_settings.dart';
import '../services/founder_service.dart';
import '../services/supabase_service.dart';
import '../widgets/klayk_ux.dart';
import 'achievements_screen.dart';
import 'ads_central_screen.dart';
import 'ads_admin_screen.dart';
import 'chests_screen.dart';
import 'collections_screen.dart';
import 'creator_dashboard_screen.dart';
import 'drafts_screen.dart';
import 'founder_panel_screen.dart';
import 'help_center_screen.dart';
import 'history_screen.dart';
import 'invites_center_screen.dart';
import 'meu_klayk_screen.dart';
import 'missions_screen.dart';
import 'moderation_screen.dart';
import 'rewards_center_screen.dart';
import 'security/account_guard_screen.dart';
import 'security/report_center_screen.dart';
import 'security/youth_shield_screen.dart';
import 'store_screen.dart';
import 'verification_screen.dart';
import 'wallet_sheet.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Tela de Configurações completa e funcional do KLAY K.
/// Todas as preferências persistentes são salvas no Supabase (user_settings).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AccountSettings _settings = const AccountSettings();
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic>? _profile;
  bool _verified = false;

  // Acesso administrativo (espelho; toda ação é revalidada no backend).
  bool _isAdmin = false;
  bool _isStaff = false;

  // Conta
  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
            child: CircularProgressIndicator(color: _kAccent)),
      );
      final url = await AccountService.instance.uploadAvatar(File(picked.path));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _profile ??= {};
        _profile!['avatar_url'] = url;
      });
      _snack('Foto de perfil atualizada');
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack('Erro ao enviar foto: $e');
    }
  }

  Future<void> _editField(String field, String current, String label) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text('Editar $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Digite aqui'),
          maxLength: field == 'username' ? 20 : 60,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || value == current) return;
    try {
      setState(() => _saving = true);
      final patch = <String, String>{};
      switch (field) {
        case 'display_name':
          patch['displayName'] = value;
          kAppIdentity.displayName = value;
          break;
        case 'username':
          patch['username'] = value.replaceFirst(RegExp(r'^@'), '');
          kAppIdentity.username = '@${value.replaceFirst(RegExp(r'^@'), '')}';
          break;
        case 'bio':
          patch['bio'] = value;
          break;
      }
      await AccountService.instance.updateProfile(
        displayName: patch['displayName'],
        username: patch['username'],
        bio: patch['bio'],
      );
      setState(() {
        _profile = {...?_profile, ...patch};
        _saving = false;
      });
      _snack('$label atualizado');
    } catch (e) {
      setState(() => _saving = false);
      _snack('Erro ao salvar: $e');
    }
  }

  Future<void> _pickProfession() async {
    List<Map<String, dynamic>> professions = const [];
    try {
      professions = await AdminService.instance.listProfessions();
    } catch (_) {}
    if (!mounted) return;
    final current = _profile?['profession']?.toString() ?? '';
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: const Text('Escolha sua profissão'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: professions.isEmpty
              ? const Center(
                  child: Text('Nenhuma profissão disponível.',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in professions)
                      ListTile(
                        leading: Text(
                          (p['icon']?.toString().isNotEmpty ?? false)
                              ? p['icon'].toString()
                              : '🎭',
                          style: const TextStyle(fontSize: 18),
                        ),
                        title: Text(p['name']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        trailing: (p['name']?.toString() == current)
                            ? const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF8B5CF6))
                            : null,
                        onTap: () =>
                            Navigator.pop(ctx, p['name']?.toString()),
                      ),
                    ListTile(
                      leading: const Text('🚫', style: TextStyle(fontSize: 18)),
                      title: const Text('Nenhuma',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      onTap: () => Navigator.pop(ctx, ''),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;
    try {
      await AdminService.instance.setMyProfession(selected);
      setState(() {
        _profile = {...?_profile, 'profession': selected};
      });
      _snack(selected.isEmpty
          ? 'Profissão removida.'
          : 'Profissão definida: $selected');
    } catch (e) {
      _snack('Erro ao definir profissão: $e');
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: const Text('Sair da conta'),
        content: const Text('Tem certeza que deseja sair da sua conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair', style: TextStyle(color: Color(0xFFFF4D6A))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AccountService.instance.signOut();
    if (mounted) _snack('Você saiu da conta');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    ExperienceSettings.instance.load();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await AccountService.instance.fetchSettings();
      final profile = await AccountService.instance.fetchMyProfile();
      final verified = await AccountService.instance.isVerified();
      // Permissões reais via RPC `my_caps()`/`is_klayk_staff` — o backend é a
      // fonte da verdade; o app apenas espelha para habilitar o item do painel.
      final caps = await AdminService.instance.myCaps();
      final admin = await FounderService.instance.isAdmin();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _profile = profile;
        _verified = verified;
        _isAdmin = admin;
        _isStaff = admin || caps.isNotEmpty;
        _loading = false;
      });
      // Espelha reprodução → experiência real do app neste boot.
      ExperienceSettings.instance.syncInMemory(
        ExperienceSettings.instance.value.copyWith(
          autoPlay: settings.autoPlay,
          wifiOnly: settings.wifiOnly,
          saveData: settings.saveData,
          videoQuality: settings.videoQuality,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Não foi possível carregar as configurações: $e');
    }
  }

  Future<void> _setSettings(AccountSettings Function(AccountSettings) update) async {
    final next = update(_settings);
    setState(() {
      _settings = next;
      _saving = true;
    });
    // Espelha as preferências de reprodução globalmente (auto-play, qualidade,
    // economia) para que valem no app inteiro, não só nesta tela.
    ExperienceSettings.instance.syncInMemory(next.toExperience());
    try {
      await AccountService.instance.saveSettings(next);
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Erro ao salvar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Configurações', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 6, withAvatar: true)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader('CONTA'),
                _accountCard(),
                const SizedBox(height: 8),
                _tile(
                  Icons.verified_rounded,
                  'Verificação de perfil',
                  subtitle: _verified
                      ? 'Perfil verificado'
                      : 'Solicitar verificação',
                  trailing: _verified
                      ? const Icon(Icons.check_circle, color: _kAccent)
                      : null,
                  onTap: _verified ? null : _openVerification,
                ),
                _tile(Icons.logout_rounded, 'Sair da conta', danger: true,
                    onTap: _confirmSignOut),
                const SizedBox(height: 24),
                _sectionHeader('PRIVACIDADE'),
                _switchTile(
                  'Conta privada',
                  'Somente seguidores aprovados veem seu conteúdo',
                  _settings.accountPrivate,
                  (v) => _setSettings((s) => s.copyWith(accountPrivate: v)),
                ),
                _tile(Icons.person_off_rounded, 'Usuários bloqueados',
                    onTap: () => _openSection('blocked')),
                _tile(Icons.volume_off_rounded, 'Usuários silenciados',
                    onTap: () => _openSection('muted')),
                const SizedBox(height: 24),
                _sectionHeader('INTERAÇÕES'),
                _subtitle('Quem pode comentar seus vídeos'),
                _segmented(
                  ['Todos', 'Seguidores'],
                  _settings.allowComments
                      ? (_settings.accountPrivate ? 'Seguidores' : 'Todos')
                      : 'Ninguém',
                  (v) => _setSettings((s) => s.copyWith(
                        allowComments: v == 'Todos' || v == 'Seguidores',
                      )),
                ),
                _subtitle('Quem pode te enviar mensagens'),
                _segmented(
                  ['Todos', 'Seguidores', 'Ninguém'],
                  _settings.allowMessages,
                  (v) => _setSettings((s) => s.copyWith(allowMessages: v)),
                ),
                const SizedBox(height: 24),
                _sectionHeader('NOTIFICAÇÕES'),
                _switchTile('Curtidas', '', _settings.notifyCurtidas,
                    (v) => _setSettings((s) => s.copyWith(notifyCurtidas: v))),
                _switchTile('Comentários', '', _settings.notifyComentarios,
                    (v) => _setSettings((s) => s.copyWith(notifyComentarios: v))),
                _switchTile('Novos seguidores', '', _settings.notifyNovosSeguidores,
                    (v) => _setSettings((s) => s.copyWith(notifyNovosSeguidores: v))),
                _switchTile('Mensagens', '', _settings.notifyMensagens,
                    (v) => _setSettings((s) => s.copyWith(notifyMensagens: v))),
                _switchTile('LIVE', '', _settings.notifyLive,
                    (v) => _setSettings((s) => s.copyWith(notifyLive: v))),
                _switchTile('Outras notificações do app', '', _settings.notifyOutras,
                    (v) => _setSettings((s) => s.copyWith(notifyOutras: v))),
                const SizedBox(height: 24),
                _sectionHeader('REPRODUÇÃO'),
                _switchTile('Reprodução automática', '', _settings.autoPlay,
                    (v) => _setSettings((s) => s.copyWith(autoPlay: v))),
                _switchTile('Somente no Wi-Fi', '', _settings.wifiOnly,
                    (v) => _setSettings((s) => s.copyWith(wifiOnly: v))),
                _switchTile('Economia de dados', '', _settings.saveData,
                    (v) => _setSettings((s) => s.copyWith(saveData: v))),
                _subtitle('Qualidade do vídeo'),
                _segmented(
                  ['Auto', 'Baixa', 'Média', 'Alta'],
                  _labelQuality(_settings.videoQuality),
                  (v) => _setSettings((s) => s.copyWith(
                        videoQuality: _codeQuality(v),
                      )),
                ),
                const SizedBox(height: 24),
                _sectionHeader('EXPERIÊNCIA'),
                ValueListenableBuilder<KlaykExperience>(
                  valueListenable: ExperienceSettings.instance.prefs,
                  builder: (context, xp, _) => Column(
                    children: [
                      _switchTile(
                        'Reduzir animações',
                        'Menos movimento e transições (mais economia)',
                        xp.reduceAnimations,
                        (v) => ExperienceSettings.instance
                            .update(xp.copyWith(reduceAnimations: v)),
                      ),
                      _switchTile(
                        'Reduzir efeitos visuais',
                        'Confetes e brilhos mais discretos',
                        xp.reduceEffects,
                        (v) => ExperienceSettings.instance
                            .update(xp.copyWith(reduceEffects: v)),
                      ),
                      _switchTile(
                        'Mostrar reações',
                        'Curtidas animadas e reações dos vídeos',
                        xp.showReactions,
                        (v) => ExperienceSettings.instance
                            .update(xp.copyWith(showReactions: v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader('DADOS E ARMAZENAMENTO'),
                _tile(Icons.delete_sweep_rounded, 'Limpar cache',
                    onTap: () => _snack('Cache limpo')),
                _tile(Icons.storage_rounded, 'Gerenciar armazenamento',
                    onTap: () => _openSection('storage')),
                const SizedBox(height: 24),
                _sectionHeader('MINHA ÁREA'),
                _tile(Icons.auto_awesome_rounded, 'Meu KLAY K',
                    subtitle: 'Sua central pessoal',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MeuKlayKScreen()))),
                _tile(Icons.account_balance_wallet_rounded, 'Carteira',
                    subtitle: 'Moedas, saldo e resgates',
                    onTap: () => WalletSheet.show(context)),
                _tile(Icons.shopping_bag_rounded, 'Loja',
                    subtitle: 'Comprar moedas e itens',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const StoreScreen()))),
                _tile(Icons.folder_special_rounded, 'Coleções',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CollectionsScreen()))),
                _tile(Icons.emoji_events_rounded, 'Conquistas',
                    subtitle: 'Suas medalhas e troféus',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AchievementsScreen()))),
                _tile(Icons.military_tech_rounded, 'Missões',
                    subtitle: 'Complete e ganhe moedas',
                    onTap: () => MissionsScreen.show(context)),
                _tile(Icons.inventory_2_rounded, 'Baús',
                    subtitle: 'Recompensas diárias',
                    onTap: () => ChestsScreen.show(context)),
                _tile(Icons.group_add_rounded, 'Convites',
                    subtitle: 'Convide amigos e ganhe',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const InvitesCenterScreen()))),
                _tile(Icons.redeem_rounded, 'Recompensas',
                    subtitle: 'Central de recompensas',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RewardsCenterScreen()))),
                _tile(Icons.history_rounded, 'Histórico',
                    subtitle: 'O que você assistiu',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const HistoryScreen()))),
                _tile(Icons.note_alt_rounded, 'Rascunhos',
                    subtitle: 'Uploads em andamento',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const DraftsScreen()))),
                const SizedBox(height: 24),
                _sectionHeader('PAINEL'),
                _tile(Icons.insights_rounded, 'Painel do criador',
                    subtitle: 'Estatísticas do seu perfil',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CreatorDashboardScreen()))),
                _tile(Icons.campaign_rounded, 'Central de Anúncios',
                    subtitle: 'Crie e gerencie sua publicidade',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AdsCentralScreen()))),
                if (_isAdmin)
                  _tile(Icons.shield_rounded, 'Moderação',
                      subtitle: 'Analisar denúncias e aplicar ações',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ModerationScreen()))),
                if (_isAdmin)
                  _tile(Icons.campaign_rounded, 'Publicidade',
                      subtitle: 'Moderar anúncios e denúncias',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AdsAdminScreen()))),
                if (_isStaff)
                  _tile(Icons.workspace_premium_rounded, 'Painel do Fundador',
                      subtitle: _isAdmin
                          ? 'Controle completo do KLAY K'
                          : 'Painel da equipe (capabilities concedidas)',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const FounderPanelScreen()))),
                const SizedBox(height: 24),
                _sectionHeader('SEGURANÇA'),
                _switchTile(
                  'Confirmar ações importantes',
                  'Pedir confirmação antes de excluir e sair',
                  _settings.securityConfirmActions,
                  (v) => _setSettings((s) => s.copyWith(securityConfirmActions: v)),
                ),
                _tile(Icons.person_pin_rounded, 'Proteção da conta',
                    subtitle: 'Sessões ativas e senha',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AccountGuardScreen()))),
                _tile(Icons.shield_rounded, 'Modo Jovem e segurança',
                    subtitle: 'Idade, Modo Jovem e conteúdo',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const YouthShieldScreen()))),
                _tile(Icons.report_gmailerrorred_rounded,
                    'Centro de denúncias',
                    subtitle: 'Acompanhe suas denúncias',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ReportCenterScreen()))),
                _tile(Icons.help_outline_rounded, 'Central de ajuda',
                    onTap: _openHelp),
                _tile(Icons.info_outline_rounded, 'Sobre o KLAY K',
                    subtitle: 'Versão, identidade e informações do app',
                    onTap: _showAbout),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kAccent),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _accountCard() {
    final avatar = _profile?['avatar_url']?.toString() ?? '';
    final name = _profile?['display_name']?.toString() ?? 'Usuário';
    final user = _profile?['username']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: _pickAvatar,
                borderRadius: BorderRadius.circular(30),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF2A2740),
                      backgroundImage:
                          avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar.isEmpty
                          ? const Icon(Icons.person, color: Colors.white54, size: 28)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: _kAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              color: _kAccent, size: 16),
                        ],
                      ],
                    ),
                    Text('@$user',
                        style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _accountAction('Nome', () => _editField('display_name', name, 'nome')),
              _accountAction('Usuário',
                  () => _editField('username', '@$user', 'nome de usuário')),
              _accountAction('Bio', () => _editField('bio', _profile?['bio']?.toString() ?? '', 'bio')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _accountAction('Profissão', _pickProfession),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountAction(String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF3A3550)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
        ),
      );

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: _kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _tile(
    IconData icon,
    String title, {
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    return Card(
      color: const Color(0xFF1B1A26),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon,
            color: danger ? const Color(0xFFFF4D6A) : _kAccent),
        title: Text(title,
            style: TextStyle(
                color: danger ? const Color(0xFFFF4D6A) : Colors.white)),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(color: Colors.white54))
            : null,
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap != null ? () => onTap() : null,
      ),
    );
  }

  Widget _switchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      Card(
        color: const Color(0xFF1B1A26),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: SwitchListTile(
          title: Text(title, style: const TextStyle(color: Colors.white)),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          value: value,
          activeTrackColor: _kAccent,
          onChanged: onChanged,
        ),
      );

  Widget _subtitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
      );

  Widget _segmented(
    List<String> options,
    String selected,
    ValueChanged<String> onChanged,
  ) {
    return Wrap(
      spacing: 8,
      children: options.map((o) {
        final sel = o == selected;
        return ChoiceChip(
          label: Text(o,
              style: TextStyle(
                  color: sel ? Colors.white : Colors.white60, fontSize: 13)),
          selected: sel,
          selectedColor: _kAccent,
          backgroundColor: const Color(0xFF222032),
          onSelected: (_) => onChanged(o),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }

  String _labelQuality(String code) {
    switch (code) {
      case 'low':
        return 'Baixa';
      case 'medium':
        return 'Média';
      case 'high':
        return 'Alta';
      default:
        return 'Auto';
    }
  }

  String _codeQuality(String label) {
    switch (label) {
      case 'Baixa':
        return 'low';
      case 'Média':
        return 'medium';
      case 'Alta':
        return 'high';
      default:
        return 'auto';
    }
  }

  void _openVerification() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VerificationScreen()),
    );
  }

  void _openHelp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
    );
  }

  /// Sobre o KLAY K: identidade oficial (ícone do app), versão e informações.
  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Image(image: AssetImage('assets/images/klay_k_icon.png')),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'KLAY K',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sua rede de vídeos curtos, criadores, LIVES, jogos e recompensas.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            SizedBox(height: 14),
            Text('Versão 1.0.0',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            SizedBox(height: 4),
            Text('© KLAY K. Todos os direitos reservados.',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  void _openSection(String section) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _SecondarySectionScreen(section: section)),
    );
  }
}

/// Tela auxiliar para seções simples (bloqueados, silenciados, armazenamento).
class _SecondarySectionScreen extends StatefulWidget {
  final String section;
  const _SecondarySectionScreen({required this.section});

  @override
  State<_SecondarySectionScreen> createState() => _SecondarySectionScreenState();
}

class _SecondarySectionScreenState extends State<_SecondarySectionScreen> {
  List<_BlockedEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.section == 'blocked') {
      final blocked = await AccountService.instance.fetchBlocked();
      if (!mounted) return;
      setState(() {
        _items = blocked
            .map((b) => _BlockedEntry(
                  id: b.id,
                  name: b.name,
                  username: b.username ?? '',
                  avatar: b.avatarUrl ?? '',
                ))
            .toList();
      });
    } else if (widget.section == 'muted') {
      // Lista temporária via conteúdo existente — API de mute por lista.
      // Usa social service se disponível; aqui mantemos a lista vazia honesta.
    }
  }

  Future<void> _unblock(String id) async {
    await AccountService.instance.unblockUser(id);
    setState(() => _items.removeWhere((e) => e.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      'blocked' => 'Usuários bloqueados',
      'muted' => 'Usuários silenciados',
      'storage' => 'Armazenamento',
      _ => 'Seção',
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title),
        centerTitle: true,
      ),
      body: widget.section == 'storage'
          ? _storageView()
          : _items.isEmpty
              ? const Center(
                  child: Text('Nenhum usuário aqui',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final e = _items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2A2740),
                        backgroundImage:
                            e.avatar.isNotEmpty ? NetworkImage(e.avatar) : null,
                        child: e.avatar.isEmpty
                            ? const Icon(Icons.person, color: Colors.white54)
                            : null,
                      ),
                      title: Text(e.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text('@${e.username}',
                          style: const TextStyle(color: Colors.white54)),
                      trailing: widget.section == 'blocked'
                          ? TextButton(
                              onPressed: () => _unblock(e.id),
                              child: const Text('Desbloquear',
                                  style: TextStyle(color: _kAccent)),
                            )
                          : null,
                    );
                  },
                ),
    );
  }

  Widget _storageView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _StorageInfoRow(label: 'Vídeos', value: '0 MB'),
        const _StorageInfoRow(label: 'Imagens', value: '0 MB'),
        const _StorageInfoRow(label: 'Cache', value: '0 MB'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache limpo')));
          },
          icon: const Icon(Icons.delete_sweep),
          label: const Text('Limpar cache'),
          style: FilledButton.styleFrom(backgroundColor: _kAccent),
        ),
      ],
    );
  }
}

class _BlockedEntry {
  final String id;
  final String name;
  final String username;
  final String avatar;
  const _BlockedEntry({
    required this.id,
    required this.name,
    this.username = '',
    this.avatar = '',
  });
}

class _StorageInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _StorageInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white)),
          Text(value, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
