import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hanna_installment/db/app_database.dart';
import 'package:hanna_installment/installment/inst_models.dart';
import 'package:hanna_installment/installment/inst_plan_math.dart';
import 'package:hanna_installment/installment/inst_plan_repository.dart';
import 'package:hanna_installment/installment/inst_repository.dart';
import 'package:hanna_installment/license/license_core.dart';
import 'package:hanna_installment/license/license_service.dart';
import 'package:hanna_installment/services/session.dart';

/// Qist plan ke baaqi paise wale raaste (asal DB par): payment hatana, plan hatana, saman wapas lena,
/// qisten dobara banana, saman badalna, qist ki tareekh badalna — role, license, cash book aur stock samet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late int customerId;
  late int catId;
  late int itemId;
  late int planId;
  final repo = InstPlanRepository.instance;

  int dayFromNow(int days) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + days).millisecondsSinceEpoch;
  }

  Future<int> newItem(String model, {double cost = 800}) async {
    final db = await AppDatabase.instance.database;
    return db.insert('inst_items', {
      'categoryId': catId,
      'brand': 'Dell',
      'model': model,
      'costPrice': cost,
      'cashPrice': 1000.0,
      'status': itemInStock,
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ah_plan_life_');
    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(tempDir.path);
    final db = await AppDatabase.instance.database;
    Session.username = 'life-tester';
    Session.role = 'admin';
    LicenseService.instance.status.value = LicenseStatus.active;
    customerId = await db.insert('customers', {'name': 'Asif', 'phone': '03001112223'});
    await db.insert('customer_profiles', {'customerId': customerId});
    catId = await db.insert('inst_categories', {'name': 'Mobile'});
    itemId = await newItem('A20');
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
      firstDueDate: dayFromNow(30),
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

  Future<PlanView> v() async => (await repo.view(planId))!;

  Future<String> itemStatus(int id) async {
    final db = await AppDatabase.instance.database;
    final r = await db.query('inst_items', columns: ['status'], where: 'id = ?', whereArgs: [id]);
    return r.first['status'] as String;
  }

  Future<int> cashInRows() async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery("SELECT COUNT(*) AS n FROM cash_transactions WHERE type = 'IN'");
    return (r.first['n'] as num).toInt();
  }

  InstPayment lastInstallment(PlanView pv) => pv.payments.lastWhere((p) => p.kind == payInstallment);

  // ------------------------------------------------------------------ payment hatana

  group('deletePayment', () {
    test('baqi wapas, cash IN row bhi hat jati hai', () async {
      final before = await cashInRows();
      await repo.receive(planId, amount: 400);
      expect(await cashInRows(), before + 1);
      await repo.deletePayment(lastInstallment(await v()));
      expect((await v()).status.remaining, 1000);
      expect(await cashInRows(), before);
    });

    test('poora adaa plan ki payment hatane par plan dobara chalta (active)', () async {
      await repo.receive(planId, amount: 1000);
      expect((await v()).plan.status, planCompleted);
      await repo.deletePayment(lastInstallment(await v()));
      final pv = await v();
      expect(pv.plan.status, planActive);
      expect(pv.status.remaining, 1000);
    });

    test('cashier payment nahi hata sakta', () async {
      await repo.receive(planId, amount: 400);
      final p = lastInstallment(await v());
      Session.role = 'cashier';
      await expectLater(repo.deletePayment(p), throwsArgumentError);
      expect((await v()).status.remaining, 600);
    });

    test('license khatam => payment nahi hatti', () async {
      await repo.receive(planId, amount: 400);
      final p = lastInstallment(await v());
      LicenseService.instance.status.value = LicenseStatus.expired;
      await expectLater(repo.deletePayment(p), throwsA(anything));
      LicenseService.instance.status.value = LicenseStatus.active;
      expect((await v()).status.remaining, 600);
    });
  });

  // ------------------------------------------------------------------ plan hatana

  group('deletePlan', () {
    test('sirf Admin; Manager nahi', () async {
      Session.role = 'manager';
      await expectLater(repo.deletePlan(planId), throwsArgumentError);
      expect(await repo.view(planId), isNotNull);
    });

    test('qist wasool ho chuki ho to plan nahi hatta', () async {
      await repo.receive(planId, amount: 100);
      await expectLater(repo.deletePlan(planId), throwsArgumentError);
      expect(await repo.view(planId), isNotNull);
    });

    test('hatane par plan + schedule khatam, piece wapas stock mein', () async {
      expect(await itemStatus(itemId), itemSold);
      await repo.deletePlan(planId);
      expect(await repo.view(planId), isNull);
      final db = await AppDatabase.instance.database;
      expect(await db.query('inst_schedule', where: 'planId = ?', whereArgs: [planId]), isEmpty);
      expect(await itemStatus(itemId), itemInStock);
    });

    test('license khatam => plan nahi hatta', () async {
      LicenseService.instance.status.value = LicenseStatus.expired;
      await expectLater(repo.deletePlan(planId), throwsA(anything));
      LicenseService.instance.status.value = LicenseStatus.active;
      expect(await repo.view(planId), isNotNull);
    });
  });

  // ------------------------------------------------------------------ saman wapas lena

  group('repossess', () {
    test('plan band (repossessed), piece repossessed, wasool raqam record mein rehti hai', () async {
      await repo.receive(planId, amount: 300);
      await repo.repossess(planId, note: 'qist nahi di');
      final pv = await v();
      expect(pv.plan.status, planRepossessed);
      expect(pv.status.paid, 300);
      expect(await itemStatus(itemId), itemRepossessed);
    });

    test('band plan par na wasooli, na dobara wapas', () async {
      await repo.repossess(planId);
      await expectLater(repo.receive(planId, amount: 100), throwsArgumentError);
      await expectLater(repo.repossess(planId), throwsArgumentError);
    });

    test('cashier saman wapas nahi le sakta', () async {
      Session.role = 'cashier';
      await expectLater(repo.repossess(planId), throwsArgumentError);
      expect((await v()).plan.status, planActive);
    });
  });

  // ------------------------------------------------------------------ qisten dobara

  group('reschedule', () {
    test('ada hissa wahi, baqi + izafi nayi qiston mein', () async {
      await repo.receive(planId, amount: 400);
      await repo.reschedule(planId, count: 3, firstDue: dayFromNow(10), frequency: freqMonthly, extra: 300);
      final pv = await v();
      expect(pv.status.paid, 400);
      expect(pv.status.remaining, 900);
      expect(pv.plan.installmentTotal, 1300);
      expect(pv.plan.profit, 300);
      final sum = pv.schedule.fold<double>(0, (a, l) => a + l.$2);
      expect(sum, closeTo(1300, 0.01));
    });

    test('minus izafi aur cashier rad', () async {
      await expectLater(
          repo.reschedule(planId, count: 2, firstDue: dayFromNow(10), frequency: freqMonthly, extra: -1), throwsArgumentError);
      Session.role = 'cashier';
      await expectLater(repo.reschedule(planId, count: 2, firstDue: dayFromNow(10), frequency: freqMonthly), throwsArgumentError);
      expect((await v()).plan.installmentTotal, 1000);
    });
  });

  // ------------------------------------------------------------------ saman badalna

  group('exchange', () {
    test('purana piece returned, naya sold, farq baqi mein', () async {
      await repo.receive(planId, amount: 400);
      final other = await newItem('A30', cost: 900);
      await repo.exchange(planId, newItemId: other, priceDiff: 200, count: 2, firstDue: dayFromNow(10));
      final pv = await v();
      expect(pv.plan.itemId, other);
      expect(pv.status.remaining, 800);
      expect(pv.plan.installmentTotal, 1200);
      expect(pv.plan.costPrice, 900);
      expect(await itemStatus(itemId), itemReturned);
      expect(await itemStatus(other), itemSold);
    });

    test('wahi piece ya bika hua piece rad', () async {
      await expectLater(
          repo.exchange(planId, newItemId: itemId, priceDiff: 0, count: 2, firstDue: dayFromNow(10)), throwsArgumentError);
      final sold = await newItem('A40');
      final db = await AppDatabase.instance.database;
      await db.update('inst_items', {'status': itemSold}, where: 'id = ?', whereArgs: [sold]);
      await expectLater(
          repo.exchange(planId, newItemId: sold, priceDiff: 0, count: 2, firstDue: dayFromNow(10)), throwsArgumentError);
      expect((await v()).plan.itemId, itemId);
    });
  });

  // ------------------------------------------------------------------ qist ki tareekh

  group('setDueDate', () {
    test('pichhli qist se pehle ki tareekh rad; agli ke baad sirf "baad wali bhi" ke saath', () async {
      final s = (await v()).schedule;
      await expectLater(repo.setDueDate(planId, 2, s[0].$1 - 86400000), throwsArgumentError);
      await expectLater(repo.setDueDate(planId, 1, s[1].$1 + 86400000), throwsArgumentError);
    });

    test('baad wali bhi khiskayein: dono qisten utne hi din aage', () async {
      final s = (await v()).schedule;
      final moved = DateTime.fromMillisecondsSinceEpoch(s[0].$1).add(const Duration(days: 5));
      await repo.setDueDate(planId, 1, moved.millisecondsSinceEpoch, shiftRest: true);
      final n = (await v()).schedule;
      expect(DateTime.fromMillisecondsSinceEpoch(n[0].$1).difference(DateTime.fromMillisecondsSinceEpoch(s[0].$1)).inDays, 5);
      expect(DateTime.fromMillisecondsSinceEpoch(n[1].$1).difference(DateTime.fromMillisecondsSinceEpoch(s[1].$1)).inDays, 5);
      expect((await v()).status.remaining, 1000);
    });

    test('cashier tareekh nahi badal sakta', () async {
      final s = (await v()).schedule;
      Session.role = 'cashier';
      await expectLater(repo.setDueDate(planId, 1, s[0].$1 + 86400000), throwsArgumentError);
    });
  });

  // ------------------------------------------------------------------ customer hatana

  group('deleteCustomer', () {
    test('qist plan wala customer nahi hatta', () async {
      await expectLater(InstRepository.instance.deleteCustomer(customerId), throwsArgumentError);
      expect(await InstRepository.instance.customer(customerId), isNotNull);
    });

    test('bina plan wala customer: customer + profile + zamin sab hat jate', () async {
      final db = await AppDatabase.instance.database;
      final other = await db.insert('customers', {'name': 'Ghalat', 'phone': '03009998887'});
      await db.insert('customer_profiles', {'customerId': other});
      await db.insert('inst_guarantors', {'customerId': other, 'name': 'Zamin'});
      await InstRepository.instance.deleteCustomer(other);
      expect(await InstRepository.instance.customer(other), isNull);
      expect(await db.query('customer_profiles', where: 'customerId = ?', whereArgs: [other]), isEmpty);
      expect(await db.query('inst_guarantors', where: 'customerId = ?', whereArgs: [other]), isEmpty);
    });

    test('purana baqi wala customer nahi hatta; cashier kisi ko nahi hata sakta', () async {
      final db = await AppDatabase.instance.database;
      final other = await db.insert('customers', {'name': 'Purana', 'phone': '03007776665'});
      await db.insert('customer_profiles', {'customerId': other, 'openingBalance': 5000.0});
      await expectLater(InstRepository.instance.deleteCustomer(other), throwsArgumentError);
      final plain = await db.insert('customers', {'name': 'Saada', 'phone': '03005554443'});
      Session.role = 'cashier';
      await expectLater(InstRepository.instance.deleteCustomer(plain), throwsArgumentError);
      expect(await InstRepository.instance.customer(plain), isNotNull);
    });
  });
}
