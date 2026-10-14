import 'package:flutter_test/flutter_test.dart';

import 'package:mon_capital/main.dart';

void main() {
  group('Montants', () {
    test('euro() formate en français', () {
      expect(euro(0), '0,00 €');
      expect(euro(8500), '85,00 €');
      expect(euro(-8500), '−85,00 €');
      expect(euro(123456), '1 234,56 €');
    });

    test('money() accepte virgule et espaces', () {
      expect(money('85'), 8500);
      expect(money('85,50'), 8550);
      expect(money('1 234,56'), 123456);
      expect(money('-12,30', signed: true), -1230);
      expect(() => money(''), throwsException);
      expect(() => money('12.345'), throwsException);
    });
  });

  group('Dates', () {
    test('dateText/parseDate aller-retour', () {
      final d = DateTime(2026, 10, 14);
      expect(dateText(d), '2026-10-14');
      expect(parseDate('2026-10-14'), d);
      expect(() => parseDate('14/10/2026'), throwsException);
    });

    test('monthKey et sameMonth', () {
      expect(monthKey(DateTime(2026, 3, 15)), '2026-03');
      expect(sameMonth(DateTime(2026, 3, 1), DateTime(2026, 3, 31)), isTrue);
      expect(sameMonth(DateTime(2026, 3, 1), DateTime(2026, 4, 1)), isFalse);
    });
  });

  group('Indicateurs invariants (phase 0)', () {
    test('un transfert interne est neutre pour le consolidé', () {
      final store = BudgetStore();
      store.seed();
      final a = Account('a', 'Perso', 'bank', 0);
      final b = Account('b', 'Commun', 'bank', 0);
      store.accounts.addAll([a, b]);
      store.entries.add(Entry(
        id: 'init-a',
        kind: 'adjustment',
        account: 'a',
        amount: 100000,
        date: DateTime(2026, 1, 1),
      ));
      store.entries.add(Entry(
        id: 't1',
        kind: 'transfer',
        account: 'a',
        destination: 'b',
        amount: 20000,
        date: DateTime(2026, 1, 2),
      ));
      // Consolidé inchangé : 1000 € avant comme après.
      expect(store.net, 100000);
      expect(store.balance(a), 80000);
      expect(store.balance(b), 20000);
    });
  });
}
