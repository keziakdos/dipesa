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

  group('Échéances et crédits (phase 5)', () {
    BudgetStore loanStore() {
      final store = BudgetStore();
      store.seed();
      store.accounts.addAll([
        Account('src', 'Courant', 'bank', 0, scope: 'personal'),
        Account('card', 'Carte', 'credit', 50000, scope: 'personal'),
      ]);
      store.entries.addAll([
        Entry(
          id: 'init',
          kind: 'adjustment',
          account: 'src',
          amount: 300000,
          date: DateTime(2026, 9, 1),
          scope: 'personal',
        ),
        Entry(
          id: 'init-card',
          kind: 'adjustment',
          account: 'card',
          amount: -20000,
          date: DateTime(2026, 9, 1),
          scope: 'personal',
        ),
      ]);
      return store;
    }

    test('prévu ne modifie pas le solde', () {
      final store = loanStore();
      store.planDue(
        label: 'Électricité',
        kind: 'bill',
        total: 8000,
        dueDate: DateTime(2026, 11, 5),
        accountId: 'src',
        scope: 'personal',
      );
      expect(store.balance(store.account('src')), 300000);
      expect(store.upcomingDues().single.status, 'prévu');
      store.validate();
    });

    test('mensualité ventilée : dette −capital, charges en dépenses', () {
      final store = loanStore();
      store.planLoan(
        name: 'Maison',
        initialAmount: 20000000,
        startDate: DateTime(2026, 9, 1),
        annualRate: 3.0,
        months: 240,
        monthly: 90000,
        insuranceMonthly: 10000,
        feesMonthly: 0,
        sourceAccountId: 'src',
        scope: 'personal',
      );
      final loan = store.loans.single;
      final split = store.loanSplit(loan, 20000000);
      final capital = split['capital']!;
      final interest = split['interest']!;
      expect(capital + interest, 90000);
      store.planDue(
        label: 'Mensualité maison',
        kind: 'loan',
        total: 100000,
        capital: capital,
        interest: interest,
        insurance: 10000,
        fees: 0,
        dueDate: DateTime(2026, 10, 5),
        accountId: 'src',
        scope: 'personal',
        loanId: loan.id,
      );
      final due = store.dues.single;
      store.settleDue(dueId: due.id, date: DateTime(2026, 10, 5));
      // Compte source débité du total ; dette réduite du capital seul.
      expect(store.balance(store.account('src')), 300000 - 100000);
      expect(store.balance(store.account(loan.debtAccountId)),
          -20000000 + capital);
      // Dépenses = intérêts + assurance, pas le capital.
      expect(store.monthly('expense', DateTime(2026, 10, 1)),
          interest + 10000);
      // Sorties de trésorerie = paiement total.
      expect(store.cashOut(DateTime(2026, 10, 1)), 100000);
      // Idempotence : second appel ne rejoue rien.
      final count = store.entries.length;
      store.settleDue(dueId: due.id, date: DateTime(2026, 10, 5));
      expect(store.entries.length, count);
      store.validate();
    });

    test('carte 50 € = transfert mensuel, pas un prêt immo', () {
      final store = loanStore();
      store.planDue(
        label: 'Carte 50 €',
        kind: 'card',
        total: 5000,
        dueDate: DateTime(2026, 10, 5),
        accountId: 'src',
        scope: 'personal',
        recurrence: 'monthly',
      );
      final first = store.upcomingDues().single;
      store.settleDue(dueId: first.id, date: DateTime(2026, 10, 5));
      expect(store.monthly('expense', DateTime(2026, 10, 1)), 0);
      expect(store.balance(store.account('src')), 300000 - 5000);
      expect(store.balance(store.account('card')), -20000 + 5000);
      // Récurrence : échéance suivante générée en prévu.
      expect(store.upcomingDues().length, 1);
      expect(store.upcomingDues().single.dueDate.month, 11);
      store.validate();
    });

    test('migration v3 → v4 : dues et loans vides', () {
      final store = BudgetStore();
      store.load({
        'version': 3,
        'accounts': [],
        'categories': [],
        'entries': [],
        'projects': [],
        'allocations': [],
        'contributions': [],
        'budgets': <String, int>{},
      });
      expect(store.dues, isEmpty);
      expect(store.loans, isEmpty);
      store.validate();
    });
  });

  group('Sauvegardes et sync (phase 6)', () {
    test('auto-backup tous les 5 jours + rattrapage', () {
      final now = DateTime(2026, 10, 14, 12);
      expect(shouldAutoBackup(null, now), isTrue);
      expect(
          shouldAutoBackup(now.subtract(const Duration(days: 6)), now),
          isTrue);
      expect(
          shouldAutoBackup(now.subtract(const Duration(days: 4)), now),
          isFalse);
      expect(
          shouldAutoBackup(now.subtract(const Duration(hours: 119)), now),
          isFalse);
      expect(
          shouldAutoBackup(now.subtract(const Duration(hours: 121)), now),
          isTrue);
    });

    test('rotation : 12 snapshots, suppression séparée', () {
      final names =
          List.generate(15, (i) => '/x/${snapshotName(1000 + i)}');
      final doomed = pruneSnapshots(names);
      expect(doomed.length, 3);
      expect(names.length - doomed.length, 12);
      // Les plus anciens partent en premier.
      expect(doomed.first.endsWith(snapshotName(1000)), isTrue);
      expect(pruneSnapshots(names.sublist(0, 12)), isEmpty);
    });

    test('toJson v4 contient dues et loans', () {
      final store = BudgetStore();
      store.seed();
      final json = store.toJson();
      expect(json['version'], 4);
      expect(json['dues'], isEmpty);
      expect(json['loans'], isEmpty);
    });
  });

  group('Sécurité (phase 7)', () {
    test('PIN : exactement 4 chiffres', () {
      expect(validPin('1234'), isTrue);
      expect(validPin('123456'), isFalse);
      expect(validPin('123'), isFalse);
      expect(validPin('12a4'), isFalse);
      expect(validPin(''), isFalse);
    });

    test('code de récupération : format + normalisation', () {
      final code = generateRecoveryCode();
      expect(code.length, 19);
      expect(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$').hasMatch(code),
          isTrue);
      expect(normalizeRecoveryCode(code.toLowerCase().replaceAll('-', ' ')),
          normalizeRecoveryCode(code));
      expect(normalizeRecoveryCode(code).length, 16);
      expect(generateRecoveryCode() != generateRecoveryCode(), isTrue);
    });

    test('wrap/unwrap de la clé : le code rétablit réellement', () async {
      final dbKey = randomBytes(32);
      const code = 'ABCD-EFGH-JKLM-NPQR';
      final salt = randomBytes(16);
      final wrapKey =
          await passwordKey(normalizeRecoveryCode(code), salt);
      final envelope = await encrypt(dbKey, wrapKey);
      final reopen = await passwordKey(
          normalizeRecoveryCode('abcd efgh jklm npqr'), salt);
      expect(await decrypt(envelope, reopen), dbKey);
    });

    test('mauvais code : déchiffrement impossible', () async {
      final dbKey = randomBytes(32);
      final salt = randomBytes(16);
      final envelope = await encrypt(
          dbKey, await passwordKey('ABCDEFGHJKLMNPQR', salt));
      final wrong =
          await passwordKey('ZZZZZZZZZZZZZZZZ', salt);
      expect(() => decrypt(envelope, wrong), throwsA(anything));
    });

    test('formats d’export : actuel + ancien acceptés', () {
      expect(currentBackupFormat, 'dipesa-backup-1');
      expect(backupFormats, contains(legacyBackupFormat));
      expect(backupFormats, contains(currentBackupFormat));
    });
  });
}
