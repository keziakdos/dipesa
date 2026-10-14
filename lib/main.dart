import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
  'loan': 'Crédit (maison, voiture, autre)',
  'prepaid': 'Portefeuille prépayé',
  'investment': 'Placement — valeur manuelle',
  'crypto': 'BTC / cryptoactifs — valeur manuelle',
  'stocks': 'Actions — valeur manuelle',
  'realestate': 'Immobilier — valeur manuelle',
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

const dueKinds = <String, String>{
  'bill': 'Facture / mensualité',
  'loan': 'Mensualité de crédit',
  'card': 'Remboursement carte',
  'other': 'Autre échéance',
};

const dueRecurrences = <String, String>{
  'none': 'Ponctuelle',
  'monthly': 'Mensuelle',
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

/// Sauvegarde auto tous les 5 jours : pas d'exécution exacte garantie en
/// arrière-plan sur iOS — rattrapage à chaque ouverture/écriture.
bool shouldAutoBackup(DateTime? last, DateTime now) {
  if (last == null) return true;
  return now.difference(last).inHours >= 5 * 24;
}

/// Rotation : 12 snapshots conservés. La suppression du fichier principal
/// ne supprime jamais les snapshots (dossiers/fichiers séparés).
List<String> pruneSnapshots(List<String> names, {int keep = 12}) {
  if (names.length <= keep) return [];
  final sorted = names.toList()..sort();
  return sorted.sublist(0, names.length - keep);
}

String snapshotName(int millis) => 'budget-$millis.enc';

/// Formats d'export chiffré (compatibilité documentée) :
/// - 'mon-capital-backup-1' : ancien format, toujours lisible ;
/// - 'dipesa-backup-1' : format actuel.
/// Un fichier déjà exporté garde son mot de passe d'origine : en changer
/// pour un futur export ne modifie jamais les anciens fichiers.
const currentBackupFormat = 'dipesa-backup-1';
const legacyBackupFormat = 'mon-capital-backup-1';
const backupFormats = [currentBackupFormat, legacyBackupFormat];

/// PIN : exactement 4 chiffres. Il ne chiffre jamais les données seul :
/// la clé de base reste aléatoire (Keychain), le PIN n'est qu'un verrou local.
bool validPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

const _recoveryAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Code de récupération : 16 caractères (80 bits), présenté en 4 groupes.
/// Il chiffre (wrap) une copie de la clé de base : sans lui, pas de
/// rétablissement sur cet appareil ; il ne part jamais sur un autre
/// appareil (le nouvel iPhone passe par l'export chiffré + mot de passe).
String generateRecoveryCode() {
  final random = Random.secure();
  final chars = List.generate(
      16, (_) => _recoveryAlphabet[random.nextInt(_recoveryAlphabet.length)]);
  final raw = chars.join();
  return '${raw.substring(0, 4)}-${raw.substring(4, 8)}-'
      '${raw.substring(8, 12)}-${raw.substring(12, 16)}';
}

String normalizeRecoveryCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-9]'), '');

/// Prochaines dates de rappel (tous les 3 jours à heure fixe).
/// Fonction pure, testée. iOS peut différer l'affichage : l'ouverture
/// de l'app replanifie les occurrences à venir.
List<DateTime> reminderDates(DateTime now, int hour, int minute,
    {int count = 10}) {
  var first = DateTime(now.year, now.month, now.day, hour, minute);
  if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
  return List.generate(
      count, (i) => first.add(Duration(days: 3 * i)));
}

/// Rappels locaux « enregistrer vos dépenses » tous les 3 jours.
/// Volontaire (opt-in), autorisation iOS demandée à l'activation, horaire
/// réglable. Non testé sur appareil dans cet environnement.
class ReminderService {
  ReminderService(this.secure);

