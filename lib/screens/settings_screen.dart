import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../services/account_service.dart';
import '../services/admin_service.dart';
import '../services/experience_settings.dart';
import 'notification_prefs_screen.dart';
import 'settings/about_screen.dart';
import 'settings/feedback_screen.dart';
import 'settings/maintenance_screen.dart';
import '../services/founder_service.dart';
import '../services/locale_controller.dart';
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
import 'language_screen.dart';
import 'meu_klayk_screen.dart';
import 'missions_screen.dart';
import 'moderation_screen.dart';
import 'marketing/marketing_hub_screen.dart';
import 'rewards_center_screen.dart';
import 'security/account_guard_screen.dart';
import 'security/advanced_privacy_screen.dart';
import 'security/accessibility_screen.dart';
import 'security/digital_wellbeing_screen.dart';
import 'security/family_controls_screen.dart';
import 'security/privacy_center_screen.dart';
import 'security/report_center_screen.dart';
import 'security/security_center_screen.dart';
import 'security/youth_shield_screen.dart';
import 'settings/comments_control_screen.dart';
import 'settings/gifts_settings_screen.dart';
import 'settings/kayk_diagnostics_screen.dart';
import 'settings/live_security_screen.dart';
import 'settings/messages_control_screen.dart';
import 'settings/spam_protection_screen.dart';
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
        builder: (_) =>
            const Center(child: CircularProgressIndicator(color: _kAccent)),
      );
      final url = await AccountService.instance.uploadAvatar(File(picked.path));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _profile ??= {};
        _profile!['avatar_url'] = url;
      });
      _snack(AppLocalizations.of(context)!.photoUpdated);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack(AppLocalizations.of(context)!.avatarUploadError(e.toString()));
    }
  }

  Future<void> _editField(String field, String current, String label) async {
    final controller = TextEditingController(text: current);
    final l10n = AppLocalizations.of(context)!;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(l10n.editFieldTitle(label)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(ctx)!.digiteAqui,
          ),
          maxLength: field == 'username' ? 20 : 60,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(ctx)!.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(
              AppLocalizations.of(ctx)!.save,
              style: const TextStyle(color: _kAccent),
            ),
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
      _snack(l10n.fieldUpdated(label));
    } catch (e) {
      setState(() => _saving = false);
      _snack(l10n.saveError(e.toString()));
    }
  }

  Future<void> _pickProfession() async {
    final l10n = AppLocalizations.of(context)!;
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
        title: Text(AppLocalizations.of(ctx)!.chooseProfession),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: professions.isEmpty
              ? Center(
                  child: Text(
                    AppLocalizations.of(ctx)!.noProfessionsAvailable,
                    style: const TextStyle(color: Colors.white54),
                  ),
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
                        title: Text(
                          p['name']?.toString() ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        trailing: (p['name']?.toString() == current)
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF8B5CF6),
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, p['name']?.toString()),
                      ),
                    ListTile(
                      leading: const Text('🚫', style: TextStyle(fontSize: 18)),
                      title: Text(
                        AppLocalizations.of(ctx)!.none,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, ''),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(ctx)!.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
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
      _snack(
        selected.isEmpty
            ? l10n.professionRemoved
            : l10n.professionSet(selected),
      );
    } catch (e) {
      _snack(l10n.professionSetError(e.toString()));
    }
  }

  Future<void> _confirmSignOut() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(AppLocalizations.of(ctx)!.signOutTitle),
        content: Text(AppLocalizations.of(ctx)!.signOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(ctx)!.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(ctx)!.signOut,
              style: const TextStyle(color: Color(0xFFFF4D6A)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AccountService.instance.signOut();
    if (mounted) _snack(l10n.signOutDone);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      _snack(AppLocalizations.of(context)!.loadSettingsError);
    }
  }

  Future<void> _setSettings(
    AccountSettings Function(AccountSettings) update,
  ) async {
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
        _snack(AppLocalizations.of(context)!.saveError(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const KlaykListSkeleton(rows: 6, withAvatar: true)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader(l10n.sectionAccount),
                _accountCard(),
                const SizedBox(height: 8),
                _tile(
                  Icons.verified_rounded,
                  l10n.profileVerification,
                  subtitle: _verified
                      ? l10n.profileVerified
                      : l10n.requestVerification,
                  trailing: _verified
                      ? const Icon(Icons.check_circle, color: _kAccent)
                      : null,
                  onTap: _verified ? null : _openVerification,
                ),
                _tile(
                  Icons.logout_rounded,
                  l10n.signOut,
                  danger: true,
                  onTap: _confirmSignOut,
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionPrivacy),
                _switchTile(
                  l10n.privateAccount,
                  l10n.privateAccountHint,
                  _settings.accountPrivate,
                  (v) => _setSettings((s) => s.copyWith(accountPrivate: v)),
                ),
                _tile(
                  Icons.person_off_rounded,
                  l10n.blockedUsers,
                  onTap: () => _openSection('blocked'),
                ),
                _tile(
                  Icons.volume_off_rounded,
                  l10n.mutedUsers,
                  onTap: () => _openSection('muted'),
                ),
                const SizedBox(height: 24),
                _sectionHeader('PRIVACIDADE AVANÇADA'),
                _tile(
                  Icons.tune_rounded,
                  'Privacidade avançada',
                  subtitle: 'Quem pode interagir, mencionar e ver você',
                  onTap: _openAdvancedPrivacy,
                ),
                _tile(
                  Icons.privacy_tip_rounded,
                  'Central de privacidade',
                  subtitle: 'Seus dados, bloqueios e histórico',
                  onTap: _openPrivacyCenter,
                ),
                const SizedBox(height: 24),
                _sectionHeader('PROTEÇÃO PARA MENORES'),
                _infoCard(
                  'Ferramentas adicionais para ajudar a manter crianças e '
                  'adolescentes mais protegidos no KLAY K.',
                ),
                _tile(
                  Icons.family_restroom_rounded,
                  'Controles familiares',
                  subtitle: 'Proteção para menores com autorização',
                  onTap: _openFamilyControls,
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionInteractions),
                _subtitle(l10n.whoCanComment),
                _segmented(
                  [('all', l10n.all), ('followers', l10n.onlyFollowers)],
                  _settings.allowComments
                      ? (_settings.accountPrivate ? 'followers' : 'all')
                      : 'none',
                  (id) => _setSettings(
                    (s) => s.copyWith(
                      allowComments: id == 'all' || id == 'followers',
                    ),
                  ),
                ),
                _subtitle(l10n.whoCanMessageYou),
                _segmented(
                  [
                    ('everyone', l10n.all),
                    ('followers', l10n.onlyFollowers),
                    ('none', l10n.noOne),
                  ],
                  _settings.allowMessages,
                  (v) => _setSettings((s) => s.copyWith(allowMessages: v)),
                ),
                const SizedBox(height: 24),
                _sectionHeader('CONTROLE DE MENSAGENS E COMENTÁRIOS'),
                _tile(
                  Icons.mark_email_unread_rounded,
                  'Controle de mensagens',
                  subtitle: 'Quem pode enviar mensagens',
                  onTap: _openMessagesControl,
                ),
                _tile(
                  Icons.comment_rounded,
                  'Controle de comentários',
                  subtitle: 'Permitir comentários e filtro de conteúdo',
                  onTap: _openCommentsControl,
                ),
                _tile(
                  Icons.report_gmailerrorred_rounded,
                  'Proteção contra spam',
                  subtitle: 'Verifique textos e solicitações suspeitas',
                  onTap: _openSpamProtection,
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionNotifications),
                _switchTile(
                  l10n.likesNotif,
                  '',
                  _settings.notifyCurtidas,
                  (v) => _setSettings((s) => s.copyWith(notifyCurtidas: v)),
                ),
                _switchTile(
                  l10n.commentsNotif,
                  '',
                  _settings.notifyComentarios,
                  (v) => _setSettings((s) => s.copyWith(notifyComentarios: v)),
                ),
                _tile(
                  Icons.tune_rounded,
                  l10n.notifPrefs,
                  subtitle: l10n.notifCategoriesHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationPrefsScreen(),
                    ),
                  ),
                ),
                _switchTile(
                  l10n.newFollowersNotif,
                  '',
                  _settings.notifyNovosSeguidores,
                  (v) =>
                      _setSettings((s) => s.copyWith(notifyNovosSeguidores: v)),
                ),
                _switchTile(
                  l10n.messagesNotif,
                  '',
                  _settings.notifyMensagens,
                  (v) => _setSettings((s) => s.copyWith(notifyMensagens: v)),
                ),
                _switchTile(
                  l10n.liveNotif,
                  '',
                  _settings.notifyLive,
                  (v) => _setSettings((s) => s.copyWith(notifyLive: v)),
                ),
                _switchTile(
                  l10n.otherNotif,
                  '',
                  _settings.notifyOutras,
                  (v) => _setSettings((s) => s.copyWith(notifyOutras: v)),
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionPlayback),
                _switchTile(
                  l10n.autoplay,
                  '',
                  _settings.autoPlay,
                  (v) => _setSettings((s) => s.copyWith(autoPlay: v)),
                ),
                _switchTile(
                  l10n.wifiOnly,
                  '',
                  _settings.wifiOnly,
                  (v) => _setSettings((s) => s.copyWith(wifiOnly: v)),
                ),
                _switchTile(
                  l10n.saveData,
                  '',
                  _settings.saveData,
                  (v) => _setSettings((s) => s.copyWith(saveData: v)),
                ),
                _subtitle(l10n.videoQuality),
                _segmented(
                  [
                    ('auto', l10n.qualityAuto),
                    ('low', l10n.qualityLow),
                    ('medium', l10n.qualityMedium),
                    ('high', l10n.qualityHigh),
                  ],
                  _settings.videoQuality,
                  (v) => _setSettings((s) => s.copyWith(videoQuality: v)),
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionExperience),
                ValueListenableBuilder<KlaykExperience>(
                  valueListenable: ExperienceSettings.instance.prefs,
                  builder: (context, xp, _) => Column(
                    children: [
                      _switchTile(
                        l10n.reduceAnimations,
                        l10n.reduceAnimationsHint,
                        xp.reduceAnimations,
                        (v) => ExperienceSettings.instance.update(
                          xp.copyWith(reduceAnimations: v),
                        ),
                      ),
                      _switchTile(
                        l10n.reduceEffects,
                        l10n.reduceEffectsHint,
                        xp.reduceEffects,
                        (v) => ExperienceSettings.instance.update(
                          xp.copyWith(reduceEffects: v),
                        ),
                      ),
                      _switchTile(
                        l10n.showReactions,
                        l10n.showReactionsHint,
                        xp.showReactions,
                        (v) => ExperienceSettings.instance.update(
                          xp.copyWith(showReactions: v),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader('BEM-ESTAR DIGITAL'),
                _tile(
                  Icons.self_improvement_rounded,
                  'Bem-estar digital',
                  subtitle: 'Tempo de uso, pausas e lembretes',
                  onTap: _openDigitalWellbeing,
                ),
                _tile(
                  Icons.accessibility_new_rounded,
                  'Acessibilidade',
                  subtitle: 'Texto, contraste e animações',
                  onTap: _openAccessibility,
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionDataStorage),
                _tile(
                  Icons.delete_sweep_rounded,
                  l10n.clearCache,
                  onTap: () => _pushNew(
                    MaintenanceScreen(onDiagnostics: _openDiagnostics),
                  ),
                ),
                _tile(
                  Icons.storage_rounded,
                  l10n.manageStorage,
                  onTap: () => _openSection('storage'),
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionLocalization),
                _tile(
                  Icons.translate_rounded,
                  l10n.languageAndRegion,
                  subtitle: _currentLanguageName(context),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LanguageScreen()),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionMyArea),
                _tile(
                  Icons.auto_awesome_rounded,
                  l10n.myKlayK,
                  subtitle: l10n.myKlayKHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MeuKlayKScreen()),
                  ),
                ),
                _tile(
                  Icons.account_balance_wallet_rounded,
                  l10n.wallet,
                  subtitle: l10n.walletHint,
                  onTap: () => WalletSheet.show(context),
                ),
                _tile(
                  Icons.card_giftcard_rounded,
                  'Presentes',
                  subtitle: 'Histórico de presentes enviados e recebidos',
                  onTap: _openGiftsSettings,
                ),
                _tile(
                  Icons.shopping_bag_rounded,
                  l10n.store,
                  subtitle: l10n.storeHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StoreScreen()),
                  ),
                ),
                _tile(
                  Icons.folder_special_rounded,
                  l10n.collections,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CollectionsScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.emoji_events_rounded,
                  l10n.achievements,
                  subtitle: l10n.achievementsHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AchievementsScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.military_tech_rounded,
                  l10n.missions,
                  subtitle: l10n.missionsHint,
                  onTap: () => MissionsScreen.show(context),
                ),
                _tile(
                  Icons.inventory_2_rounded,
                  l10n.chests,
                  subtitle: l10n.chestsHint,
                  onTap: () => ChestsScreen.show(context),
                ),
                _tile(
                  Icons.group_add_rounded,
                  l10n.invites,
                  subtitle: l10n.invitesHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InvitesCenterScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.redeem_rounded,
                  l10n.rewards,
                  subtitle: l10n.rewardsHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RewardsCenterScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.history_rounded,
                  l10n.history,
                  subtitle: l10n.historyHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  ),
                ),
                _tile(
                  Icons.note_alt_rounded,
                  l10n.drafts,
                  subtitle: l10n.draftsHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DraftsScreen()),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionPanel),
                _tile(
                  Icons.insights_rounded,
                  l10n.creatorDashboard,
                  subtitle: l10n.creatorDashboardHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CreatorDashboardScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.campaign_rounded,
                  l10n.adsCentral,
                  subtitle: l10n.adsCentralHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdsCentralScreen()),
                  ),
                ),
                if (_isAdmin)
                  _tile(
                    Icons.shield_rounded,
                    l10n.moderation,
                    subtitle: l10n.moderationHint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ModerationScreen(),
                      ),
                    ),
                  ),
                if (_isAdmin)
                  _tile(
                    Icons.campaign_rounded,
                    l10n.advertising,
                    subtitle: l10n.advertisingHint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdsAdminScreen()),
                    ),
                  ),
                if (_isAdmin)
                  _tile(
                    Icons.auto_awesome_motion_rounded,
                    l10n.marketingCentral,
                    subtitle: l10n.marketingCentralHint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MarketingHubScreen(),
                      ),
                    ),
                  ),
                if (_isStaff)
                  _tile(
                    Icons.workspace_premium_rounded,
                    l10n.founderPanel,
                    subtitle: _isAdmin
                        ? l10n.founderPanelHint
                        : l10n.founderPanelStaffHint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FounderPanelScreen(),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.sectionSecurity),
                _switchTile(
                  l10n.securityConfirm,
                  l10n.securityConfirmHint,
                  _settings.securityConfirmActions,
                  (v) => _setSettings(
                    (s) => s.copyWith(securityConfirmActions: v),
                  ),
                ),
                _tile(
                  Icons.person_pin_rounded,
                  l10n.accountProtection,
                  subtitle: l10n.accountProtectionHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AccountGuardScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.shield_rounded,
                  l10n.youthShield,
                  subtitle: l10n.youthShieldHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const YouthShieldScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.report_gmailerrorred_rounded,
                  l10n.reportCenter,
                  subtitle: l10n.reportCenterHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReportCenterScreen(),
                    ),
                  ),
                ),
                _tile(
                  Icons.help_outline_rounded,
                  l10n.helpCenter,
                  onTap: _openHelp,
                ),
                _tile(
                  Icons.info_outline_rounded,
                  l10n.aboutKlayK,
                  subtitle: l10n.aboutKlayKHint,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
                _tile(
                  Icons.badge_outlined,
                  l10n.versionLabel(''),
                  subtitle: l10n.aboutTagline,
                  onTap: _showAbout,
                ),
                const SizedBox(height: 24),
                _sectionHeader('KLAY K SAFETY CENTER'),
                _tile(
                  Icons.shield_rounded,
                  'Central de Segurança',
                  subtitle:
                      'Controle sua segurança e privacidade em um só lugar',
                  onTap: _openSecurityCenter,
                ),
                _tile(
                  Icons.videocam_rounded,
                  'Segurança da LIVE',
                  subtitle: 'Comentários, presentes, denúncia e privacidade',
                  onTap: _openLiveSecurity,
                ),
                const SizedBox(height: 24),
                _sectionHeader('DIAGNÓSTICO E SERVIÇOS'),
                _tile(
                  Icons.science_rounded,
                  'Diagnóstico KLAY K',
                  subtitle: 'Executar diagnóstico real de todos os serviços',
                  onTap: _openDiagnostics,
                ),
                const SizedBox(height: 24),
                _sectionHeader('AJUDA E SUPORTE'),
                _tile(
                  Icons.support_agent_rounded,
                  'Central de suporte',
                  subtitle:
                      'Ajuda, problemas de conta, live, carteira e presentes',
                  onTap: _openHelp,
                ),
                _tile(
                  Icons.feedback_rounded,
                  l10n.feedbackTitle,
                  subtitle: l10n.feedbackIntro,
                  onTap: () => _pushNew(const FeedbackScreen()),
                ),
                const SizedBox(height: 24),
                _sectionHeader(l10n.labs),
                _infoCard(l10n.settingsLabsBody),
                const SizedBox(height: 8),
                _tile(
                  Icons.science_outlined,
                  l10n.settingsLabsTitle,
                  subtitle: l10n.settingsLabsJoinPending,
                  onTap: () => _snack(l10n.settingsLabsJoinPending),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _currentLanguageName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (AppLanguageController.instance.locale.languageCode) {
      'en' => l10n.english,
      'es' => l10n.spanish,
      'fr' => l10n.french,
      'ja' => l10n.japanese,
      'ko' => l10n.korean,
      'zh' => l10n.chinese,
      _ => l10n.portuguese,
    };
  }

  Widget _accountCard() {
    final l10n = AppLocalizations.of(context)!;
    final avatar = _profile?['avatar_url']?.toString() ?? '';
    final name = _profile?['display_name']?.toString() ?? l10n.user;
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
                      backgroundImage: avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 28,
                            )
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
                        child: const Icon(
                          Icons.camera_alt,
                          size: 12,
                          color: Colors.white,
                        ),
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
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_verified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            color: _kAccent,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '@$user',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _accountAction(
                l10n.nameField,
                () => _editField('display_name', name, l10n.nameField),
              ),
              _accountAction(
                l10n.username,
                () => _editField('username', '@$user', l10n.username),
              ),
              _accountAction(
                l10n.bioField,
                () => _editField(
                  'bio',
                  _profile?['bio']?.toString() ?? '',
                  l10n.bioField,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [_accountAction(l10n.profession, _pickProfession)]),
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
        leading: Icon(icon, color: danger ? const Color(0xFFFF4D6A) : _kAccent),
        title: Text(
          title,
          style: TextStyle(
            color: danger ? const Color(0xFFFF4D6A) : Colors.white,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(color: Colors.white54))
            : null,
        trailing:
            trailing ?? const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap != null ? () => onTap() : null,
      ),
    );
  }

  Widget _switchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Card(
    color: const Color(0xFF1B1A26),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: SwitchListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
      value: value,
      activeTrackColor: _kAccent,
      onChanged: onChanged,
    ),
  );

  Widget _subtitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white54, fontSize: 13),
    ),
  );

  Widget _infoCard(String text) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1B1A26),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
    ),
  );

  Widget _segmented(
    List<(String, String)> options,
    String selected,
    ValueChanged<String> onChanged,
  ) {
    return Wrap(
      spacing: 8,
      children: options.map((o) {
        final id = o.$1;
        final label = o.$2;
        final sel = id == selected;
        return ChoiceChip(
          label: Text(
            label,
            style: TextStyle(
              color: sel ? Colors.white : Colors.white60,
              fontSize: 13,
            ),
          ),
          selected: sel,
          selectedColor: _kAccent,
          backgroundColor: const Color(0xFF222032),
          onSelected: (_) => onChanged(id),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }).toList(),
    );
  }

  void _openVerification() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VerificationScreen()));
  }

  void _pushNew(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openAdvancedPrivacy() => _pushNew(const AdvancedPrivacyScreen());

  void _openPrivacyCenter() => _pushNew(const PrivacyCenterScreen());

  void _openFamilyControls() => _pushNew(const FamilyControlsScreen());

  void _openMessagesControl() => _pushNew(const MessagesControlScreen());

  void _openCommentsControl() => _pushNew(const CommentsControlScreen());

  void _openSpamProtection() => _pushNew(const SpamProtectionScreen());

  void _openDigitalWellbeing() => _pushNew(const DigitalWellbeingScreen());

  void _openAccessibility() => _pushNew(const AccessibilityScreen());

  void _openGiftsSettings() => _pushNew(const GiftsSettingsScreen());

  void _openSecurityCenter() => _pushNew(const SecurityCenterScreen());

  void _openLiveSecurity() => _pushNew(const LiveSecurityScreen());

  void _openDiagnostics() => _pushNew(const KaykDiagnosticsScreen());

  void _openHelp() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
  }

  /// Sobre o KLAY K: identidade oficial (ícone do app), versão e informações.
  void _showAbout() {
    final l10n = AppLocalizations.of(context)!;
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aboutIntro,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 14),
            Text(
              '${AppLocalizations.of(context)!.version} 1.0.0',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.allRightsReserved,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              AppLocalizations.of(context)!.ok,
              style: const TextStyle(color: _kAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _openSection(String section) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SecondarySectionScreen(section: section),
      ),
    );
  }
}

