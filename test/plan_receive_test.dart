import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hanna_installment/db/app_database.dart';
import 'package:hanna_installment/installment/inst_plan_math.dart';
import 'package:hanna_installment/installment/inst_plan_repository.dart';
import 'package:hanna_installment/license/license_core.dart';
import 'package:hanna_installment/license/license_service.dart';
import 'package:hanna_installment/services/session.dart';

/// Qist wasooli (InstPlanRepository.receive) — asal DB par: baqi se zyada nahi, ek phone par do
/// saath wali wasooliyan mil kar bhi baqi se zyada nahi, poora hone par plan band, discount sirf manager,
/// band plan par wasooli nahi, har wasooli ke saath cash IN.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late int planId;
  final repo = InstPlanRepository.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ah_plan_receive_');
    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(tempDir.path);
    final db = await AppDatabase.instance.database;
    Session.username = 'plan-tester';
    Session.role = 'admin';
    LicenseService.instance.status.value = LicenseStatus.active;
    final customerId = await db.insert('customers', {'name': 'Asif', 'phone': '03001112223'});
    await db.insert('customer_profiles', {'customerId': customerId});
    final catId = await db.insert('inst_categories', {'name': 'Mobile'});
    final itemId = await db.insert('inst_items', {
      'categoryId': catId,
      'brand': 'Dell',
      'model': 'A20',
      'costPrice': 800.0,
      'cashPrice': 1000.0,
      'status': 'in_stock',
    });
    final now = DateTime.now();
    planId = await repo.createPlan(
      customerId: customerId,
      itemId: itemId,
      guarantorIds: const [],
      cashPrice: 1000,
      advance: 0,
      advanceMethod: 'cash',
      profitMode: profitPercent,
      profitValue: 0,
      count: 2,
      frequency: freqMonthly,
      firstDueDate: DateTime(now.year, now.month, now.day).add(const Duration(days: 30)).millisecondsSinceEpoch,
      roundTo: 1,
      lateFee: 0,
      graceDays: 0,
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    Session.username = null;
    Session.role = 'cashier';
    LicenseService.instance.status.value = null;
    await tempDir.delete(recursive: true);
  });

  Future<double> remaining() async => (await repo.view(planId))!.status.remaining;

  test('customer QR: plan number se plan milta hai (chhote harf bhi), ghalat number => null', () async {
    final no = (await repo.view(planId))!.plan.planNo;
    expect(no, startsWith('Q-'));
    expect(await repo.planIdForNo(no), planId);
    expect(await repo.planIdForNo(no.toLowerCase()), planId);
    expect(await repo.planIdForNo('Q-ZZ9999'), isNull);
  });

  Future<int> cashInRows() async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery("SELECT COUNT(*) AS n FROM cash_transactions WHERE type = 'IN'");
    return (r.first['n'] as num).toInt();
  }

  test('naya plan: poori raqam baqi', () async {
    expect(await remaining(), 1000);
  });

  test('wasooli: baqi ghatta hai, cash IN banta hai', () async {
    final before = await cashInRows();
    await repo.receive(planId, amount: 400);
    expect(await remaining(), 600);
    expect(await cashInRows(), before + 1);
  });

  test('baqi se zyada raqam rad; kuch nahi likha jata', () async {
    final before = await cashInRows();
    await expectLater(repo.receive(planId, amount: 1001), throwsArgumentError);
    expect(await remaining(), 1000);
    expect(await cashInRows(), before);
  });

  test('ek phone par do wasooliyan saath saath: mil kar baqi se zyada nahi', () async {
    final results = await Future.wait([
      repo.receive(planId, amount: 700).then((_) => true, onError: (_) => false),
      repo.receive(planId, amount: 700).then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((ok) => ok).length, 1);
    expect(await remaining(), 300);
  });

  test('poora adaa => plan completed, phir wasooli rad', () async {
    await repo.receive(planId, amount: 1000);
    final v = await repo.view(planId);
    expect(v!.plan.status, planCompleted);
    expect(v.status.remaining, 0);
    await expectLater(repo.receive(planId, amount: 1), throwsArgumentError);
  });

  test('discount sirf Admin / Manager; cash row nahi banti', () async {
    Session.role = 'cashier';
    await expectLater(repo.receive(planId, amount: 0, discount: 100), throwsArgumentError);
    Session.role = 'admin';
    final before = await cashInRows();
    await repo.receive(planId, amount: 0, discount: 100);
    expect(await remaining(), 900);
    expect(await cashInRows(), before);
  });

  test('raqam + discount mil kar baqi se zyada nahi', () async {
    await expectLater(repo.receive(planId, amount: 950, discount: 100), throwsArgumentError);
    expect(await remaining(), 1000);
  });

  test('ghalat input: 0 / manfi / ghalat method rad', () async {
    await expectLater(repo.receive(planId, amount: 0), throwsArgumentError);
    await expectLater(repo.receive(planId, amount: -5), throwsArgumentError);
    await expectLater(repo.receive(planId, amount: 10, method: 'card'), throwsArgumentError);
  });

  test('fine qist ke baqi ko kam nahi karta', () async {
    await repo.receive(planId, amount: 100, fine: 50);
    expect(await remaining(), 900);
  });
}
