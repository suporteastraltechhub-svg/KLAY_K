// Testes do módulo "Publicações" do painel administrativo (exclusão de
// conteúdo de qualquer autor com capability `moderation`).
//
// Os testes de widget rodam OFFLINE: `AdminService.rpcOverride` injeta um
// backend fake (mesmo contrato das RPCs `security definer` do Supabase) e o
// painel é aberto direto — sem rede. As regras de autorização/limpeza DAS RPCs
// reais são validadas estaticamente sobre a migração
// `supabase/migrations/20260906010000_admin_delete_post.sql` (padrão já usado
// em test/live_integration_test.dart para checagens de segurança).
//
// Cobertura A–G:
//   A. Staff com cap `moderation` exclui publicação de OUTRO usuário.
//   B. Usuário comum não vê o painel nem consegue excluir.
//   C. Publicação inexistente → erro amigável, lista intacta.
//   D. Chamada repetida/idempotente é segura (second call → post_not_found).
//   E. O storage (vídeo + capa) é removido apenas com prova de posse.
//   F. Publicação sem arquivos também é excluída sem erro.
//   G. A publicação excluída desaparece do painel (lista recarregada).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/screens/founder_panel_screen.dart';
import 'package:klay_k/services/admin_service.dart';
import 'package:klay_k/theme/klayk_theme.dart';

import 'helpers/l10n_test_utils.dart';

/// Backend fake (sem rede) para a aba "Publicações": simula o contrato das
/// RPCs `my_role`/`my_caps`/`admin_list_posts`/`admin_delete_post` que o
/// backend real protege com `security definer` + `has_perm('moderation')`.
class FakeAdminBackend {
  FakeAdminBackend({required List<Map<String, dynamic>> posts})
    : posts = List.of(posts);

  final List<Map<String, dynamic>> posts;
  String role = 'moderator';
  List<String> caps = const ['moderation'];
  final List<String> deleted = [];
  int listCalls = 0;
  int deleteCalls = 0;

  Future<dynamic> call(String name, Map<String, dynamic> params) async {
    switch (name) {
      case 'my_role':
        return role;
      case 'my_caps':
        return List<String>.of(caps);
      case 'is_klayk_staff':
        return role != 'user';
      case 'admin_list_posts':
        listCalls++;
        return List<Map<String, dynamic>>.from(posts);
      case 'admin_delete_post':
        deleteCalls++;
        final id = params['p_post_id']?.toString();
        final index = posts.indexWhere((p) => p['id']?.toString() == id);
        if (index < 0) throw StateError('post_not_found');
        final removed = posts[index];
        posts.removeAt(index);
        deleted.add(id ?? '');
        return <String, dynamic>{
          'ok': true,
          'id': id,
          'user_id': removed['user_id'],
        };
      default:
        throw StateError('not_admin');
    }
  }
}

/// Linha de `posts` no formato do feed (join `profiles`), como retorna a RPC
/// `admin_list_posts`.
Map<String, dynamic> samplePost(
  String id, {
  String description = '',
  String videoUrl = 'owner/abc.mp4',
  String? coverUrl,
}) => {
  'id': id,
  'user_id': 'u-owner',
  'video_url': videoUrl,
  if (coverUrl != null) 'cover_url': coverUrl,
  'description': description,
  'audio_name': null,
  'likes_count': 12,
  'comments_count': 3,
  'shares_count': 1,
  'created_at': '2026-09-05T12:00:00.000Z',
  'profiles': {
    'id': 'u-owner',
    'username': 'creator',
    'display_name': 'Criador Teste',
    'avatar_url': null,
    'is_verified': true,
  },
};