  final FlutterSecureStorage secure;
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));
    } catch (_) {}
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(settings);
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  Future<void> schedule({required int hour, required int minute}) async {
    await init();
    await plugin.cancelAll();
    const details = NotificationDetails(iOS: DarwinNotificationDetails());
    final dates = reminderDates(DateTime.now(), hour, minute);
    var n = 0;
    for (final d in dates) {
      await plugin.zonedSchedule(
        1000 + n,
        'DiPeSa — vos dépenses',
        'Prenez 1 minute pour enregistrer vos dépenses du jour.',
        tz.TZDateTime.from(d, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      n++;
    }
    await secure.write(key: 'reminder-enabled', value: 'true');
    await secure.write(key: 'reminder-hour', value: '$hour');
    await secure.write(key: 'reminder-minute', value: '$minute');
  }

  Future<void> disable() async {
    try {
      await plugin.cancelAll();
    } catch (_) {}
    await secure.write(key: 'reminder-enabled', value: 'false');
  }

  Future<Map<String, String?>> prefs() async => {
        'enabled': await secure.read(key: 'reminder-enabled'),
        'hour': await secure.read(key: 'reminder-hour'),
        'minute': await secure.read(key: 'reminder-minute'),
      };
}

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
  final String scope;

  Project(
    this.id,
    this.name,
    this.icon,
    this.color,
    this.target,
    this.deadline, {
    this.scope = 'personal',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'target': target,
        'deadline': deadline == null ? null : dateText(deadline!),
        'scope': scope,
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        j['id'] as String,
        j['name'] as String,
        j['icon'] as String,
        j['color'] as String,
        j['target'] as int,
        j['deadline'] == null ? null : parseDate(j['deadline'] as String),
        scope: (j['scope'] as String?) ?? 'personal',
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

/// Échéance : facture, mensualité ou remboursement prévu.
/// « Prévu » ne modifie jamais le solde ; « comptabilisé » crée les écritures.
class Due {
  final String id;
  final String label;
  final String kind;
  final int total;
  final int capital;
  final int interest;
  final int insurance;
  final int fees;
  final DateTime dueDate;
  final String accountId;
  final String scope;
  final String? categoryId;
  final String status;
  final List<String> entryIds;
  final String recurrence;
  final String? loanId;

  Due({
    required this.id,
    required this.label,
    required this.kind,
    required this.total,
    required this.dueDate,
    required this.accountId,
    required this.scope,
    this.categoryId,
    this.status = 'prévu',
    List<String>? entryIds,
    this.recurrence = 'none',
    this.loanId,
    this.capital = 0,
    this.interest = 0,
    this.insurance = 0,
    this.fees = 0,
  }) : entryIds = entryIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind,
        'total': total,
        'capital': capital,
        'interest': interest,
        'insurance': insurance,
        'fees': fees,
        'dueDate': dateText(dueDate),
        'accountId': accountId,
        'scope': scope,
        'categoryId': categoryId,
        'status': status,
        'entryIds': entryIds,
        'recurrence': recurrence,
        'loanId': loanId,
      };

  factory Due.fromJson(Map<String, dynamic> j) => Due(
        id: j['id'] as String,
        label: j['label'] as String,
        kind: j['kind'] as String,
        total: j['total'] as int,
        capital: (j['capital'] as int?) ?? 0,
        interest: (j['interest'] as int?) ?? 0,
        insurance: (j['insurance'] as int?) ?? 0,
        fees: (j['fees'] as int?) ?? 0,
        dueDate: parseDate(j['dueDate'] as String),
        accountId: j['accountId'] as String,
        scope: (j['scope'] as String?) ?? 'personal',
        categoryId: j['categoryId'] as String?,
        status: (j['status'] as String?) ?? 'prévu',
        entryIds:
            ((j['entryIds'] as List?) ?? []).map((e) => e as String).toList(),
        recurrence: (j['recurrence'] as String?) ?? 'none',
        loanId: j['loanId'] as String?,
      );
}

/// Crédit amortissable : les mensualités déjà incluses dans les soldes
/// initiaux ne sont jamais rejouées. Saisir le capital restant dû à une
/// date connue pour un crédit déjà commencé.
class Loan {
  final String id;
  final String name;
  final String debtAccountId;
  final int initialAmount;
  final DateTime startDate;
  final double annualRate;
  final int months;
  final int monthly;
  final int insuranceMonthly;
  final int feesMonthly;
  final String sourceAccountId;
  final String scope;
  final int? remainingDue;
  final DateTime? remainingDate;
  final int paidCount;

  Loan({
    required this.id,
    required this.name,
    required this.debtAccountId,
    required this.initialAmount,
    required this.startDate,
    required this.annualRate,
    required this.months,
    required this.monthly,
    required this.sourceAccountId,
    required this.scope,
    this.insuranceMonthly = 0,
    this.feesMonthly = 0,
    this.remainingDue,
    this.remainingDate,
    this.paidCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'debtAccountId': debtAccountId,
        'initialAmount': initialAmount,
        'startDate': dateText(startDate),
        'annualRate': annualRate,
        'months': months,
        'monthly': monthly,
        'insuranceMonthly': insuranceMonthly,
        'feesMonthly': feesMonthly,
        'sourceAccountId': sourceAccountId,
        'scope': scope,
        'remainingDue': remainingDue,
        'remainingDate':
            remainingDate == null ? null : dateText(remainingDate!),
        'paidCount': paidCount,
      };

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        id: j['id'] as String,
        name: j['name'] as String,
        debtAccountId: j['debtAccountId'] as String,
        initialAmount: j['initialAmount'] as int,
        startDate: parseDate(j['startDate'] as String),
        annualRate: (j['annualRate'] as num).toDouble(),
        months: j['months'] as int,
        monthly: j['monthly'] as int,
        insuranceMonthly: (j['insuranceMonthly'] as int?) ?? 0,
        feesMonthly: (j['feesMonthly'] as int?) ?? 0,
        sourceAccountId: j['sourceAccountId'] as String,
        scope: (j['scope'] as String?) ?? 'personal',
        remainingDue: j['remainingDue'] as int?,
        remainingDate: j['remainingDate'] == null
            ? null
            : parseDate(j['remainingDate'] as String),
        paidCount: (j['paidCount'] as int?) ?? 0,
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
  List<Due> dues = [];
  List<Loan> loans = [];
  Map<String, int> budgets = {};
  DateTime? lastSavedAt;
  DateTime? lastAutoBackupAt;

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
      // Protection : copie chiffrée telle quelle avant toute migration.
      final raw = await file.readAsString();
      final envelope = jsonMap(jsonDecode(raw));
      final bytes = await decrypt(envelope, key);
      final data = jsonMap(jsonDecode(utf8.decode(bytes)));
      if ((data['version'] as int?) != 4) {
        final backupFile =
            File('${file.path}.bak-${DateTime.now().millisecondsSinceEpoch}');
        await backupFile.writeAsString(raw, flush: true);
      }
      load(data);
      validate();
      final lastRaw = await secure.read(key: 'last-auto-backup');
      lastAutoBackupAt = lastRaw == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(int.parse(lastRaw));
      await snapshotIfDue();
    } else {
      seed();
      await save();
    }
  }

  Directory snapshotsDir() => Directory('${file.parent.path}/snapshots');

  Future<List<File>> listSnapshots() async {
    final dir = snapshotsDir();
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.enc'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Snapshot versionné (copie chiffrée telle quelle). Rattrapage à
  /// l'ouverture : si > 5 jours depuis le dernier, on capture maintenant.
  Future<void> snapshotIfDue() async {
    try {
      if (!await file.exists()) return;
      if (!shouldAutoBackup(lastAutoBackupAt, DateTime.now())) return;
      final dir = snapshotsDir();
      await dir.create(recursive: true);
      final name = snapshotName(DateTime.now().millisecondsSinceEpoch);
      await File(file.path).copy('${dir.path}/$name');
      final all = await listSnapshots();
      for (final doomed
          in pruneSnapshots(all.map((f) => f.path).toList())) {
        try {
          await File(doomed).delete();
        } catch (_) {}
      }
      lastAutoBackupAt = DateTime.now();
      await secure.write(
        key: 'last-auto-backup',
        value: '${lastAutoBackupAt!.millisecondsSinceEpoch}',
      );
    } catch (_) {
      // La sauvegarde auto ne doit jamais bloquer l'ouverture.
    }
  }

  Future<Map<String, dynamic>> readSnapshot(File snap) async {
    final envelope = jsonMap(jsonDecode(await snap.readAsString()));
    final bytes = await decrypt(envelope, key);
    return jsonMap(jsonDecode(utf8.decode(bytes)));
  }

  void seed() {
    accounts = [];
    entries = [];
    projects = [];
    allocations = [];
    contributions = [];
    dues = [];
    loans = [];
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
        'version': 4,
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'projects': projects.map((e) => e.toJson()).toList(),
        'allocations': allocations.map((e) => e.toJson()).toList(),
        'contributions': contributions.map((e) => e.toJson()).toList(),
        'dues': dues.map((e) => e.toJson()).toList(),
        'loans': loans.map((e) => e.toJson()).toList(),
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

  /// Migration v2 → v3 : périmètre des projets. Ne supprime rien.
  Map<String, dynamic> migrateV2ToV3(Map<String, dynamic> old) {
    final projectsJson = (old['projects'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    for (final p in projectsJson) {
      p['scope'] ??= 'personal';
    }
    return {
      ...old,
      'version': 3,
      'projects': projectsJson,
      'contributions': old['contributions'] ?? [],
    };
  }

  /// Migration v3 → v4 : échéances et crédits. Ne supprime rien.
  Map<String, dynamic> migrateV3ToV4(Map<String, dynamic> old) {
    return {
      ...old,
      'version': 4,
      'dues': old['dues'] ?? [],
      'loans': old['loans'] ?? [],
    };
  }

  void load(Map<String, dynamic> j) {
    var data = j;
    if (data['version'] == 1) {
      data = migrateV1ToV2(data);
    }
    if (data['version'] == 2) {
      data = migrateV2ToV3(data);
    }
    if (data['version'] == 3) {
      data = migrateV3ToV4(data);
    }
    if (data['version'] != 4) {
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
    dues = ((data['dues'] as List?) ?? [])
        .map((e) => Due.fromJson(jsonMap(e))).toList();
    loans = ((data['loans'] as List?) ?? [])
        .map((e) => Loan.fromJson(jsonMap(e))).toList();
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
    lastSavedAt = DateTime.now();
    await snapshotIfDue();
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

  /// Argent disponible = soldes des comptes courants du périmètre.
  int checkingFor(String filter) => inScope(filter)
      .where((a) => a.type == 'bank')
      .fold(0, (sum, a) => sum + balance(a));

  /// Argent épargné = soldes des comptes d'épargne du périmètre.
  int savingsFor(String filter) => inScope(filter)
      .where((a) => a.type == 'savings')
      .fold(0, (sum, a) => sum + balance(a));

  int cashFor(String filter) => inScope(filter)
      .where((a) => a.type == 'cash')
      .fold(0, (sum, a) => sum + balance(a));

  /// Total liquidités = courants + épargne (+ espèces).
  /// Le crédit disponible d'une carte n'y est jamais inclus.
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

  int reservedFor(String filter) => projects
      .where((p) => filter == 'all' || p.scope == filter)
      .fold(0, (sum, p) => sum + reserved(p));

  int get totalReserved =>
      projects.fold(0, (sum, p) => sum + reserved(p));

  int get available => liquidTotal - totalReserved;

  /// Disponible pour les projets = comptes courants admissibles
  /// moins réservations actives du périmètre.
  int projectAvailableFor(String filter) =>
      checkingFor(filter) - reservedFor(filter);

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

  String homeContributionCategoryId() {
    for (final c in categories) {
      if (c.name.toLowerCase() == 'contribution au foyer') return c.id;
    }
    throw Exception('Catégorie « Contribution au foyer » introuvable.');
  }

  List<Account> get jointAccounts =>
      accounts.where((a) => a.scope == 'joint').toList();

  List<Account> get personalSourceAccounts => accounts
      .where((a) => a.scope == 'personal' && liquid(a) && a.type != 'credit')
      .toList();

  Entry? entryForContribution(Contribution c) {
    if (c.entryId != null) {
      for (final e in entries) {
        if (e.id == c.entryId) return e;
      }
    }
    Entry? found;
    for (final e in entries) {
      if (e.contributionId == c.id) {
        if (found != null) {
          throw Exception(
              'Deux écritures liées à la même contribution : corrigez avant de continuer.');
        }
        found = e;
      }
    }
    return found;
  }

  void _replaceContribution(Contribution old, Contribution updated) {
    final index = contributions.indexWhere((c) => c.id == old.id);
    if (index == -1) throw Exception('Suivi de contribution introuvable.');
    contributions[index] = updated;
  }

  String _contributionStatus(int expected, int received) {
    if (received <= 0) return 'attendu';
    if (received < expected) return 'partiel';
    return 'reçu';
  }

  /// Crée une contribution attendue. Ne modifie pas les soldes.
  void planContribution({
    required String person,
    required int expected,
    required DateTime dueDate,
    required String accountId,
  }) {
    if (!authors.containsKey(person)) throw Exception('Personne invalide.');
    if (expected <= 0) throw Exception('Le montant attendu doit être positif.');
    if (!jointAccounts.any((a) => a.id == accountId)) {
      throw Exception('Choisissez un compte commun.');
    }
    contributions.add(Contribution(
      id: id(),
      person: person,
      expected: expected,
      received: 0,
      dueDate: dueDate,
      status: 'attendu',
      accountId: accountId,
    ));
  }

  /// Confirme un montant qui vient d'être reçu (partiel accepté).
  /// Idempotent : met à jour l'écriture liée au lieu d'en créer une 2e.
  void confirmContributionReceived({
    required String contributionId,
    required int amountNow,
    required DateTime date,
    String? sourceAccountId,
  }) {
    if (amountNow <= 0) throw Exception('Le montant reçu doit être positif.');
    final c = contributions.firstWhere((x) => x.id == contributionId);
    final total = c.received + amountNow;
    _applyContributionTotal(
      c,
      total,
      date,
      sourceAccountId: sourceAccountId,
    );
  }

  /// Corrige le total reçu (ex. erreur de saisie). Met à jour l'écriture.
  void correctContributionReceived({
    required String contributionId,
    required int newTotal,
    required DateTime date,
    String? sourceAccountId,
  }) {
    if (newTotal < 0) throw Exception('Total invalide.');
    final c = contributions.firstWhere((x) => x.id == contributionId);
    _applyContributionTotal(
      c,
      newTotal,
      date,
      sourceAccountId: sourceAccountId,
    );
  }

  void _applyContributionTotal(
    Contribution c,
    int total,
    DateTime date, {
    String? sourceAccountId,
  }) {
    Entry? linked;
    try {
      linked = entryForContribution(c);
    } catch (_) {
      rethrow;
    }

    if (total == 0) {
      if (linked != null) {
        entries.removeWhere((e) => e.id == linked!.id);
      }
      _replaceContribution(
        c,
        Contribution(
          id: c.id,
          person: c.person,
          expected: c.expected,
          received: 0,
          dueDate: c.dueDate,
          receivedDate: null,
          status: 'attendu',
          accountId: c.accountId,
        ),
      );
      return;
    }

    if (c.person == 'me') {
      if (sourceAccountId == null) {
        throw Exception('Choisissez le compte personnel débité.');
      }
      final src = account(sourceAccountId);
      if (src.scope != 'personal' || !liquid(src)) {
        throw Exception('Le versement part d’un compte personnel liquide.');
      }
      if (src.id == c.accountId) {
        throw Exception('Choisissez deux comptes différents.');
      }
      if (linked != null) {
        if (linked.kind != 'transfer') {
          throw Exception(
              'L’écriture liée n’est pas un transfert : corrigez avant de continuer.');
        }
        entries.removeWhere((e) => e.id == linked!.id);
        entries.add(Entry(
          id: linked.id,
          kind: 'transfer',
          account: src.id,
          destination: c.accountId,
          amount: total,
          date: date,
          note: 'Contribution au foyer — Moi',
          scope: 'joint',
          author: 'me',
          contributionId: c.id,
        ));
      } else {
        final created = Entry(
          id: id(),
          kind: 'transfer',
          account: src.id,
          destination: c.accountId,
          amount: total,
          date: date,
          note: 'Contribution au foyer — Moi',
          scope: 'joint',
          author: 'me',
          contributionId: c.id,
        );
        entries.add(created);
        linked = created;
      }
      _replaceContribution(
        c,
        Contribution(
          id: c.id,
          person: c.person,
          expected: c.expected,
          received: total,
          dueDate: c.dueDate,
          receivedDate: date,
          status: _contributionStatus(c.expected, total),
          accountId: c.accountId,
          entryId: linked!.id,
        ),
      );
      return;
    }

    // Versement de ma femme : entrée externe, pas un transfert.
    final catId = homeContributionCategoryId();
    if (linked != null) {
      if (linked.kind != 'income') {
        throw Exception(
            'L’écriture liée n’est pas un revenu : corrigez avant de continuer.');
      }
      entries.removeWhere((e) => e.id == linked!.id);
      entries.add(Entry(
        id: linked.id,
        kind: 'income',
        account: c.accountId,
        category: catId,
        amount: total,
        date: date,
        note: 'Contribution au foyer — Ma femme',
        scope: 'joint',
        author: 'wife',
        contributionId: c.id,
      ));
    } else {
      final created = Entry(
        id: id(),
        kind: 'income',
        account: c.accountId,
        category: catId,
        amount: total,
        date: date,
        note: 'Contribution au foyer — Ma femme',
        scope: 'joint',
        author: 'wife',
        contributionId: c.id,
      );
      entries.add(created);
      linked = created;
    }
    _replaceContribution(
      c,
      Contribution(
        id: c.id,
        person: c.person,
        expected: c.expected,
        received: total,
        dueDate: c.dueDate,
        receivedDate: date,
        status: _contributionStatus(c.expected, total),
        accountId: c.accountId,
        entryId: linked!.id,
      ),
    );
  }

  /// Annule le versement : supprime l'écriture liée, revient à « attendu ».
  void cancelContributionReceived(String contributionId) {
    final c = contributions.firstWhere((x) => x.id == contributionId);
    final linked = entryForContribution(c);
    if (linked != null) {
      entries.removeWhere((e) => e.id == linked.id);
    }
    _replaceContribution(
      c,
      Contribution(
        id: c.id,
        person: c.person,
        expected: c.expected,
        received: 0,
        dueDate: c.dueDate,
        receivedDate: null,
        status: 'attendu',
        accountId: c.accountId,
      ),
    );
  }

  void deleteContribution(String contributionId) {
    final c = contributions.firstWhere((x) => x.id == contributionId);
    if (entryForContribution(c) != null) {
      throw Exception(
          'Annulez d’abord le versement reçu avant de supprimer ce suivi.');
    }
    contributions.removeWhere((x) => x.id == contributionId);
  }

  int jointExpensesTotal(DateTime month) =>
      monthly('expense', month, scope: 'joint');

  Map<String, int> jointExpensesByCategory(DateTime month) {
    final result = <String, int>{};
    for (final c in categories) {
      final amount = monthly('expense', month,
          categoryId: c.id, scope: 'joint');
      if (amount > 0) result[c.id] = amount;
    }
    return result;
  }

  /// Échéances à venir (prévu), triées. Ne modifient pas les soldes.
  List<Due> upcomingDues({String scope = 'all'}) {
    final list = dues
        .where((d) =>
            d.status == 'prévu' &&
            (scope == 'all' || d.scope == scope))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  /// Sorties de trésorerie comptabilisées sur le mois (dépenses + transferts
  /// sortants, dont le paiement total des crédits).
  int cashOut(DateTime month, {String scope = 'all'}) {
    var out = monthly('expense', month, scope: scope);
    for (final e in entries.where((e) =>
        e.kind == 'transfer' && sameMonth(e.date, month))) {
      if (scope != 'all') {
        final src = account(e.account).scope;
        if (src != scope) continue;
      }
      out += e.amount;
    }
    return out;
  }

  void planDue({
    required String label,
    required String kind,
    required int total,
    required DateTime dueDate,
    required String accountId,
    required String scope,
    String? categoryId,
    String recurrence = 'none',
    String? loanId,
    int capital = 0,
    int interest = 0,
    int insurance = 0,
    int fees = 0,
  }) {
    if (!dueKinds.containsKey(kind)) throw Exception('Type d’échéance invalide.');
    if (!dueRecurrences.containsKey(recurrence)) {
      throw Exception('Récurrence invalide.');
    }
    if (total <= 0) throw Exception('Le montant doit être positif.');
    if (capital + interest + insurance + fees != total && kind == 'loan') {
      throw Exception(
          'Capital + intérêts + assurance + frais doit égaler le total.');
    }
    account(accountId);
    if (!scopes.containsKey(scope)) throw Exception('Périmètre invalide.');
    dues.add(Due(
      id: id(),
      label: label,
      kind: kind,
      total: total,
      capital: capital,
      interest: interest,
      insurance: insurance,
      fees: fees,
      dueDate: dueDate,
      accountId: accountId,
      scope: scope,
      categoryId: categoryId,
      recurrence: recurrence,
      loanId: loanId,
    ));
  }

  /// Comptabilise une échéance. Idempotent : si des écritures liées existent,
  /// elles sont mises à jour, pas dupliquées. Relance la récurrence mensuelle.
  /// DiPeSa enregistre : aucun paiement bancaire réel.
  void settleDue({required String dueId, required DateTime date}) {
    final index = dues.indexWhere((d) => d.id == dueId);
    if (index == -1) throw Exception('Échéance introuvable.');
    final d = dues[index];
    if (d.status == 'comptabilisé' && d.entryIds.isNotEmpty) {
      // Déjà comptabilisée : on ne rejoue rien (idempotence multi-appareils).
      return;
    }
    final src = account(d.accountId);
    final createdIds = <String>[];

    if (d.kind == 'card') {
      // Remboursement carte : transfert, pas une dépense, pas de modèle immo.
      final card = accounts.firstWhere(
        (a) => a.type == 'credit',
        orElse: () => throw Exception(
            'Créez d’abord une carte de crédit pour ce remboursement.'),
      );
      final t = Entry(
        id: id(),
        kind: 'transfer',
        account: src.id,
        destination: card.id,
        amount: d.total,
        date: date,
        note: d.label,
        scope: src.scope,
        author: 'me',
      );
      entries.add(t);
      createdIds.add(t.id);
    } else if (d.kind == 'loan') {
      // Mensualité : débit total du compte source ; la dette ne baisse que
      // du capital ; intérêts/assurance/frais = dépenses (pas de conso).
      Loan? loan;
      if (d.loanId != null) {
        for (final l in loans) {
          if (l.id == d.loanId) loan = l;
        }
      }
      final debtId = loan?.debtAccountId;
      final debt = debtId == null
          ? null
          : accounts.firstWhere((a) => a.id == debtId);
      if (d.capital > 0 && debt != null) {
        final t = Entry(
          id: id(),
          kind: 'transfer',
          account: src.id,
          destination: debt.id,
          amount: d.capital,
          date: date,
          note: '${d.label} — capital',
          scope: d.scope,
          author: 'me',
        );
        entries.add(t);
        createdIds.add(t.id);
      }
      void expensePart(int part, String suffix) {
        if (part <= 0) return;
        final e = Entry(
          id: id(),
          kind: 'expense',
          account: src.id,
          category: d.categoryId ?? categories.first.id,
          amount: part,
          date: date,
          note: '${d.label} — $suffix',
          scope: d.scope,
          author: 'me',
        );
        entries.add(e);
        createdIds.add(e.id);
      }

      expensePart(d.interest, 'intérêts');
      expensePart(d.insurance, 'assurance');
      expensePart(d.fees, 'frais');
      if (d.capital == 0 && d.interest == 0 && d.insurance == 0 && d.fees == 0) {
        // Sans ventilation : sortie simple comptée en dépense.
        final e = Entry(
          id: id(),
          kind: 'expense',
          account: src.id,
          category: d.categoryId ?? categories.first.id,
          amount: d.total,
          date: date,
          note: d.label,
          scope: d.scope,
          author: 'me',
        );
        entries.add(e);
        createdIds.add(e.id);
      }
      if (loan != null) {
        final li = loans.indexWhere((l) => l.id == loan!.id);
        loans[li] = Loan(
          id: loan.id,
          name: loan.name,
          debtAccountId: loan.debtAccountId,
          initialAmount: loan.initialAmount,
          startDate: loan.startDate,
          annualRate: loan.annualRate,
          months: loan.months,
          monthly: loan.monthly,
          insuranceMonthly: loan.insuranceMonthly,
          feesMonthly: loan.feesMonthly,
          sourceAccountId: loan.sourceAccountId,
          scope: loan.scope,
          remainingDue: loan.remainingDue,
          remainingDate: loan.remainingDate,
          paidCount: loan.paidCount + 1,
        );
      }
    } else {
      final e = Entry(
        id: id(),
        kind: 'expense',
        account: src.id,
        category: d.categoryId ?? categories.first.id,
        amount: d.total,
        date: date,
        note: d.label,
        scope: d.scope,
        author: 'me',
      );
      entries.add(e);
      createdIds.add(e.id);
    }

    dues[index] = Due(
      id: d.id,
      label: d.label,
      kind: d.kind,
      total: d.total,
      capital: d.capital,
      interest: d.interest,
      insurance: d.insurance,
      fees: d.fees,
      dueDate: d.dueDate,
      accountId: d.accountId,
      scope: d.scope,
      categoryId: d.categoryId,
      status: 'comptabilisé',
      entryIds: createdIds,
      recurrence: d.recurrence,
      loanId: d.loanId,
    );

    // Récurrence mensuelle : génère l'échéance suivante (prévu), même total.
    if (d.recurrence == 'monthly') {
      final next = DateTime(d.dueDate.year, d.dueDate.month + 1, d.dueDate.day);
      dues.add(Due(
        id: id(),
        label: d.label,
        kind: d.kind,
        total: d.total,
        capital: d.capital,
        interest: d.interest,
        insurance: d.insurance,
        fees: d.fees,
        dueDate: next,
        accountId: d.accountId,
        scope: d.scope,
        categoryId: d.categoryId,
        recurrence: 'monthly',
        loanId: d.loanId,
      ));
    }
  }

  void cancelDueSettlement(String dueId) {
    final index = dues.indexWhere((d) => d.id == dueId);
    if (index == -1) throw Exception('Échéance introuvable.');
    final d = dues[index];
    entries.removeWhere((e) => d.entryIds.contains(e.id));
    dues[index] = Due(
      id: d.id,
      label: d.label,
      kind: d.kind,
      total: d.total,
      capital: d.capital,
      interest: d.interest,
      insurance: d.insurance,
      fees: d.fees,
      dueDate: d.dueDate,
      accountId: d.accountId,
      scope: d.scope,
      categoryId: d.categoryId,
      status: 'prévu',
      entryIds: [],
      recurrence: d.recurrence,
      loanId: d.loanId,
    );
  }

  void deleteDue(String dueId) {
    final d = dues.firstWhere((x) => x.id == dueId);
    if (d.status == 'comptabilisé') {
      throw Exception(
          'Annulez d’abord la comptabilisation avant de supprimer.');
    }
    dues.removeWhere((x) => x.id == dueId);
  }

  /// Crée un crédit + son compte de dette (montant dû).
  /// Pour un crédit déjà commencé : renseignez remainingDue/remainingDate
  /// (ou importez l'échéancier) au lieu de rejouer les mensualités passées.
  void planLoan({
    required String name,
    required int initialAmount,
    required DateTime startDate,
    required double annualRate,
    required int months,
    required int monthly,
    required String sourceAccountId,
    required String scope,
    int insuranceMonthly = 0,
    int feesMonthly = 0,
    int? remainingDue,
    DateTime? remainingDate,
    String debtAccountName = '',
  }) {
    if (initialAmount <= 0 || months <= 0 || monthly <= 0) {
      throw Exception('Montant, durée et mensualité doivent être positifs.');
    }
    if (annualRate < 0 || annualRate > 100) {
      throw Exception('Taux annuel invalide.');
    }
    final bookedDate = remainingDate ?? startDate;
    if (bookedDate.isAfter(parseDate(dateText(DateTime.now())))) {
      throw Exception('La date de reprise ne peut pas être future.');
    }
    if (remainingDue != null && remainingDue <= 0) {
      throw Exception('Capital restant dû invalide.');
    }
    account(sourceAccountId);
    final debt = Account(
      id(),
      debtAccountName.isEmpty ? 'Crédit — $name' : debtAccountName,
      'loan',
      0,
      scope: scope,
    );
    accounts.add(debt);
    final due = remainingDue ?? initialAmount;
    entries.add(Entry(
      id: id(),
      kind: 'adjustment',
      account: debt.id,
      amount: -due,
      date: remainingDate ?? startDate,
      note: remainingDue == null
          ? 'Capital initial — $name'
          : 'Capital restant dû — $name (reprise, sans rejouer le passé)',
      scope: scope,
    ));
    loans.add(Loan(
      id: id(),
      name: name,
      debtAccountId: debt.id,
      initialAmount: initialAmount,
      startDate: startDate,
      annualRate: annualRate,
      months: months,
      monthly: monthly,
      insuranceMonthly: insuranceMonthly,
      feesMonthly: feesMonthly,
      sourceAccountId: sourceAccountId,
      scope: scope,
      remainingDue: remainingDue,
      remainingDate: remainingDate,
    ));
  }

  /// Ventilation d'une mensualité à capital constant d'intérêts dégressifs :
  /// intérêts du mois = restant dû × taux annuel / 12.
  Map<String, int> loanSplit(Loan loan, int remaining) {
    final interest =
        ((remaining * loan.annualRate / 12 / 100).round()).clamp(0, loan.monthly);
    final capital = (loan.monthly - interest).clamp(0, loan.monthly);
    return {'capital': capital, 'interest': interest};
  }

  /// Aperçu d'un document décodé (post-migration) avant import.
  static Map<String, int> summarizeDoc(Map<String, dynamic> doc) {
    int count(String key) => ((doc[key] as List?) ?? []).length;
    var net = 0;
    final impactByAccount = <String, int>{};
    for (final raw in ((doc['entries'] as List?) ?? [])) {
      final e = Map<String, dynamic>.from(raw as Map);
      final amount = (e['amount'] as int?) ?? 0;
      if (e['kind'] == 'transfer') {
        impactByAccount[e['account'] as String] =
            (impactByAccount[e['account'] as String] ?? 0) - amount;
        final dst = e['destination'] as String?;
        if (dst != null) {
          impactByAccount[dst] =
              (impactByAccount[dst] ?? 0) + amount;
        }
      } else if (e['account'] != null) {
        final signed = e['kind'] == 'expense' ? -amount : amount;
        impactByAccount[e['account'] as String] =
            (impactByAccount[e['account'] as String] ?? 0) + signed;
      }
    }
    for (final v in impactByAccount.values) {
      net += v;
    }
    return {
      'version': (doc['version'] as int?) ?? 0,
      'accounts': count('accounts'),
      'categories': count('categories'),
      'entries': count('entries'),
      'projects': count('projects'),
      'contributions': count('contributions'),
      'dues': count('dues'),
      'loans': count('loans'),
      'net': net,
    };
  }

  /// Compte, par collection, les objets déjà présents (doublons ignorés en fusion).
  Map<String, int> duplicateCounts(Map<String, dynamic> doc) {
    int dups(String key, Set<String> live) {
      var n = 0;
      for (final raw in ((doc[key] as List?) ?? [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (live.contains(m['id'])) n++;
      }
      return n;
    }

    final budgetKeys = ((doc['budgets'] as Map?) ?? {}).keys
        .where((k) => budgets.containsKey(k))
        .length;
    return {
      'accounts': dups('accounts', accounts.map((e) => e.id).toSet()),
      'categories': dups('categories', categories.map((e) => e.id).toSet()),
      'entries': dups('entries', entries.map((e) => e.id).toSet()),
      'projects': dups('projects', projects.map((e) => e.id).toSet()),
      'contributions':
          dups('contributions', contributions.map((e) => e.id).toSet()),
      'dues': dups('dues', dues.map((e) => e.id).toSet()),
      'loans': dups('loans', loans.map((e) => e.id).toSet()),
      'budgets': budgetKeys,
    };
  }

  /// Fusion : ajoute uniquement les objets inconnus (anti-doublons par id),
  /// les budgets entrants écrasent par clé. Atomique via change() + validate().
  /// Les relations et identités des échéances sont conservées (ids intacts).
  void mergeDoc(Map<String, dynamic> doc) {
    void addNew<T>(
        String key, Set<String> live, List<T> target, T Function(Map<String, dynamic>) parse) {
      for (final raw in ((doc[key] as List?) ?? [])) {
        final m = jsonMap(raw);
        if (live.contains(m['id'])) continue;
        target.add(parse(m));
      }
    }

    addNew('accounts', accounts.map((e) => e.id).toSet(), accounts,
        Account.fromJson);
    addNew('categories', categories.map((e) => e.id).toSet(), categories,
        Category.fromJson);
    addNew('entries', entries.map((e) => e.id).toSet(), entries,
        Entry.fromJson);
    addNew('projects', projects.map((e) => e.id).toSet(), projects,
        Project.fromJson);
    addNew('contributions', contributions.map((e) => e.id).toSet(),
        contributions, Contribution.fromJson);
    addNew('dues', dues.map((e) => e.id).toSet(), dues, Due.fromJson);
    addNew('loans', loans.map((e) => e.id).toSet(), loans, Loan.fromJson);
    // Allocations sans id : anti-doublon par contenu (projet+montant+date).
    final liveAllocs = allocations
        .map((a) => '${a.project}|${a.amount}|${dateText(a.date)}')
        .toSet();
    for (final raw in ((doc['allocations'] as List?) ?? [])) {
      final a = Allocation.fromJson(jsonMap(raw));
      final key = '${a.project}|${a.amount}|${dateText(a.date)}';
      if (liveAllocs.contains(key)) continue;
      liveAllocs.add(key);
      allocations.add(a);
    }
    final incoming = Map<String, int>.from((doc['budgets'] as Map?) ?? {});
    budgets.addAll(incoming);
    ensureHomeContributionCategory();
  }

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
            account(e.account).type != 'bank') {
          throw Exception(
            'Une dépense de projet doit utiliser un compte courant.',
          );
        }
      }
      if (e.date.isAfter(DateTime.now())) {
        throw Exception(
            'Opération future : utilisez une échéance (Budget / Échéances), comptabilisée à sa date.');
      }
    }

    final dueIds = dues.map((e) => e.id).toSet();
    final loanIds = loans.map((e) => e.id).toSet();
    if (dueIds.length != dues.length || loanIds.length != loans.length) {
      throw Exception('Identifiants dupliqués.');
    }

    for (final d in dues) {
      if (!dueKinds.containsKey(d.kind) ||
          !dueRecurrences.containsKey(d.recurrence) ||
          !['prévu', 'comptabilisé'].contains(d.status)) {
        throw Exception('Échéance invalide.');
      }
      if (!accountIds.contains(d.accountId)) {
        throw Exception('Compte de prélèvement introuvable.');
      }
      if (!scopes.containsKey(d.scope)) {
        throw Exception('Périmètre d’échéance invalide.');
      }
      if (d.total <= 0) throw Exception('Montant d’échéance invalide.');
      if (d.kind == 'loan' &&
          d.capital + d.interest + d.insurance + d.fees != d.total) {
        throw Exception('Ventilation de mensualité incohérente.');
      }
      for (final eid in d.entryIds) {
        if (!entryIds.contains(eid)) {
          throw Exception('Écriture d’échéance introuvable.');
        }
      }
      if (d.status == 'prévu' && d.entryIds.isNotEmpty) {
        throw Exception('Échéance prévue avec écritures liées.');
      }
      if (d.loanId != null && !loanIds.contains(d.loanId)) {
        throw Exception('Crédit lié introuvable.');
      }
    }

    for (final l in loans) {
      if (!accountIds.contains(l.debtAccountId) ||
          !accountIds.contains(l.sourceAccountId)) {
        throw Exception('Comptes du crédit introuvables.');
      }
      if (account(l.debtAccountId).type != 'loan') {
        throw Exception('Le compte de dette doit être un crédit.');
      }
      if (!scopes.containsKey(l.scope)) {
        throw Exception('Périmètre de crédit invalide.');
      }
      if (l.initialAmount <= 0 || l.months <= 0 || l.monthly <= 0) {
        throw Exception('Crédit invalide.');
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
      if (!scopes.containsKey(p.scope)) {
        throw Exception('Périmètre de projet invalide.');
      }
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
  final recovery = TextEditingController();
  final auth = LocalAuthentication();

  bool busy = false;
  String step = 'loading';
  bool biometrics = false;
  String? error;
  String? pendingRecoveryCode;
  bool legacyVerifier = false;
  bool storeOpened = false;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final raw = await widget.store.secure.read(key: 'pin-verifier');
      if (raw == null) {
        step = 'createPin';
      } else {
        legacyVerifier = jsonMap(jsonDecode(raw))['v'] == null;
        step = 'enterPin';
      }
      biometrics =
          await widget.store.secure.read(key: 'biometrics') == 'true';
    } catch (_) {
      error = 'Impossible d’accéder au stockage sécurisé du téléphone.';
      step = 'enterPin';
    }
    if (mounted) setState(() {});
  }

  Future<void> checkBlock() async {
    final raw = await widget.store.secure.read(key: 'pin-blocked-until');
    if (raw != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
      if (DateTime.now().isBefore(until)) {
        throw Exception(
            'Trop d’essais. Patientez 30 secondes avant de réessayer.');
      }
    }
  }

  Future<void> registerFailure() async {
    final raw = await widget.store.secure.read(key: 'pin-fails');
    final fails = (raw == null ? 0 : int.parse(raw)) + 1;
    if (fails >= 5) {
      await widget.store.secure.write(key: 'pin-fails', value: '0');
      await widget.store.secure.write(
        key: 'pin-blocked-until',
        value: '${DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch}',
      );
    } else {
      await widget.store.secure.write(key: 'pin-fails', value: '$fails');
    }
  }

  Future<void> resetFailures() async {
    await widget.store.secure.delete(key: 'pin-fails');
    await widget.store.secure.delete(key: 'pin-blocked-until');
  }

  Future<bool> checkPin(String text) async {
    final raw = await widget.store.secure.read(key: 'pin-verifier');
    if (raw == null) throw Exception('Configuration du PIN introuvable.');
    final verifier = jsonMap(jsonDecode(raw));
    final derived = await passwordKey(
      text,
      base64Decode(verifier['salt'] as String),
    );
    return constantEquals(
      await derived.extractBytes(),
      base64Decode(verifier['hash'] as String),
    );
  }

  Future<void> writeVerifier(String text) async {
    final salt = randomBytes(16);
    final derived = await passwordKey(text, salt);
    await widget.store.secure.write(
      key: 'pin-verifier',
      value: jsonEncode({
        'v': 2,
        'salt': base64Encode(salt),
        'hash': base64Encode(await derived.extractBytes()),
      }),
    );
  }

  /// Le code de récupération chiffre une copie de la clé de base : il permet
  /// réellement de rétablir l'accès sur CET appareil (pas un contournement).
  /// Il ne part jamais sur un autre appareil (nouvel iPhone = export + mot de passe).
  Future<void> writeRecoveryRecord(String code) async {
    final encodedKey = await widget.store.secure.read(key: 'database-key');
    if (encodedKey == null) {
      throw Exception('Clé locale introuvable : impossible de sceller le code.');
    }
    final salt = randomBytes(16);
    final wrapKey = await passwordKey(
      normalizeRecoveryCode(code),
      salt,
    );
    final envelope =
        await encrypt(base64Decode(encodedKey), wrapKey);
    await widget.store.secure.write(
      key: 'pin-recovery',
      value: jsonEncode({
        'v': 1,
        'salt': base64Encode(salt),
        'wrap': envelope,
      }),
    );
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
        await widget.store.open();
        await resetFailures();
        if (mounted) widget.onUnlocked();
        return;
      }

      await checkBlock();
      final accepted = await checkPin(pin.text);
      if (!accepted) {
        await registerFailure();
        throw Exception('Code PIN incorrect.');
      }
      await resetFailures();
      await widget.store.open();
      storeOpened = true;
      if (legacyVerifier) {
        // Migration sécurisée de l'ancien PIN (6 chiffres) : nouveau PIN
        // à 4 chiffres + code de récupération avant d'entrer.
        pin.clear();
        confirm.clear();
        setState(() => step = 'migratePin');
        return;
      }
      if (mounted) widget.onUnlocked();
    } catch (e) {
      if (mounted) {
        setState(() => error = cleanError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startRecoveryDisplay({bool migration = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!validPin(pin.text)) {
        throw Exception('Choisissez un PIN de 4 chiffres.');
      }
      if (pin.text != confirm.text) {
        throw Exception('Les deux codes ne correspondent pas.');
      }
      pendingRecoveryCode = generateRecoveryCode();
      recovery.clear();
      setState(() => step = 'showRecovery');
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmRecoveryDisplay() async {
    if (busy || pendingRecoveryCode == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (normalizeRecoveryCode(recovery.text) !=
          normalizeRecoveryCode(pendingRecoveryCode!)) {
        throw Exception('Recopiez le code affiché pour prouver que vous l’avez noté.');
      }
      if (!storeOpened) {
        await writeVerifier(pin.text);
        await widget.store.open();
        storeOpened = true;
      } else if (legacyVerifier) {
        await writeVerifier(pin.text);
        legacyVerifier = false;
      }
      await writeRecoveryRecord(pendingRecoveryCode!);
      pendingRecoveryCode = null;
      if (mounted) widget.onUnlocked();
    } catch (e) {
      if (mounted) setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recoverWithCode() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await checkBlock();
      final raw = await widget.store.secure.read(key: 'pin-recovery');
      if (raw == null) {
        throw Exception(
            'Aucun code de récupération sur cet appareil. Nouvel iPhone : utilisez l’export chiffré + mot de passe.');
      }
      final record = jsonMap(jsonDecode(raw));
      final wrapKey = await passwordKey(
        normalizeRecoveryCode(recovery.text),
        base64Decode(record['salt'] as String),
      );
      List<int> dbKey;
      try {
        dbKey = await decrypt(jsonMap(record['wrap']), wrapKey);
      } catch (_) {
        await registerFailure();
        throw Exception('Code de récupération incorrect.');
      }
      // Rétablit la clé locale (y compris si elle avait disparu), puis
      // impose un nouveau PIN : pas de contournement, la clé fait foi.
      await widget.store.secure
          .write(key: 'database-key', value: base64Encode(dbKey));
      await resetFailures();
      await widget.store.open();
      storeOpened = true;
      legacyVerifier = false;
      pin.clear();
      confirm.clear();
      setState(() => step = 'newPinAfterRecovery');
    } catch (e) {
      if (mounted) setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finishNewPinAfterRecovery() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!validPin(pin.text)) {
        throw Exception('Choisissez un PIN de 4 chiffres.');
      }
      if (pin.text != confirm.text) {
        throw Exception('Les deux codes ne correspondent pas.');
      }
      await writeVerifier(pin.text);
      if (mounted) widget.onUnlocked();
    } catch (e) {
      if (mounted) setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    pin.dispose();
    confirm.dispose();
    recovery.dispose();
    super.dispose();
  }

  Widget pinField(TextEditingController c, String label) => TextField(
        controller: c,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 4,
        decoration: InputDecoration(labelText: label),
      );

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
                  Text(switch (step) {
                    'createPin' => 'Créez votre code personnel (4 chiffres)',
                    'showRecovery' => 'Notez votre code de récupération',
                    'migratePin' => 'Nouveau : PIN à 4 chiffres',
                    'recoverCode' => 'Rétablir l’accès avec le code',
                    'newPinAfterRecovery' => 'Choisissez un nouveau PIN',
                    _ => 'Vos finances, rien qu’à vous',
                  }),
                  const SizedBox(height: 28),
                  if (step == 'loading')
                    const CircularProgressIndicator()
                  else ...[
                    if (step == 'enterPin') ...[
                      pinField(pin, 'Code PIN (4 chiffres)'),
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
                        child:
                            Text(busy ? 'Ouverture…' : 'Déverrouiller'),
                      ),
                      if (biometrics)
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => unlock(biometric: true),
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Face ID / biométrie'),
                        ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                recovery.clear();
                                setState(() {
                                  error = null;
                                  step = 'recoverCode';
                                });
                              },
                        child: const Text('PIN oublié ? Code de récupération'),
                      ),
                    ],
                    if (step == 'createPin') ...[
                      pinField(pin, 'Code PIN (4 chiffres)'),
                      pinField(confirm, 'Confirmer le PIN'),
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
                        onPressed:
                            busy ? null : () => startRecoveryDisplay(),
                        child: Text(busy ? '…' : 'Créer mon espace'),
                      ),
                    ],
                    if (step == 'migratePin') ...[
                      const Text(
                        'Votre ancien code est remplacé : choisissez un PIN de 4 chiffres, puis notez le code de récupération.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      pinField(pin, 'Nouveau PIN (4 chiffres)'),
                      pinField(confirm, 'Confirmer le PIN'),
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
                        onPressed:
                            busy ? null : () => startRecoveryDisplay(migration: true),
                        child: const Text('Continuer'),
                      ),
                    ],
                    if (step == 'showRecovery') ...[
                      panelLikeCode(),
                      const SizedBox(height: 12),
                      const Text(
                        'Recopiez-le ci-dessous pour prouver que vous l’avez conservé. Il ne s’affichera plus. Sur un nouvel iPhone, utilisez l’export chiffré + son mot de passe (différent du PIN).',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: recovery,
                        decoration: const InputDecoration(
                            labelText: 'Recopier le code'),
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
                        onPressed:
                            busy ? null : () => confirmRecoveryDisplay(),
                        child: const Text('J’ai noté le code, entrer'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  pendingRecoveryCode = null;
                                  error = null;
                                  step = storeOpened
                                      ? 'migratePin'
                                      : 'createPin';
                                }),
                        child: const Text('Retour'),
                      ),
                    ],
                    if (step == 'recoverCode') ...[
                      TextField(
                        controller: recovery,
                        decoration: const InputDecoration(
                            labelText: 'Code de récupération'),
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
                        onPressed:
                            busy ? null : () => recoverWithCode(),
                        child: const Text('Rétablir l’accès'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  error = null;
                                  step = 'enterPin';
                                }),
                        child: const Text('Retour'),
                      ),
                    ],
                    if (step == 'newPinAfterRecovery') ...[
                      pinField(pin, 'Nouveau PIN (4 chiffres)'),
                      pinField(confirm, 'Confirmer le PIN'),
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
                        onPressed:
                            busy ? null : () => finishNewPinAfterRecovery(),
                        child: const Text('Enregistrer et entrer'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'Données locales chiffrées • PIN ≠ mot de passe d’export • Aucune connexion bancaire',
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

  Widget panelLikeCode() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          pendingRecoveryCode ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: ink,
          ),
        ),
      );
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
        width: double.maxFinite,
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

  @override
  void initState() {
    super.initState();
    ensureReminder();
  }

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
        'loan' => Icons.home_work_outlined,
        'prepaid' => Icons.account_balance_wallet_rounded,
        'investment' => Icons.trending_up_rounded,
        'crypto' => Icons.currency_bitcoin_rounded,
        'stocks' => Icons.candlestick_chart_rounded,
        'realestate' => Icons.house_rounded,
        _ => Icons.account_balance_rounded,
      };

  Future<void> addAccount() async {
    final result = await ask(context, 'Ajouter un compte', [
      const Question('name', 'Nom du compte'),
      const Question('type', 'Type', options: accountTypes),
      const Question('scope', 'Périmètre', initial: 'personal', options: scopes),
      const Question(
        'balance',
        'Solde initial en € / montant dû si carte ou crédit',
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
          final debtLike = type == 'credit' || type == 'loan';
          var initial = money(result['balance']!, signed: !debtLike);
          final limit = type == 'credit' ? money(result['limit']!) : 0;

          if (type == 'credit') {
            if (limit <= 0) throw Exception('Indiquez le plafond de la carte.');
            initial = -initial;
          }
          if (type == 'loan') {
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
          if (kind != 'transfer' &&
              ['investment', 'crypto', 'stocks', 'realestate']
                  .contains(source.type)) {
            throw Exception(
              'Utilisez un transfert pour alimenter ce placement, puis ajustez '
              'la valorisation depuis le compte.',
            );
          }

          final project = result['project'];
          final entryScope = kind == 'transfer'
              ? s.account(result['destination']!).scope
              : (result['scope'] ?? source.scope);
          final entryAuthor = result['author'] ?? 'me';
          final entryDate = parseDate(result['date']!);
          s.entries.add(Entry(
            id: id(),
            kind: kind,
            account: source.id,
            destination: result['destination'],
            category: result['category'],
            project: project == null || project.isEmpty ? null : project,
            amount: amount,
            date: entryDate,
            note: result['note'] ?? '',
            scope: entryScope,
            author: entryAuthor,
          ));
          // Si opération passée : bascule le mois affiché pour recalculer
          // budgets et vues concernées.
          if (!sameMonth(entryDate, month)) {
            month = DateTime(entryDate.year, entryDate.month);
          }
        }));
    if (mounted) setState(() {});
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
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
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
          a.type == 'credit' || a.type == 'loan'
              ? 'Nouveau montant dû en €'
              : 'Nouveau solde en €',
          initial: amountText(
            a.type == 'credit' || a.type == 'loan'
                ? max(0, -s.balance(a))
                : s.balance(a),
          ),
          numeric: true,
        ),
        const Question('note', 'Motif', initial: 'Mise à jour manuelle'),
      ]);
      if (result == null) return;
      await run(() => s.change(() {
            final debtLike = a.type == 'credit' || a.type == 'loan';
            var value = money(
              result['balance']!,
              signed: !debtLike,
            );
            if (debtLike) value = -value;

            s.entries.add(Entry(
              id: id(),
              kind: 'adjustment',
              account: a.id,
              amount: value - s.balance(a),
              date: DateTime.now(),
              note: result['note']!,
              scope: a.scope,
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

  Future<void> addDue() async {
    if (s.accounts.isEmpty) {
      message('Ajoutez d’abord un compte de prélèvement.');
      await addAccount();
      return;
    }
    final result = await ask(context, 'Nouvelle échéance (prévu)', [
      const Question('label', 'Libellé — ex. Électricité, carte 50 €'),
      const Question('kind', 'Type', initial: 'bill', options: dueKinds),
      const Question('total', 'Montant total en €', numeric: true),
      Question(
        'dueDate',
        'Date d’échéance — AAAA-MM-JJ',
        initial: dateText(DateTime.now()),
      ),
      Question(
        'account',
        'Compte de prélèvement',
        initial: s.accounts.first.id,
        options: {for (final a in s.accounts) a.id: a.name},
      ),
      const Question('scope', 'Périmètre', initial: 'personal', options: scopes),
      Question(
        'category',
        'Catégorie (factures)',
        initial: s.categories.first.id,
        options: {
          for (final c in s.categories)
            c.id: '${iconNames[c.icon]?.split(' ').first ?? '🔷'} ${c.name}',
        },
      ),
      const Question('recurrence', 'Récurrence',
          initial: 'none', options: dueRecurrences),
    ]);
    if (result == null) return;
    await run(() => s.change(() {
          final kind = result['kind']!;
          if (kind == 'card' && money(result['total']!) != 5000) {
            // Rappel, pas blocage : le 50 € récurrent reste modifiable.
            message('Rappel : remboursement carte habituel de 50 €.');
          }
          s.planDue(
            label: result['label']!,
            kind: kind,
            total: money(result['total']!),
            dueDate: parseDate(result['dueDate']!),
            accountId: result['account']!,
            scope: result['scope']!,
            categoryId: result['category'],
            recurrence: result['recurrence']!,
          );
        }));
  }

  Future<void> addLoan() async {
    final liquidSources = s.accounts.where((a) => s.liquid(a)).toList();
    if (liquidSources.isEmpty) {
      message('Ajoutez d’abord un compte de prélèvement.');
      await addAccount();
      return;
    }
    final result = await ask(context, 'Nouveau crédit', [
      const Question('name', 'Nom — ex. Maison, voiture'),
      const Question('initial', 'Montant initial emprunté en €', numeric: true),
      Question('start', 'Date de départ — AAAA-MM-JJ',
          initial: dateText(DateTime.now())),
      const Question('rate', 'Taux annuel en % — ex. 3,5', numeric: true),
      const Question('months', 'Durée en mois — ex. 240', numeric: true),
      const Question('monthly', 'Mensualité hors assurance en €', numeric: true),
      const Question('insurance', 'Assurance mensuelle en €',
          initial: '0', numeric: true),
      const Question('fees', 'Frais mensuels en €', initial: '0', numeric: true),
      Question('source', 'Compte de prélèvement',
          initial: liquidSources.first.id,
          options: {for (final a in liquidSources) a.id: a.name}),
      const Question('scope', 'Périmètre', initial: 'personal', options: scopes),
      const Question('resume', 'Crédit déjà commencé ? (oui/non)',
          initial: 'non', optional: true),
      const Question('remaining', 'Capital restant dû en € si reprise',
          initial: '0', numeric: true, optional: true),
      Question('remainingDate', 'Date du restant dû — AAAA-MM-JJ',
          initial: dateText(DateTime.now()), optional: true),
    ]);
    if (result == null) return;
    await run(() => s.change(() {
          final resumed = result['resume']!.trim().toLowerCase() == 'oui';
          s.planLoan(
            name: result['name']!,
            initialAmount: money(result['initial']!),
            startDate: parseDate(result['start']!),
            annualRate: double.parse(result['rate']!.replaceAll(',', '.')),
            months: int.parse(result['months']!),
            monthly: money(result['monthly']!),
            insuranceMonthly: money(result['insurance']!),
            feesMonthly: money(result['fees']!),
            sourceAccountId: result['source']!,
            scope: result['scope']!,
            remainingDue: resumed ? money(result['remaining']!) : null,
            remainingDate:
                resumed && result['remainingDate']!.isNotEmpty
                    ? parseDate(result['remainingDate']!)
                    : null,
          );
        }));
  }

  Future<void> dueActions(Due d) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${d.label} — ${euro(d.total)}'),
              subtitle: Text(
                  '${dueKinds[d.kind]} · le ${dateText(d.dueDate)} · ${d.status}'),
            ),
            if (d.status == 'prévu')
              ListTile(
                leading: const Icon(Icons.check_circle, color: mint),
                title: const Text('Comptabiliser à sa date'),
                subtitle: const Text(
                    'Crée les écritures (capital / intérêts / assurance / frais). Idempotent.'),
                onTap: () => Navigator.pop(ctx, 'settle'),
              ),
            if (d.status == 'comptabilisé')
              ListTile(
                leading: const Icon(Icons.undo, color: violet),
                title: const Text('Annuler la comptabilisation'),
                onTap: () => Navigator.pop(ctx, 'cancel'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'settle':
        final confirm = await ask(context, 'Comptabiliser ${d.label}', [
          Question('date', 'Date comptable — AAAA-MM-JJ',
              initial: dateText(d.dueDate.isAfter(DateTime.now())
                  ? DateTime.now()
                  : d.dueDate)),
        ]);
        if (confirm == null) return;
        await run(() => s.change(() => s.settleDue(
              dueId: d.id,
              date: parseDate(confirm['date']!),
            )));
        break;
      case 'cancel':
        final yes = await confirmAction(
          'Annuler la comptabilisation ?',
          'Les écritures liées seront supprimées.',
        );
        if (yes) {
          await run(() => s.change(() => s.cancelDueSettlement(d.id)));
        }
        break;
      case 'delete':
        final yes = await confirmAction(
          'Supprimer cette échéance ?',
          'Possible uniquement si elle n’est pas comptabilisée.',
        );
        if (yes) {
          await run(() => s.change(() => s.deleteDue(d.id)));
        }
        break;
    }
  }

  Widget duesSection() {
    final upcoming = s.upcomingDues(scope: scopeFilter);
    final settled = dues
        .where((d) =>
            d.status == 'comptabilisé' &&
            (scopeFilter == 'all' || d.scope == scopeFilter))
        .toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    Widget dueTile(Due d) {
      final statusColor =
          d.status == 'comptabilisé' ? const Color(0xFF009A78) : violet;
      return panel(
        InkWell(
          onTap: () => dueActions(d),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: blue.withOpacity(.12),
                child: Icon(
                  d.kind == 'card'
                      ? Icons.credit_card_rounded
                      : d.kind == 'loan'
                          ? Icons.home_work_outlined
                          : Icons.receipt_long_rounded,
                  color: blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d.label} — ${euro(d.total)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${dueKinds[d.kind]} · le ${dateText(d.dueDate)} · ${scopes[d.scope]}'
                      '${d.recurrence == 'monthly' ? ' · mensuelle' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(d.status,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        heading(
          'Échéances — prévu / comptabilisé',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: addLoan,
                tooltip: 'Nouveau crédit',
                icon: const Icon(Icons.home_work_outlined, color: blue),
              ),
              IconButton(
                onPressed: addDue,
                icon: const Icon(Icons.add_circle, color: violet),
              ),
            ],
          ),
        ),
        panel(const Text(
          'Une échéance « prévu » ne modifie pas le solde réel. Comptabilisez-la à sa date : le compte source est débité du total, la dette baisse du capital, intérêts / assurance / frais passent en dépenses. DiPeSa enregistre : aucun paiement bancaire réel.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        )),
        if (s.loans.isNotEmpty)
          panel(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Crédits suivis',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...s.loans.map((l) {
                int debt = 0;
                try {
                  debt = -s.balance(s.account(l.debtAccountId));
                } catch (_) {}
                return Text(
                    '${l.name} : reste ${euro(debt)} · ${l.paidCount} mensualité(s) comptabilisée(s)');
              }),
            ],
          )),
        heading('À venir'),
        if (upcoming.isEmpty) panel(const Text('Aucune échéance prévue.')),
        ...upcoming.map(dueTile),
        heading('Comptabilisées'),
        if (settled.isEmpty) panel(const Text('Rien de comptabilisé.')),
        ...settled.take(10).map(dueTile),
      ],
    );
  }

  Future<void> addCategory() async {    final result = await ask(context, 'Nouvelle catégorie', [
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
      const Question('scope', 'Périmètre', initial: 'personal', options: scopes),
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
            scope: result['scope']!,
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
              : 'Montant — disponible projets (${scopes[p.scope]}) : ${euro(s.projectAvailableFor(p.scope))}',
          numeric: true,
        ),
      ],
    );
    if (result == null) return;

    await run(() => s.change(() {
          final amount = money(result['amount']!);
          if (amount <= 0) throw Exception('Indiquez un montant positif.');
          if (!remove && amount > s.projectAvailableFor(p.scope)) {
            throw Exception(
              'Comptes courants ${scopes[p.scope]} insuffisants : '
              'réservation virtuelle impossible au-delà du disponible projets.',
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

  Future<void> addContribution() async {
    if (s.jointAccounts.isEmpty) {
      message('Ajoutez d’abord un compte commun (périmètre « Commun »).');
      await addAccount();
      return;
    }
    final result = await ask(context, 'Contribution attendue', [
      const Question('person', 'Personne', initial: 'me', options: authors),
      const Question(
        'expected',
        'Montant attendu en € — 50/50 par défaut, ajustez au réel',
        numeric: true,
      ),
      Question(
        'dueDate',
        'Date prévue — AAAA-MM-JJ',
        initial: dateText(DateTime.now()),
      ),
      Question(
        'account',
        'Compte commun crédité',
        initial: s.jointAccounts.first.id,
        options: {for (final a in s.jointAccounts) a.id: a.name},
      ),
    ]);
    if (result == null) return;
    await run(() => s.change(() {
          s.planContribution(
            person: result['person']!,
            expected: money(result['expected']!),
            dueDate: parseDate(result['dueDate']!),
            accountId: result['account']!,
          );
        }));
  }

  Future<void> confirmContribution(Contribution c) async {
    final questions = [
      const Question(
        'amount',
        'Montant qui vient d’être reçu en € (partiel accepté)',
        numeric: true,
      ),
      Question(
        'date',
        'Date réelle — AAAA-MM-JJ',
        initial: dateText(DateTime.now()),
      ),
      if (c.person == 'me')
        Question(
          'source',
          'Compte personnel débité (transfert)',
          initial: s.personalSourceAccounts.isEmpty
              ? ''
              : s.personalSourceAccounts.first.id,
          options: {
            for (final a in s.personalSourceAccounts) a.id: a.name,
          },
        ),
    ];
    if (c.person == 'me' && s.personalSourceAccounts.isEmpty) {
      message('Ajoutez d’abord un compte personnel liquide.');
      return;
    }
    final result = await ask(context, 'Confirmer un versement reçu', questions);
    if (result == null) return;
    await run(() => s.change(() {
          s.confirmContributionReceived(
            contributionId: c.id,
            amountNow: money(result['amount']!),
            date: parseDate(result['date']!),
            sourceAccountId:
                c.person == 'me' ? result['source'] : null,
          );
        }));
  }

  Future<void> correctContribution(Contribution c) async {
    final result = await ask(context, 'Corriger le total reçu', [
      Question(
        'total',
        'Nouveau total reçu en € (0 = tout annuler)',
        initial: amountText(c.received),
        numeric: true,
      ),
      Question(
        'date',
        'Date — AAAA-MM-JJ',
        initial: dateText(c.receivedDate ?? DateTime.now()),
      ),
      if (c.person == 'me' && c.received > 0)
        Question(
          'source',
          'Compte personnel débité (transfert)',
          initial: s.personalSourceAccounts.isEmpty
              ? ''
              : s.personalSourceAccounts.first.id,
          options: {
            for (final a in s.personalSourceAccounts) a.id: a.name,
          },
        ),
    ]);
    if (result == null) return;
    await run(() => s.change(() {
          s.correctContributionReceived(
            contributionId: c.id,
            newTotal: money(result['total']!),
            date: parseDate(result['date']!),
            sourceAccountId:
                c.person == 'me' && c.received > 0 ? result['source'] : null,
          );
        }));
  }

  Future<void> contributionActions(Contribution c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                  '${authors[c.person]} — ${euro(c.received)} / ${euro(c.expected)}'),
              subtitle: Text(
                  'Échéance : ${dateText(c.dueDate)} · Statut : ${c.status}'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: mint),
              title: const Text('Confirmer un versement reçu'),
              subtitle: const Text(
                  'Ajoute le montant au total, sans doublon d’écriture'),
              onTap: () => Navigator.pop(ctx, 'confirm'),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: blue),
              title: const Text('Corriger le total reçu'),
              onTap: () => Navigator.pop(ctx, 'correct'),
            ),
            ListTile(
              leading: const Icon(Icons.undo, color: violet),
              title: const Text('Annuler le versement'),
              subtitle: const Text(
                  'Supprime l’écriture liée, revient à « attendu »'),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer ce suivi'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'confirm':
        await confirmContribution(c);
        break;
      case 'correct':
        await correctContribution(c);
        break;
      case 'cancel':
        final yes = await confirmAction(
          'Annuler ce versement ?',
          'L’écriture liée sera supprimée et le suivi repassera à « attendu ».',
        );
        if (yes) {
          await run(() =>
              s.change(() => s.cancelContributionReceived(c.id)));
        }
        break;
      case 'delete':
        final yes = await confirmAction(
          'Supprimer ce suivi ?',
          'Possible uniquement si aucun versement reçu n’est lié.',
        );
        if (yes) {
          await run(() => s.change(() => s.deleteContribution(c.id)));
        }
        break;
    }
  }

  Widget contributionTile(Contribution c) {
    final accountName = () {
      try {
        return s.account(c.accountId).name;
      } catch (_) {
        return 'Compte supprimé';
      }
    }();
    final statusColor = switch (c.status) {
      'reçu' => const Color(0xFF009A78),
      'partiel' => const Color(0xFFF6B543),
      _ => violet,
    };
    return panel(
      InkWell(
        onTap: () => contributionActions(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: mint.withOpacity(.15),
                  child: Icon(
                    c.person == 'me' ? Icons.person : Icons.person_outline,
                    color: mint,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${authors[c.person]} — ${euro(c.received)} / ${euro(c.expected)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Prévue : ${dateText(c.dueDate)}'
                        '${c.receivedDate == null ? '' : ' · Reçue : ${dateText(c.receivedDate!)}'}'
                        ' · $accountName',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.status,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget jointPage() {
    final jointBalance = s.liquidFor('joint');
    final monthExpenses = s.jointExpensesTotal(month);
    final byCategory = s.jointExpensesByCategory(month);
    final byMe = s.monthly('expense', month, scope: 'joint', author: 'me');
    final byWife =
        s.monthly('expense', month, scope: 'joint', author: 'wife');
    final contribMe = s.contributions
        .where((c) => c.person == 'me')
        .fold(0, (sum, c) => sum + c.received);
    final contribWife = s.contributions
        .where((c) => c.person == 'wife')
        .fold(0, (sum, c) => sum + c.received);
    final upcoming = s.contributions
        .where((c) => c.status != 'reçu')
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Column(
      children: [
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SOLDE RÉEL DU COMPTE COMMUN',
                  style: TextStyle(letterSpacing: 1.5, color: ink)),
              const SizedBox(height: 8),
              Text(
                euro(jointBalance),
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w800, color: ink),
              ),
              const SizedBox(height: 8),
              ...s.jointAccounts.map((a) =>
                  Text('${a.name} : ${euro(s.balance(a))}')),
              if (s.jointAccounts.isEmpty)
                const Text('Aucun compte commun pour le moment.'),
              const SizedBox(height: 8),
              const Text(
                'Participation 50/50 par défaut : ajustez les montants réellement versés.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          color: mint.withOpacity(.12),
        ),
        heading(
          'Contributions du mois',
          trailing: IconButton(
            onPressed: addContribution,
            icon: const Icon(Icons.add_circle, color: mint),
          ),
        ),
        if (s.contributions.isEmpty)
          panel(const Text(
              'Planifiez une contribution attendue : elle ne modifie pas le solde tant qu’elle n’est pas confirmée reçue.')),
        ...s.contributions.map(contributionTile),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Contributions reçues — Moi : ${euro(contribMe)}'),
              Text('Contributions reçues — Ma femme : ${euro(contribWife)}'),
              const SizedBox(height: 4),
              const Text(
                'Le versement de ma femme est une entrée externe « Contribution au foyer », pas votre salaire. Votre versement est un transfert depuis un compte personnel : il ne crée ni dépense ni revenu consolidé.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        heading('Dépenses communes — ${monthText(month)}'),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total : ${euro(monthExpenses)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...byCategory.entries.map((entry) {
                final cat = s.category(entry.key);
                return Text(
                    '${cat?.name ?? 'Catégorie'} : ${euro(entry.value)}');
              }),
              const Divider(),
              Text('Payées par moi : ${euro(byMe)}'),
              Text('Payées par ma femme : ${euro(byWife)}'),
              const SizedBox(height: 4),
              const Text(
                '« Payées par chacun » indique qui a réalisé les paiements, pas qui les a financés. Aucune dette n’est calculée entre partenaires.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        heading('Prochaines charges'),
        if (upcoming.isEmpty)
          panel(const Text('Rien en attente.')),
        ...upcoming.map((c) => panel(
              Row(
                children: [
                  Expanded(
                    child: Text(
                        '${authors[c.person]} — reste ${euro(c.expected - c.received)} · le ${dateText(c.dueDate)}'),
                  ),
                  Text(c.status,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            )),
      ],
    );
  }

  Widget dashboard() {
    final expenses = s.monthly('expense', month, scope: scopeFilter);
    final income = s.monthly('income', month, scope: scopeFilter);

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
                euro(s.checkingFor(scopeFilter)),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Argent épargné : ${euro(s.savingsFor(scopeFilter))} · '
                'Périmètre : $scopeLabel',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Text(
                'Argent disponible = comptes courants. Le disponible des cartes n’est jamais compté.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
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
                    a.type == 'credit' || a.type == 'loan'
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
              if (a.type == 'loan') ...[
                const SizedBox(height: 8),
                const Text(
                  'Capital restant dû présenté séparément du patrimoine liquide.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      );
    }

    String typeSummary(List<Account> list) {
      int sum(String type) =>
          list.where((a) => a.type == type).fold(0, (x, a) => x + s.balance(a));
      return 'Courants : ${euro(sum('bank'))} · Épargne : ${euro(sum('savings'))} · '
          'Espèces : ${euro(sum('cash'))} · Cartes dues : ${euro(max(0, -sum('credit')))} · '
          'Crédits dus : ${euro(max(0, -sum('loan')))}';
    }

    List<Account> ordered(List<Account> list) {
      const order = [
        'bank',
        'savings',
        'cash',
        'credit',
        'loan',
        'prepaid',
        'investment',
        'crypto',
        'stocks',
        'realestate'
      ];
      final sorted = list.toList()
        ..sort((a, b) =>
            order.indexOf(a.type).compareTo(order.indexOf(b.type)));
      return sorted;
    }

    final personal = ordered(
        s.accounts.where((a) => a.scope == 'personal').toList());
    final joint =
        ordered(s.accounts.where((a) => a.scope == 'joint').toList());

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
          heading('Personnel — Total liquidités ${euro(s.liquidFor('personal'))}'),
          if (personal.isEmpty)
            panel(const Text('Aucun compte personnel.'))
          else
            panel(Text(
              typeSummary(personal),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            )),
          ...personal.map(accountCard),
          heading('Commun — Total liquidités ${euro(s.liquidFor('joint'))}'),
          if (joint.isEmpty)
            panel(const Text(
                'Aucun compte commun. Ajoutez-le avec le bouton + puis périmètre « Commun ».'))
          else
            panel(Text(
              typeSummary(joint),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            )),
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
            if (limit > 0)
              Text(
                total <= limit
                    ? 'Reste à dépenser : ${euro(limit - total)}'
                    : 'Dépassement : ${euro(total - limit)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: total <= limit ? const Color(0xFF009A78) : Colors.red,
                ),
              ),
            Text('Périmètre : $scopeLabel',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
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
        duesSection(),
        panel(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sorties de trésorerie — ${monthText(month)} : '
                '${euro(s.cashOut(month, scope: scopeFilter))}'),
            const Text(
              'Dépenses + transferts sortants, dont le paiement total des crédits.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        )),
      ],
    );
  }

  Widget projectsPage() {
    final visible = scopeFilter == 'all'
        ? s.projects
        : s.projects.where((p) => p.scope == scopeFilter).toList();
    return Column(
        children: [
          scopeSelector(),
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
                Text('DISPONIBLE POUR LES PROJETS — $scopeLabel'.toUpperCase()),
                const SizedBox(height: 8),
                Text(
                  euro(s.projectAvailableFor(scopeFilter)),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                    '${euro(s.reservedFor(scopeFilter))} réservés · '
                    'Courants ${scopes[scopeFilter] ?? scopeLabel} : ${euro(s.checkingFor(scopeFilter))}'),
                const SizedBox(height: 8),
                const Text(
                  'Réserver une somme ne déplace pas réellement l’argent, '
                  'ne crée pas de dépense et ne place rien automatiquement en épargne. '
                  'La dépense finale se paie depuis un compte courant avec la tirelire choisie : elle libère la réservation.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            color: mint.withOpacity(.12),
          ),
          if (visible.isEmpty)
            panel(const Text(
              'Créez votre première tirelire : chauffage, vacances, '
              'travaux ou fonds de sécurité.',
            )),
          ...visible.map((p) {
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
                final months = max<int>(1, (days / 30.44).ceil());
                final weeks = max<int>(1, (days / 7).ceil());
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            scopes[p.scope] ?? p.scope,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
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
  }

  Widget wealthPage() {
    Widget typeRow(String label, IconData icon, int amount) => ListTile(
          leading: Icon(icon, color: violet),
          title: Text(label),
          trailing: Text(euro(amount)),
        );
    int sumType(String type, [String scope = 'all']) => s.accounts
        .where((a) =>
            a.type == type && (scope == 'all' || a.scope == scope))
        .fold<int>(0, (x, a) => x + s.balance(a));

    return Column(
        children: [
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL LIQUIDITÉS — $scopeLabel'.toUpperCase(),
                    style: const TextStyle(letterSpacing: 1.5, color: ink)),
                const SizedBox(height: 8),
                Text(
                  euro(s.liquidFor(scopeFilter)),
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                    'Comptes courants : ${euro(s.checkingFor(scopeFilter))} · '
                    'Épargne : ${euro(s.savingsFor(scopeFilter))} · '
                    'Espèces : ${euro(s.cashFor(scopeFilter))}'),
                Text('Périmètre : $scopeLabel',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                const Text(
                  'Les crédits (cartes, maison, voiture) ne sont jamais soustraits des liquidités : ils figurent plus bas, séparément.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
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
          scopeSelector(),
          heading('Liquidités par périmètre'),
          panel(Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: mint),
                title: const Text('Mon argent personnel (liquidités)'),
                trailing: Text(euro(s.liquidFor('personal'))),
              ),
              ListTile(
                leading: const Icon(Icons.people, color: blue),
                title: const Text('Solde complet du compte commun'),
                subtitle: const Text(
                  'Présenté en entier, pas comme patrimoine personnel.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Text(euro(s.liquidFor('joint'))),
              ),
              const Divider(),
              const ListTile(
                title: Text(
                  'Vue consolidée : chaque compte compté une seule fois. Un transfert interne ne change pas son total.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          )),
          heading('Comptes courants'),
          panel(Column(children: [
            typeRow('Personnel', Icons.person, sumType('bank', 'personal')),
            typeRow('Commun', Icons.people, sumType('bank', 'joint')),
          ])),
          heading('Épargne'),
          panel(Column(children: [
            typeRow('Personnel', Icons.person, sumType('savings', 'personal')),
            typeRow('Commun', Icons.people, sumType('savings', 'joint')),
          ])),
          heading('Crédits dus (hors liquidités)'),
          panel(Column(
            children: [
              typeRow('Cartes de crédit dues',
                  Icons.credit_card_rounded, -sumType('credit')),
              typeRow('Maison / voiture / autres dus',
                  Icons.home_work_outlined, -sumType('loan')),
              const ListTile(
                title: Text(
                  'Capital restant dû affiché en positif ici. La valeur d’un bien (immobilier) et sa dette restent deux lignes séparées.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          )),
          heading(
            'Placements & autres valeurs (manuelles)',
            trailing: TextButton(
              onPressed: addAccount,
              child: const Text('Ajouter'),
            ),
          ),
          ...s.accounts
              .where((a) => [
                    'investment',
                    'crypto',
                    'stocks',
                    'realestate'
                  ].contains(a.type))
              .map((a) => panel(ListTile(
                    leading: Icon(accountIcon(a), color: violet),
                    title: Text(a.name),
                    subtitle: Text(
                        '${accountTypes[a.type]} · ${scopes[a.scope] ?? ''} · valorisation manuelle, sans cours de marché'),
                    trailing: Text(euro(s.balance(a))),
                    onTap: () => accountActions(a),
                  ))),
          panel(
            const Text(
              'Placements, BTC/cryptoactifs, actions et immobilier : valeur totale saisie à la main. '
              'Les versements et retraits se font par transfert. '
              'Les variations se saisissent avec '
              '« Actualiser la valeur du placement ».\n\n'
              'Ces ajustements modifient le patrimoine, mais pas '
              'les revenus ni les dépenses du budget. Aucune valorisation automatique.\n\n'
              'Les portefeuilles prépayés sont inclus dans les avoirs : '
              'leur solde peut ne pas être remboursable.',
            ),
          ),
        ],
      );
  }

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
      const Question('password', 'Mot de passe — 8 caractères minimum',
          secret: true),
      const Question('confirm', 'Confirmer le mot de passe', secret: true),
    ]);
    if (result == null) return;

    await run(() async {
      final password = result['password']!;
      if (password.length < 8 || password != result['confirm']) {
        throw Exception(
          'Utilisez au moins 8 caractères et une confirmation identique. '
          'Ce mot de passe est différent du PIN : il protège ce fichier, '
          'qui gardera ce mot de passe même si vous en choisissez un autre plus tard.',
        );
      }

      final salt = randomBytes(16);
      final backupKey = await passwordKey(password, salt);
      final encrypted = await encrypt(
        utf8.encode(jsonEncode(s.toJson())),
        backupKey,
      );
      final envelope = {
        'format': currentBackupFormat,
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
      if (!mounted) return;
      message(
          'Astuce : « Enregistrer dans Fichiers » → iCloud Drive pour vos autres appareils.');
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
      if (!backupFormats.contains(envelope['format'])) {
        throw Exception('Ce fichier n’est pas une sauvegarde DiPeSa.');
      }

      if (!mounted) return;
      final result = await ask(context, 'Restaurer une sauvegarde', [
        const Question('password', 'Mot de passe de la sauvegarde',
            secret: true),
      ]);
      if (result == null) return;

      Map<String, dynamic> decrypted;
      try {
        final backupKey = await passwordKey(
          result['password']!,
          base64Decode(envelope['salt'] as String),
        );
        final plain = await decrypt(
          jsonMap(envelope['data']),
          backupKey,
        );
        decrypted = jsonMap(jsonDecode(utf8.decode(plain)));
      } catch (_) {
        throw Exception('Mot de passe incorrect ou sauvegarde endommagée.');
      }

      // Validation + aperçu AVANT toute écriture (import atomique).
      final probe = BudgetStore();
      probe.load(decrypted);
      probe.validate();
      final summary = BudgetStore.summarizeDoc(decrypted);
      final dups = s.duplicateCounts(decrypted);

      if (!mounted) return;
      final mode = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Aperçu de l’import'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Format : ${envelope['format']}'),
                Text(
                    '${summary['accounts']} comptes · ${summary['entries']} opérations'),
                Text(
                    '${summary['categories']} catégories · ${summary['projects']} tirelires'),
                Text(
                    '${summary['contributions']} contributions · ${summary['dues']} échéances · ${summary['loans']} crédits'),
                Text('Solde net du fichier : ${euro(summary['net']!)}'),
                const Divider(),
                Text(
                    'Déjà présents (ignorés en fusion) : ${dups['entries']} opérations, ${dups['accounts']} comptes, ${dups['dues']} échéances.'),
                const Text(
                  'Fusion = ajoute les nouveautés sans doublon. Remplacement = snapshot actuel d’abord, puis remplace tout.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Fusionner'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (mode == null || !mounted) return;

      if (mode == 'merge') {
        await s.change(() => s.mergeDoc(decrypted));
        message('Import fusionné sans doublon.');
      } else {
        final confirmed = await confirmAction(
          'Remplacer les données actuelles ?',
          'Un snapshot de sécurité est créé avant. Exportez aussi en .mcb si besoin.',
        );
        if (!confirmed) return;
        await s.snapshotIfDue();
        try {
          final dir = s.snapshotsDir();
          await dir.create(recursive: true);
          await File(s.file.path).copy(
              '${dir.path}/pre-restore-${DateTime.now().millisecondsSinceEpoch}.enc');
        } catch (_) {}
        await s.change(() => s.load(decrypted));
        message('Sauvegarde restaurée (remplacement).');
      }
    });
  }

  Future<void> backupsScreen() async {
    final snaps = await s.listSnapshots();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .82,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              heading('Sauvegardes et synchronisation'),
              panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STATUT',
                      style:
                          TextStyle(letterSpacing: 1.5, color: ink)),
                  const SizedBox(height: 8),
                  Text(
                      'Données : locales chiffrées, hors ligne OK · format v4'),
                  Text(
                      'Dernière écriture : ${s.lastSavedAt == null ? '—' : s.lastSavedAt.toString().substring(0, 19)}'),
                  Text(
                      'Dernière sauvegarde auto : ${s.lastAutoBackupAt == null ? 'jamais — sera créée à l’ouverture' : s.lastAutoBackupAt.toString().substring(0, 19)}'),
                  Text(
                      'Objets : ${s.accounts.length} comptes · ${s.entries.length} opérations · ${s.dues.length} échéances'),
                  const Divider(),
                  const Text(
                      'Synchronisation CloudKit : non configurée. '
                      'Pré-requis : compte développeur Apple payant + conteneur iCloud privé (jamais partagé avec un autre compte Apple). '
                      'En attendant : export chiffré → « Enregistrer dans Fichiers » → iCloud Drive, puis import sur le nouvel iPhone.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const Text(
                      'Sauvegarde auto tous les 5 jours : iOS ne garantit pas l’exécution exacte en arrière-plan — rattrapage à chaque ouverture, dernière réussite affichée ci-dessus.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              )),
              heading('Snapshots versionnés (${snaps.length}/12)'),
              if (snaps.isEmpty)
                panel(const Text(
                    'Aucun snapshot pour le moment. Il sera créé automatiquement.')),
              ...snaps.map((f) {
                final name = f.path.split('/').last;
                return panel(
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await restoreSnapshot(f);
                        },
                        child: const Text('Restaurer'),
                      ),
                      IconButton(
                        tooltip: 'Supprimer ce snapshot',
                        onPressed: () async {
                          final yes = await confirmAction(
                            'Supprimer ce snapshot ?',
                            'Les autres snapshots sont conservés.',
                          );
                          if (yes) {
                            try {
                              await f.delete();
                            } catch (e) {
                              message(cleanError(e));
                              return;
                            }
                            if (mounted) Navigator.pop(ctx);
                            message('Snapshot supprimé.');
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              }),
              panel(const Text(
                'Une suppression (même synchronisée un jour) ne supprime jamais tous les snapshots : ils vivent dans un dossier séparé et la rotation n’en garde que les 12 derniers.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              )),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> restoreSnapshot(File snap) async {
    await run(() async {
      Map<String, dynamic> restored;
      try {
        restored = await s.readSnapshot(snap);
      } catch (_) {
        throw Exception('Snapshot illisible (clé locale différente ?).');
      }
      if (!mounted) return;
      final confirmed = await confirmAction(
        'Restaurer ce snapshot ?',
        'La version actuelle sera d’abord copiée en snapshot. Les doublons sont refusés par validation.',
      );
      if (!confirmed) return;
      await s.snapshotIfDue();
      await s.change(() => s.load(restored));
      message('Snapshot restauré.');
    });
  }

  Future<void> changePin() async {
    final result = await ask(context, 'Changer le PIN', [
      const Question('pin', 'Nouveau PIN (4 chiffres)', secret: true, numeric: true),
      const Question('confirm', 'Confirmer le PIN', secret: true, numeric: true),
    ]);
    if (result == null) return;
    await run(() async {
      if (!validPin(result['pin']!)) {
        throw Exception('Le PIN doit contenir exactement 4 chiffres.');
      }
      if (result['pin'] != result['confirm']) {
        throw Exception('Les deux codes ne correspondent pas.');
      }
      final salt = randomBytes(16);
      final derived = await passwordKey(result['pin']!, salt);
      await s.secure.write(
        key: 'pin-verifier',
        value: jsonEncode({
          'v': 2,
          'salt': base64Encode(salt),
          'hash': base64Encode(await derived.extractBytes()),
        }),
      );
      message('PIN mis à jour.');
    });
  }

  Future<void> regenerateRecovery() async {
    final code = generateRecoveryCode();
    final shown = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau code de récupération'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            const SizedBox(height: 12),
            const Text(
              'Notez-le maintenant : l’ancien code ne marchera plus. Il ne sert que sur cet appareil.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Je l’ai noté'),
          ),
        ],
      ),
    );
    if (shown != true || !mounted) return;
    final typed = await ask(context, 'Confirmer le code', [
      const Question('code', 'Recopiez le code affiché'),
    ]);
    if (typed == null) return;
    await run(() async {
      if (normalizeRecoveryCode(typed['code']!) !=
          normalizeRecoveryCode(code)) {
        throw Exception('Le code recopié ne correspond pas.');
      }
      final encodedKey = await s.secure.read(key: 'database-key');
      if (encodedKey == null) throw Exception('Clé locale introuvable.');
      final salt = randomBytes(16);
      final wrapKey =
          await passwordKey(normalizeRecoveryCode(code), salt);
      final envelope = await encrypt(base64Decode(encodedKey), wrapKey);
      await s.secure.write(
        key: 'pin-recovery',
        value: jsonEncode(
            {'v': 1, 'salt': base64Encode(salt), 'wrap': envelope}),
      );
      message('Code de récupération remplacé.');
    });
  }

  late final reminders = ReminderService(s.secure);

  Future<void> ensureReminder() async {
    try {
      final p = await reminders.prefs();
      if (p['enabled'] != 'true') return;
      final h = int.tryParse(p['hour'] ?? '') ?? 20;
      final m = int.tryParse(p['minute'] ?? '') ?? 0;
      await reminders.schedule(hour: h, minute: m);
    } catch (_) {}
  }

  Future<void> reminderSettings() async {
    final p = await reminders.prefs();
    final enabled = p['enabled'] == 'true';
    final h = int.tryParse(p['hour'] ?? '') ?? 20;
    final m = int.tryParse(p['minute'] ?? '') ?? 0;
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Rappel tous les 3 jours',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(enabled
                  ? 'Activé · $h:${m.toString().padLeft(2, '0')}'
                  : 'Désactivé · volontaire, autorisation iOS requise'),
            ),
            ListTile(
              leading: Icon(
                  enabled ? Icons.notifications_off : Icons.notifications),
              title: Text(enabled ? 'Désactiver' : 'Activer'),
              onTap: () => Navigator.pop(ctx, enabled ? 'off' : 'on'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Régler l’horaire'),
              onTap: () => Navigator.pop(ctx, 'time'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'off') {
      await run(() async => reminders.disable());
      message('Rappels désactivés.');
    } else if (action == 'on') {
      final granted = await reminders.requestPermission();
      if (!granted && mounted) {
        message(
            'Autorisez les notifications dans Réglages iOS pour recevoir les rappels.');
      }
      await run(
          () async => reminders.schedule(hour: h, minute: m));
      message('Rappel tous les 3 jours activé.');
    } else if (action == 'time') {
      final result = await ask(context, 'Horaire du rappel', [
        Question('hour', 'Heure (0–23)', initial: '$h', numeric: true),
        Question('minute', 'Minute (0–59)',
            initial: m.toString().padLeft(2, '0'), numeric: true),
      ]);
      if (result == null) return;
      await run(() async {
        final nh = int.parse(result['hour']!);
        final nm = int.parse(result['minute']!);
        if (nh < 0 || nh > 23 || nm < 0 || nm > 59) {
          throw Exception('Horaire invalide.');
        }
        await reminders.schedule(hour: nh, minute: nm);
        message('Rappel réglé à $nh:${nm.toString().padLeft(2, '0')}.');
      });
    }
  }

  Future<void> settings() async {    final action = await showModalBottomSheet<String>(
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
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Changer le PIN (4 chiffres)'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Rappel dépenses tous les 3 jours'),
              subtitle: const Text('Volontaire, horaire réglable'),
              onTap: () => Navigator.pop(ctx, 'reminder'),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Régénérer le code de récupération'),
              onTap: () => Navigator.pop(ctx, 'recovery'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Exporter une sauvegarde chiffrée'),
              subtitle: const Text(
                  'Mot de passe — pour nouvel iPhone via Fichiers / iCloud Drive'),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restaurer une sauvegarde'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Sauvegardes et synchronisation'),
              subtitle: const Text('Versionnées locales, statut, iCloud'),
              onTap: () => Navigator.pop(ctx, 'backups'),
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
      case 'pin':
        await changePin();
        break;
      case 'recovery':
        await regenerateRecovery();
        break;
      case 'reminder':
        await reminderSettings();
        break;
      case 'export':
        await exportBackup();
        break;
      case 'restore':
        await restoreBackup();
        break;
      case 'backups':
        await backupsScreen();
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
      'Espace commun',
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
                2 => jointPage(),
                3 => budgetsPage(),
                4 => projectsPage(),
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
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Commun',
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