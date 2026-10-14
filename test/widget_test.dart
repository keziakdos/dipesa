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
      final a = Account('a', 'Perso', 'bank', 0, scope: 'personal');
      final b = Account('b', 'Commun', 'bank', 0, scope: 'joint');
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

  group('Migration v1 → v2 (phase 2)', () {
    Map<String, dynamic> v1doc() => {
          'version': 1,
          'accounts': [
            {'id': 'a1', 'name': 'Perso', 'type': 'bank', 'limit': 0},
            {'id': 'a2', 'name': 'Commun', 'type': 'bank', 'limit': 0},
          ],
          'categories': [
            {'id': 'c1', 'name': 'Alimentation', 'icon': 'food', 'color': 'orange'},
          ],
          'entries': [
            {
              'id': 'e1',
              'kind': 'adjustment',
              'account': 'a1',
              'destination': null,
              'category': null,
              'project': null,
              'amount': 100000,
              'date': '2026-01-05',
              'note': 'Solde initial',
            },
          ],
          'projects': [],
          'allocations': [],
          'budgets': <String, int>{},
        };

    test('migre sans perte et ajoute scope/auteur/foyer', () {
      final store = BudgetStore();
      final migrated = store.migrateV1ToV2(v1doc());
      expect(migrated['version'], 2);
      final accounts = migrated['accounts'] as List;
      expect(accounts.length, 2);
      expect(accounts[0]['scope'], 'personal');
      expect(accounts[0]['initialDate'], '2026-01-05');
      final entries = migrated['entries'] as List;
      expect(entries[0]['scope'], 'personal');
      expect(entries[0]['author'], 'me');
      final categories = migrated['categories'] as List;
      expect(
        categories.any((c) =>
            ((c as Map)['name'] as String).toLowerCase() ==
            'contribution au foyer'),
        isTrue,
      );
      expect((migrated['contributions'] as List), isEmpty);
    });

    test('load(v1) puis validate() OK', () {
      final store = BudgetStore();
      store.load(v1doc());
      store.validate();
      expect(store.accounts.length, 2);
      expect(store.net, 100000);
    });

    test('contribution reçue partielle invalide', () {
      final store = BudgetStore();
      store.seed();
      final joint =
          Account('j', 'Commun', 'bank', 0, scope: 'joint');
      store.accounts.add(joint);
      store.contributions.add(Contribution(
        id: 'k1',
        person: 'wife',
        expected: 50000,
        received: 10000,
        dueDate: DateTime(2026, 10, 1),
        status: 'reçu',
        accountId: 'j',
      ));
      expect(() => store.validate(), throwsException);
    });
  });

  group('Périmètres (phase 2)', () {
    test('liquidFor sépare personnel et commun', () {
      final store = BudgetStore();
      store.seed();
      final p = Account('p', 'Perso', 'bank', 0, scope: 'personal');
      final j = Account('j', 'Commun', 'bank', 0, scope: 'joint');
      store.accounts.addAll([p, j]);
      store.entries.addAll([
        Entry(
            id: 'e1',
            kind: 'adjustment',
            account: 'p',
            amount: 100000,
            date: DateTime(2026, 1, 1),
            scope: 'personal'),
        Entry(
            id: 'e2',
            kind: 'adjustment',
            account: 'j',
            amount: 50000,
            date: DateTime(2026, 1, 1),
            scope: 'joint'),
        Entry(
            id: 'e3',
            kind: 'expense',
            account: 'j',
            amount: 8500,
            date: DateTime(2026, 10, 2),
            category: store.categories.first.id,
            scope: 'joint',
            author: 'wife'),
      ]);
      expect(store.liquidFor('personal'), 100000);
      expect(store.liquidFor('joint'), 41500);
      expect(store.liquidFor('all'), 141500);
      expect(
          store.monthly('expense', DateTime(2026, 10, 1),
              scope: 'joint', author: 'wife'),
          8500);
      expect(store.history(scope: 'joint').length, 2);
    });
  });

  group('Contributions (phase 3)', () {
    BudgetStore jointStore() {
      final store = BudgetStore();
      store.seed();
      store.accounts.addAll([
        Account('p', 'Perso', 'bank', 0, scope: 'personal'),
        Account('j', 'Commun', 'bank', 0, scope: 'joint'),
      ]);
      store.entries.add(Entry(
        id: 'init-p',
        kind: 'adjustment',
        account: 'p',
        amount: 200000,
        date: DateTime(2026, 9, 1),
        scope: 'personal',
      ));
      return store;
    }

    test('attente ne modifie pas le solde', () {
      final store = jointStore();
      store.planContribution(
        person: 'wife',
        expected: 50000,
        dueDate: DateTime(2026, 10, 5),
        accountId: 'j',
      );
      expect(store.balance(store.account('j')), 0);
      expect(store.contributions.single.status, 'attendu');
      store.validate();
    });

    test('mon versement = transfert neutre au consolidé', () {
      final store = jointStore();
      store.planContribution(
        person: 'me',
        expected: 50000,
        dueDate: DateTime(2026, 10, 5),
        accountId: 'j',
      );
      final c = store.contributions.single;
      store.confirmContributionReceived(
        contributionId: c.id,
        amountNow: 50000,
        date: DateTime(2026, 10, 5),
        sourceAccountId: 'p',
      );
      expect(store.balance(store.account('p')), 150000);
      expect(store.balance(store.account('j')), 50000);
      expect(store.net, 200000);
      // Ni dépense ni revenu consolidé.
      expect(store.monthly('expense', DateTime(2026, 10, 1)), 0);
      expect(store.monthly('income', DateTime(2026, 10, 1)), 0);
      store.validate();
    });

    test('confirmation idempotente : pas de double écriture', () {
      final store = jointStore();
      store.planContribution(
        person: 'wife',
        expected: 50000,
        dueDate: DateTime(2026, 10, 5),
        accountId: 'j',
      );
      final c = store.contributions.single;
      store.confirmContributionReceived(
        contributionId: c.id,
        amountNow: 30000,
        date: DateTime(2026, 10, 5),
      );
      final countAfterFirst =
          store.entries.where((e) => e.contributionId == c.id).length;
      store.confirmContributionReceived(
        contributionId: store.contributions.single.id,
        amountNow: 20000,
        date: DateTime(2026, 10, 6),
      );
      final linked =
          store.entries.where((e) => e.contributionId == c.id).toList();
      expect(countAfterFirst, 1);
      expect(linked.length, 1);
      expect(linked.single.amount, 50000);
      expect(linked.single.kind, 'income');
      expect(store.contributions.single.status, 'reçu');
      expect(store.balance(store.account('j')), 50000);
      store.validate();
    });

    test('partiel puis annulation', () {
      final store = jointStore();
      store.planContribution(
        person: 'wife',
        expected: 50000,
        dueDate: DateTime(2026, 10, 5),
        accountId: 'j',
      );
      final c = store.contributions.single;
      store.confirmContributionReceived(
        contributionId: c.id,
        amountNow: 20000,
        date: DateTime(2026, 10, 5),
      );
      expect(store.contributions.single.status, 'partiel');
      expect(store.balance(store.account('j')), 20000);
      store.cancelContributionReceived(c.id);
      expect(store.contributions.single.status, 'attendu');
      expect(store.contributions.single.received, 0);
      expect(store.entries.where((e) => e.contributionId == c.id), isEmpty);
      expect(store.balance(store.account('j')), 0);
      store.validate();
    });

    test('dépense commune 85 € par ma femme : pas de dette', () {
      final store = jointStore();
      store.entries.add(Entry(
        id: 'courses',
        kind: 'expense',
        account: 'j',
        category: store.categories.first.id,
        amount: 8500,
        date: DateTime(2026, 10, 7),
        scope: 'joint',
        author: 'wife',
      ));
      // Compte commun débité, indicateur de dépenses augmenté, rien d'autre.
      expect(store.balance(store.account('j')), -8500);
      expect(store.monthly('expense', DateTime(2026, 10, 1), scope: 'joint'),
          8500);
      expect(
          store.monthly('expense', DateTime(2026, 10, 1),
              scope: 'joint', author: 'wife'),
          8500);
      expect(store.contributions, isEmpty);
      store.validate();
    });
  });

  group('Indicateurs et écrans (phase 4)', () {
    BudgetStore mixedStore() {
      final store = BudgetStore();
      store.seed();
      store.accounts.addAll([
        Account('cc', 'Courant', 'bank', 0, scope: 'personal'),
        Account('ep', 'Livret', 'savings', 0, scope: 'personal'),
        Account('jc', 'Commun courant', 'bank', 0, scope: 'joint'),
        Account('carte', 'Carte', 'credit', 100000, scope: 'personal'),
        Account('pret', 'Prêt maison', 'loan', 0, scope: 'personal'),
      ]);
      store.entries.addAll([
        Entry(
            id: 'a1',
            kind: 'adjustment',
            account: 'cc',
            amount: 100000,
            date: DateTime(2026, 9, 1),
            scope: 'personal'),
        Entry(
            id: 'a2',
            kind: 'adjustment',
            account: 'ep',
            amount: 50000,
            date: DateTime(2026, 9, 1),
            scope: 'personal'),
        Entry(
            id: 'a3',
            kind: 'adjustment',
            account: 'jc',
            amount: 80000,
            date: DateTime(2026, 9, 1),
            scope: 'joint'),
        Entry(
            id: 'a4',
            kind: 'adjustment',
            account: 'carte',
            amount: -20000,
            date: DateTime(2026, 9, 1),
            scope: 'personal'),
        Entry(
            id: 'a5',
            kind: 'adjustment',
            account: 'pret',
            amount: -150000,
            date: DateTime(2026, 9, 1),
            scope: 'personal'),
      ]);
      return store;
    }

    test('intitulés validés : disponible, épargné, liquidités', () {
      final store = mixedStore();
      expect(store.checkingFor('personal'), 100000);
      expect(store.savingsFor('personal'), 50000);
      // Total liquidités = courants + épargne (+ espèces), jamais le crédit.
      expect(store.liquidFor('personal'), 150000);
      expect(store.liquidFor('joint'), 80000);
      expect(store.liquidFor('all'), 230000);
      // Dettes séparées, non soustraites des liquidités.
      expect(store.debts, 170000);
      store.validate();
    });

    test('migration v2 → v3 : scope projet par défaut', () {
      final store = BudgetStore();
      final v2 = {
        'version': 2,
        'accounts': [],
        'categories': [],
        'entries': [],
        'projects': [
          {
            'id': 'p1',
            'name': 'Chauffage',
            'icon': 'pig',
            'color': 'mint',
            'target': 100000,
            'deadline': null,
          },
        ],
        'allocations': [],
        'contributions': [],
        'budgets': <String, int>{},
      };
      store.load(v2);
      expect(store.projects.single.scope, 'personal');
      store.validate();
    });

    test('projets : courants uniquement + périmètre', () {
      final store = mixedStore();
      store.projects.add(Project(
        'p1',
        'Chauffage',
        'pig',
        'mint',
        60000,
        null,
        scope: 'personal',
      ));
      // Disponible projets = courants personnels − réservations.
      expect(store.projectAvailableFor('personal'), 100000);
      store.allocations.add(Allocation('p1', 40000, DateTime(2026, 10, 1)));
      expect(store.reservedFor('personal'), 40000);
      expect(store.projectAvailableFor('personal'), 60000);
      // Dépense épargne liée à un projet refusée (courants uniquement).
      store.entries.add(Entry(
        id: 'bad',
        kind: 'expense',
        account: 'ep',
        category: store.categories.first.id,
        project: 'p1',
        amount: 1000,
        date: DateTime(2026, 10, 2),
        scope: 'personal',
      ));
      expect(() => store.validate(), throwsException);
    });
  });
}
