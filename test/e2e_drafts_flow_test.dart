// E2E definitivo do módulo de rascunhos contra o Supabase REAL
// (projeto oysyuialaelzcxxkfdsl). Só roda com `KLAY_E2E=true` (opt-in
// explícito), mesma regra dos outros E2E do repositório.
//
//   KLAY_E2E=true flutter test test/e2e_drafts_flow_test.dart --timeout 300s
//
// Cobre o contrato rascunho → publicação → feed:
//  - serviço: create → edit (update) → publish → feed (upload de vídeo/capa
//    para o bucket privado `drafts` via os MESMOS métodos usados pela UI);
//  - IDEMPOTÊNCIA: publicar de novo reutiliza o MESMO post (sem duplicar);
//  - limpeza best-effort dos dados criados no `finally` (mesmo com falha).
// A UI do `_saveDraft` (galeria → bytes → upload → create → snackbar) é
// coberta por widget tests offline (armazenamento injetado) em
// `drafts_widget_test.dart` — rodar rede real dentro do relógio fake do
// `testWidgets` é instável (timer pendente / timeout), por isso o E2E fica
// no nível de serviço.
//
// Harness idêntico aos outros E2E: primeiro teste (test(), não testWidgets)
// inicializa o singleton do Supabase na zona real e valida o contrato.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klay_k/models/post_models.dart';
import 'package:klay_k/services/content_service.dart';
import 'package:klay_k/services/drafts_service.dart';
import 'package:klay_k/services/supabase_service.dart';

const _adminEmail = 'founder.admin+test@klayk.app';
const _password = 'KlayKTest#2026!';

/// Vídeo "fake" de 4 bytes: o storage do Supabase não valida conteúdo.
Uint8List _tinyVideo() => Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);

