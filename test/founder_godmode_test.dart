import 'package:flutter_test/flutter_test.dart';

import 'package:klay_k/services/admin_service.dart';
import 'package:klay_k/services/founder_service.dart';

void _resetOverrides() {
  FounderService.rpcOverride = null;
  AdminService.rpcOverride = null;
}

void main() {
  setUp(_resetOverrides);
  tearDown(_resetOverrides);

  group('FounderService — god mode (moedas)', () {
    test(
      'searchUsers: chama founder_search_users com p_query e mapeia lista',
      () async {
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'founder_search_users');
          expect(params['p_query'], 'klay');
          return [
            {
              'id': 'u-1',
              'username': 'klaymasta',
              'display_name': 'Klay',
              'role': 'user',
            },
            {
              'id': 'u-2',
              'username': 'klayking',
              'display_name': 'Rei',
              'role': 'user',
            },
          ];
        };
        final list = await FounderService.instance.searchUsers('klay');
        expect(list, hasLength(2));
        expect(list.first['username'], 'klaymasta');
        expect(list.last['id'], 'u-2');
      },
    );

    test('searchUsers: resposta não-lista vira []', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.searchUsers('x'), isEmpty);
    });

    test('userWallet: chama founder_user_wallet e mapeia saldo', () async {
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'founder_user_wallet');
        expect(params['p_user_id'], 'u-1');
        return {
          'user_id': 'u-1',
          'username': 'klaymasta',
          'credits': 1000,
          'diamonds': 250,
          'crystals': 40,
          'rubies': 0,
          'emeralds': 0,
          'crystal_rare': 1,
        };
      };
      final w = await FounderService.instance.userWallet('u-1');
      expect(w['credits'], 1000);
      expect(w['diamonds'], 250);
    });

    test(
      'adjustCurrency: envia p_user_id/p_currency/p_delta/p_reason',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'founder_adjust_currency');
          received = Map<String, dynamic>.from(params);
          return {'balance': 1500, 'delta': 500, 'currency': 'credits'};
        };
        final res = await FounderService.instance.adjustCurrency(
          userId: 'u-1',
          currency: 'credits',
          delta: 500,
          reason: 'recompensa oficial',
        );
        expect(received!['p_user_id'], 'u-1');
        expect(received!['p_currency'], 'credits');
        expect(received!['p_delta'], 500);
        expect(received!['p_reason'], 'recompensa oficial');
        expect(res['balance'], 1500);
      },
    );

    test('adjustCurrency: delta negativo é enviado como está', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        received = Map<String, dynamic>.from(params);
        return {'balance': 500};
      };
      await FounderService.instance.adjustCurrency(
        userId: 'u-1',
        currency: 'diamonds',
        delta: -100,
        reason: 'ajuste manual por erro',
      );
      expect(received!['p_delta'], -100);
    });

    test(
      'recentAdjustments: chama founder_recent_adjustments e mapeia lista',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'founder_recent_adjustments');
          received = Map<String, dynamic>.from(params);
          return [
            {
              'id': 'a-1',
              'target_name': 'Klay',
              'details': {
                'delta': 500,
                'currency': 'credits',
                'note': 'recompensa',
              },
              'created_at': '2026-09-11T12:00:00Z',
            },
          ];
        };
        final list = await FounderService.instance.recentAdjustments(limit: 10);
        expect(received!['p_limit'], 10);
        expect(list, hasLength(1));
        expect(list.first['details']?['delta'], 500);
      },
    );

    test('recentAdjustments: resposta não-lista vira []', () async {
      FounderService.rpcOverride = (_, __) async => const <int>[1, 2];
      expect(await FounderService.instance.recentAdjustments(), isEmpty);
    });
  });

  group('FounderService — god mode (segurança)', () {
    test('securityOverview: mapeia overview; não-map vira {}', () async {
      FounderService.rpcOverride = (name, _) async {
        expect(name, 'founder_security_overview');
        return {
          'blocked_ips': 2,
          'blocked_devices': 1,
          'open_alerts': 0,
          'critical_alerts': 0,
          'suspicious': 0,
          'blocked_users': 0,
        };
      };
      final o = await FounderService.instance.securityOverview();
      expect(o['blocked_ips'], 2);

      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.securityOverview(), isEmpty);
    });

    test('blockIp: chama founder_block_ip com ip + motivo', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'founder_block_ip');
        received = Map<String, dynamic>.from(params);
        return null;
      };
      await FounderService.instance.blockIp('1.2.3.4', 'flood de lives');
      expect(received!['p_ip'], '1.2.3.4');
      expect(received!['p_reason'], 'flood de lives');
    });

    test('unblockIp: chama founder_unblock_ip com ip', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'founder_unblock_ip');
        received = Map<String, dynamic>.from(params);
        return null;
      };
      await FounderService.instance.unblockIp('1.2.3.4');
      expect(received!['p_ip'], '1.2.3.4');
    });

    test(
      'blockDevice: chama founder_block_device com device + motivo',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'founder_block_device');
          received = Map<String, dynamic>.from(params);
          return null;
        };
        await FounderService.instance.blockDevice('dev-abc', 'conta roubada');
        expect(received!['p_device_id'], 'dev-abc');
        expect(received!['p_reason'], 'conta roubada');
      },
    );

    test('unblockDevice: chama founder_unblock_device com device', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'founder_unblock_device');
        received = Map<String, dynamic>.from(params);
        return null;
      };
      await FounderService.instance.unblockDevice('dev-abc');
      expect(received!['p_device_id'], 'dev-abc');
    });

    test(
      'setSecurityScore: envia usuário, delta e motivo; retorna score',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'founder_set_security_score');
          received = Map<String, dynamic>.from(params);
          return {'score': 45, 'level': 'suspicious'};
        };
        final res = await FounderService.instance.setSecurityScore(
          userId: 'u-1',
          delta: 10,
          reason: 'padrão de gift suspeito',
        );
        expect(received!['p_user_id'], 'u-1');
        expect(received!['p_delta'], 10);
        expect(received!['p_reason'], 'padrão de gift suspeito');
        expect(res['score'], 45);
        expect(res['level'], 'suspicious');
      },
    );

    test(
      'logAuthAttempt: chama log_auth_attempt com email/sucesso/device',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'log_auth_attempt');
          received = Map<String, dynamic>.from(params);
          return null;
        };
        await FounderService.instance.logAuthAttempt(
          email: 'x@k.app',
          success: false,
          deviceId: 'd1',
        );
        expect(received!['p_email'], 'x@k.app');
        expect(received!['p_success'], false);
        expect(received!['p_device_id'], 'd1');
      },
    );

    test('activateEmergency: chama guardian_emergency com mensagem', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_emergency');
        received = Map<String, dynamic>.from(params);
        return {'mode': 'max', 'message': 'ataque em andamento'};
      };
      final res = await FounderService.instance.activateEmergency(
        'ataque em andamento',
      );
      expect(received!['p_message'], 'ataque em andamento');
      expect(res['mode'], 'max');
    });

    test('activateEmergency: não-map vira {}', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.activateEmergency('x'), isEmpty);
    });
  });

  group('FounderService — god mode (dashboard)', () {
    test('dashboard: chama founder_dashboard e mapeia métricas', () async {
      FounderService.rpcOverride = (name, _) async {
        expect(name, 'founder_dashboard');
        return {
          'active_lives': 3,
          'total_viewers': 1240,
          'gifts_today': 540,
          'diamonds_spent_7d': 32000,
          'new_users_7d': 92,
          'retention_d30': 38,
          'health': {'alerts_open': 0, 'active_maintenance': 0},
        };
      };
      final d = await FounderService.instance.dashboard();
      expect(d['active_lives'], 3);
      expect(d['gifts_today'], 540);
      expect(d['health']['alerts_open'], 0);
    });

    test('dashboard: resposta não-map vira {}', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.dashboard(), isEmpty);
    });
  });

  group('FounderService — feedback', () {
    test('submitFeedback: envia categoria/nota/mensagem', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'submit_feedback');
        received = Map<String, dynamic>.from(params);
        return {'id': 'fb-1'};
      };
      final res = await FounderService.instance.submitFeedback(
        category: 'suggestion',
        rating: 5,
        message: 'Adicionar modo escuro no chat',
      );
      expect(received!['p_category'], 'suggestion');
      expect(received!['p_rating'], 5);
      expect(received!['p_message'], 'Adicionar modo escuro no chat');
      expect(res['id'], 'fb-1');
    });

    test('submitFeedback: resposta não-map vira {}', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(
        await FounderService.instance.submitFeedback(
          category: 'bug',
          rating: 1,
          message: 'x',
        ),
        isEmpty,
      );
    });

    test('listFeedbacks: chama mod_list_feedbacks e mapeia lista', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'mod_list_feedbacks');
        received = Map<String, dynamic>.from(params);
        return [
          {
            'id': 'fb-1',
            'category': 'suggestion',
            'rating': 5,
            'message': 'Adicionar modo escuro',
            'status': 'new',
            'username': 'klaymasta',
            'display_name': 'Klay',
            'created_at': '2026-09-11T12:00:00Z',
          },
        ];
      };
      final list = await FounderService.instance.listFeedbacks(status: 'new');
      expect(received!['p_status'], 'new');
      expect(list, hasLength(1));
      expect(list.first['category'], 'suggestion');
    });

    test(
      'listFeedbacks: sem status não envia p_status; não-lista vira []',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          received = Map<String, dynamic>.from(params);
          return null;
        };
        final list = await FounderService.instance.listFeedbacks();
        expect(received!.containsKey('p_status'), isFalse);
        expect(list, isEmpty);
      },
    );

    test('updateFeedbackStatus: envia id/status/notas', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'mod_update_feedback');
        received = Map<String, dynamic>.from(params);
        return null;
      };
      await FounderService.instance.updateFeedbackStatus(
        feedbackId: 'fb-1',
        status: 'reviewed',
        notes: 'Ok',
      );
      expect(received!['p_feedback_id'], 'fb-1');
      expect(received!['p_status'], 'reviewed');
      expect(received!['p_notes'], 'Ok');
    });

    test(
      'feedbackStats: chama founder_feedback_stats; não-map vira {}',
      () async {
        FounderService.rpcOverride = (name, _) async {
          expect(name, 'founder_feedback_stats');
          return {'total': 12, 'new': 3, 'reviewed': 8, 'avg_rating': 4};
        };
        final s = await FounderService.instance.feedbackStats();
        expect(s['new'], 3);
        expect(s['avg_rating'], 4);

        FounderService.rpcOverride = (_, __) async => null;
        expect(await FounderService.instance.feedbackStats(), isEmpty);
      },
    );
  });

  group('FounderService — god mode (manutenção)', () {
    test(
      'listMaintenance: chama guardian_list_maintenance e mapeia lista',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'guardian_list_maintenance');
          received = Map<String, dynamic>.from(params);
          return [
            {
              'id': 'w-1',
              'status': 'active',
              'mode': 'max',
              'feature': 'all',
              'message': 'Ataque em andamento',
              'is_emergency': true,
              'started_at': '2026-09-11T12:00:00Z',
            },
          ];
        };
        final list = await FounderService.instance.listMaintenance(limit: 25);
        expect(received!['p_limit'], 25);
        expect(list, hasLength(1));
        expect(list.first['mode'], 'max');
      },
    );

    test('listMaintenance: resposta não-lista vira []', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.listMaintenance(), isEmpty);
    });

    test('startMaintenance: envia modo/escopo/mensagem/emergência', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_set_maintenance');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'id': 'w-2', 'mode': 'medium'};
      };
      final res = await FounderService.instance.startMaintenance(
        mode: 'medium',
        feature: 'chat',
        message: 'Melhorias programadas',
        emergency: false,
      );
      expect(received!['p_mode'], 'medium');
      expect(received!['p_feature'], 'chat');
      expect(received!['p_message'], 'Melhorias programadas');
      expect(received!['p_emergency'], false);
      expect(res['id'], 'w-2');
    });

    test('startMaintenance: não-map vira {}', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(
        await FounderService.instance.startMaintenance(mode: 'max'),
        isEmpty,
      );
    });

    test('endMaintenance: envia id e motivo', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_end_maintenance');
        received = Map<String, dynamic>.from(params);
        return {'ok': true};
      };
      final res = await FounderService.instance.endMaintenance(
        windowId: 'w-1',
        reason: 'Serviço normalizado',
      );
      expect(received!['p_window_id'], 'w-1');
      expect(received!['p_reason'], 'Serviço normalizado');
      expect(res['ok'], true);
    });
  });

  group('FounderService — god mode (notificações)', () {
    test(
      'notificationStats: chama founder_notification_stats; não-map vira {}',
      () async {
        FounderService.rpcOverride = (name, _) async {
          expect(name, 'founder_notification_stats');
          return {'total': 120, 'unread': 9, 'today': 4, 'active_tokens': 3};
        };
        final s = await FounderService.instance.notificationStats();
        expect(s['unread'], 9);

        FounderService.rpcOverride = (_, __) async => null;
        expect(await FounderService.instance.notificationStats(), isEmpty);
      },
    );

    test('listNotifications: envia filtros e mapeia lista', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'mod_list_notifications');
        received = Map<String, dynamic>.from(params);
        return [
          {
            'id': 'n-1',
            'user_id': 'u-1',
            'username': 'klaymasta',
            'display_name': 'Klay',
            'type': 'broadcast',
            'message': 'Atualização em breve',
            'read': false,
            'created_at': '2026-09-11T12:00:00Z',
          },
        ];
      };
      final list = await FounderService.instance.listNotifications(
        type: 'broadcast',
        username: 'klay',
        limit: 25,
      );
      expect(received!['p_type'], 'broadcast');
      expect(received!['p_username'], 'klay');
      expect(received!['p_limit'], 25);
      expect(list, hasLength(1));
      expect(list.first['message'], 'Atualização em breve');
    });

    test(
      'listNotifications: sem filtros só envia p_limit; não-lista vira []',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          received = Map<String, dynamic>.from(params);
          return null;
        };
        final list = await FounderService.instance.listNotifications(limit: 50);
        expect(received!.containsKey('p_type'), isFalse);
        expect(received!.containsKey('p_username'), isFalse);
        expect(received!['p_limit'], 50);
        expect(list, isEmpty);
      },
    );

    test(
      'broadcastNotification: envia tipo/mensagem e retorna contagem',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          expect(name, 'founder_broadcast_notification');
          received = Map<String, dynamic>.from(params);
          return {'ok': true, 'count': 42, 'type': 'event'};
        };
        final res = await FounderService.instance.broadcastNotification(
          type: 'event',
          message: 'Torneio começa hoje!',
        );
        expect(received!['p_type'], 'event');
        expect(received!['p_message'], 'Torneio começa hoje!');
        expect(res['count'], 42);
      },
    );

    test('broadcastNotification: não-map vira {}', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(
        await FounderService.instance.broadcastNotification(
          type: 'alert',
          message: 'aviso',
        ),
        isEmpty,
      );
    });
  });

  group('FounderService — god mode (ferramentas de rei)', () {
    test('kingRules: chama guardian_list_rules e mapeia lista', () async {
      FounderService.rpcOverride = (name, _) async {
        expect(name, 'guardian_list_rules');
        return [
          {
            'id': 'abuse_tickets',
            'name': 'Abuso de tickets',
            'category': 'anti_abuse',
            'enabled': true,
            'priority': 90,
          },
        ];
      };
      final list = await FounderService.instance.kingRules();
      expect(list, hasLength(1));
      expect(list.first['id'], 'abuse_tickets');
    });

    test('kingRules: resposta não-lista vira []', () async {
      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.kingRules(), isEmpty);
    });

    test('kingToggleRule: envia id e enabled', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_toggle_rule');
        received = Map<String, dynamic>.from(params);
        return {'ok': true};
      };
      final res = await FounderService.instance.kingToggleRule(
        ruleId: 'wallet_negative',
        enabled: false,
      );
      expect(received!['p_rule_id'], 'wallet_negative');
      expect(received!['p_enabled'], false);
      expect(res['ok'], true);
    });

    test('kingRunRules: chama guardian_run_rules com limite padrão', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_run_rules');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'checks': 10};
      };
      final res = await FounderService.instance.kingRunRules();
      expect(received!['p_limit'], 200);
      expect(res['checks'], 10);
    });

    test('kingAlerts: envia filtros e mapeia lista', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_list_alerts');
        received = Map<String, dynamic>.from(params);
        return [
          {
            'id': 'al-1',
            'severity': 'high',
            'status': 'open',
            'title': 'Abuso de baús',
            'message': 'Muitos baús em 10 min.',
          },
        ];
      };
      final list = await FounderService.instance.kingAlerts(
        status: 'open',
        severity: 'high',
        limit: 25,
      );
      expect(received!['p_status'], 'open');
      expect(received!['p_severity'], 'high');
      expect(received!['p_limit'], 25);
      expect(list, hasLength(1));
      expect(list.first['severity'], 'high');
    });

    test(
      'kingAlerts: sem filtros só envia p_limit; não-lista vira []',
      () async {
        Map<String, dynamic>? received;
        FounderService.rpcOverride = (name, params) async {
          received = Map<String, dynamic>.from(params);
          return null;
        };
        final list = await FounderService.instance.kingAlerts();
        expect(received!.containsKey('p_status'), isFalse);
        expect(received!.containsKey('p_severity'), isFalse);
        expect(list, isEmpty);
      },
    );

    test('kingResolveAlert: envia id e nota', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'guardian_resolve_alert');
        received = Map<String, dynamic>.from(params);
        return {'ok': true};
      };
      final res = await FounderService.instance.kingResolveAlert(
        alertId: 'al-1',
        note: 'bot banido',
      );
      expect(received!['p_alert_id'], 'al-1');
      expect(received!['p_note'], 'bot banido');
      expect(res['ok'], true);
    });
  });

  group('FounderService — god mode (config globais)', () {
    test('configList: chama founder_get_config; não-map vira {}', () async {
      FounderService.rpcOverride = (name, _) async {
        expect(name, 'founder_get_config');
        return {
          'economy.gift_spend_multiplier': {'value': 1.0, 'description': 'x'},
        };
      };
      final c = await FounderService.instance.configList();
      expect(c.containsKey('economy.gift_spend_multiplier'), isTrue);

      FounderService.rpcOverride = (_, __) async => null;
      expect(await FounderService.instance.configList(), isEmpty);
    });

    test('setConfig: envia chave/valor/descrição', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'founder_set_config');
        received = Map<String, dynamic>.from(params);
        return {'ok': true, 'key': 'growth.xp_multiplier'};
      };
      final res = await FounderService.instance.setConfig(
        key: 'growth.xp_multiplier',
        value: 2,
        description: 'XP dobrado',
      );
      expect(received!['p_key'], 'growth.xp_multiplier');
      expect(received!['p_value'], 2);
      expect(received!['p_description'], 'XP dobrado');
      expect(res['key'], 'growth.xp_multiplier');
    });

    test('deleteConfig: chama founder_delete_config com chave', () async {
      Map<String, dynamic>? received;
      FounderService.rpcOverride = (name, params) async {
        expect(name, 'founder_delete_config');
        received = Map<String, dynamic>.from(params);
        return {'ok': true};
      };
      final res = await FounderService.instance.deleteConfig(
        'growth.xp_multiplier',
      );
      expect(received!['p_key'], 'growth.xp_multiplier');
      expect(res['ok'], true);
    });
  });
}
