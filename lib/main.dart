import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const blue = Color(0xFF49B6F5);
const mint = Color(0xFF00CFA0);
const violet = Color(0xFF8271ED);
const background = Color(0xFFF5F7FC);
const ink = Color(0xFF243249);

const accountTypes = <String, String>{
  'bank': 'Compte courant',
  'savings': 'Épargne',
  'cash': 'Espèces',
  'credit': 'Carte de crédit',
  'prepaid': 'Portefeuille prépayé',
  'investment': 'Placement — valeur manuelle',
};

const scopes = <String, String>{
  'personal': 'Personnel',
  'joint': 'Commun',
};

const scopeFilters = <String, String>{
  'all': 'Tout',
  'personal': 'Personnel',
  'joint': 'Commun',
};

const authors = <String, String>{
  'me': 'Moi',
  'wife': 'Ma femme',
};

const categoryIcons = <String, IconData>{
  'salary': Icons.work_rounded,
  'home': Icons.home_rounded,
  'food': Icons.shopping_basket_rounded,
  'lunch': Icons.restaurant_rounded,
  'car': Icons.directions_car_rounded,
  'transport': Icons.train_rounded,
  'health': Icons.favorite_rounded,
  'outing': Icons.celebration_rounded,
  'gift': Icons.card_giftcard_rounded,
  'ai': Icons.smart_toy_rounded,
  'api': Icons.code_rounded,
  'web': Icons.language_rounded,
  'software': Icons.devices_rounded,
  'heat': Icons.local_fire_department_rounded,
  'travel': Icons.flight_rounded,
  'pig': Icons.savings_rounded,
  'basket': Icons.shopping_bag_rounded,
  'other': Icons.category_rounded,
};

const iconNames = <String, String>{
  'salary': '💼 Travail',
  'home': '🏠 Maison',
  'food': '🛒 Alimentation',
  'lunch': '🍽️ Restaurant',
  'car': '🚗 Voiture',
  'transport': '🚆 Transport',
  'health': '❤️ Santé',
  'outing': '🎉 Sortie',
  'gift': '🎁 Cadeau',
  'ai': '🤖 Intelligence artificielle',
  'api': '💻 API / code',
  'web': '🌐 Site internet',
  'software': '📱 Logiciel',
  'heat': '🔥 Chauffage',
  'travel': '✈️ Voyage',
  'pig': '🐷 Tirelire',
  'basket': '🛍️ Panier',
  'other': '🔷 Autre',
};

const colors = <String, Color>{
  'blue': blue,
  'mint': mint,
  'violet': violet,
  'orange': Color(0xFFF6B543),
  'pink': Color(0xFFEF86AD),
};

const colorNames = <String, String>{
  'blue': 'Bleu ciel',
  'mint': 'Vert menthe',
  'violet': 'Lavande',
  'orange': 'Orange',
  'pink': 'Rose',
};

String id() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';

String euro(int cents) {
  final value = (cents.abs() / 100).toStringAsFixed(2);
  final parts = value.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return '${cents < 0 ? "−" : ""}$whole,${parts[1]} €';
}

String amountText(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

int money(String input, {bool signed = false}) {
  final text = input.trim().replaceAll(' ', '').replaceAll(',', '.');
  final regex = signed
      ? RegExp(r'^-?\d+(\.\d{1,2})?$')
      : RegExp(r'^\d+(\.\d{1,2})?$');

  if (!regex.hasMatch(text)) {
    throw Exception('Saisissez un montant avec deux décimales maximum.');
  }

  final negative = text.startsWith('-');
  final parts = text.replaceFirst('-', '').split('.');
  final whole = int.parse(parts[0]);
  final fraction =
      parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;

  if (whole > 1000000000) {
    throw Exception('Montant trop élevé.');
  }
  return (whole * 100 + fraction) * (negative ? -1 : 1);
}

String dateText(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String text) {
  final value = DateTime.tryParse(text);
  if (value == null || dateText(value) != text) {
    throw Exception('Date invalide. Format attendu : AAAA-MM-JJ.');
  }
  return value;
}

String monthText(DateTime d) {
  const names = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];
  return '${names[d.month - 1]} ${d.year}';
}

String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

bool sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

List<int> randomBytes(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}

Future<SecretKey> passwordKey(String password, List<int> salt) {
  return Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
}

Future<Map<String, dynamic>> encrypt(
  List<int> bytes,
  SecretKey key,
) async {
  final box = await AesGcm.with256bits().encrypt(bytes, secretKey: key);
  return {
    'nonce': base64Encode(box.nonce),
    'mac': base64Encode(box.mac.bytes),
    'cipher': base64Encode(box.cipherText),
  };
}

Future<List<int>> decrypt(
  Map<String, dynamic> data,
  SecretKey key,
) {
  return AesGcm.with256bits().decrypt(
    SecretBox(
      base64Decode(data['cipher'] as String),
      nonce: base64Decode(data['nonce'] as String),
      mac: Mac(base64Decode(data['mac'] as String)),
    ),
    secretKey: key,
  );
}

bool constantEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}

Map<String, dynamic> jsonMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

class Account {
  final String id;
  final String name;
  final String type;
  final int limit;
  final String scope;
  final DateTime? initialDate;

  Account(
    this.id,
    this.name,
    this.type,
    this.limit, {
    this.scope = 'personal',
    this.initialDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'limit': limit,
        'scope': scope,
        'initialDate': initialDate == null ? null : dateText(initialDate!),
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        j['id'] as String,
        j['name'] as String,
        j['type'] as String,
        j['limit'] as int,
        scope: (j['scope'] as String?) ?? 'personal',
        initialDate: j['initialDate'] == null
            ? null
            : parseDate(j['initialDate'] as String),
      );
}

class Category {
  final String id;
  final String name;
  final String icon;
  final String color;

  Category(this.id, this.name, this.icon, this.color);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'icon': icon, 'color': color};

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        j['id'] as String,
        j['name'] as String,
        j['icon'] as String,
        j['color'] as String,
      );
}

class Entry {
  final String id;
  final String kind;
  final String account;
  final String? destination;
  final String? category;
  final String? project;
  final int amount;
  final DateTime date;
  final String note;
  final String scope;
  final String author;
  final String? contributionId;

  Entry({
    required this.id,
    required this.kind,
    required this.account,
    required this.amount,
    required this.date,
    this.destination,
    this.category,
    this.project,
    this.note = '',
    this.scope = 'personal',
    this.author = 'me',
    this.contributionId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'account': account,
        'destination': destination,
        'category': category,
        'project': project,
        'amount': amount,
        'date': dateText(date),
        'note': note,
        'scope': scope,
        'author': author,
        'contributionId': contributionId,
      };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        kind: j['kind'] as String,
        account: j['account'] as String,
        destination: j['destination'] as String?,
        category: j['category'] as String?,
        project: j['project'] as String?,
        amount: j['amount'] as int,
        date: parseDate(j['date'] as String),
        note: (j['note'] as String?) ?? '',
        scope: (j['scope'] as String?) ?? 'personal',
        author: (j['author'] as String?) ?? 'me',
        contributionId: j['contributionId'] as String?,
      );
}

class Project {
  final String id;
  final String name;
  final String icon;
  final String color;
  final int target;
  final DateTime? deadline;

  Project(
    this.id,
    this.name,
    this.icon,
    this.color,
    this.target,
    this.deadline,
  );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'target': target,
        'deadline': deadline == null ? null : dateText(deadline!),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        j['id'] as String,
        j['name'] as String,
        j['icon'] as String,
        j['color'] as String,
        j['target'] as int,
        j['deadline'] == null ? null : parseDate(j['deadline'] as String),
      );
}

class Allocation {
  final String project;
  final int amount;
  final DateTime date;

