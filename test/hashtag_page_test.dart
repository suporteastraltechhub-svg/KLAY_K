import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/services/content_service.dart';

/// A página de hashtag depende de casar a tag como o app GRAVA.
///
/// `main.dart:_parseHashtags` remove só o `#` e preserva a caixa, então
/// `#Brasil` é armazenado como `Brasil`. Um filtro `contains` sensível a caixa
/// não encontraria nada ao buscar `brasil` — que é o que toda pessoa digita.
/// Estes testes travam o comportamento de [ContentService.hashtagCaseVariants].
void main() {
  group('variações de caixa da hashtag', () {
    test('minúscula gera minúscula, capitalizada e maiúscula', () {
      final v = ContentService.hashtagCaseVariants('brasil');
      expect(v, containsAll(<String>['brasil', 'Brasil', 'BRASIL']));
      expect(v.length, 3, reason: 'sem duplicatas');
    });

    test('já maiúscula não gera duplicata', () {
      final v = ContentService.hashtagCaseVariants('BRASIL');
      expect(v.length, 3);
      expect(v, containsAll(<String>['BRASIL', 'Brasil', 'brasil']));
    });

    test('tag vazia não quebra', () {
      expect(ContentService.hashtagCaseVariants(''), isNotEmpty);
      expect(ContentService.hashtagCaseVariants('').length, 1);
    });

    test('tag com acento e número é preservada', () {
      final v = ContentService.hashtagCaseVariants('musica2');
      expect(v, contains('musica2'));
      expect(v, contains('Musica2'));
    });
  });

  group('consulta sem hashtag utilizável', () {
    test('tag só com # devolve lista vazia sem tocar no banco', () async {
      expect(await ContentService.instance.fetchPostsByHashtag('#'), isEmpty);
      expect(await ContentService.instance.fetchPostsByHashtag('  '), isEmpty);
      expect(await ContentService.instance.countPostsByHashtag('#'), 0);
    });

    test('id de post vazio devolve null', () async {
      expect(await ContentService.instance.fetchPostById(''), isNull);
    });
  });
}
