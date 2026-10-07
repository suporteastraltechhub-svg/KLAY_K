import 'package:flutter_test/flutter_test.dart';
import 'package:klay_k/models/store_extras_models.dart';

void main() {
  group('StoreFavorite', () {
    Map<String, dynamic> row({bool isActive = true, int stock = 5}) => {
      'favorite_id': 'f1',
      'product_id': 'p1',
      'title': 'Caneca KLAY K',
      'description': 'Caneca oficial',
      'price': 49.9,
      'image_url': 'https://x/y.png',
      'stock': stock,
      'is_active': isActive,
      'category_name': 'Merch',
      'seller_id': 's1',
      'created_at': '2026-09-29T12:00:00Z',
    };

    test('lê a linha da RPC sem perder campo', () {
      final f = StoreFavorite.fromRow(row());
      expect(f.favoriteId, 'f1');
      expect(f.productId, 'p1');
      expect(f.title, 'Caneca KLAY K');
      expect(f.price, 49.9);
      expect(f.stock, 5);
      expect(f.categoryName, 'Merch');
      expect(f.isActive, isTrue);
    });

    test('valores ausentes viram padrão seguro, não erro', () {
      final f = StoreFavorite.fromRow(const {'product_id': 'p9'});
      expect(f.favoriteId, '');
      expect(f.title, '');
      expect(f.price, 0);
      expect(f.isActive, isTrue, reason: 'sem dado, assume ativo');
    });

    test('produto desativado ou sem estoque fica indisponível', () {
      expect(StoreFavorite.fromRow(row(isActive: false)).unavailable, isTrue);
      expect(StoreFavorite.fromRow(row(stock: 0)).unavailable, isTrue);
      expect(StoreFavorite.fromRow(row()).unavailable, isFalse);
    });

    test('preço sai com 2 casas', () {
      expect(StoreFavorite.fromRow(row()).priceLabel, '49.90');
    });
  });

  group('StoreAddress', () {
    Map<String, dynamic> row() => {
      'id': 'a1',
      'label': 'Casa',
      'recipient': 'Ana',
      'phone': '11988887777',
      'street': 'Rua das Flores',
      'number': '120',
      'complement': 'Apto 3',
      'district': 'Centro',
      'city': 'São Paulo',
      'state': 'SP',
      'zip_code': '01001000',
      'country': 'BR',
      'is_default': true,
    };

    test('lê todos os campos', () {
      final a = StoreAddress.fromRow(row());
      expect(a.id, 'a1');
      expect(a.recipient, 'Ana');
      expect(a.street, 'Rua das Flores');
      expect(a.city, 'São Paulo');
      expect(a.state, 'SP');
      expect(a.zipCode, '01001000');
      expect(a.isDefault, isTrue);
    });

    test('oneLine junta logradouro e cidade', () {
      expect(
        StoreAddress.fromRow(row()).oneLine,
        'Rua das Flores, 120, Apto 3 — Centro · São Paulo · SP',
      );
    });

    test('endereço incompleto é detectado como vazio', () {
      final a = StoreAddress.fromRow(const {
        'id': 'a2',
        'street': 'Rua A',
        'number': '1',
        'city': '', // falta cidade
      });
      expect(a.isEmpty, isTrue);
    });

    test('toRow envia o que o backend espera e nunca user_id', () {
      final a = StoreAddress.fromRow(row()).toRow();
      expect(a.containsKey('user_id'), isFalse);
      expect(a['street'], 'Rua das Flores');
      expect(a['zip_code'], '01001000');
      expect(a['country'], 'BR');
    });

    test('copyWith preserva o que não mudou', () {
      final a = StoreAddress.fromRow(row());
      final b = a.copyWith(label: 'Trabalho');
      expect(b.label, 'Trabalho');
      expect(b.id, a.id);
      expect(b.city, a.city);
      expect(b.zipCode, a.zipCode);
    });
  });

  group('StorePaymentMethod', () {
    Map<String, dynamic> row({String kind = 'card'}) => {
      'id': 'm1',
      'kind': kind,
      'label': '',
      'brand': 'Visa',
      'last4': '4242',
      'holder': 'ANA S',
      'expiry_month': 12,
      'expiry_year': 2030,
      'is_default': true,
    };

    test('lê cartão sem guardar segredo', () {
      final m = StorePaymentMethod.fromRow(row());
      expect(m.isCard, isTrue);
      expect(m.brand, 'Visa');
      expect(m.last4, '4242');
      expect(m.holder, 'ANA S');
      expect(m.expiryMonth, 12);
      expect(m.expiryYear, 2030);
    });

    test('displayLabel usa a bandeira quando não há rótulo', () {
      expect(
        StorePaymentMethod.fromRow(row()).displayLabel,
        'Visa ••4242',
      );
    });

    test('toRow NUNCA envia número de cartão, CVV ou token', () {
      final m = StorePaymentMethod.fromRow(row()).toRow();
      for (final forbidden in [
        'number',
        'card_number',
        'cvv',
        'cvc',
        'security_code',
        'gateway_token',
      ]) {
        expect(
          m.containsKey(forbidden),
          isFalse,
          reason: '$forbidden não pode ir para o banco',
        );
      }
      expect(m['last4'], '4242', reason: 'só os 4 últimos dígitos');
    });

    test('last4 com tamanho errado é descartado pelo toRow', () {
      final m = StorePaymentMethod.fromRow(row()).copyWith(last4: '42424242');
      expect(m.toRow()['last4'], '');
    });

    test('detecta cartão vencido', () {
      final vencido = StorePaymentMethod.fromRow(row())
          .copyWith(expiryMonth: 1, expiryYear: 2020);
      expect(vencido.isExpired, isTrue);
      final valido = StorePaymentMethod.fromRow(row());
      expect(valido.isExpired, isFalse);
    });

    test('PIX nunca expira', () {
      final pix = StorePaymentMethod.fromRow(
        row(kind: 'pix'),
      ).copyWith(expiryMonth: 1, expiryYear: 2020);
      expect(pix.isExpired, isFalse);
      expect(pix.displayLabel, 'PIX');
    });

    test('kind desconhecido cai em other, não quebra', () {
      final m = StorePaymentMethod.fromRow(row(kind: 'bitcoin'));
      expect(m.kind, StorePaymentKind.other);
      expect(m.displayLabel, 'Outro');
    });
  });

  group('StorePrivacy', () {
    test('padrão é privado: nada aparece publicamente', () {
      const p = StorePrivacy();
      expect(p.showPurchasesOnProfile, isFalse);
      expect(p.showOrdersPublicly, isFalse);
    });

    test('fromMap tolera chaves ausentes e mantém privado', () {
      final p = StorePrivacy.fromMap(const {});
      expect(p.showPurchasesOnProfile, isFalse);
      expect(p.showOrdersPublicly, isFalse);
    });

    test('copyWith alterna só o campo pedido', () {
      const p = StorePrivacy();
      final q = p.copyWith(showOrdersPublicly: true);
      expect(q.showOrdersPublicly, isTrue);
      expect(q.showPurchasesOnProfile, isFalse);
    });
  });
}