  Allocation(this.project, this.amount, this.date);

  Map<String, dynamic> toJson() => {
        'project': project,
        'amount': amount,
        'date': dateText(date),
      };

  factory Allocation.fromJson(Map<String, dynamic> j) => Allocation(
        j['project'] as String,
        j['amount'] as int,
        parseDate(j['date'] as String),
      );
}

class Contribution {
  final String id;
  final String person;
  final int expected;
  final int received;
  final DateTime dueDate;
  final DateTime? receivedDate;
  final String status;
  final String accountId;
  final String? entryId;

  Contribution({
    required this.id,
    required this.person,
    required this.expected,
    required this.received,
    required this.dueDate,
    this.receivedDate,
    required this.status,
    required this.accountId,
    this.entryId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'person': person,
        'expected': expected,
        'received': received,
        'dueDate': dateText(dueDate),
        'receivedDate':
            receivedDate == null ? null : dateText(receivedDate!),
        'status': status,
        'accountId': accountId,
        'entryId': entryId,
      };

  factory Contribution.fromJson(Map<String, dynamic> j) => Contribution(
        id: j['id'] as String,
        person: j['person'] as String,
        expected: j['expected'] as int,
        received: (j['received'] as int?) ?? 0,
        dueDate: parseDate(j['dueDate'] as String),
        receivedDate: j['receivedDate'] == null
            ? null
            : parseDate(j['receivedDate'] as String),
        status: j['status'] as String,
        accountId: j['accountId'] as String,
        entryId: j['entryId'] as String?,
      );
}

class BudgetStore extends ChangeNotifier {
  final FlutterSecureStorage secure = const FlutterSecureStorage();

  late File file;
  late SecretKey key;

  List<Account> accounts = [];
  List<Category> categories = [];
  List<Entry> entries = [];
  List<Project> projects = [];
  List<Allocation> allocations = [];
  List<Contribution> contributions = [];
  Map<String, int> budgets = {};

  bool saving = false;

  Future<void> open() async {
    final directory = await getApplicationSupportDirectory();
    file = File('${directory.path}/budget.enc');

    var encodedKey = await secure.read(key: 'database-key');
    if (encodedKey == null) {
      if (await file.exists()) {
        throw Exception(
          'La clé locale est introuvable. Ne supprimez pas votre sauvegarde.',
        );
      }
      encodedKey = base64Encode(randomBytes(32));
      await secure.write(key: 'database-key', value: encodedKey);
    }

    key = SecretKey(base64Decode(encodedKey));

    if (await file.exists()) {
      // Protection P2 : copie chiffrée telle quelle avant toute migration.
      final raw = await file.readAsString();
      final envelope = jsonMap(jsonDecode(raw));
      final bytes = await decrypt(envelope, key);
      final data = jsonMap(jsonDecode(utf8.decode(bytes)));
      if ((data['version'] as int?) == 1) {
        final backupFile =
            File('${file.path}.bak-${DateTime.now().millisecondsSinceEpoch}');
        await backupFile.writeAsString(raw, flush: true);
      }
      load(data);
      validate();
    } else {
      seed();
      await save();
    }
  }

  void seed() {
    accounts = [];
    entries = [];
    projects = [];
    allocations = [];
    contributions = [];
    budgets = {};

    categories = [
      Category(id(), 'Salaire', 'salary', 'mint'),
      Category(id(), 'Maison', 'home', 'blue'),
      Category(id(), 'Alimentation', 'food', 'orange'),
      Category(id(), 'Repas du midi', 'lunch', 'orange'),
      Category(id(), 'Voiture', 'car', 'blue'),
      Category(id(), 'Transport', 'transport', 'blue'),
      Category(id(), 'Santé', 'health', 'pink'),
      Category(id(), 'Sorties', 'outing', 'violet'),
      Category(id(), 'Cadeaux', 'gift', 'pink'),
      Category(id(), 'Contribution au foyer', 'home', 'mint'),
      Category(id(), 'Intelligence artificielle', 'ai', 'violet'),
      Category(id(), 'Crédits et consommation API', 'api', 'violet'),
      Category(id(), 'Sites et hébergement', 'web', 'blue'),
      Category(id(), 'Logiciels et abonnements', 'software', 'mint'),
      Category(id(), 'Chauffage et travaux', 'heat', 'orange'),
      Category(id(), 'Autres', 'other', 'blue'),
    ];
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'projects': projects.map((e) => e.toJson()).toList(),
        'allocations': allocations.map((e) => e.toJson()).toList(),
        'contributions': contributions.map((e) => e.toJson()).toList(),
        'budgets': budgets,
      };