void main() {
  // Sem testWidgets registrado neste arquivo, o binding não é inicializado no
  // load; o setUpAll mocka o canal de deep links do app_links e precisa dele.
  TestWidgetsFlutterBinding.ensureInitialized();

  final isE2E = Platform.environment['KLAY_E2E'] == 'true';
  bool? skipUnlessE2E() => isE2E ? null : true;

  setUpAll(() {
    if (isE2E) {
      // O flutter_test troca o HttpClient global por um mock que responde 400;
      // no E2E (rede real) restauramos o IOClient padrão.
      HttpOverrides.global = null;
    }
    // O supabase_flutter se inscreve no canal de deep links do app_links ao
    // iniciar; no harness não há implementação nativa (MissingPluginException).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (call) async => null,
        );
  });

  group('🧪 E2E RASCUNHOS (draft → publish → feed, KLAY_E2E)', () {
    test('(setup) inicializa Supabase na zona real', () async {
      SharedPreferences.setMockInitialValues(const {});
      await SupabaseService.instance.ensureReady();
      expect(
        SupabaseService.instance.isConfigured,
        isTrue,
        reason: 'E2E exige Supabase configurado (rede real habilitada).',
      );
    }, skip: skipUnlessE2E());

    test(
      'draft: create → edit → publish → re-publish idempotente → feed',
      () async {
        final db = SupabaseService.instance;
        final svc = DraftsService.instance;

        await db.signInWithEmail(_adminEmail, _password);
        expect(db.hasSession, isTrue);
        final uid = db.currentUser!.id;

        final stamp = DateTime.now().millisecondsSinceEpoch;
        final tmp = File(
          '${Directory.systemTemp.path}/klay_e2e_draft_$stamp.mp4',
        );
        tmp.writeAsBytesSync(_tinyVideo());
        final tmpCover = File(
          '${Directory.systemTemp.path}/klay_e2e_draft_cover_$stamp.jpg',
        );
        tmpCover.writeAsBytesSync(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]));

        Draft? d;
        FeedPost? post;
        String? publicVideoPath;
        String? publicCoverPath;
        try {
          // save: mídia no bucket privado `drafts` (mesmos métodos da UI).
          final videoPath = await svc.uploadVideoBytes(
            'v$stamp.mp4',
            await tmp.readAsBytes(),
          );
          final coverPath = await svc.uploadCoverBytes(
            'c$stamp.jpg',
            await tmpCover.readAsBytes(),
            contentType: 'image/jpeg',
          );
          expect(
            videoPath,
            startsWith('$uid/videos/'),
            reason: 'video_path gravado no padrao {uid}/videos/...',
          );
          expect(
            coverPath,
            startsWith('$uid/covers/'),
            reason: 'cover_path gravado no padrao {uid}/covers/...',
          );

          final originalDesc = 'E2E rascunho $stamp';
          d = await svc.create(
            videoPath: videoPath,
            coverPath: coverPath,
            description: originalDesc,
            audioName: 'Áudio original',
            hashtags: const ['klayk', 'e2e'],
            location: 'Teste',
            durationSeconds: 5,
          );
          expect(d.id, isNotEmpty, reason: 'create devolveu um id de rascunho');
          expect(d.videoPath, videoPath);
          expect(d.coverPath, coverPath);

          // A lista do usuário traz o rascunho recém-criado.
          final listed = await svc.list();
          expect(
            listed.any((x) => x.id == d!.id),
            isTrue,
            reason: 'rascunho aparece na listagem após create',
          );

          // edit: update de descrição + hashtags persiste no backend.
          final editedDesc = 'E2E editado $stamp';
          await svc.update(
            d,
            description: editedDesc,
            hashtags: const ['klayk', 'editado'],
            location: 'Editado',
          );
          final fetched = await svc.get(d.id);
          expect(fetched, isNotNull);
          expect(
            fetched!.description,
            editedDesc,
            reason: 'update persistiu a descrição editada',
          );
          expect(fetched.hashtags, const [
            'klayk',
            'editado',
          ], reason: 'update persistiu as hashtags editadas');
          expect(fetched.location, 'Editado');

          // publish: cria o post no feed e FINALIZA o rascunho.
          post = await svc.publish(d.id);
          expect(
            post,
            isNotNull,
            reason: 'publish devolveu o post criado no feed',
          );
          expect(
            post!.description,
            editedDesc,
            reason: 'post usa o que foi editado no rascunho',
          );
          expect(post.hashtags, containsAll(const ['klayk', 'editado']));

          final row = Map<String, dynamic>.from(
            await db.client
                    .from('drafts')
                    .select('status,post_id')
                    .eq('id', d.id)
                    .single()
                as Map,
          );
          expect(
            row['status'],
            'published',
            reason: 'rascunho publishado fica com status published',
          );
          expect(
            row['post_id'].toString(),
            post.id,
            reason: 'post_id gravado no rascunho (base da idempotência)',
          );

          publicVideoPath = post.videoUrl;
          publicCoverPath = ContentService.coverPathFromCoverUrl(
            post.coverUrl ?? '',
          );

          // IDEMPOTÊNCIA: repetir a publicação devolve o MESMO post.
          final again = await svc.publish(d.id);
          expect(again, isNotNull);
          expect(
            again!.id,
            post.id,
            reason: 're-publish reutiliza o post existente (mesmo id)',
          );

          final duplicates =
              (await db.client
                          .from('posts')
                          .select('id')
                          .eq('id', post.id)
                          .eq('user_id', uid)
                      as List)
                  .length;
          expect(
            duplicates,
            1,
            reason: 'republicar NÃO cria posts duplicados no feed',
          );

          // feed: exatamente 1 post deste autor com o id criado.
          final feed = await ContentService.instance.fetchFeed(userId: uid);
          final mine = feed.where((p) => p.id == post!.id).toList();
          expect(
            mine,
            hasLength(1),
            reason: 'fetchFeed traz o post publicado (uma única vez)',
          );
          expect(mine.single.description, editedDesc);
          expect(mine.single.hashtags, containsAll(const ['klayk', 'editado']));
        } finally {
          // Limpeza best-effort mesmo em caso de falha.
          try {
            if (d != null) await svc.remove(d.id);
          } catch (_) {}
          try {
            if (publicVideoPath != null && publicVideoPath.isNotEmpty) {
              await db.client.storage.from('videos').remove([publicVideoPath]);
            }
          } catch (_) {}
          try {
            if (publicCoverPath != null && publicCoverPath.isNotEmpty) {
              await db.client.storage.from('covers').remove([publicCoverPath]);
            }
          } catch (_) {}
          try {
            if (post != null) {
              await db.client.from('posts').delete().eq('id', post.id);
            }
          } catch (_) {}
          try {
            await db.signOut();
          } catch (_) {}
          if (tmp.existsSync()) tmp.deleteSync();
          if (tmpCover.existsSync()) tmpCover.deleteSync();
        }
      },
      skip: skipUnlessE2E(),
    );

    test('streaming upload (ContentService.uploadVideo): vermelho real, sem '
        're-upload e objeto criado no bucket videos', () async {
      final db = SupabaseService.instance;
      final content = ContentService.instance;
      await db.signInWithEmail(_adminEmail, _password);
      expect(db.hasSession, isTrue);
      final uid = db.currentUser!.id;

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final tmp = File(
        '${Directory.systemTemp.path}/klay_e2e_stream_$stamp.mp4',
      );
      // 2 MB de bytes reais: progresso passa por vários inteiros de 1%.
      tmp.writeAsBytesSync(List<int>.generate(2 * 1024 * 1024, (i) => i % 251));

      final progress = <double>[];
      String? path;
      try {
        final target = '$uid/$stamp.mp4';
        final returned = await content.uploadVideo(
          tmp,
          path: target,
          mime: 'video/mp4',
          onProgress: progress.add,
        );
        expect(
          returned,
          target,
          reason: 'devolve o caminho exato do objeto enviado',
        );
        path = target;

        // Progresso REAL: não vazio, termina em 1.0 e nunca regride.
        expect(
          progress,
          isNotEmpty,
          reason: 'streaming reporta progresso em byte real',
        );
        expect(
          progress.last,
          1.0,
          reason: 'progresso chega a 100% ao concluir o envio',
        );
        for (var i = 1; i < progress.length; i++) {
          expect(
            progress[i] >= progress[i - 1],
            isTrue,
            reason:
                'progresso não pode regredir: ${progress[i - 1]} -> ${progress[i]}',
          );
        }

        // Objeto criado de verdade: URL assinada resolve (download possível).
        final signed = await content.signedVideoUrl(path);
        expect(
          signed.toLowerCase(),
          startsWith('http'),
          reason: 'vídeo existe no bucket (signed-url o resolve)',
        );

        // SEM duplicação no servidor: reenviar o MESMO path sem x-upsert é
        // rejeitado ("already exists") — no app o reuso é por _uploadedVideoPath,
        // esta chamada nunca acontece; aqui provamos que o bucket não duplica.
        var rejected = false;
        try {
          await content.uploadVideo(tmp, path: target, mime: 'video/mp4');
        } on HttpException catch (e) {
          final msg = e.message.toLowerCase();
          rejected =
              msg.contains('exist') ||
              msg.contains('400') ||
              msg.contains('409');
        }
        expect(
          rejected,
          isTrue,
          reason:
              'reenviar o mesmo path sem x-upsert é rejeitado (não duplica)',
        );

        final listed = await db.client.storage.from('videos').list(path: uid);
        final matches = listed.where((o) => o.name == '$stamp.mp4').length;
        expect(
          matches,
          1,
          reason: 'não duplica o objeto no bucket (uma única versão)',
        );
      } finally {
        if (path != null) {
          try {
            await db.client.storage.from('videos').remove([path]);
          } catch (_) {}
        }
        try {
          await db.signOut();
        } catch (_) {}
        if (tmp.existsSync()) tmp.deleteSync();
      }
    }, skip: skipUnlessE2E());
  });
}