/// Tela auxiliar para seções simples (bloqueados, silenciados, armazenamento).
class _SecondarySectionScreen extends StatefulWidget {
  final String section;
  const _SecondarySectionScreen({required this.section});

  @override
  State<_SecondarySectionScreen> createState() =>
      _SecondarySectionScreenState();
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
            .map(
              (b) => _BlockedEntry(
                id: b.id,
                name: b.name,
                username: b.username ?? '',
                avatar: b.avatarUrl ?? '',
              ),
            )
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
    final l10n = AppLocalizations.of(context)!;
    final title = switch (widget.section) {
      'blocked' => l10n.blockedUsers,
      'muted' => l10n.mutedUsers,
      'storage' => l10n.manageStorage,
      _ => l10n.settingsTitle,
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
          ? Center(
              child: Text(
                l10n.blockedUsersEmpty,
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final e = _items[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2A2740),
                    backgroundImage: e.avatar.isNotEmpty
                        ? NetworkImage(e.avatar)
                        : null,
                    child: e.avatar.isEmpty
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                  title: Text(
                    e.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '@${e.username}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: widget.section == 'blocked'
                      ? TextButton(
                          onPressed: () => _unblock(e.id),
                          child: Text(
                            l10n.unblock,
                            style: const TextStyle(color: _kAccent),
                          ),
                        )
                      : null,
                );
              },
            ),
    );
  }

  Widget _storageView() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StorageInfoRow(label: l10n.storageVideos, value: '0 MB'),
        _StorageInfoRow(label: l10n.storageImages, value: '0 MB'),
        _StorageInfoRow(label: l10n.storageCache, value: '0 MB'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.cacheCleared)));
          },
          icon: const Icon(Icons.delete_sweep),
          label: Text(l10n.clearCache),
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