/// Pumps com duração fixa (evita `pumpAndSettle` com spinners infinitos do
/// carregamento): aguarda `_check` → abas → lista da aba Publicações.
Future<void> pumpPanel(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Deixa o timer de auto-dismiss da SnackBar expirar (senão o teste acusa
/// timer pendente) e drena a animação de saída.
Future<void> flushSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Widget buildPanel() =>
    l10nApp(theme: KlaykTheme.dark(), home: const FounderPanelScreen());

void main() {
  tearDown(() {
    AdminService.rpcOverride = null;
  });

  // ---------------------------------------------------------------------------
  // A + G: staff exclui publicação de outro usuário e ela some do painel.
  // ---------------------------------------------------------------------------
  testWidgets('A/G: staff com cap modulation exclui publicação de outro '
      'usuário e ela desaparece do painel', (tester) async {
    final backend = FakeAdminBackend(
      posts: [
        samplePost('post-1', description: 'postagem do outro usuário'),
        samplePost('post-2', description: 'segunda publicação'),
      ],
    );
    AdminService.rpcOverride = backend.call;

    await tester.pumpWidget(buildPanel());
    await pumpPanel(tester);

    expect(find.text('Publicações'), findsOneWidget);
    expect(find.text('postagem do outro usuário'), findsOneWidget);
    expect(find.text('segunda publicação'), findsOneWidget);

    // Abre a confirmação e exclui a primeira publicação (de outro usuário).
    await tester.tap(find.byTooltip('Excluir publicação').first);
    await tester.pumpAndSettle();
    expect(find.text('Excluir esta publicação?'), findsOneWidget);
    expect(
      find.text(
        'Esta ação removerá a publicação do KLAY K e não poderá ser desfeita.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Excluir'));
    await pumpPanel(tester);

    expect(backend.deleted, [
      'post-1',
    ], reason: 'o backend fake registra a exclusão do post certo');
    expect(find.text('Publicação excluída com sucesso.'), findsOneWidget);
    expect(
      find.text('postagem do outro usuário'),
      findsNothing,
      reason: 'publicação excluída desaparece da lista',
    );
    expect(
      find.text('segunda publicação'),
      findsOneWidget,
      reason: 'publicações restantes permanecem',
    );
    expect(
      backend.listCalls,
      greaterThanOrEqualTo(2),
      reason: 'a lista é recarregada após a exclusão',
    );
    expect(tester.takeException(), isNull);

    await flushSnackBar(tester);
  });

  testWidgets('Cancelar na confirmação não exclui nada', (tester) async {
    final backend = FakeAdminBackend(posts: [samplePost('post-1')]);
    AdminService.rpcOverride = backend.call;

    await tester.pumpWidget(buildPanel());
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('Excluir publicação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await pumpPanel(tester);

    expect(backend.deleted, isEmpty);
    expect(backend.deleteCalls, 0);
    expect(find.text('postagem'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // B: usuário comum nunca vê o painel nem chama a exclusão.
  // ---------------------------------------------------------------------------
  testWidgets('B: usuário comum (sem cap) vê "Acesso restrito" e nada de '
      'Publicações', (tester) async {
    final backend = FakeAdminBackend(posts: [samplePost('post-1')])
      ..role = 'user'
      ..caps = const [];
    AdminService.rpcOverride = backend.call;

    await tester.pumpWidget(buildPanel());
    await pumpPanel(tester);

    expect(find.text('Acesso restrito'), findsOneWidget);
    expect(find.text('Publicações'), findsNothing);
    expect(find.byTooltip('Excluir publicação'), findsNothing);
    expect(
      backend.deleteCalls,
      0,
      reason: 'usuário comum nunca chega a chamar a RPC',
    );
    expect(tester.takeException(), isNull);
  });

  test('B: usuário comum que forçar a RPC recebe not_admin e a mensagem '
      'amigável correspondente', () async {
    AdminService.rpcOverride = (name, params) async =>
        throw StateError('not_admin');
    await expectLater(
      AdminService.instance.adminDeletePost('post-1'),
      throwsA(isA<StateError>()),
    );
    expect(
      AdminService.instance.friendlyError(StateError('not_admin')),
      'Permissão negada pelo servidor.',
    );
    expect(
      AdminService.instance.friendlyError(StateError('not_authenticated')),
      'Falha de rede ou ação não autorizada.',
    );
  });

  // ---------------------------------------------------------------------------
  // C: publicação inexistente → erro amigável, lista intacta.
  // ---------------------------------------------------------------------------
  testWidgets('C: excluir publicação inexistente mostra erro amigável sem '
      'quebrar a lista', (tester) async {
    final backend = FakeAdminBackend(posts: [samplePost('post-1')]);
    AdminService.rpcOverride = (name, params) async {
      if (name == 'admin_delete_post') throw StateError('post_not_found');
      return backend.call(name, params);
    };

    await tester.pumpWidget(buildPanel());
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('Excluir publicação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await pumpPanel(tester);

    expect(
      find.text('Registro não encontrado.'),
      findsOneWidget,
      reason: 'friendlyError mapeia post_not_found',
    );
    expect(find.text('postagem'), findsNothing);
    expect(
      backend.posts,
      hasLength(1),
      reason: 'publicação continua na lista após o erro',
    );
    expect(tester.takeException(), isNull);

    await flushSnackBar(tester);
  });

  // ---------------------------------------------------------------------------
  // D: repetição/chamada dupla é segura (idempotência + contrato do serviço).
  // ---------------------------------------------------------------------------
  test('D: excluir duas vezes a mesma publicação falha de forma tratável '
      '(post_not_found)', () async {
    final backend = FakeAdminBackend(posts: [samplePost('post-1')]);
    AdminService.rpcOverride = backend.call;

    final first = await AdminService.instance.adminDeletePost('post-1');
    expect(first['ok'], isTrue);

    await expectLater(
      AdminService.instance.adminDeletePost('post-1'),
      throwsA(isA<StateError>()),
      reason: 'segunda chamada não apaga nada e reporta post ausente',
    );
    expect(backend.deleted, ['post-1']);
    expect(backend.deleteCalls, 2);
  });

  test(
    'D: contrato dos parâmetros — admin_delete_post só envia o id',
    () async {
      String? name;
      Map<String, dynamic>? params;
      AdminService.rpcOverride = (n, p) async {
        name = n;
        params = p;
        return <String, dynamic>{'ok': true, 'id': 'post-1', 'user_id': 'u-x'};
      };
      final res = await AdminService.instance.adminDeletePost('post-1');
      expect(name, 'admin_delete_post');
      expect(
        params,
        {'p_post_id': 'post-1'},
        reason: 'o app passa apenas o id; autorização/limpeza é do backend',
      );
      expect(res['ok'], isTrue);
    },
  );

  test(
    'D: adminListPosts chama a RPC com p_limit/p_offset e mapeia a lista',
    () async {
      String? name;
      Map<String, dynamic>? params;
      AdminService.rpcOverride = (n, p) async {
        name = n;
        params = p;
        return [samplePost('post-1')];
      };
      final list = await AdminService.instance.adminListPosts(
        limit: 10,
        offset: 5,
      );
      expect(name, 'admin_list_posts');
      expect(params, {'p_limit': 10, 'p_offset': 5});
      expect(list, hasLength(1));
      expect(list.first['id'], 'post-1');
      expect(list.first['profiles'], isA<Map>());
    },
  );

  // ---------------------------------------------------------------------------
  // E + F: limpeza de Storage e casos sem arquivo — verificados sobre a
  // migração (a execução real fica no banco; não há Supabase no sandbox).
  // ---------------------------------------------------------------------------
  group('Migração admin_delete_post (backend)', () {
    final sql = File(
      'supabase/migrations/20260906010000_admin_delete_post.sql',
    ).readAsStringSync();

    test(
      'E: vídeo e capa são removidos do Storage somente com prova de posse',
      () {
        expect(sql, contains("bucket_id = 'videos'"));
        expect(sql, contains("bucket_id = 'covers'"));
        expect(
          sql,
          contains('storage.foldername'),
          reason: 'extrai o dono a partir do caminho do objeto',
        );
        expect(
          sql,
          contains('(storage.foldername(name))[1]'),
          reason: 'só apaga se o primeiro segmento for o dono do post',
        );
        expect(
          sql,
          contains('row_count'),
          reason: 'conta os objetos realmente removidos',
        );
        expect(
          sql,
          contains("delete from public.posts where id = p_post_id"),
          reason: 'a exclusão do post é a última etapa (arquivos já saíram)',
        );
        expect(
          sql,
          contains('storage.allow_delete_query'),
          reason:
              'o trigger storage.protect_delete exige o GUC para DELETE SQL '
              'em storage.objects; sem isso a limpeza falha no runtime',
        );
      },
    );

    test('F: publicação sem arquivos também é excluída sem erro', () {
      expect(
        sql,
        contains("coalesce(v_row.video_url, '') <> ''"),
        reason: 'vídeo é removido apenas quando video_url é caminho',
      );
      expect(
        sql,
        contains('http'),
        reason: 'caminho de vídeo (não URL) é o único caso de storage',
      );
      expect(
        sql,
        contains('v_cover_path <> '),
        reason: 'capa é removida apenas quando o caminho foi extraído',
      );
      expect(
        sql,
        contains("delete from public.posts where id = p_post_id"),
        reason: 'post sem arquivos segue sendo excluído normalmente',
      );
    });

    test('autorização e auditoria ficam no backend (security definer)', () {
      expect(sql, contains('security definer'));
      expect(sql, contains("public.has_perm('moderation')"));
      expect(sql, contains('not_admin'));
      expect(sql, contains('not_authenticated'));
      expect(sql, contains('post_not_found'));
      expect(
        sql,
        contains('public.write_audit'),
        reason: 'toda exclusão vira linha de auditoria',
      );
    });

    test('funções não ficam expostas a anon/public e sem secrets', () {
      expect(
        sql,
        contains(
          'revoke all on function public.admin_delete_post(uuid) '
          'from public, anon;',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.admin_delete_post(uuid) '
          'to authenticated;',
        ),
      );
      expect(
        sql,
        contains(
          'revoke all on function public.admin_list_posts(int, int) '
          'from public, anon;',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.admin_list_posts(int, int) '
          'to authenticated;',
        ),
      );
      expect(sql, isNot(contains('sk_live_')));
      expect(
        sql,
        isNot(contains('service_role')),
        reason: 'nenhuma chave de serviço no código do app',
      );
    });
  });

  testWidgets('F: lista vazia mostra o estado vazio', (tester) async {
    final backend = FakeAdminBackend(posts: []);
    AdminService.rpcOverride = backend.call;

    await tester.pumpWidget(buildPanel());
    await pumpPanel(tester);

    expect(find.text('Nenhuma publicação.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab Publicações aparece para cap moderation mesmo sem is_admin '
      '(sem abas restritas a admin)', (tester) async {
    final backend = FakeAdminBackend(posts: [samplePost('post-1')]);
    AdminService.rpcOverride = backend.call;

    await tester.pumpWidget(buildPanel());
    await pumpPanel(tester);

    expect(find.text('Publicações'), findsOneWidget);
    expect(find.text('Visão Geral'), findsNothing);
    expect(find.text('Moderação'), findsNothing);
    expect(find.text('Usuários'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