  /// Migration v1 → v2 : ajoute scope/auteur, soldes initiaux datés,
  /// catégorie « Contribution au foyer ». Ne supprime rien.
  Map<String, dynamic> migrateV1ToV2(Map<String, dynamic> old) {
    final accountsJson = (old['accounts'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final entriesJson = (old['entries'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    var categoriesJson = (old['categories'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!categoriesJson.any(
        (c) => (c['name'] as String).toLowerCase() == 'contribution au foyer')) {
      categoriesJson.add(Category(id(), 'Contribution au foyer', 'home', 'mint')
          .toJson());
    }

    // Date de solde initial = date de la première écriture d'ajustement
    // « Solde initial » du compte, si elle existe.
    final initialByAccount = <String, String>{};
    for (final e in entriesJson) {
      if (e['kind'] == 'adjustment' &&
          (e['note'] as String?) == 'Solde initial' &&
          !initialByAccount.containsKey(e['account'])) {
        initialByAccount[e['account'] as String] = e['date'] as String;
      }
    }
    for (final a in accountsJson) {
      a['scope'] = 'personal';
      a['initialDate'] = initialByAccount[a['id']];
    }
    final scopeByAccount = {
      for (final a in accountsJson) a['id'] as String: 'personal',
    };
    for (final e in entriesJson) {
      e['scope'] = scopeByAccount[e['account']] ?? 'personal';
      e['author'] = 'me';
      e['contributionId'] = null;
    }

    return {
      'version': 2,
      'accounts': accountsJson,
      'categories': categoriesJson,
      'entries': entriesJson,
      'projects': old['projects'],
      'allocations': old['allocations'],
      'contributions': [],
      'budgets': old['budgets'],
    };
  }

  void load(Map<String, dynamic> j) {
    var data = j;
    if (data['version'] == 1) {
      data = migrateV1ToV2(data);
    }
    if (data['version'] != 2) {
      throw Exception('Version de sauvegarde non prise en charge.');
    }
    accounts = (data['accounts'] as List)
        .map((e) => Account.fromJson(jsonMap(e))).toList();
    categories = (data['categories'] as List)
        .map((e) => Category.fromJson(jsonMap(e))).toList();
    entries = (data['entries'] as List)
        .map((e) => Entry.fromJson(jsonMap(e))).toList();
    projects = (data['projects'] as List)
        .map((e) => Project.fromJson(jsonMap(e))).toList();
    allocations = (data['allocations'] as List)
        .map((e) => Allocation.fromJson(jsonMap(e))).toList();
    contributions = ((data['contributions'] as List?) ?? [])
        .map((e) => Contribution.fromJson(jsonMap(e))).toList();
    budgets = Map<String, int>.from(data['budgets'] as Map);
    ensureHomeContributionCategory();
  }

  void ensureHomeContributionCategory() {
    final exists = categories.any(
        (c) => c.name.toLowerCase() == 'contribution au foyer');
    if (!exists) {
      categories.add(Category(id(), 'Contribution au foyer', 'home', 'mint'));
    }
  }

  Future<void> save() async {
    final envelope = await encrypt(utf8.encode(jsonEncode(toJson())), key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(envelope), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> change(void Function() action) async {
    if (saving) throw Exception('Une sauvegarde est déjà en cours.');
    saving = true;
    final previous = jsonEncode(toJson());
    try {
      action();
      validate();
      await save();
      notifyListeners();
    } catch (_) {
      load(jsonMap(jsonDecode(previous)));
      rethrow;
    } finally {
      saving = false;
    }
  }

  Account account(String value) =>
      accounts.firstWhere((a) => a.id == value);

  Category? category(String? value) {
    for (final c in categories) {
      if (c.id == value) return c;
    }
    return null;
  }

  int impact(Entry e, String accountId) {
    if (e.kind == 'transfer') {
      if (e.account == accountId) return -e.amount;
      if (e.destination == accountId) return e.amount;
      return 0;
    }
    if (e.account != accountId) return 0;
    return e.kind == 'expense' ? -e.amount : e.amount;
  }

  int balance(Account a) =>
      entries.fold(0, (sum, e) => sum + impact(e, a.id));

  int get net => accounts.fold(0, (sum, a) => sum + balance(a));

  Iterable<Account> inScope(String filter) =>
      filter == 'all' ? accounts : accounts.where((a) => a.scope == filter);

  int netFor(String filter) =>
      inScope(filter).fold(0, (sum, a) => sum + balance(a));

  int liquidFor(String filter) => inScope(filter)
      .where(liquid)
      .fold(0, (sum, a) => sum + balance(a));

  int get assets => accounts.fold(
        0, (sum, a) => sum + max(0, balance(a)),
      );

  int get debts => accounts.fold(
        0, (sum, a) => sum + max(0, -balance(a)),
      );

  bool liquid(Account a) =>
      ['bank', 'savings', 'cash'].contains(a.type);

  int get liquidTotal => accounts
      .where(liquid)
      .fold(0, (sum, a) => sum + balance(a));

  int spent(Project p) => entries
      .where((e) => e.kind == 'expense' && e.project == p.id)
      .fold(0, (sum, e) => sum + e.amount);

  int funded(Project p) => allocations
      .where((a) => a.project == p.id)
      .fold(0, (sum, a) => sum + a.amount);

  int reserved(Project p) => funded(p) - spent(p);

  int get totalReserved =>
      projects.fold(0, (sum, p) => sum + reserved(p));

  int get available => liquidTotal - totalReserved;

  int monthly(
    String kind,
    DateTime month, {
    String? categoryId,
    String scope = 'all',
    String? author,
  }) {
    return entries
        .where((e) =>
            e.kind == kind &&
            sameMonth(e.date, month) &&
            (categoryId == null || e.category == categoryId) &&
            (scope == 'all' || e.scope == scope) &&
            (author == null || e.author == author))
        .fold(0, (sum, e) => sum + e.amount);
  }

  int budget(DateTime month, [String categoryId = 'all']) =>
      budgets['${monthKey(month)}:$categoryId'] ?? 0;

  List<Entry> history({
    String? accountId,
    String? projectId,
    String scope = 'all',
    String? author,
  }) {
    final result = entries.where((e) {
      if (accountId != null &&
          e.account != accountId &&
          e.destination != accountId) return false;
      if (projectId != null && e.project != projectId) return false;
      if (scope != 'all') {
        // Un transfert touche deux comptes : visible des deux côtés.
        if (e.kind == 'transfer') {
          final src = account(e.account).scope;
          final dst =
              e.destination == null ? src : account(e.destination!).scope;
          if (src != scope && dst != scope) return false;
        } else if (e.scope != scope) {
          return false;
        }
      }
      if (author != null && e.author != author) return false;
      return true;
    }).toList();
    result.sort((a, b) {
      final dateOrder = b.date.compareTo(a.date);
      return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
    });
    return result;
  }

  List<double> netHistory() {
    final now = DateTime.now();
    return List.generate(30, (i) {
      final end = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 29 - i))
          .add(const Duration(days: 1));

      var value = 0;
      for (final e in entries.where((e) => e.date.isBefore(end))) {
        if (e.kind == 'income' || e.kind == 'adjustment') {
          value += e.amount;
        } else if (e.kind == 'expense') {
          value -= e.amount;
        }
      }
      return value / 100;
    });
  }

  void validate() {
    final accountIds = accounts.map((e) => e.id).toSet();
    final categoryIds = categories.map((e) => e.id).toSet();
    final projectIds = projects.map((e) => e.id).toSet();
    final entryIds = entries.map((e) => e.id).toSet();
    final contributionIds = contributions.map((e) => e.id).toSet();

    if (accountIds.length != accounts.length ||
        categoryIds.length != categories.length ||
        projectIds.length != projects.length ||
        entryIds.length != entries.length ||
        contributionIds.length != contributions.length) {
      throw Exception('Identifiants dupliqués.');
    }

    for (final a in accounts) {
      if (!accountTypes.containsKey(a.type) || a.limit < 0) {
        throw Exception('Compte invalide.');
      }
      if (!scopes.containsKey(a.scope)) {
        throw Exception('Périmètre de compte invalide.');
      }
      if (a.type == 'credit' && balance(a) < -a.limit) {
        throw Exception('Le plafond de la carte ${a.name} serait dépassé.');
      }
    }

    for (final e in entries) {
      if (!accountIds.contains(e.account) ||
          !['income', 'expense', 'transfer', 'adjustment']
              .contains(e.kind)) {
        throw Exception('Opération invalide.');
      }
      if (!scopes.containsKey(e.scope) || !authors.containsKey(e.author)) {
        throw Exception('Périmètre ou auteur invalide.');
      }
      if (e.contributionId != null &&
          !contributionIds.contains(e.contributionId)) {
        throw Exception('Contribution liée introuvable.');
      }
      if (e.kind != 'adjustment' && e.amount <= 0) {
        throw Exception('Le montant doit être supérieur à zéro.');
      }
      if (e.kind == 'transfer' &&
          (!accountIds.contains(e.destination) ||
              e.destination == e.account)) {
        throw Exception('Choisissez deux comptes différents.');
      }
      if (['income', 'expense'].contains(e.kind) &&
          !categoryIds.contains(e.category)) {
        throw Exception('Catégorie invalide.');
      }
      if (e.project != null) {
        if (!projectIds.contains(e.project) ||
            e.kind != 'expense' ||
            !liquid(account(e.account))) {
          throw Exception(
            'Une dépense de projet doit utiliser un compte courant, '
            'épargne ou espèces.',
          );
        }
      }
      if (e.date.isAfter(DateTime.now())) {
        throw Exception('Les opérations futures ne sont pas encore gérées.');
      }
    }

    for (final c in contributions) {
      if (!authors.containsKey(c.person) ||
          !['attendu', 'partiel', 'reçu'].contains(c.status)) {
        throw Exception('Contribution invalide.');
      }
      if (!accountIds.contains(c.accountId)) {
        throw Exception('Compte commun de contribution introuvable.');
      }
      if (account(c.accountId).scope != 'joint') {
        throw Exception('Une contribution doit cibler un compte commun.');
      }
      if (c.expected <= 0 || c.received < 0) {
        throw Exception('Montants de contribution invalides.');
      }
      if (c.status == 'reçu' && c.received < c.expected) {
        throw Exception('Contribution marquée reçue mais partielle.');
      }
      if (c.entryId != null && !entryIds.contains(c.entryId)) {
        throw Exception('Écriture de contribution introuvable.');
      }
    }

    for (final a in allocations) {
      if (!projectIds.contains(a.project)) {
        throw Exception('Affectation de projet invalide.');
      }
    }

    for (final p in projects) {
      if (p.target <= 0 || reserved(p) < 0) {
        throw Exception(
          'La tirelire doit être suffisamment alimentée pour cette dépense.',
        );
      }
    }

    if (budgets.values.any((v) => v < 0)) {
      throw Exception('Un budget ne peut pas être négatif.');
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CapitalApp());
}

class CapitalApp extends StatefulWidget {
  const CapitalApp({super.key});

  @override
  State<CapitalApp> createState() => _CapitalAppState();
}

class _CapitalAppState extends State<CapitalApp>
    with WidgetsBindingObserver {
  final store = BudgetStore();
  final navigator = GlobalKey<NavigatorState>();
  bool unlocked = false;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void lock() {
    navigator.currentState?.popUntil((route) => route.isFirst);
    setState(() => unlocked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pausedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed && pausedAt != null) {
      final elapsed = DateTime.now().difference(pausedAt!);
      pausedAt = null;
      if (unlocked && elapsed.inSeconds >= 30) lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      title: 'DiPeSa',
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          primary: violet,
          secondary: mint,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: ink,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: mint.withOpacity(.18),
        ),
      ),
      home: unlocked
          ? Home(store: store, onLock: lock)
          : PinGate(
              store: store,
              onUnlocked: () => setState(() => unlocked = true),
            ),
    );
  }
}

class PinGate extends StatefulWidget {
  final BudgetStore store;
  final VoidCallback onUnlocked;

  const PinGate({
    super.key,
    required this.store,
    required this.onUnlocked,
  });

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  final pin = TextEditingController();
  final confirm = TextEditingController();
  final auth = LocalAuthentication();

  bool loading = true;
  bool busy = false;
  bool fresh = false;
  bool biometrics = false;
  String? error;
  int failures = 0;
  DateTime? blockedUntil;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      fresh = await widget.store.secure.read(key: 'pin-verifier') == null;
      biometrics =
          await widget.store.secure.read(key: 'biometrics') == 'true';
    } catch (_) {
      error = 'Impossible d’accéder au stockage sécurisé du téléphone.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> unlock({bool biometric = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });

    try {
      if (biometric) {
        final accepted = await auth.authenticate(
          localizedReason: 'Déverrouiller vos données financières',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        if (!accepted) return;
      } else if (fresh) {
        if (!RegExp(r'^\d{6}$').hasMatch(pin.text)) {
          throw Exception('Choisissez un PIN de 6 chiffres.');
        }
        if (pin.text != confirm.text) {
          throw Exception('Les deux codes ne correspondent pas.');
        }

        final salt = randomBytes(16);
        final derived = await passwordKey(pin.text, salt);
        await widget.store.secure.write(
          key: 'pin-verifier',
          value: jsonEncode({
            'salt': base64Encode(salt),
            'hash': base64Encode(await derived.extractBytes()),
          }),
        );
        fresh = false;
      } else {
        if (blockedUntil != null &&
            DateTime.now().isBefore(blockedUntil!)) {
          throw Exception('Patientez 30 secondes avant de réessayer.');
        }

        final raw =
            await widget.store.secure.read(key: 'pin-verifier');
        if (raw == null) throw Exception('Configuration du PIN introuvable.');

        final verifier = jsonMap(jsonDecode(raw));
        final derived = await passwordKey(
          pin.text,
          base64Decode(verifier['salt'] as String),
        );

        final accepted = constantEquals(
          await derived.extractBytes(),
          base64Decode(verifier['hash'] as String),
        );

        if (!accepted) {
          failures++;
          if (failures >= 5) {
            failures = 0;
            blockedUntil = DateTime.now().add(const Duration(seconds: 30));
          }
          throw Exception('Code PIN incorrect.');
        }
      }

      await widget.store.open();
      if (mounted) widget.onUnlocked();
    } catch (e) {
      if (mounted) {
        setState(() => error = cleanError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: mint,
                    child: Icon(
                      Icons.savings_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'DiPeSa',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(fresh
                      ? 'Créez votre code personnel'
                      : 'Vos finances, rien qu’à vous'),
                  const SizedBox(height: 28),
                  if (loading)
                    const CircularProgressIndicator()
                  else ...[
                    TextField(
                      controller: pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'Code PIN'),
                      onSubmitted: (_) {
                        if (!fresh) unlock();
                      },
                    ),
                    if (fresh)
                      TextField(
                        controller: confirm,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Confirmer le PIN',
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    FilledButton(
                      onPressed: busy ? null : () => unlock(),
                      child: Text(busy
                          ? 'Ouverture…'
                          : fresh ? 'Créer mon espace' : 'Déverrouiller'),
                    ),
                    if (!fresh && biometrics)
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => unlock(biometric: true),
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Face ID / biométrie'),
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'Données locales chiffrées • Aucune connexion bancaire',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String cleanError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

class Question {
  final String key;
  final String label;
  final String initial;
  final Map<String, String>? options;
  final bool optional;
  final bool secret;
  final bool numeric;

  const Question(
    this.key,
    this.label, {
    this.initial = '',
    this.options,
    this.optional = false,
    this.secret = false,
    this.numeric = false,
  });
}

Future<Map<String, String>?> ask(
  BuildContext context,
  String title,
  List<Question> questions,
) {
  final values = <String, String>{
    for (final q in questions)
      q.key: q.options != null && !q.options!.containsKey(q.initial)
          ? q.options!.keys.first
          : q.initial,
  };
  final form = GlobalKey<FormState>();

  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final q in questions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: q.options != null
                        ? DropdownButtonFormField<String>(
                            value: values[q.key],
                            isExpanded: true,
                            decoration: InputDecoration(labelText: q.label),
                            items: q.options!.entries
                                .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) values[q.key] = value;
                            },
                          )
                        : TextFormField(
                            initialValue: values[q.key],
                            obscureText: q.secret,
                            autocorrect: !q.secret,
                            enableSuggestions: !q.secret,
                            keyboardType: q.numeric
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  )
                                : TextInputType.text,
                            decoration: InputDecoration(labelText: q.label),
                            onChanged: (value) => values[q.key] = value.trim(),
                            validator: (value) =>
                                !q.optional && (value ?? '').trim().isEmpty
                                    ? 'Champ obligatoire'
                                    : null,
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(dialogContext, values);
            }
          },
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

class Home extends StatefulWidget {
  final BudgetStore store;
  final VoidCallback onLock;

  const Home({
    super.key,
    required this.store,
    required this.onLock,
  });

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  BudgetStore get s => widget.store;
  int tab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String scopeFilter = 'all';

  String get scopeLabel =>
      scopeFilter == 'all' ? 'Tous périmètres' : scopes[scopeFilter]!;

  Widget scopeSelector() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('Tout')),
            ButtonSegment(value: 'personal', label: Text('Personnel')),
            ButtonSegment(value: 'joint', label: Text('Commun')),
          ],
          selected: {scopeFilter},
          onSelectionChanged: (selected) =>
              setState(() => scopeFilter = selected.first),
        ),
      );

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      message(cleanError(e));
    }
  }

  Widget panel(Widget child, {Color? color}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      );

  Widget heading(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget badge(String icon, String color) => CircleAvatar(
        backgroundColor: (colors[color] ?? blue).withOpacity(.15),
        child: Icon(
          categoryIcons[icon] ?? Icons.category_rounded,
          color: colors[color] ?? blue,
        ),
      );

  Widget progress(int current, int target, Color color) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: target <= 0
              ? 0
              : (current / target).clamp(0.0, 1.0).toDouble(),
          minHeight: 9,
          backgroundColor: color.withOpacity(.12),
          color: color,
        ),
      );

  Widget monthSelector() => Row(
        children: [
          IconButton(
            onPressed: () => setState(() {
              month = DateTime(month.year, month.month - 1);
            }),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              monthText(month),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              month = DateTime(month.year, month.month + 1);
            }),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      );

  IconData accountIcon(Account a) => switch (a.type) {
        'savings' => Icons.savings_rounded,
        'cash' => Icons.payments_rounded,
        'credit' => Icons.credit_card_rounded,
        'prepaid' => Icons.account_balance_wallet_rounded,
        'investment' => Icons.trending_up_rounded,
        _ => Icons.account_balance_rounded,
      };

  Future<void> addAccount() async {
    final result = await ask(context, 'Ajouter un compte', [
      const Question('name', 'Nom du compte'),
      const Question('type', 'Type', options: accountTypes),
      const Question('scope', 'Périmètre', initial: 'personal', options: scopes),
      const Question(
        'balance',
        'Solde initial en € / montant dû si carte',
        initial: '0',
        numeric: true,
      ),
      Question(
        'initialDate',
        'Date du solde initial — AAAA-MM-JJ',
        initial: dateText(DateTime.now()),
      ),
      const Question(
        'limit',
        'Plafond en € — carte de crédit uniquement',
        initial: '0',
        numeric: true,
      ),
    ]);
    if (result == null) return;

    await run(() => s.change(() {
          final type = result['type']!;
          var initial = money(result['balance']!, signed: type != 'credit');
          final limit = type == 'credit' ? money(result['limit']!) : 0;

          if (type == 'credit') {
            if (limit <= 0) throw Exception('Indiquez le plafond de la carte.');
            initial = -initial;
          }

          final scope = result['scope']!;
          if (!scopes.containsKey(scope)) {
            throw Exception('Périmètre invalide.');
          }
          final initialDate = parseDate(result['initialDate']!);
          if (initialDate.isAfter(parseDate(dateText(DateTime.now())))) {
            throw Exception('La date du solde initial ne peut pas être future.');
          }

          final a = Account(
            id(),
            result['name']!,
            type,
            limit,
            scope: scope,
            initialDate: initialDate,
          );
          s.accounts.add(a);
          s.entries.add(Entry(
            id: id(),
            kind: 'adjustment',
            account: a.id,
            amount: initial,
            date: initialDate,
            note: 'Solde initial',
            scope: scope,
          ));
        }));
  }

  Future<void> addEntry([String kind = 'expense']) async {
    if (s.accounts.isEmpty) {
      message('Ajoutez d’abord un compte.');
      await addAccount();
      return;
    }
    if (kind == 'transfer' && s.accounts.length < 2) {
      message('Un transfert nécessite deux comptes.');
      return;
    }

    final result = await ask(
      context,
      switch (kind) {
        'income' => 'Ajouter un revenu',
        'transfer' => 'Transférer de l’argent',
        _ => 'Ajouter une dépense',
      },
      [
        const Question('amount', 'Montant en €', numeric: true),
        Question(
          'account',
          kind == 'transfer' ? 'Compte débité' : 'Compte',
          options: {for (final a in s.accounts) a.id: a.name},
        ),
        if (kind == 'transfer')
          Question(
            'destination',
            'Compte crédité',
            initial: s.accounts[1].id,
            options: {for (final a in s.accounts) a.id: a.name},
          ),
        if (kind != 'transfer')
          Question(
            'category',
            'Catégorie',
            initial: kind == 'income' ? s.categories.first.id : '',
            options: {
              for (final c in s.categories)
                c.id: '${iconNames[c.icon]?.split(' ').first ?? '🔷'} ${c.name}',
            },
          ),
        if (kind == 'expense')
          Question(
            'project',
            'Payer avec une tirelire',
            initial: '',
            options: {
              '': 'Aucune',
              for (final p in s.projects)
                p.id: '${p.name} — ${euro(s.reserved(p))}',
            },
          ),
        if (kind != 'transfer') ...[
          const Question(
            'scope',
            'Périmètre',
            initial: 'personal',
            options: scopes,
          ),
          const Question(
            'author',
            'Effectuée par',
            initial: 'me',
            options: authors,
          ),
        ],
        Question(
          'date',
          'Date — AAAA-MM-JJ',
          initial: dateText(DateTime.now()),
        ),
        const Question(
          'note',
          'Note / nom du service',
          optional: true,
        ),
      ],
    );
    if (result == null) return;

    await run(() => s.change(() {
          final amount = money(result['amount']!);
          if (amount <= 0) throw Exception('Le montant doit être positif.');

          final source = s.account(result['account']!);
          if (source.type == 'investment') {
            throw Exception(
              'Utilisez un transfert pour investir, puis ajustez '
              'la valorisation depuis le compte de placement.',
            );
          }

          final project = result['project'];
          final entryScope = kind == 'transfer'
              ? s.account(result['destination']!).scope
              : (result['scope'] ?? source.scope);
          final entryAuthor = result['author'] ?? 'me';
          s.entries.add(Entry(
            id: id(),
            kind: kind,
            account: source.id,
            destination: result['destination'],
            category: result['category'],
            project: project == null || project.isEmpty ? null : project,
            amount: amount,
            date: parseDate(result['date']!),
            note: result['note'] ?? '',
            scope: entryScope,
            author: entryAuthor,
          ));
        }));
  }

  Future<void> quickAdd() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle, color: violet),
              title: const Text('Ajouter une dépense'),
              onTap: () => Navigator.pop(ctx, 'expense'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle, color: mint),
              title: const Text('Ajouter un revenu'),
              onTap: () => Navigator.pop(ctx, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: blue),
              title: const Text('Faire un transfert'),
              subtitle: const Text('Épargne, recharge de site, remboursement'),
              onTap: () => Navigator.pop(ctx, 'transfer'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await addEntry(selected);
  }

