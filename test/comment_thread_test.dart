import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/models/post_models.dart';

/// Regras de exibição de comentário que a sheet de comentários depende.
///
/// A thread virou real nesta fatia: o `parentId` que já existia no banco é
/// enviado pelo cliente e volta em `parentCommentId`, que é o que recua a
/// resposta na lista. Estes testes travam esse contrato.
void main() {
  PostComment cmt({required String id, String? parentId, int likes = 0}) {
    return PostComment(
      id: id,
      postId: 'p1',
      parentId: parentId,
      text: 'texto',
      createdAt: DateTime(2026, 1, 1),
      likesCount: likes,
    );
  }

  group('thread', () {
    test('comentário raiz não tem pai', () {
      expect(cmt(id: 'a').parentId, isNull);
    });

    test('resposta carrega o id do pai', () {
      expect(cmt(id: 'b', parentId: 'a').parentId, 'a');
    });

    test('fromJson le parent_id, likes_count e liked_by_me', () {
      final c = PostComment.fromJson(<String, dynamic>{
        'id': 'c1',
        'post_id': 'p1',
        'parent_id': 'a',
        'text': 'oi',
        'created_at': '2026-01-01T00:00:00.000Z',
        'likes_count': 7,
        'liked_by_me': true,
      });
      expect(c.parentId, 'a');
      expect(c.likesCount, 7);
      expect(c.likedByMe, isTrue);
    });

    test('ausência de likes_count e liked_by_me não quebra', () {
      final c = PostComment.fromJson(<String, dynamic>{
        'id': 'c2',
        'post_id': 'p1',
        'text': 'oi',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(c.likesCount, 0);
      expect(c.likedByMe, isFalse);
      expect(c.parentId, isNull);
    });
  });
}
