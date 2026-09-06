// E2E dos FLUXOS RECOMPENSÁVEIS contra o Supabase REAL (projeto oysyuialaelzcxxkfdsl).
//
// Só roda com `KLAY_E2E=true` (opt-in explícito, rede real); do contrário é
// pulado — mesma regra dos outros E2E do repositório.
//
// Cobre as migrations novas que nenhum teste do repo exercitava:
//   * CONVITES (20260831130000_invites.sql):
//       - validate_invite_code (conferência pública ANTES do cadastro);
//       - redeem_invite: registra convidado real 'validated' e é idempotente;
//       - claim_invite_rewards: paid 5 cristais → ledger kind='reward'
//         currency='crystals' ref_type='invite' com balance_after real;
//       - idempotência (claim repetido = 0).
//   * ECONOMIA (20260831125000_economy_complete.sql):
//       - my_wallet reflete o crédito; credit_transactions fecha o saldo.
//   * JOGOS (20260831150000_games.sql):
//       - game_start_session (jogo 'active', sessão real);
//       - game_submit_score: melhoria paga o patamar das rules,
//         piora/empate NÃO paga, re-submit é negado, score>max_score negado;
//       - detector de divergência: quiz no patamar alto (regra do topo).
//
// As contas "convidado"/"jogador" são sessões ANÔNIMAS reais do Supabase
// (identidade real em auth.users + trigger handle_new_user), criadas no
// próprio teste — o cadastro por e-mail exige confirmação (mailer_autoconfirm
// = false), então não é automatizável; o caminho do backend é o mesmo: um
// usuário authenticated chamando as mesmas RPCs que o app chama.
//
//   KLAY_E2E=true flutter test test/e2e_rewards_flow_test.dart --timeout 300s
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/services/supabase_service.dart';

const _adminEmail = 'founder.admin+test@klayk.app';
const _password = 'KlayKTest#2026!';

// Patamar de cristais esperado para um score, seguindo a regra INTENCIONAL
// do backend: o patamar com maior min_score satisfeito (não o último do array).
int _tierReward(List<dynamic> tiers, int score) {
  var best = 0;
  for (final t in tiers) {
    final m = Map<String, dynamic>.from(t as Map);
    final minScore = (m['min_score'] as num).toInt();
    if (score >= minScore) {
      best = (m['crystals'] as num).toInt() > best
          ? (m['crystals'] as num).toInt()
          : best;
    }
  }
  return best;
}

