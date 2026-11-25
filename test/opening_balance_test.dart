import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hanna_installment/db/app_database.dart';
import 'package:hanna_installment/installment/inst_opening_balance.dart';
import 'package:hanna_installment/license/license_core.dart';
import 'package:hanna_installment/license/license_service.dart';
import 'package:hanna_installment/services/session.dart';

/// Purana baqi (v49): wasooli baqi se zyada nahi, ek hi phone par do jaldi wali wasooliyan
/// mil kar bhi baqi se zyada nahi, har wasooli ke saath cash IN, mitane par cash bhi mite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late int customerId;
  final repo = InstOpeningRepository.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ah_opening_');
    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(tempDir.path);
    final db = await AppDatabase.instance.database;
    Session.username = 'opening-tester';
    Session.role = 'admin';
    LicenseService.instance.status.value = LicenseStatus.active;
    customerId = await db.insert('customers', {'name': 'Ali', 'phone': '03001234567'});
    await db.insert('customer_profiles', {'customerId': customerId, 'openingBalance': 1000.0});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    Session.username = null;
    Session.role = 'cashier';
    LicenseService.instance.status.value = null;
    await tempDir.delete(recursive: true);
  });

  Future<int> cashRows() async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery("SELECT COUNT(*) AS n FROM cash_transactions WHERE reference LIKE 'inst-open:%'");
    return (r.first['n'] as num).toInt();
  }

  test('wasooli: baqi ghatta hai, cash IN banta hai', () async {
    await repo.receive(customerId: customerId, amount: 400);
    final st = await repo.status(customerId);
    expect(st.received, 400);
    expect(st.remaining, 600);
    expect(await cashRows(), 1);
  });

  test('baqi se zyada raqam rad; kuch nahi likha jata', () async {
    await expectLater(repo.receive(customerId: customerId, amount: 1000.5), throwsArgumentError);
    expect((await repo.status(customerId)).received, 0);
    expect(await cashRows(), 0);
  });

  test('poora baqi wasool => phir koi wasooli nahi', () async {
    await repo.receive(customerId: customerId, amount: 1000);
    expect((await repo.status(customerId)).remaining, 0);
    await expectLater(repo.receive(customerId: customerId, amount: 1), throwsArgumentError);
    expect(await repo.withRemaining(), isEmpty);
  });

  test('ek phone par do wasooliyan saath saath: mil kar baqi se zyada nahi', () async {
    final results = await Future.wait([
      repo.receive(customerId: customerId, amount: 700).then((_) => true, onError: (_) => false),
      repo.receive(customerId: customerId, amount: 700).then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((ok) => ok).length, 1);
    final st = await repo.status(customerId);
    expect(st.received, 700);
    expect(st.remaining, 300);
    expect(await cashRows(), 1);
  });

  test('ghalat raqam (0 / manfi) rad', () async {
    await expectLater(repo.receive(customerId: customerId, amount: 0), throwsArgumentError);
    await expectLater(repo.receive(customerId: customerId, amount: -5), throwsArgumentError);
  });

  test('wasooli mitayein => baqi wapas, cash row bhi mite', () async {
    await repo.receive(customerId: customerId, amount: 250);
    final list = await repo.receipts(customerId);
    expect(list, hasLength(1));
    await repo.delete(list.single);
    expect((await repo.status(customerId)).remaining, 1000);
    expect(await cashRows(), 0);
  });

  test('cashier wasooli nahi mita sakta', () async {
    await repo.receive(customerId: customerId, amount: 250);
    final r = (await repo.receipts(customerId)).single;
    Session.role = 'cashier';
    await expectLater(repo.delete(r), throwsArgumentError);
    expect(await repo.receipts(customerId), hasLength(1));
  });

  test('Home ke totals: bacha baqi, tareekh guzri to late, aaj ki wasooli', () async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    await db.update('customer_profiles', {'openingDue': today - 86400000}, where: 'customerId = ?', whereArgs: [customerId]);
    await repo.receive(customerId: customerId, amount: 100);
    final t = await repo.totals(today: today);
    expect(t.remaining, 900);
    expect(t.late, 900);
    expect(t.lateCount, 1);
    expect(t.receivedToday, 100);
  });
}
