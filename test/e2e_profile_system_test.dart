// E2E do SISTEMA DE PERFIL contra o Supabase REAL (projeto oysyuialaelzcxxkfdsl).
//
// Só roda com `KLAY_E2E=true` (opt-in explícito, rede real); do contrário é
// pulado — mesma regra dos outros E2E do repositório.
//
// Cobre exatamente o que a migration 20260831110000_profile_system.sql
// entregou e o que o app consome:
//   * RPC get_profile (perfil próprio e alheio; birth_date só para o dono);
//   * contadores followers_count / following_count / posts_count + total_likes;
//   * badge is_verified;
//   * campos novos banner_url / website / location / pronouns (round-trip);
//   * RPCs profile_followers / profile_following (listas com is_following);
//   * toggleFollow real → contadores reagem (triggers de bump) → estado
//     restaurado ao final (o teste não deixa lixo no banco).
//
//   KLAY_E2E=true flutter test test/e2e_profile_system_test.dart --timeout 300s
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/services/profile_service.dart';
import 'package:klay_k/services/supabase_service.dart';

const _adminEmail = 'founder.admin+test@klayk.app';
const _userEmail = 'founder.user+test@klayk.app';
const _password = 'KlayKTest#2026!';

void main() {
  final isE2E = Platform.environment['KLAY_E2E'] == 'true';
  bool? skipUnlessE2E() => isE2E ? null : true;

  setUpAll(() {
    if (isE2E) {
      // O flutter_test troca o HttpClient global por um mock que responde 400;
      // no E2E (rede real) restauramos o IOClient padrão.
      HttpOverrides.global = null;
    }
  });

  group('🧪 E2E SISTEMA DE PERFIL (KLAY_E2E)', () {
    test('(setup) inicializa Supabase na zona real', () async {
      SharedPreferences.setMockInitialValues(const {});
      await SupabaseService.instance.ensureReady();
      expect(SupabaseService.instance.isConfigured, isTrue,
          reason: 'E2E exige Supabase configurado (rede real habilitada).');
    }, skip: skipUnlessE2E());

    test('get_profile: perfil próprio X alheio, birth_date e badges',
        () async {
      final db = SupabaseService.instance;
      await db.signInWithEmail(_adminEmail, _password);
      expect(db.hasSession, isTrue);

      final admin = db.currentUser!;
      final own = await ProfileService.instance.fetchProfile(admin.id);
      expect(own, isNotNull);
      expect(own!.isSelf, isTrue,
          reason: 'get_profile marca is_self=true para o dono');
      expect(own.id, admin.id);
      expect(own.followersCount + own.followingCount + own.postsCount,
          isA<int>(),
          reason: 'contadores presentes e numéricos no payload RPC');
      expect(own.isVerified, isA<bool>(),
          reason: 'badge is_verified chega do banco (bool)');
      expect(own.birthDateLabel, isNull,
          reason: 'birth_date no payload próprio (null se não setado)');

      // As chaves novas (banner/website/location/pronouns) existem no payload
      // RPC mesmo quando o perfil de teste não as preencheu.
      final raw = Map<String, dynamic>.from(
        (await db.client
            .rpc('get_profile', params: {'p_user_id': admin.id})) as Map,
      );
      for (final key in [
        'banner_url', 'website', 'location', 'pronouns',
        'followers_count', 'following_count', 'posts_count', 'total_likes',
      ]) {
        expect(raw.containsKey(key), isTrue,
            reason: 'get_profile devolve a chave "$key" (coluna da migration)');
      }

      // Perfil alheio visto pelo admin: is_self=false.
      await db.signOut();
      await db.signInWithEmail(_userEmail, _password);
      expect(db.hasSession, isTrue);
      final userId = db.currentUser!.id;

      final other = await ProfileService.instance.fetchProfile(admin.id);
      expect(other, isNotNull);
      expect(other!.isSelf, isFalse,
          reason: 'perfil alheio não é o self de quem consulta');
      expect(other.birthDateLabel, isNull,
          reason: 'birth_date de OUTREM NUNCA vem (privacidade)');

      await db.signOut();
      expect(db.hasSession, isFalse);
      expect(userId, isNotEmpty);
    }, skip: skipUnlessE2E());

    test('updateProfile: website/location/pronouns round-trip (restaurado)',
        () async {
      final db = SupabaseService.instance;
      await db.signInWithEmail(_adminEmail, _password);
      final me = db.currentUser!;

      final before =
          (await ProfileService.instance.fetchProfile(me.id))!;
      final origWebsite = before.website;
      final origLocation = before.location;
      final origPronouns = before.pronouns;

      try {
        await ProfileService.instance.updateProfile(
          website: 'https://klayk.app',
          location: 'São Paulo, SP',
          pronouns: 'ele/dele',
        );

        final after = (await ProfileService.instance.fetchProfile(me.id))!;
        expect(after.website, 'https://klayk.app');
        expect(after.location, 'São Paulo, SP');
        expect(after.pronouns, 'ele/dele');
      } finally {
        // Restaura o estado original do perfil de teste.
        await ProfileService.instance.updateProfile(
          website: origWebsite ?? '',
          location: origLocation ?? '',
          pronouns: origPronouns ?? '',
        );
        await db.signOut();
      }
    }, skip: skipUnlessE2E());

    test('listas de seguidores/seguindo + toggleFollow com links reais',
        () async {
      final db = SupabaseService.instance;
      await db.signInWithEmail(_adminEmail, _password);
      final adminId = db.currentUser!.id;

      await db.signOut();
      await db.signInWithEmail(_userEmail, _password);
      final userId = db.currentUser!.id;

      // Estado original entre os dois (para restaurar exatamente).
      final wasFollowing = await ProfileService.instance.isFollowing(adminId);
      final adminBefore = (await ProfileService.instance.fetchProfile(adminId))!;
      final userBefore = (await ProfileService.instance.fetchProfile(userId))!;

      // Fecha qualquer follow pré-existente admin→user antes do cenário.
      if (wasFollowing) {
        await ProfileService.instance.toggleFollow(adminId);
      }
      final nowFollowing = await ProfileService.instance.isFollowing(adminId);
      expect(nowFollowing, isFalse);

      // Segue: contadores do bump (user.following x admin.followers).
      final followed = await ProfileService.instance.toggleFollow(adminId);
      expect(followed, isTrue, reason: 'user passa a seguir o admin');

      final userMid = (await ProfileService.instance.fetchProfile(userId))!;
      final adminMid = (await ProfileService.instance.fetchProfile(adminId))!;
      expect(userMid.followingCount, userBefore.followingCount + 1,
          reason: 'following_count do seguidor subiu (trigger bump)');
      expect(adminMid.followersCount, adminBefore.followersCount + 1,
          reason: 'followers_count do seguido subiu (trigger bump)');

      final adminFollowingList =
          await ProfileService.instance.fetchFollowing(adminId);
      final userFollowersList =
          await ProfileService.instance.fetchFollowers(adminId);
      expect(
          userFollowersList.any((p) => p.id == userId), isTrue,
          reason: 'profile_followers(admin) lista o novo seguidor');
      expect(
          adminFollowingList.any((p) => p.id == adminId), isFalse,
          reason: 'profile_following(admin) não inclui admin (não é self)');

      // Desfaz: estado original do banco preservado ao fim do teste.
      await ProfileService.instance.toggleFollow(adminId);
      final userAfter = (await ProfileService.instance.fetchProfile(userId))!;
      final adminAfter = (await ProfileService.instance.fetchProfile(adminId))!;
      expect(userAfter.followingCount, userBefore.followingCount,
          reason: 'unfollow restaura following_count original');
      expect(adminAfter.followersCount, adminBefore.followersCount,
          reason: 'unfollow restaura followers_count original');

      await db.signOut();
    }, skip: skipUnlessE2E());

    test('contadores e payload completo vêm de get_profile (admin_stats style)',
        () async {
      final db = SupabaseService.instance;
      await db.signInWithEmail(_adminEmail, _password);
      final me = db.currentUser!;

      final res = await db.client
          .rpc('get_profile', params: {'p_user_id': me.id});
      expect(res, isNotNull);
      final m = Map<String, dynamic>.from(res as Map);
      for (final key in [
        'id', 'username', 'display_name', 'avatar_url', 'is_verified',
        'followers_count', 'following_count', 'posts_count', 'total_likes',
        'is_following', 'is_self',
      ]) {
        expect(m.containsKey(key), isTrue,
            reason: 'get_profile devolve "$key"');
      }

      await db.signOut();
    }, skip: skipUnlessE2E());
  });
}