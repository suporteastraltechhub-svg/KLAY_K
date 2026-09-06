import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/main.dart';
import 'package:klay_k/models/klayk_live_models.dart';
import 'package:klay_k/screens/start_live_screen.dart';
import 'package:klay_k/services/app_config.dart';
import 'package:klay_k/services/live_kit_service.dart';
import 'package:klay_k/services/supabase_service.dart';

void main() {
  group('AppConfig', () {
    test('credenciais públicas padrão configuram o Supabase', () {
      expect(AppConfig.isSupabaseConfigured, isTrue);
      expect(
        AppConfig.supabaseUrl,
        'https://oysyuialaelzcxxkfdsl.supabase.co',
      );
      expect(AppConfig.supabaseKey, startsWith('sb_publishable_'));
      expect(AppConfig.projectRef.isNotEmpty, isTrue);
    });
  });

  group('KAppIdentity', () {
    test('identidade padrão do KLAY K', () {
      expect(kAppIdentity.displayName, 'KLAY K OFICIAL');
      expect(kAppIdentity.username, '@klaykoficial');
    });
  });

  group('RealLive.fromJson', () {
    test('converte linha com join de profiles', () {
      final live = RealLive.fromJson({
        'id': 'live-1',
        'room_name': 'room-klay-k-12345',
        'streamer_id': 'u-1',
        'title': 'Bora jogar!',
        'description': 'Vim de trás',
        'category': 'Jogos',
        'hashtags': ['klayk', 'raiz'],
        'privacy': 'public',
        'status': 'live',
        'started_at': '2026-08-27T12:00:00.000Z',
        'viewer_count': 7,
        'profiles': {
          'display_name': 'SEM NOÇÃO TV OFICIAL',
          'username': 'semnocaotv',
          'avatar_url': 'https://i.pravatar.cc/150?img=12',
        },
      });

      expect(live.id, 'live-1');
      expect(live.roomName, 'room-klay-k-12345');
      expect(live.category, 'Jogos');
      expect(live.hashtags, ['klayk', 'raiz']);
      expect(live.streamerDisplayName, 'SEM NOÇÃO TV OFICIAL');
      expect(live.streamerUsername, 'semnocaotv');
      expect(live.viewerCount, 7);
      expect(live.ended, isFalse);
    });

    test('tolera dados parciais', () {
      final live = RealLive.fromJson({
        'id': 'x',
        'room_name': 'r',
        'streamer_id': 'u',
        'started_at': '',
      });
      expect(live.title, 'Live ao vivo');
      expect(live.hashtags, isEmpty);
      expect(live.streamerDisplayName, isNull);
    });
  });

  group('LiveChatMessage.fromJson', () {
    test('marca mine quando user_id bate com myId', () {
      final msg = LiveChatMessage.fromJson({
        'id': 'm1',
        'live_id': 'live-1',
        'user_id': 'u-42',
        'message': 'olá',
        'created_at': '2026-08-27T12:05:00.000Z',
        'sender': {'display_name': 'Zeca', 'username': 'zeca'},
      }, myId: 'u-42');

      expect(msg.mine, isTrue);
      expect(msg.senderDisplayName, 'Zeca');
    });

    test('sem sender join cai no username da linha', () {
      final msg = LiveChatMessage.fromJson({
        'id': 'm2',
        'live_id': 'live-1',
        'user_id': 'u-7',
        'message': 'oi',
        'created_at': '',
        'username': '@anon',
      }, myId: 'u-1');

      expect(msg.mine, isFalse);
      expect(msg.senderDisplayName, '@anon');
    });
  });

  group('GiftCatalog', () {
    test('catálogo tem 8 presentes com id/emoji', () {
      expect(kGiftCatalog.length, 8);
      expect(kGiftCatalog.first.id, 'rosa');
      expect(kGiftCatalog.first.emoji, '🌹');
      final ids = kGiftCatalog.map((g) => g.id).toSet();
      expect(ids.length, kGiftCatalog.length);
    });
  });

  group('LiveKitCredentials', () {
    test('carrega server_url e participant_token', () {
      const creds = LiveKitCredentials(
        serverUrl: 'wss://example.livekit.cloud',
        participantToken: 'token-abc',
      );
      expect(creds.serverUrl, 'wss://example.livekit.cloud');
      expect(creds.participantToken, 'token-abc');
    });
  });

  group('LiveRole', () {
    test('distingue streamer de espectador', () {
      expect(LiveRole.values, contains(LiveRole.streamer));
      expect(LiveRole.values, contains(LiveRole.viewer));
      expect(LiveRole.streamer, isNot(LiveRole.viewer));
    });
  });

  group('Segurança: nenhum segredo no código', () {
    const dirs = ['lib', 'supabase'];
    const filesToScan = <String>[
      'services/livekit-bot/src',
      'services/livekit-bot/.env.example',
    ];

    test('nenhum valor de LIVEKIT_API_SECRET / service role / JWT no app', () {
      final files = <File>[];
      for (final dir in dirs) {
        final d = Directory(dir);
        if (d.existsSync()) {
          d.listSync(recursive: true).whereType<File>().forEach(files.add);
        }
      }
      for (final rel in filesToScan) {
        final d = Directory(rel);
        if (d.existsSync()) {
          d.listSync(recursive: true).whereType<File>().forEach(files.add);
        }
      }

      final skLive = RegExp(r'sk_live_[A-Za-z0-9_\-/=+]{8,}');
      final jwt = RegExp(r'eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+');
      final secretAssign =
          RegExp(r'(LIVEKIT_API_KEY|LIVEKIT_API_SECRET)\s*=\s*\S+');
      final serviceRole = RegExp(r'SUPABASE_SERVICE_ROLE_KEY\s*=\s*\S+');

      final suspects = <String>[];
      for (final f in files) {
        if (!f.path.endsWith('.dart') && f.path.endsWith('.png')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (skLive.hasMatch(line) ||
              jwt.hasMatch(line) ||
              secretAssign.hasMatch(line) ||
              serviceRole.hasMatch(line)) {
            suspects.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(suspects, isEmpty, reason: 'Encontrado potencial segredo: $suspects');
    });

    test('livekit-token responde apenas server_url + participant_token', () {
      final src = File('supabase/functions/livekit-token/index.ts');
      expect(src.existsSync(), isTrue);
      final code = src.readAsStringSync();
      // A resposta JSON nunca deve expor as chaves da API (elas só existem em
      // Secrets lidos via Deno.env.get).
      expect(code, isNot(contains('"api_secret"')));
      expect(code, isNot(contains('"api_key"')));
      expect(code, isNot(contains('"secret"')));
      expect(code, isNot(contains('sk_live_')));
      expect(code, contains('server_url'));
      expect(code, contains('participant_token'));
    });
  });

  group('Menu de publicação (+)', () {
    testWidgets('abre com Vídeo/Live/Áudio/Amigos e Live navega para StartLiveScreen',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const KlayKApp());
      await tester.pump();
      // AppGate: splash animado (~4s) + transição do switcher.
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Criar no KLAY K'), findsOneWidget);
      expect(find.text('Vídeo curto'), findsOneWidget);
      expect(find.text('Live ao vivo'), findsOneWidget);

      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Áudio')),
          findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Amigos')),
          findsOneWidget);

      await tester.tap(find.text('Live ao vivo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(StartLiveScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}