  Widget entryTile(Entry e, {bool deletable = false}) {
    final c = s.category(e.category);
    final transfer = e.kind == 'transfer';
    final adjustment = e.kind == 'adjustment';
    final name = transfer
        ? 'Transfert'
        : adjustment ? 'Ajustement de solde' : c?.name ?? 'Opération';
    final subtitle = [
      dateText(e.date),
      s.account(e.account).name,
      if (transfer) '→ ${s.account(e.destination!).name}',
      scopes[e.scope] ?? e.scope,
      if (!transfer && !adjustment) authors[e.author] ?? e.author,
      if (e.note.isNotEmpty) e.note,
    ].join(' · ');

    final signed = e.kind == 'expense' ? -e.amount : e.amount;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: c != null
          ? badge(c.icon, c.color)
          : CircleAvatar(
              backgroundColor: blue.withOpacity(.12),
              child: Icon(
                transfer ? Icons.swap_horiz : Icons.tune,
                color: blue,
              ),
            ),
      title: Text(name),
      subtitle: Text(subtitle),
      trailing: Text(
        '${transfer ? "↔ " : signed > 0 ? "+" : ""}${euro(signed)}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: transfer || adjustment
              ? ink
              : e.kind == 'income' ? const Color(0xFF009A78) : violet,
        ),
      ),
      onLongPress: deletable
          ? () async {
              final yes = await confirmAction(
                'Supprimer cette opération ?',
                'Les soldes et la tirelire associée seront recalculés.',
              );
              if (yes) {
                await run(() => s.change(() {
                      s.entries.removeWhere((item) => item.id == e.id);
                    }));
              }
            }
          : null,
    );
  }

  Future<bool> confirmAction(String title, String description) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> showHistory({
    String? accountId,
    String? projectId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .78,
          child: AnimatedBuilder(
            animation: s,
            builder: (_, __) {
              final items = s.history(
                accountId: accountId,
                projectId: projectId,
                scope: accountId == null && projectId == null
                    ? scopeFilter
                    : 'all',
              );
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  heading('Historique'),
                  const Text(
                    'Appui long sur une opération pour la supprimer.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty) const Text('Aucune opération.'),
                  ...items.map((e) => entryTile(e, deletable: true)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> accountActions(Account a) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(a.name)),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Voir les opérations'),
              onTap: () => Navigator.pop(ctx, 'history'),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(a.type == 'investment'
                  ? 'Actualiser la valeur du placement'
                  : 'Ajuster le solde'),
              onTap: () => Navigator.pop(ctx, 'adjust'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'history') {
      await showHistory(accountId: a.id);
    }
    if (action == 'adjust') {
      final result = await ask(context, 'Actualiser ${a.name}', [
        Question(
          'balance',
          a.type == 'credit' ? 'Nouveau montant dû en €' : 'Nouveau solde en €',
          initial: amountText(
            a.type == 'credit' ? max(0, -s.balance(a)) : s.balance(a),
          ),
          numeric: true,
        ),
        const Question('note', 'Motif', initial: 'Mise à jour manuelle'),
      ]);
      if (result == null) return;
      await run(() => s.change(() {
            var value = money(
              result['balance']!,
              signed: a.type != 'credit',
            );
            if (a.type == 'credit') value = -value;

            s.entries.add(Entry(
              id: id(),
              kind: 'adjustment',
              account: a.id,
              amount: value - s.balance(a),
              date: DateTime.now(),
              note: result['note']!,
            ));
          }));
    }
  }

  Future<void> editBudget([Category? category]) async {
    final result = await ask(
      context,
      category == null ? 'Budget mensuel global' : 'Budget ${category.name}',
      [
        Question(
          'amount',
          '${monthText(month)} — montant en €',
          initial: amountText(s.budget(month, category?.id ?? 'all')),
          numeric: true,
        ),
      ],
    );
    if (result == null) return;
    await run(() => s.change(() {
          s.budgets['${monthKey(month)}:${category?.id ?? "all"}'] =
              money(result['amount']!);
        }));
  }

  Future<void> addCategory() async {
    final result = await ask(context, 'Nouvelle catégorie', [
      const Question('name', 'Nom'),
      const Question('icon', 'Icône', options: iconNames),
      const Question('color', 'Couleur', options: colorNames),
    ]);
    if (result == null) return;
    await run(() => s.change(() {
          if (s.categories.any(
            (c) => c.name.toLowerCase() == result['name']!.toLowerCase(),
          )) {
            throw Exception('Cette catégorie existe déjà.');
          }
          s.categories.add(Category(
            id(),
            result['name']!,
            result['icon']!,
            result['color']!,
          ));
        }));
  }

  Future<void> addProject() async {
    final result = await ask(context, 'Créer une tirelire', [
      const Question('name', 'Projet — ex. Nouveau chauffage'),
      const Question('target', 'Objectif en €', numeric: true),
      const Question(
        'date',
        'Échéance AAAA-MM-JJ — facultative',
        optional: true,
      ),
      const Question('icon', 'Icône', initial: 'pig', options: iconNames),
      const Question('color', 'Couleur', initial: 'mint', options: colorNames),
    ]);
    if (result == null) return;
    await run(() => s.change(() {
          final deadline =
              result['date']!.isEmpty ? null : parseDate(result['date']!);
          final today = parseDate(dateText(DateTime.now()));
          if (deadline != null && deadline.isBefore(today)) {
            throw Exception('Choisissez une échéance à partir d’aujourd’hui.');
          }
          s.projects.add(Project(
            id(),
            result['name']!,
            result['icon']!,
            result['color']!,
            money(result['target']!),
            deadline,
          ));
        }));
  }

  Future<void> allocate(Project p, {bool remove = false}) async {
    final result = await ask(
      context,
      remove ? 'Retirer de la tirelire' : 'Alimenter ${p.name}',
      [
        Question(
          'amount',
          remove
              ? 'Montant — réservé : ${euro(s.reserved(p))}'
              : 'Montant — non réservé : ${euro(s.available)}',
          numeric: true,
        ),
      ],
    );
    if (result == null) return;

    await run(() => s.change(() {
          final amount = money(result['amount']!);
          if (amount <= 0) throw Exception('Indiquez un montant positif.');
          if (!remove && amount > s.available) {
            throw Exception(
              'Fonds non réservés insuffisants sur les comptes '
              'courants, épargne et espèces.',
            );
          }
          if (remove && amount > s.reserved(p)) {
            throw Exception('Le retrait dépasse le montant réservé.');
          }
          s.allocations.add(Allocation(
            p.id,
            remove ? -amount : amount,
            DateTime.now(),
          ));
        }));
  }

  Future<void> projectHistory(Project p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final list = s.allocations
            .where((a) => a.project == p.id)
            .toList()
            .reversed
            .toList();
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .7,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                heading(p.name),
                const Text('Mouvements de la tirelire'),
                ...list.map((a) => ListTile(
                      leading: const Icon(Icons.savings, color: mint),
                      title: Text(a.amount > 0
                          ? 'Somme réservée'
                          : 'Somme libérée'),
                      subtitle: Text(dateText(a.date)),
                      trailing: Text(euro(a.amount)),
                    )),
                heading('Dépenses du projet'),
                ...s.history(projectId: p.id).map((e) => entryTile(e)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget dashboard() {
    final expenses = s.monthly('expense', month, scope: scopeFilter);
    final income = s.monthly('income', month, scope: scopeFilter);
    final limit = s.budget(month);

    return Column(
      children: [
        scopeSelector(),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ARGENT DISPONIBLE — $scopeLabel'.toUpperCase(),
                  style:
                      const TextStyle(letterSpacing: 1.5, color: ink)),
              const SizedBox(height: 8),
              Text(
                euro(s.liquidFor(scopeFilter)),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Périmètre : $scopeLabel · Personnel et Commun présentés séparément dans Comptes',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 95,
                width: double.infinity,
                child: CustomPaint(
                  painter: WealthPainter(s.netHistory()),
                ),
              ),
              const SizedBox(height: 8),
              const Text('30 derniers jours · historique enregistré',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          color: mint.withOpacity(.12),
        ),
        monthSelector(),
        Row(
          children: [
            Expanded(
              child: panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Revenus'),
                  const SizedBox(height: 8),
                  Text(euro(income),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF009A78),
                      )),
                ],
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dépenses'),
                  const SizedBox(height: 8),
                  Text(euro(expenses),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: violet,
                      )),
                ],
              )),
            ),
          ],
        ),
        panel(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('Budget du mois'),
            if (limit == 0)
              TextButton(
                onPressed: () => editBudget(),
                child: const Text('Définir mon budget'),
              )
            else ...[
              Text('${euro(expenses)} / ${euro(limit)}'),
              const SizedBox(height: 12),
              progress(expenses, limit, blue),
              const SizedBox(height: 12),
              Text(expenses <= limit
                  ? '${euro(limit - expenses)} encore disponibles'
                  : 'Dépassement de ${euro(expenses - limit)}'),
            ],
          ],
        )),
        if (s.available < 0)
          panel(
            Text(
              'Attention : vos tirelires dépassent vos liquidités de '
              '${euro(-s.available)}. Libérez une partie des sommes réservées.',
            ),
            color: Colors.orange.shade50,
          ),
        heading(
          'Dernières opérations',
          trailing: TextButton(
            onPressed: () => showHistory(),
            child: const Text('Tout voir'),
          ),
        ),
        panel(Column(
          children: s.entries.isEmpty
              ? [
                  const Text('Bienvenue ! Commencez par ajouter vos comptes.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: addAccount,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un compte'),
                  ),
                ]
              : s
                    .history(scope: scopeFilter)
                    .take(5)
                    .map((e) => entryTile(e))
                    .toList(),
        )),
      ],
    );
  }

  Widget accountsPage() {
    Widget accountCard(Account a) {
      final balance = s.balance(a);
      return panel(
        InkWell(
          onTap: () => accountActions(a),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: blue.withOpacity(.12),
                    child: Icon(accountIcon(a), color: blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800)),
                        Text(
                            '${accountTypes[a.type]!} · ${scopes[a.scope] ?? ''}',
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    a.type == 'credit'
                        ? '${euro(max(0, -balance))} dus'
                        : euro(balance),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              if (a.type == 'credit') ...[
                const SizedBox(height: 14),
                progress(max(0, -balance), a.limit, violet),
                const SizedBox(height: 8),
                Text(
                  'Plafond : ${euro(a.limit)} · '
                  'Disponible : ${euro(a.limit + balance)}',
                ),
                if (balance > 0)
                  Text('Solde créditeur : ${euro(balance)}'),
              ],
            ],
          ),
        ),
      );
    }

    final personal = s.accounts.where((a) => a.scope == 'personal').toList();
    final joint = s.accounts.where((a) => a.scope == 'joint').toList();

    return Column(
        children: [
          scopeSelector(),
          heading(
            'Mes comptes',
            trailing: IconButton(
              onPressed: addAccount,
              icon: const Icon(Icons.add_circle, color: blue),
            ),
          ),
          if (s.accounts.isEmpty)
            panel(const Text('Ajoutez votre premier compte avec le bouton +.')),
          heading('Personnel — ${euro(s.liquidFor('personal'))}'),
          if (personal.isEmpty)
            panel(const Text('Aucun compte personnel.')),
          ...personal.map(accountCard),
          heading('Commun — ${euro(s.liquidFor('joint'))}'),
          if (joint.isEmpty)
            panel(const Text(
                'Aucun compte commun. Ajoutez-le avec le bouton + puis périmètre « Commun ».')),
          ...joint.map(accountCard),
          panel(
            const Text(
              'Recharge de crédits API ou d’un site : créez un portefeuille '
              'prépayé, puis faites un transfert vers ce portefeuille. '
              'Enregistrez ensuite les consommations comme dépenses.\n\n'
              'Pour une carte de crédit, le remboursement est également '
              'un transfert : il ne crée pas une deuxième dépense.',
            ),
            color: blue.withOpacity(.08),
          ),
        ],
      );

  Widget budgetsPage() {
    final total = s.monthly('expense', month, scope: scopeFilter);
    final limit = s.budget(month);
    final previous = DateTime(month.year, month.month - 1);
    final previousTotal = s.monthly('expense', previous, scope: scopeFilter);

    return Column(
      children: [
        scopeSelector(),
        monthSelector(),
        panel(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('Budget global',
                trailing: IconButton(
                  onPressed: () => editBudget(),
                  icon: const Icon(Icons.edit_outlined),
                )),
            Text('${euro(total)} / ${limit == 0 ? "non défini" : euro(limit)}'),
            const SizedBox(height: 12),
            progress(total, limit, blue),
            const SizedBox(height: 12),
            Text('Mois précédent : ${euro(previousTotal)}'),
            Text('Écart : ${euro(total - previousTotal)}'),
          ],
        )),
        heading('Répartition des dépenses'),
        panel(
          total == 0
              ? const Text('Aucune dépense pour cette période.')
              : Column(
                  children: s.categories.where((c) {
                    return s.monthly('expense', month,
                            categoryId: c.id, scope: scopeFilter) >
                        0;
                  }).map((c) {
                    final amount = s.monthly('expense', month,
                        categoryId: c.id, scope: scopeFilter);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              badge(c.icon, c.color),
                              const SizedBox(width: 10),
                              Expanded(child: Text(c.name)),
                              Text(
                                '${(amount * 100 / total).round()} %',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          progress(amount, total, colors[c.color] ?? blue),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        heading(
          'Budgets par catégorie',
          trailing: IconButton(
            onPressed: addCategory,
            icon: const Icon(Icons.add_circle, color: violet),
          ),
        ),
        ...s.categories.map((c) {
          final spent = s.monthly('expense', month,
              categoryId: c.id, scope: scopeFilter);
          final budget = s.budget(month, c.id);
          return panel(
            InkWell(
              onTap: () => editBudget(c),
              child: Column(
                children: [
                  Row(
                    children: [
                      badge(c.icon, c.color),
                      const SizedBox(width: 12),
                      Expanded(child: Text(c.name)),
                      Text(
                        euro(spent),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  progress(spent, budget, colors[c.color] ?? blue),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      budget == 0
                          ? 'Toucher pour définir une limite'
                          : spent > budget
                              ? 'Dépassement : ${euro(spent - budget)}'
                              : 'Limite : ${euro(budget)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: budget > 0 && spent > budget
                            ? Colors.red
                            : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget projectsPage() => Column(
        children: [
          heading(
            'Projets & épargne',
            trailing: IconButton(
              onPressed: addProject,
              icon: const Icon(Icons.add_circle, color: mint),
            ),
          ),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LIQUIDITÉS NON RÉSERVÉES'),
                const SizedBox(height: 8),
                Text(
                  euro(s.available),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text('${euro(s.totalReserved)} réservés dans vos tirelires'),
                const SizedBox(height: 8),
                const Text(
                  'Réserver une somme ne déplace pas réellement l’argent '
                  'et ne crée pas de dépense.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            color: mint.withOpacity(.12),
          ),
          if (s.projects.isEmpty)
            panel(const Text(
              'Créez votre première tirelire : chauffage, vacances, '
              'travaux ou fonds de sécurité.',
            )),
          ...s.projects.map((p) {
            final funded = s.funded(p);
            final spent = s.spent(p);
            final reserved = s.reserved(p);
            final remaining = max(0, p.target - funded);

            var plan = 'Ajoutez de l’argent à votre rythme.';
            if (remaining == 0) {
              plan = 'Objectif financé 🎉';
            } else if (p.deadline != null) {
              final days = p.deadline!
                  .difference(parseDate(dateText(DateTime.now())))
                  .inDays;
              if (days < 0) {
                plan = 'Échéance dépassée · reste ${euro(remaining)}';
              } else {
                final months = max(1, (days / 30.44).ceil());
                final weeks = max(1, (days / 7).ceil());
                plan =
                    '${euro((remaining / months).ceil())} / mois '
                    'ou ${euro((remaining / weeks).ceil())} / semaine';
              }
            }

            return panel(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    badge(p.icon, p.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => projectHistory(p),
                      icon: const Icon(Icons.history),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('${euro(funded)} financés sur ${euro(p.target)}'),
                const SizedBox(height: 10),
                progress(funded, p.target, colors[p.color] ?? mint),
                const SizedBox(height: 14),
                Text('Dans la tirelire : ${euro(reserved)}'),
                Text('Déjà dépensé pour le projet : ${euro(spent)}'),
                Text('Reste à financer : ${euro(remaining)}'),
                if (p.deadline != null)
                  Text('Échéance : ${dateText(p.deadline!)}'),
                const SizedBox(height: 12),
                Text(
                  plan,
                  style: const TextStyle(
                      color: violet, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => allocate(p),
                      icon: const Icon(Icons.add),
                      label: const Text('Alimenter'),
                    ),
                    TextButton(
                      onPressed: reserved > 0
                          ? () => allocate(p, remove: true)
                          : null,
                      child: const Text('Libérer une somme'),
                    ),
                  ],
                ),
              ],
            ));
          }),
        ],
      );

  Widget wealthPage() => Column(
        children: [
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Patrimoine net'),
                const SizedBox(height: 8),
                Text(
                  euro(s.net),
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 160,
                  child: CustomPaint(
                    painter: WealthPainter(s.netHistory()),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '30 derniers jours · les soldes initiaux apparaissent '
                  'à leur date de saisie.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            color: violet.withOpacity(.09),
          ),
          panel(Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: mint),
                title: const Text('Total des avoirs'),
                trailing: Text(euro(s.assets)),
              ),
              ListTile(
                leading: const Icon(Icons.credit_card, color: violet),
                title: const Text('Total des dettes'),
                trailing: Text(euro(s.debts)),
              ),
              const Divider(),
              ...accountTypes.entries.map((type) {
                final amount = s.accounts
                    .where((a) => a.type == type.key)
                    .fold<int>(0, (sum, a) => sum + s.balance(a));
                return ListTile(
                  title: Text(type.value),
                  trailing: Text(euro(amount)),
                );
              }),
            ],
          )),
          heading(
            'Placements',
            trailing: TextButton(
              onPressed: addAccount,
              child: const Text('Ajouter'),
            ),
          ),
          ...s.accounts.where((a) => a.type == 'investment').map((a) =>
              panel(ListTile(
                leading: const Icon(Icons.trending_up, color: violet),
                title: Text(a.name),
                subtitle: const Text('Valorisation manuelle en euros'),
                trailing: Text(euro(s.balance(a))),
                onTap: () => accountActions(a),
              ))),
          panel(
            const Text(
              'Un placement est suivi ici par sa valeur totale en euros. '
              'Les versements et retraits se font par transfert. '
              'Les variations de marché se saisissent avec '
              '« Actualiser la valeur du placement ».\n\n'
              'Ces ajustements modifient le patrimoine, mais pas '
              'les revenus ni les dépenses du budget.\n\n'
              'Les portefeuilles prépayés sont inclus dans les avoirs : '
              'leur solde peut ne pas être remboursable.',
            ),
          ),
        ],
      );

  Future<void> biometricSettings() async {
    await run(() async {
      final enabled =
          await s.secure.read(key: 'biometrics') == 'true';
      if (enabled) {
        await s.secure.write(key: 'biometrics', value: 'false');
        message('Biométrie désactivée.');
        return;
      }

      final auth = LocalAuthentication();
      if (!await auth.canCheckBiometrics) {
        throw Exception('Aucune biométrie disponible ou configurée.');
      }

      final accepted = await auth.authenticate(
        localizedReason: 'Activer la biométrie pour DiPeSa',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (accepted) {
        await s.secure.write(key: 'biometrics', value: 'true');
        message('Biométrie activée.');
      }
    });
  }

  Future<void> exportBackup() async {
    final result = await ask(context, 'Sauvegarde chiffrée', [
      const Question('password', 'Mot de passe — 12 caractères minimum',
          secret: true),
      const Question('confirm', 'Confirmer le mot de passe', secret: true),
    ]);
    if (result == null) return;

    await run(() async {
      final password = result['password']!;
      if (password.length < 12 || password != result['confirm']) {
        throw Exception(
          'Utilisez au moins 12 caractères et une confirmation identique.',
        );
      }

      final salt = randomBytes(16);
      final backupKey = await passwordKey(password, salt);
      final encrypted = await encrypt(
        utf8.encode(jsonEncode(s.toJson())),
        backupKey,
      );
      final envelope = {
        'format': 'mon-capital-backup-1',
        'salt': base64Encode(salt),
        'data': encrypted,
      };

      final directory = await getTemporaryDirectory();
      final backup = File(
        '${directory.path}/dipesa-${DateTime.now().millisecondsSinceEpoch}.mcb',
      );
      await backup.writeAsString(jsonEncode(envelope), flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(backup.path)],
        text: 'Sauvegarde chiffrée DiPeSa',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    });
  }

  Future<void> restoreBackup() async {
    await run(() async {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (picked == null || !mounted) return;

      final selected = picked.files.single;
      if (selected.size > 20 * 1024 * 1024) {
        throw Exception('Sauvegarde trop volumineuse — maximum 20 Mo.');
      }

      final bytes = selected.bytes ??
          await File(selected.path!).readAsBytes();

      final envelope = jsonMap(jsonDecode(utf8.decode(bytes)));
      if (envelope['format'] != 'mon-capital-backup-1') {
        throw Exception('Ce fichier n’est pas une sauvegarde DiPeSa.');
      }

      if (!mounted) return;
      final result = await ask(context, 'Restaurer une sauvegarde', [
        const Question('password', 'Mot de passe de la sauvegarde',
            secret: true),
      ]);
      if (result == null) return;

      Map<String, dynamic> restored;
      try {
        final backupKey = await passwordKey(
          result['password']!,
          base64Decode(envelope['salt'] as String),
        );
        final plain = await decrypt(
          jsonMap(envelope['data']),
          backupKey,
        );
        restored = jsonMap(jsonDecode(utf8.decode(plain)));
      } catch (_) {
        throw Exception('Mot de passe incorrect ou sauvegarde endommagée.');
      }

      if (!mounted) return;
      final confirmed = await confirmAction(
        'Remplacer les données actuelles ?',
        'La restauration remplace les comptes, opérations et projets '
        'présents sur ce téléphone. Exportez-les d’abord si nécessaire.',
      );
      if (!confirmed) return;

      await s.change(() => s.load(restored));
      message('Sauvegarde restaurée.');
    });
  }

  Future<void> settings() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Réglages',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Stockage local chiffré · version 0.1.0'),
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Activer / désactiver la biométrie'),
              onTap: () => Navigator.pop(ctx, 'bio'),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Ajouter une catégorie et son icône'),
              onTap: () => Navigator.pop(ctx, 'category'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Exporter une sauvegarde chiffrée'),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restaurer une sauvegarde'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Verrouiller maintenant'),
              onTap: () => Navigator.pop(ctx, 'lock'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case 'bio':
        await biometricSettings();
        break;
      case 'category':
        await addCategory();
        break;
      case 'export':
        await exportBackup();
        break;
      case 'restore':
        await restoreBackup();
        break;
      case 'lock':
        widget.onLock();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'DiPeSa',
      'Mes comptes',
      'Mon budget',
      'Mes tirelires',
      'Mon patrimoine',
    ];

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            titles[tab],
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              onPressed: settings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            key: ValueKey(tab),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              switch (tab) {
                0 => dashboard(),
                1 => accountsPage(),
                2 => budgetsPage(),
                3 => projectsPage(),
                _ => wealthPage(),
              },
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: quickAdd,
          backgroundColor: mint,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add, size: 30),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Comptes',
            ),
            NavigationDestination(
              icon: Icon(Icons.pie_chart_outline),
              selectedIcon: Icon(Icons.pie_chart),
              label: 'Budgets',
            ),
            NavigationDestination(
              icon: Icon(Icons.savings_outlined),
              selectedIcon: Icon(Icons.savings),
              label: 'Projets',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart),
              label: 'Patrimoine',
            ),
          ],
        ),
      ),
    );
  }
}

class WealthPainter extends CustomPainter {
  final List<double> values;
  WealthPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    final minimum = values.reduce(min);
    final maximum = values.reduce(max);
    final range = maximum - minimum;

    Offset point(int index) {
      final y = range == 0
          ? size.height * .5
          : size.height -
              8 -
              ((values[index] - minimum) / range) * (size.height - 16);
      return Offset(index * size.width / (values.length - 1), y);
    }

    final gridPaint = Paint()
      ..color = violet.withOpacity(.10)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final first = point(0);
    final line = Path()..moveTo(first.dx, first.dy);

    for (var i = 1; i < values.length; i++) {
      final p = point(i);
      line.lineTo(p.dx, p.dy);
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [violet.withOpacity(.25), violet.withOpacity(.01)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = violet
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(point(values.length - 1), 4, Paint()..color = violet);
  }

  @override
  bool shouldRepaint(covariant WealthPainter oldDelegate) => true;
}