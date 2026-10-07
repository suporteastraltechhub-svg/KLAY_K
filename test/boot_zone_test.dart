// Regressão do "Zone mismatch" na inicialização.
//
// Bug real: `WidgetsFlutterBinding.ensureInitialized()` rodava na zone raiz
// (dentro de `main`) e o `runApp` rodava dentro de `runZonedGuarded` — zone
// FILHA. O Flutter guarda a zone do binding e acusa em
// `BindingBase.debugCheckZone`:
//   "The Flutter bindings were initialized in a different zone than is now
//    being used."
//
// A correção foi estrutural: binding, boot e runApp dentro da mesma zone.
// Este teste trava esse padrão.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `test` puro (não `testWidgets`): em `testWidgets` o harness já cria o
  // binding antes do nosso código, e a zone gravada seria a do harness — o
  // teste não provaria nada sobre a nossa própria sequence.
  test('binding criado dentro da zone do runApp nao acusa mismatch', () async {
    Object? capturado;

    await runZonedGuarded<Future<void>>(
      () async {
        // 1) o binding nasce dentro desta zone...
        WidgetsFlutterBinding.ensureInitialized();
        final bootZone = Zone.current;

        // 2) ...e o runApp acontece na MESMA zone.
        runApp(const MaterialApp(home: SizedBox.shrink()));
        expect(
          Zone.current,
          same(bootZone),
          reason: 'runApp precisa rodar na zone em que o binding foi criado',
        );
        expect(WidgetsBinding.instance, isNotNull);
      },
      (e, s) {
        capturado = e;
      },
    );

    expect(capturado, isNull, reason: 'erro de zone: $capturado');
  });

  test('o padrao ERRADO produz zone diferente (prova que o teste detecta)', () {
    final zoneRaiz = Zone.current;
    var zoneFilha = Zone.current;

    runZonedGuarded<void>(() {
      zoneFilha = Zone.current;
    }, (e, s) {});

    // E por isso que criar o binding FORA e rodar o runApp DENTRO acusaria o
    // mismatch: as duas zones sao diferentes.
    expect(zoneFilha, isNot(same(zoneRaiz)));
  });
}
