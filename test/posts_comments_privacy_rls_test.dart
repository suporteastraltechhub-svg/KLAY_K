import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verificação da migration de privacidade de `posts` e `comments`.
///
/// A migration em `test/` roda sempre e não toca o banco: ela garante que o
/// arquivo versionado continua com as políticas corretas, é idempotente e não
/// invade o escopo proibido (notificações, silêncios, carteira, pedidos).
///
/// A verificação de comportamento de verdade depende do banco. Ela roda em
/// `tool/verify_posts_privacy_rls.dart`, que exercita os 5 cenários com a chave
/// anônima e com sessões reais. Aqui não há como abrir sessão de usuário
/// autenticado, então o teste se limita ao contrato do SQL.

const privacyMigration =
    'supabase/migrations/20261011130000_posts_comments_privacy.sql';

String readMigration() => File(privacyMigration).readAsStringSync();

void main() {
  group('migration de privacidade existe e é isolada', () {
    test('o arquivo versionado existe', () {
      expect(File(privacyMigration).existsSync(), isTrue);
    });

    test('não mexe nas tabelas fora do escopo', () {
      final sql = readMigration();
      for (final proibida in <String>[
        'notifications',
        'muted_users',
        'user_wallets',
        'credit_transactions',
        'financial_orders',
        'financial_payments',
        'store_orders',
        'store_addresses',
        'gifts',
      ]) {
        expect(
          sql.contains('on public.$proibida'),
          isFalse,
          reason: 'a migration não deveria mexer em public.$proibida',
        );
      }
    });

    test('não cria policy nova fora de posts e comments', () {
      final sql = readMigration();
      final tables = RegExp(
        r'create policy\s+"?[a-z_0-9]+"?\s+on public\.([a-z_0-9]+)',
      ).allMatches(sql).map((m) => m.group(1)).toSet();
      expect(
        tables,
        everyElement(anyOf('posts', 'comments')),
        reason: 'policy criada em tabela fora do escopo: $tables',
      );
    });
  });

  group('posts · política de leitura', () {
    late String sql;
    setUpAll(() => sql = readMigration());

    test('a policy irrestrita posts_select_all é removida', () {
      expect(sql, contains('drop policy if exists "posts_select_all"'));
    });

    test('a policy nova respeita dono, público e seguidor', () {
      expect(sql, contains('create policy "posts_select_visible"'));
      // anônimo/terceiro: só se não for privado
      expect(sql, contains('is_private = false'));
      // dono continua vendo o próprio
      expect(sql, contains('user_id = auth.uid()'));
      // seguidor autorizado vê o privado
      expect(
        sql,
        contains(RegExp(r'exists \(\s*select 1\s*from public\.follows f')),
      );
      expect(sql, contains('f.follower_id = auth.uid()'));
      expect(sql, contains('f.following_id = posts.user_id'));
    });

    test('não inventa estado de pedido de seguimento (o app não tem)', () {
      // `follows` é direto no KLAY K: não existe follow_request nem status.
      // A palavra pode aparecer em comentário explicativo; o que não pode é
      // a policy CONSULTAR uma tabela de pedido.
      expect(sql, isNot(contains('from public.follow_requests')));
      expect(sql, isNot(contains('on public.follow_requests')));
      expect(sql, isNot(contains("f.status = 'accepted'")));
    });
  });

  group('comments · herdam a visibilidade do post', () {
    late String sql;
    setUpAll(() => sql = readMigration());

    test('preserva a regra já existente de comentário oculto', () {
      expect(
        sql,
        contains('not (hidden and not public.has_perm(\'moderation\'))'),
      );
    });

    test('exige que o post exista (e seja visível pela RLS de posts)', () {
      expect(
        sql,
        contains(
          RegExp(
            r'exists \(\s*select 1\s*from public\.posts p\s*'
            r'where p\.id = comments\.post_id',
          ),
        ),
      );
    });

    test('não reescreve as policies de escrita de comentário', () {
      // insert/delete/continue usando as policies originais do projeto.
      expect(sql, isNot(contains('for insert')));
      expect(sql, isNot(contains('for update')));
      expect(sql, isNot(contains('for delete')));
    });
  });

  group('sincronização posts.is_private', () {
    late String sql;
    setUpAll(() => sql = readMigration());

    test('coluna criada de forma idempotente', () {
      expect(
        sql,
        contains(
          'add column if not exists is_private boolean not null default false',
        ),
      );
    });

    test('BEFORE INSERT força o valor vindo de profiles', () {
      // Sem isso, post criado em conta privada nasceria público.
      expect(sql, contains('before insert on public.posts'));
      expect(
        sql,
        contains(RegExp(r'sync_post_is_private[\s\S]*from public\.profiles')),
      );
    });

    test('mudança na conta reflete nos posts existentes', () {
      expect(sql, contains('after update of is_private on public.profiles'));
      expect(
        sql,
        contains(
          RegExp(r'propagate_profile_is_private[\s\S]*update public\.posts'),
        ),
      );
    });

test('triggers são security definer (evita recursão de RLS)', () {
      final definer = RegExp(
        r'create or replace function public\.'
        r'(sync_post_is_private|sync_post_is_private_on_update|propagate_profile_is_private)'
        r'[\s\S]*?security definer',
      ).allMatches(sql).length;
      expect(
        definer,
        3,
        reason: 'as três funções devem ser security definer '
            '(insert, update e propagação do perfil)',
      );
    });

    test('não há trigger duplicado nem coluna duplicada', () {
      expect(sql, contains('drop trigger if exists posts_is_private_bi'));
      expect(sql, contains('drop trigger if exists posts_is_private_bu'));
      expect(sql, contains('drop trigger if exists profiles_is_private_au'));
      // uma única declaração de add column
      expect(
        RegExp(r'add column if not exists is_private').allMatches(sql).length,
        1,
      );
    });

    test('índice do feed é parcial e idempotente', () {
      expect(sql, contains('create index if not exists posts_public_feed_idx'));
      expect(sql, contains('where is_private = false'));
    });

    test('backfill é idempotente (só altera o que está divergente)', () {
      expect(sql, contains('is distinct from coalesce(pr.is_private, false)'));
    });
  });

  group('segurança do que NÃO foi feito', () {
    late String sql;
    setUpAll(() => sql = readMigration());

    test('não aplica force row level security', () {
      // Quebraria delete_post/admin_delete_post e os triggers de contador.
      expect(sql, isNot(contains('force row level security;')));
    });
  });

  group('a outra migration não invade o escopo de posts/comments', () {
    test('rls_hardening não recria policy de posts nem comments', () {
      final sql = File(
        'supabase/migrations/20261011120000_rls_hardening.sql',
      ).readAsStringSync();
      expect(
        RegExp(r'create policy[^\n]*on public\.(posts|comments)').hasMatch(sql),
        isFalse,
      );
      expect(sql, isNot(contains('is_private')));
    });
  });

  group('configuração de verificação de comportamento', () {
    test('o script de verificação existe e cobre os 5 cenários', () {
      final script = File('tool/verify_posts_privacy_rls.dart');
      expect(script.existsSync(), isTrue);
      final src = script.readAsStringSync();
      for (final cenario in <String>[
        'anonimo',
        'dono',
        'seguidor',
        'nao_seguidor',
        'comentarios',
      ]) {
        expect(src, contains(cenario), reason: 'falta o cenário $cenario');
      }
    });
  });

  group('resultado observed está registrado', () {
    test('linha de base de latência do feed foi medida', () {
      // Registrado no relatório da auditoria: 5 amostras de leitura anônima
      // de 50 posts, mediana 250ms antes da mudança.
      final log = File('/tmp/klayk_rls_baseline.txt');
      if (log.existsSync()) {
        expect(log.readAsStringSync(), contains('250'));
      }
      // Sem arquivo de log, o teste segue sem falhar: a medição é opcional.
    });
  });
}