Future<String> _rpcLabel(Future<dynamic> Function() call) async {
  try {
    await call();
    return 'no-error';
  } catch (e) {
    return e.toString();
  }
}

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

  Future<Map<String, dynamic>> wallet(SupabaseService db) async {
    final r = await db.client.rpc('my_wallet');
    return Map<String, dynamic>.from(r as Map);
  }

  int crystalsOf(Map<String, dynamic> w) => (w['crystals'] as num).toInt();

  Future<List<Map<String, dynamic>>> ledger(
    SupabaseService db, {
    int limit = 10,
  }) async {
    final res = await db.client
        .from('credit_transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  group('🧪 E2E RECOMPENSAS (convites + economia + jogos) (KLAY_E2E)', () {
    test('(setup) inicializa Supabase na zona real', () async {
      SharedPreferences.setMockInitialValues(const {});
      await SupabaseService.instance.ensureReady();
      expect(SupabaseService.instance.isConfigured, isTrue,
          reason: 'E2E exige Supabase configurado (rede real habilitada).');
    }, skip: skipUnlessE2E());

    test('convites: validate_invite_code resolve o convidante PRÉ-cadastro',
        () async {
      final db = SupabaseService.instance;

      await db.signInWithEmail(_adminEmail, _password);
      final adminId = db.currentUser!.id;
      final code = (await db.client.rpc('invite_summary'))
          ['code']
          .toString()
          .toUpperCase();
      await db.signOut();

      // Sem sessão (como um visitante antes de se cadastrar).
      final v = await db.client.rpc('validate_invite_code', params: {
        'p_code': code,
      });
      expect(v, isNotNull, reason: 'código válido resolve o convidante');
      final m = Map<String, dynamic>.from(v as Map);
      expect(m['code'].toString().toUpperCase(), code);
      expect(m['inviter_id'].toString(), adminId,
          reason: 'validate_invite_code devolve o id REAL do dono do código');
      expect(m['display_name'], isNotEmpty);

      // Código inexistente → null (não vaza nenhum dado).
      final bad = await db.client.rpc('validate_invite_code', params: {
        'p_code': 'ZZZZZZ',
      });
      expect(bad, isNull);
    }, skip: skipUnlessE2E());

    test('convites: redeem idempotente + claim paga 5 cristais no ledger',
        () async {
      final db = SupabaseService.instance;

      await db.signInWithEmail(_adminEmail, _password);
      final code = (await db.client.rpc('invite_summary'))
          ['code']
          .toString()
          .toUpperCase();
      final wBefore = await wallet(db);
      await db.signOut();

      // "Convidado": identidade REAL nova (sessão anônima do Supabase).
      final anon = await db.ensureAnonymous();
      final anonId = anon.id;
      final redeem = await db.client.rpc('redeem_invite', params: {'p_code': code});
      expect(redeem, isNotNull,
          reason: 'redeem_invite respondeu o resumo do convidado');
      // Idempotente: um segundo redeem NÃO duplica a linha.
      await db.client.rpc('redeem_invite', params: {'p_code': code});
      await db.signOut();

      // De volta como admin (dono do convite): a linha existe e está validated.
      await db.signInWithEmail(_adminEmail, _password);
      final invites = await db.client
          .from('invites')
          .select('id,status,invited_user_id')
          .eq('invite_code', code)
          .eq('invited_user_id', anonId);
      final rows = (invites as List).whereType<Map>().toList();
      expect(rows.length, 1, reason: 'redeem idempotente criou UMA linha');
      final inviteRow = Map<String, dynamic>.from(rows.first);
      final inviteId = inviteRow['id'].toString();
      expect(inviteRow['status'], 'validated',
          reason: 'convidado real já nasce validated (pronto para claim)');

      // Claim: o backend decide o quanto paga (5 cristais/convidado).
      final claim = Map<String, dynamic>.from(
        await db.client.rpc('claim_invite_rewards') as Map,
      );
      expect((claim['claimed'] as num).toInt(), greaterThanOrEqualTo(1),
          reason: 'o convite novo está entre os reivindicados');
      final paid = (claim['crystals'] as num).toInt();

      // Saldo: subiu EXATAMENTE o que o backend reportou.
      final wAfter = await wallet(db);
      expect(crystalsOf(wAfter), crystalsOf(wBefore) + paid,
          reason: 'my_wallet refletiu o crédito do claim');

      // Ledger: transação daquele convite, com saldo de verdade.
      final tx = await ledger(db);
      Map<String, dynamic>? inviteTx;
      for (final t in tx) {
        if (t['ref_type'] == 'invite' && t['ref_id'] == inviteId) {
          inviteTx = t;
        }
      }
      expect(inviteTx, isNotNull,
          reason: 'ledger registrou a transação daquele convite');
      expect((inviteTx!['delta'] as num).toInt(), 5,
          reason: 'convite vale 5 cristais (delta do ledger)');
      expect(inviteTx['currency'], 'crystals');
      expect(inviteTx['kind'], 'reward');
      expect((inviteTx['balance_after'] as num).toInt(), crystalsOf(wAfter),
          reason: 'balance_after do ledger fecha com o saldo real');

      // A linha do convite foi travada: validated -> rewarded.
      final after = await db.client
          .from('invites')
          .select('status')
          .eq('invite_code', code)
          .eq('invited_user_id', anonId);
      expect((after as List).first['status'], 'rewarded',
          reason: 'claim marca o convite como rewarded');

      // Idempotência do claim: nada a pagar de novo (0 cristais).
      final wIdem = await wallet(db);
      final claim2 = Map<String, dynamic>.from(
        await db.client.rpc('claim_invite_rewards') as Map,
      );
      expect((claim2['claimed'] as num).toInt(), 0,
          reason: 'claim repetido não reinvidica nada');
      expect(crystalsOf(await wallet(db)), crystalsOf(wIdem),
          reason: 'claim repetido não credita de novo');

      await db.signOut();
    }, skip: skipUnlessE2E());

    test('jogos: sessão real, melhoria paga patamar, piora/empate não paga',
        () async {
      final db = SupabaseService.instance;

      await db.ensureAnonymous(); // jogador REAL novo, sem recordes
      final baseline = crystalsOf(await wallet(db));

      final velha = Map<String, dynamic>.from(await db.client
          .from('games')
          .select('id,status,rules,max_score')
          .eq('id', 'velha')
          .single() as Map);
      expect(velha['status'], 'active');
      final maxScore = (velha['max_score'] as num).toInt();
      final tiers = ((velha['rules'] as Map? ?? {})['rewards'] as List?) ?? [];
      final expected10 = _tierReward(tiers, 10);
      expect(expected10, 3,
          reason: 'seed da velha: patamar 10 → 3 cristais');

      // 1) MELHOROU (sem recorde antes): paga o patamar.
      final s1 = (await db.client
              .rpc('game_start_session', params: {'p_game_id': 'velha'}))
          .toString();
      final r1 = Map<String, dynamic>.from(await db.client.rpc(
              'game_submit_score',
              params: {
                'p_session_id': s1,
                'p_score': 10,
                'p_duration_seconds': 5,
              })
          as Map);
      expect(r1['improved'], isTrue);
      expect((r1['best_score'] as num).toInt(), 10);
      expect((r1['reward'] as num).toInt(), expected10,
          reason: 'primeira vitória credita 3 cristais');
      expect(crystalsOf(await wallet(db)), baseline + expected10,
          reason: 'my_wallet subiu com a recompensa do jogo');

      Map<String, dynamic>? gameTx;
      for (final t in await ledger(db)) {
        if (t['ref_type'] == 'game:velha' && t['ref_id'] == s1) {
          gameTx = t;
        }
      }
      expect(gameTx, isNotNull, reason: 'ledger tem a recompensa da sessão');
      expect((gameTx!['delta'] as num).toInt(), expected10);
      expect(gameTx['currency'], 'crystals');
      expect(gameTx['kind'], 'reward');
      expect((gameTx['balance_after'] as num).toInt(), baseline + expected10);

      // 2) PIOROU (abaixo do recorde): não melhora → não paga.
      final s2 = (await db.client
              .rpc('game_start_session', params: {'p_game_id': 'velha'}))
          .toString();
      final r2 = Map<String, dynamic>.from(await db.client.rpc(
              'game_submit_score',
              params: {
                'p_session_id': s2,
                'p_score': 5,
                'p_duration_seconds': 3,
              })
          as Map);
      expect(r2['improved'], isFalse,
          reason: 'score menor que o recorde não melhora');
      expect((r2['reward'] as num).toInt(), 0);
      expect((r2['best_score'] as num).toInt(), 10,
          reason: 'recorde permanece 10');
      expect(crystalsOf(await wallet(db)), baseline + expected10,
          reason: 'não paga nada quando o usuário não melhora');

      // 3) EMPATE (score == recorde): também não melhora → não paga.
      final s3 = (await db.client
              .rpc('game_start_session', params: {'p_game_id': 'velha'}))
          .toString();
      final r3 = Map<String, dynamic>.from(await db.client.rpc(
              'game_submit_score',
              params: {
                'p_session_id': s3,
                'p_score': 10,
                'p_duration_seconds': 4,
              })
          as Map);
      expect(r3['improved'], isFalse,
          reason: 'empatar o recorde não é melhoria (exige >)');
      expect((r3['reward'] as num).toInt(), 0);
      expect(crystalsOf(await wallet(db)), baseline + expected10,
          reason: 'empate não paga');

      // 6) O RECORDE guardado em game_scores jamais piora: após uma jogada
      //    pior e um empate, a linha do usuário continua com o topo (10).
      final me = db.currentUser!.id;
      final stored = Map<String, dynamic>.from(await db.client
          .from('game_scores')
          .select('score')
          .eq('user_id', me)
          .eq('game_id', 'velha')
          .single() as Map);
      expect((stored['score'] as num).toInt(), 10,
          reason: 'game_scores guarda o RECORDE (score pior não apaga o topo)');

      // 4) Re-submit da mesma sessão → backend nega.
      final resub = await _rpcLabel(() => db.client.rpc(
            'game_submit_score',
            params: {
              'p_session_id': s3,
              'p_score': 10,
            },
          ));
      expect(resub, contains('session_already_submitted'),
          reason: 'uma sessão só aceita UMA submissão');

      // 5) Score acima do max_score → backend nega (anti-speedhack).
      final overflow = await _rpcLabel(() async {
        final s = (await db.client
                .rpc('game_start_session', params: {'p_game_id': 'velha'}))
            .toString();
        await db.client.rpc('game_submit_score', params: {
          'p_session_id': s,
          'p_score': maxScore + 1,
          'p_duration_seconds': 5,
        });
      });
      expect(overflow, contains('invalid_score'),
          reason: 'score > max_score (${maxScore + 1}) é negado');

      await db.signOut();
    }, skip: skipUnlessE2E());

    test('jogos: quiz no topo do patamar (detector de divergência do algoritmo)',
        () async {
      final db = SupabaseService.instance;

      await db.ensureAnonymous();
      final quiz = Map<String, dynamic>.from(await db.client
          .from('games')
          .select('id,rules,max_score')
          .eq('id', 'quiz')
          .single() as Map);
      final tiers = ((quiz['rules'] as Map? ?? {})['rewards'] as List?) ?? [];
      expect(tiers.length, greaterThanOrEqualTo(2),
          reason: 'seed do quiz tem 2 patamares (6→3 e 4→2)');

      final intended = _tierReward(tiers, 6);
      final sq = (await db.client
              .rpc('game_start_session', params: {'p_game_id': 'quiz'}))
          .toString();
      final rq = Map<String, dynamic>.from(await db.client.rpc(
              'game_submit_score',
              params: {
                'p_session_id': sq,
                'p_score': 6,
                'p_duration_seconds': 8,
              })
          as Map);
      expect(rq['improved'], isTrue);
      expect((rq['best_score'] as num).toInt(), 6);
      expect((rq['reward'] as num).toInt(), intended,
          reason: 'patamar libera o TOPO satisfeito (6/6 deve pagar o de maior '
              'min_score; se vier o de baixo, o backend ainda itera o array '
              'decrescente e a migration do repo está divergente do aplicado)');

      await db.signOut();
    }, skip: skipUnlessE2E());
  });
}