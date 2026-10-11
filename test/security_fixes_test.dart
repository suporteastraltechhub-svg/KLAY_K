import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Remove os comentários `--` de um arquivo SQL.
///
/// Os testes de segurança assertam a ausência de comandos, e os comentários das
/// migrations citam literalmente os comandos perigosos que estão sendo
/// removidos (para documentar de onde veio o problema). Sem esta etapa o teste
/// acusaria a própria documentação.
String _code(String sql) => sql
    .split('\n')
    .map((linha) {
      final i = linha.indexOf('--');
      return i < 0 ? linha : linha.substring(0, i);
    })
    .join('\n');

/// Contrato das correções de segurança aplicadas ao banco.
///
/// Estas migrations ainda NÃO foram aplicadas em produção — os testes
/// verificam o SQL versionado, não o estado do banco. O comportamento real é
/// verificado por `tool/verify_posts_privacy_rls.dart` e
/// `supabase/tests/rls_privacy_integration_test.sql`.
void main() {
  final shareFix =
      File('supabase/migrations/20261012120000_fix_increment_post_share.sql');
  final privacy =
      File('supabase/migrations/20261011130000_posts_comments_privacy.sql');

  group('increment_post_share · vulnerabilidade corrigida', () {
    late String sql;
    late String code;
    setUpAll(() {
      sql = shareFix.readAsStringSync();
      code = _code(sql);
    });

    test('a migration existe', () {
      expect(shareFix.existsSync(), isTrue);
    });

test('exige usuário autenticado antes de escrever', () {
      expect(
        RegExp(r'v_user\s+uuid\s*:=\s*auth\.uid\(\)').hasMatch(code),
        isTrue,
      );
      // Anônimo sai ANTES de qualquer UPDATE em posts. O bloco anônimo não tem
      // `if` aninhado, então o primeiro `end if;` é o que fecha ele.
      final guarda = RegExp(r'if v_user is null then([\s\S]*?)end if;')
          .firstMatch(code)?.group(1);
      expect(guarda, isNotNull, reason: 'não achei a guarda de anônimo');
      expect(
        guarda,
        isNot(contains('update public.posts')),
        reason: 'o UPDATE está dentro do bloco de anônimo',
      );
      expect(
        guarda,
        isNot(contains('share_events')),
        reason: 'anônimo não deve gravar evento de compartilhamento',
      );
    });

    test('anônimo recebe o valor corrente, não 0', () {
      // Se devolvesse 0, `FeedItem._countShare` sobrescreveria o incremento
      // local com 0 e o contador do visitante deslogado iria 1 -> 0.
      final guarda = RegExp(r'if v_user is null then([\s\S]*?)end if;')
          .firstMatch(code)?.group(1);
      expect(guarda, isNotNull);
      expect(guarda, contains('select coalesce(shares_count, 0) into v_count'));
      expect(
        RegExp(r'if v_user is null then\s*\n\s*return 0;').hasMatch(code),
        isFalse,
        reason: 'anônimo não pode receber 0 (zeraria o contador na tela)',
      );
    });

    test('anon perde o privilégio de execução', () {
      expect(
        code,
        contains(
          'revoke execute on function public.increment_post_share(uuid) from anon',
        ),
      );
      // Nenhum grant pode voltar a incluir anon.
      expect(
        RegExp(r'grant\s+execute[^;]*\banon\b').hasMatch(code),
        isFalse,
        reason: 'existe grant de execute para anon',
      );
    });

    test('fecha também o default PUBLIC do Postgres', () {
      // Sem isso, o EXECUTABLE BY PUBLIC continua valendo para anônimo.
      expect(
        code,
        contains(
          'revoke execute on function public.increment_post_share(uuid) from public',
        ),
      );
    });

    test('preserva o funcionamento para autenticado', () {
      expect(
        code,
        contains('grant execute on function public.increment_post_share(uuid) to authenticated'),
      );
    });

    test('mantém security definer com search_path fixo', () {
      final bloco = RegExp(
        r'create or replace function public\.increment_post_share[\s\S]*?\$\$;',
      ).firstMatch(code)?.group(0);
      expect(bloco, isNotNull);
      expect(bloco, contains('security definer'));
      expect(bloco, contains('set search_path = public'));
    });

    test('tem teto anti-abuso por usuário/post/hora', () {
      expect(code, contains('create table if not exists public.share_events'));
      expect(
        RegExp(r"created_at > now\(\) - interval '1 hour'").hasMatch(code),
        isTrue,
      );
    });

    test('a tabela de controle não é legível pelo usuário', () {
      // Sem policy de select: só o RPC (definer) enxerga.
      expect(code, contains('alter table public.share_events enable row level security'));
      expect(
        RegExp(r'create policy[^\n]*on public\.share_events').hasMatch(code),
        isFalse,
        reason: 'share_events não deve ter policy de select',
      );
    });

    test('a função de limpeza não é executável pelo app', () {
      expect(
        code,
        contains(
          'revoke execute on function public.prune_share_events() from public, anon, authenticated',
        ),
      );
    });

    test('é idempotente', () {
      expect(code, contains('create table if not exists public.share_events'));
      expect(code, contains('create index if not exists share_events_hour_idx'));
      expect(code, contains('create or replace function public.increment_post_share'));
      expect(code, contains('create or replace function public.prune_share_events'));
    });
  });

  group('contador de compartilhamentos nunca regride na tela', () {
    late String code;
    setUpAll(() => code = _code(File('lib/main.dart').readAsStringSync()));

    test('o total do servidor só é aplicado se for >= o valor local', () {
      final bloco = RegExp(
        r'Future<void> _countShare\(\) async \{[\s\S]*?\n  \}',
      ).firstMatch(code)?.group(0);
      expect(bloco, isNotNull, reason: 'não achei _countShare');

      expect(bloco, contains('total == null'));
      expect(
        bloco,
        contains('total < widget.video.shares'),
        reason: 'sem isso, um servidor desatualizado faz o contador voltar',
      );
      // O incremento local continua sendo a verdade mínima.
      expect(bloco, contains('widget.video.shares++'));
    });

    test('o setState continua protegido por mounted', () {
      final bloco = RegExp(
        r'Future<void> _countShare\(\) async \{[\s\S]*?\n  \}',
      ).firstMatch(code)!.group(0)!;
      expect(bloco, matches(RegExp(r'if \(!mounted[^;]*\)\s*return;')));
    });
  });

  group('posts.is_private · coluna protegida', () {
    late String code;
    setUpAll(() => code = _code(privacy.readAsStringSync()));

    test('revoga o update direto da coluna para anon e authenticated', () {
      expect(
        code,
        contains('revoke update (is_private) on public.posts from anon, authenticated'),
      );
    });

    test('o revoke de coluna está documentado como insuficiente', () {
      // Testa o arquivo CRU: aqui o objetivo é justamente o comentário.
      // Se alguém "simplificar" removendo o trigger achando que o revoke
      // basta, a brecha reabre — o comentário precisa explicar o porquê.
      final bruto = privacy.readAsStringSync();
      expect(bruto, contains('sozinho este `revoke` NÃO fecha a brecha'));
      expect(bruto, contains('implica o privilégio'));
      expect(bruto, contains('posts_is_private_bu'));
    });

    test('um trigger BEFORE UPDATE força o valor do perfil', () {
      // `revoke update (is_private)` sozinho NÃO funciona: `posts` tem UPDATE
      // no nível de tabela (ACL `arwdDxtm`), e no Postgres isso implica UPDATE
      // em todas as colunas, sobrepondo o revoke de coluna. O trigger é o que
      // realmente fecha a brecha, porque não depende de ACL.
      expect(code, contains('create or replace function public.sync_post_is_private_on_update'));
      expect(code, contains('before update on public.posts'));
      expect(
        code,
        contains('for each row execute function public.sync_post_is_private_on_update()'),
      );

      // O trigger reidr `profiles` e sobrescreve `new.is_private`.
      final fn = RegExp(
        r'create or replace function public\.sync_post_is_private_on_update[\s\S]*?\$\$;',
      ).firstMatch(code)?.group(0);
      expect(fn, isNotNull);
      expect(fn, contains('security definer'));
      expect(fn, contains('set search_path = public'));
      expect(
        RegExp(r'select coalesce\(p\.is_private, false\) into v_profile_private[\s\S]*?from public\.profiles')
            .hasMatch(fn!),
        isTrue,
      );
      expect(fn, contains('new.is_private := v_profile_private'));
    });

    test('a propagação autorizada continua existindo', () {
      expect(code, contains('after update of is_private on public.profiles'));
      expect(
        RegExp(
          r'propagate_profile_is_private[\s\S]*?update public\.posts',
        ).hasMatch(code),
        isTrue,
      );
    });
  });
}
