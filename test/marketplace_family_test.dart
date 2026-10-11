import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato das migrations do Marketplace e dos Controles Familiares.
///
/// Os arquivos são verificados SEM applied: estas migrations ainda não foram
/// aplicadas em produção. O comportamento real é coberto por
/// `supabase/tests/marketplace_family_rls_test.sql` (que roda dentro de uma
/// transação com ROLLBACK).
void main() {
  String sql(String p) => File(p).readAsStringSync();

  /// Remove comentários `--`, para os asserts de ausência não serem
  /// enganados pela própria documentação das migrations.
  String codigo(String s) => s
      .split('\n')
      .map((l) {
        final i = l.indexOf('--');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');

  const marketplace = 'supabase/migrations/20261017130000_marketplace.sql';
  const familia = 'supabase/migrations/20261017120000_family_controls.sql';

  group('Marketplace · schema', () {
    late String code;
    setUpAll(() => code = codigo(sql(marketplace)));

    test('produto ganha fotos, condição, entrega, status e vendas', () {
      for (final c in [
        'photos text[]',
        'condition text',
        'delivery_options text[]',
        'status text',
        'sold_count integer',
      ]) {
        expect(code, contains(c), reason: 'faltou a coluna $c');
      }
    });

    test('condição e status são listas fechadas', () {
      expect(code, contains("check (condition in ('novo', 'usado'))"));
      expect(
        code,
        contains("check (status in ('publicado', 'pausado', 'vendido'))"),
      );
    });

    test('índice de busca e de navegação existem', () {
      expect(code, contains('store_products_search_idx'));
      expect(code, contains('store_products_browse_idx'));
      expect(code, contains('store_products_seller_idx'));
      expect(code, contains('store_orders_buyer_idx'));
    });

    test('o bucket de imagens do marketplace é criado com limite de tamanho', () {
      expect(code, contains("'store-media'"));
      expect(code, contains('5242880'), reason: 'sem limite de 5 MB');
    });

    test('escrita do bucket só para o dono da pasta', () {
      expect(code, contains("and (storage.foldername(name))[1] = auth.uid()::text"));
    });
  });

  group('Marketplace · pagamento e status', () {
    late String code;
    setUpAll(() => code = codigo(sql(marketplace)));

    test('pedido nasce aguardando pagamento', () {
      expect(
        code,
        contains("payment_status text not null default 'aguardando_pagamento'"),
      );
    });

    test('cliente não escreve payment_status', () {
      expect(code, contains('store_orders_payment_guard'));
      expect(code, contains('store_guard_payment_status'));
      expect(code, contains("raise exception 'payment_status_readonly'"));
      // O guarda só deixa passar service_role/postgres.
      expect(code, contains("not in ('service_role', 'postgres')"));
    });

    test('transições de pedido são explícitas', () {
      // `when 'x' then p_to in (...)` e `when 'x' then false` (estado final).
      final linhas = RegExp(
        r"when '(\w+)'\s+then\s+(p_to in \([^)]*\)|false)",
      ).allMatches(code);
      expect(linhas, isNotEmpty);
      final mapa = {
        for (final m in linhas) m.group(1)!: m.group(2)!,
      };
      // Não pode pular de 'pendente' direto para 'entregue'.
      expect(mapa['pendente'], isNotNull);
      expect(mapa['pendente'], isNot(contains("'entregue'")));
      // 'entregue' e 'cancelado' são finais.
      expect(mapa['entregue'], 'false');
      expect(mapa['cancelado'], 'false');
    });

    test('validar produto no servidor, não só no cliente', () {
      expect(code, contains('store_publish_product'));
      expect(code, contains("raise exception 'bad_price'"));
      expect(code, contains("raise exception 'bad_stock'"));
      expect(code, contains("raise exception 'bad_title'"));
    });

    test('a policy de INSERT impede preço/estoque negativo', () {
      expect(code, contains('and price >= 0'));
      expect(code, contains('and stock >= 0'));
    });
  });

  group('Controles Familiares · schema', () {
    late String code;
    setUpAll(() => code = codigo(sql(familia)));

    test('limite de tempo com janela e um por responsável/membro', () {
      expect(code, contains('create table if not exists public.family_time_limits'));
      expect(code, contains('daily_minutes integer'));
      expect(code, contains('window_start time'));
      expect(code, contains('unique (guardian_id, member_id)'));
      // Responsável não pode definir limite para si mesmo.
      expect(code, contains('check (guardian_id <> member_id)'));
    });

    test('membro lê o próprio limite, mas não escreve', () {
      expect(code, contains('family_time_limits_member_select'));
      final select = RegExp(
        r'create policy "family_time_limits_member_select"[\s\S]*?;',
      ).firstMatch(code)?.group(0);
      expect(select, isNotNull);
      expect(select, contains('for select'));
      expect(select, isNot(contains('for insert')));
    });

    test('ticks de uso existem para o limite virar minutos', () {
      expect(code, contains('create table if not exists public.family_usage_ticks'));
      expect(code, contains('family_usage_tick'));
    });

    test('aprovação de seguidores é opt-in, não obrigatória', () {
      expect(code, contains('add column if not exists require_follow_approval'));
      expect(code, contains('default false'));
      expect(code, contains('create table if not exists public.follow_requests'));
      // Precisa do grant de COLUNA: profiles não tem UPDATE de tabela.
      expect(code, contains('grant update (require_follow_approval)'));
    });

    test('vínculo precisa estar ativo E com can_manage_safety', () {
      expect(code, contains("l.status = 'active'"));
      expect(code, contains('coalesce(l.can_manage_safety, true)'));
    });

    test('funções pedem auth e recusam quem não é responsável', () {
      for (final f in [
        'family_time_limit_status',
        'family_set_time_limit',
        'family_activity_report',
      ]) {
        expect(code, contains('create or replace function public.$f'));
      }
      expect(code, contains("raise exception 'auth_required'"));
      expect(code, contains("raise exception 'forbidden'"));
    });

    test('o relatório só agrega dados que o app já grava', () {
      expect(code, contains('family_activity_report'));
      for (final t in [
        'public.posts',
        'public.comments',
        'public.post_likes',
        'public.user_history',
        'public.follows',
      ]) {
        expect(code, contains(t), reason: 'faltou $t no relatório');
      }
    });

    test('follow com aprovação preserva o caminho direto', () {
      expect(code, contains('request_follow'));
      // Se o alvo não exige, o follow é direto como antes.
      expect(code, contains("return jsonb_build_object('status', 'seguindo'"));
    });

    test('só o dono do perfil aprova pedidos', () {
      final resp = RegExp(
        r'respond_follow_request[\s\S]*?where r\.id = p_request_id[\s\S]*?and r\.following_id = v_me',
      ).firstMatch(code)?.group(0);
      expect(resp, isNotNull);
    });
  });
}