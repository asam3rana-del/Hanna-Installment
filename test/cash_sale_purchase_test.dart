import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hanna_installment/db/app_database.dart';
import 'package:hanna_installment/installment/inst_cash_sale_repository.dart';
import 'package:hanna_installment/installment/inst_models.dart';
import 'package:hanna_installment/installment/inst_purchase_repository.dart';
import 'package:hanna_installment/license/license_core.dart';
import 'package:hanna_installment/license/license_service.dart';
import 'package:hanna_installment/services/session.dart';

/// Naqd sale (bechna / wapsi / cancel) aur khareed (bill / supplier adaigi / piece wapsi / bill delete) —
/// asal DB par: stock, cash book, supplier ka baqi, role aur license.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late int catId;
  late int supplierId;
  final sales = InstCashSaleRepository.instance;
  final buy = InstPurchaseRepository.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ah_sale_buy_');
    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(tempDir.path);
    final db = await AppDatabase.instance.database;
    Session.username = 'sale-tester';
    Session.role = 'admin';
    LicenseService.instance.status.value = LicenseStatus.active;
    catId = await db.insert('inst_categories', {'name': 'Mobile'});
    supplierId = await db.insert('inst_suppliers', {'name': 'Ali Traders'});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    Session.username = null;
    Session.role = 'cashier';
    LicenseService.instance.status.value = null;
    await tempDir.delete(recursive: true);
  });

  Future<int> stockItem(String model, {double cost = 800}) async {
    final db = await AppDatabase.instance.database;
    return db.insert('inst_items', {'categoryId': catId, 'model': model, 'costPrice': cost, 'cashPrice': 1000.0, 'status': itemInStock});
  }

  Future<String> itemStatus(int id) async {
    final db = await AppDatabase.instance.database;
    return (await db.query('inst_items', columns: ['status'], where: 'id = ?', whereArgs: [id])).first['status'] as String;
  }

  Future<double> cashSum(String type, String refPrefix) async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS v FROM cash_transactions WHERE type = ? AND reference LIKE ?', [type, '$refPrefix%']);
    return ((r.first['v'] as num?) ?? 0).toDouble();
  }

  Future<InstCashSale> sale(int id) async => (await sales.view(id))!.sale;

  // ================================================================== naqd sale

  group('naqd sale', () {
    test('bechne par piece sold, cash IN qeemat ke barabar', () async {
      final it = await stockItem('A20');
      await sales.sell(itemId: it, price: 1200);
      expect(await itemStatus(it), itemSold);
      expect(await cashSum('IN', 'inst-sale:'), 1200);
    });

    test('bika hua piece dobara nahi bikta; 0 qeemat / ghalat method rad', () async {
      final it = await stockItem('A20');
      await sales.sell(itemId: it, price: 1200);
      await expectLater(sales.sell(itemId: it, price: 1200), throwsArgumentError);
      final it2 = await stockItem('A30');
      await expectLater(sales.sell(itemId: it2, price: 0), throwsArgumentError);
      await expectLater(sales.sell(itemId: it2, price: 100, method: 'card'), throwsArgumentError);
      expect(await itemStatus(it2), itemInStock);
    });

    test('ek phone par ek hi piece ki do sale saath saath: sirf ek', () async {
      final it = await stockItem('A20');
      final ok = await Future.wait([
        sales.sell(itemId: it, price: 1200).then((_) => true, onError: (_) => false),
        sales.sell(itemId: it, price: 1200).then((_) => true, onError: (_) => false),
      ]);
      expect(ok.where((x) => x).length, 1);
      expect(await cashSum('IN', 'inst-sale:'), 1200);
    });

    test('wapsi: piece stock mein, refund cash OUT, dobara wapsi rad', () async {
      final it = await stockItem('A20');
      final id = await sales.sell(itemId: it, price: 1200);
      final s = await sale(id);
      await sales.returnSale(s, refund: 1000);
      expect(await itemStatus(it), itemInStock);
      expect(await cashSum('OUT', 'inst-sret:'), 1000);
      await expectLater(sales.returnSale(await sale(id), refund: 1000), throwsArgumentError);
      // Purana (stale) object bhi dobara refund na de.
      await expectLater(sales.returnSale(s, refund: 1000), throwsArgumentError);
      expect(await cashSum('OUT', 'inst-sret:'), 1000);
    });

    test('wapsi: refund qeemat se zyada rad; cashier wapsi nahi le sakta', () async {
      final it = await stockItem('A20');
      final id = await sales.sell(itemId: it, price: 1200);
      await expectLater(sales.returnSale(await sale(id), refund: 1300), throwsArgumentError);
      Session.role = 'cashier';
      await expectLater(sales.returnSale(await sale(id), refund: 100), throwsArgumentError);
      expect(await itemStatus(it), itemSold);
    });

    test('cancel: sale aur us ki cash row khatam, piece stock mein', () async {
      final it = await stockItem('A20');
      final id = await sales.sell(itemId: it, price: 1200);
      await sales.cancel(await sale(id));
      expect(await sales.view(id), isNull);
      expect(await itemStatus(it), itemInStock);
      expect(await cashSum('IN', 'inst-sale:'), 0);
    });

    test('license khatam => na bikri, na cancel', () async {
      final it = await stockItem('A20');
      final id = await sales.sell(itemId: it, price: 1200);
      final it2 = await stockItem('A30');
      LicenseService.instance.status.value = LicenseStatus.expired;
      await expectLater(sales.sell(itemId: it2, price: 500), throwsA(anything));
      await expectLater(sales.cancel(await sale(id)), throwsA(anything));
      LicenseService.instance.status.value = LicenseStatus.active;
      expect(await sales.view(id), isNotNull);
      expect(await itemStatus(it2), itemInStock);
    });
  });

  // ================================================================== khareed

  group('khareed', () {
    Future<int> bill({double paidNow = 0}) => buy.createPurchase(
          supplierId: supplierId,
          items: [
            InstItem(categoryId: catId, model: 'A20', costPrice: 800, cashPrice: 1000),
            InstItem(categoryId: catId, model: 'A30', costPrice: 1200, cashPrice: 1500),
          ],
          billNo: 'B-1',
          paidNow: paidNow,
        );

    test('bill: pieces stock mein, supplier ka baqi = bill - adaigi', () async {
      final pid = await bill(paidNow: 500);
      final p = (await buy.purchase(pid))!;
      expect(p.total, 2000);
      expect(p.due, 1500);
      final items = await buy.purchaseItems(pid);
      expect(items, hasLength(2));
      expect(items.every((i) => i.inStock), isTrue);
      expect((await buy.supplierRow(supplierId))!.balance, 1500);
      expect(await cashSum('OUT', ''), 500);
    });

    test('bill se zyada adaigi rad (bill banate waqt bhi, baad mein bhi)', () async {
      await expectLater(bill(paidNow: 2001), throwsArgumentError);
      final pid = await bill();
      await expectLater(buy.pay(supplierId: supplierId, purchaseId: pid, amount: 2001), throwsArgumentError);
      await buy.pay(supplierId: supplierId, purchaseId: pid, amount: 2000);
      expect((await buy.purchase(pid))!.due, 0);
    });

    test('ek phone par do adaigiyan saath saath: mil kar bill se zyada nahi', () async {
      final pid = await bill();
      final ok = await Future.wait([
        buy.pay(supplierId: supplierId, purchaseId: pid, amount: 1500).then((_) => true, onError: (_) => false),
        buy.pay(supplierId: supplierId, purchaseId: pid, amount: 1500).then((_) => true, onError: (_) => false),
      ]);
      expect(ok.where((x) => x).length, 1);
      expect((await buy.purchase(pid))!.due, 500);
    });

    test('adaigi hatane par baqi wapas, cash row bhi hatti hai', () async {
      final pid = await bill();
      await buy.pay(supplierId: supplierId, purchaseId: pid, amount: 700);
      final pay = (await buy.payments(purchaseId: pid)).single;
      await buy.deletePayment(pay);
      expect((await buy.purchase(pid))!.due, 2000);
      expect(await cashSum('OUT', ''), 0);
    });

    test('piece supplier ko wapas: piece returned, baqi kam; cancel karne par sab wapas', () async {
      final pid = await bill();
      final p = (await buy.purchase(pid))!;
      final a20 = (await buy.purchaseItems(pid)).firstWhere((i) => i.model == 'A20');
      await buy.returnPieces(p, [a20]);
      expect(await itemStatus(a20.id!), itemReturned);
      expect((await buy.purchase(pid))!.due, 1200);
      final r = (await buy.returns(purchaseId: pid)).single;
      await buy.cancelReturn(r);
      expect(await itemStatus(a20.id!), itemInStock);
      expect((await buy.purchase(pid))!.due, 2000);
    });

    test('bika hua piece supplier ko wapas nahi; bill bhi delete nahi', () async {
      final pid = await bill();
      final a20 = (await buy.purchaseItems(pid)).firstWhere((i) => i.model == 'A20');
      await sales.sell(itemId: a20.id!, price: 1000);
      final p = (await buy.purchase(pid))!;
      await expectLater(buy.returnPieces(p, [a20]), throwsArgumentError);
      await expectLater(buy.deletePurchase(p), throwsArgumentError);
      expect(await buy.purchase(pid), isNotNull);
    });

    test('bill delete: pieces, adaigi aur cash row sab khatam', () async {
      final pid = await bill(paidNow: 300);
      await buy.deletePurchase((await buy.purchase(pid))!);
      expect(await buy.purchase(pid), isNull);
      expect(await buy.purchaseItems(pid), isEmpty);
      expect(await cashSum('OUT', ''), 0);
      expect((await buy.supplierRow(supplierId))!.balance, 0);
    });

    test('cashier khareed / adaigi nahi kar sakta; license khatam => bill delete nahi', () async {
      final pid = await bill();
      Session.role = 'cashier';
      await expectLater(bill(), throwsArgumentError);
      await expectLater(buy.pay(supplierId: supplierId, amount: 100), throwsArgumentError);
      Session.role = 'admin';
      LicenseService.instance.status.value = LicenseStatus.expired;
      await expectLater(buy.deletePurchase((await buy.purchase(pid))!), throwsA(anything));
      LicenseService.instance.status.value = LicenseStatus.active;
      expect(await buy.purchase(pid), isNotNull);
    });
  });
}
