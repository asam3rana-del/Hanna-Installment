import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hanna_installment/db/app_database.dart';
import 'package:hanna_installment/installment/inst_due_alert.dart';
import 'package:hanna_installment/installment/inst_photo_sync.dart';
import 'package:hanna_installment/installment/inst_sync.dart';
import 'package:hanna_installment/sync/sync_pull_plan.dart';
import 'package:hanna_installment/sync/sync_push_plan.dart';
import 'package:hanna_installment/sync/sync_queue_helper.dart';

/// Device A par qist ka data -> sync_queue payloads -> (cloud documents) -> device B par apply.
Future<Database> _device() async {
  // singleInstance: false — warna dono ":memory:" ek hi database ban jate hain (device A = device B).
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    phone TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL DEFAULT '', serverId TEXT, updatedAt INTEGER NOT NULL DEFAULT 0)''');
  await db.execute('''CREATE TABLE cash_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL,
    method TEXT NOT NULL, amount REAL NOT NULL, reason TEXT NOT NULL DEFAULT '', reference TEXT NOT NULL DEFAULT '',
    createdAt INTEGER NOT NULL, serverId TEXT, updatedAt INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1)''');
  await db.execute('''CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, entityType TEXT NOT NULL,
    entityId TEXT NOT NULL, operation TEXT NOT NULL, payloadJson TEXT NOT NULL, createdAt INTEGER NOT NULL,
    syncedAt INTEGER, retryCount INTEGER NOT NULL DEFAULT 0, lastError TEXT)''');
  for (final sql in [...AppDatabase.installmentTablesSql, ...AppDatabase.installmentPlanTablesSql, ...AppDatabase.installmentPriceTablesSql]) {
    await db.execute(sql);
  }
  return db;
}

/// Queue -> collection -> documents (har entity ka aakhri upsert; delete = tombstone).
Future<Map<String, List<Map<String, Object?>>>> _cloud(Database db) async {
  final byId = <String, Map<String, Object?>>{};
  final coll = <String, String>{};
  for (final r in await db.query('sync_queue', orderBy: 'id')) {
    final type = r['entityType'] as String;
    final c = instPushCollections[type];
    if (c == null) continue;
    final id = r['entityId'] as String;
    coll[id] = c;
    byId[id] = r['operation'] == 'delete'
        ? {...?byId[id], 'serverId': id, '_deleted': true}
        : Map<String, Object?>.from(jsonDecode(r['payloadJson'] as String) as Map);
  }
  final out = <String, List<Map<String, Object?>>>{};
  byId.forEach((id, doc) => out.putIfAbsent(coll[id]!, () => []).add(doc));
  return out;
}

void main() {
  sqfliteFfiInit();
  late Database a;
  late Database b;

  setUp(() async {
    a = await _device();
    b = await _device();
    SyncQueueHelper.nowMs = () => 5000;
    SyncQueueHelper.branchId = () => 'main';
    SyncQueueHelper.onQueued = null;
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('collections are registered for push and pull', () {
    for (final e in instPushCollections.entries) {
      expect(pushCollections[e.key], e.value);
      expect(pullCollections, contains(e.value));
      expect(branchScopedCollections, contains(e.value));
    }
    expect(instPullCollections.length, 8);
  });

  Future<void> seedA() async {
    await a.insert('customers', {'name': 'Ali', 'serverId': 'customer:AAAA-1'});
    await a.insert('customer_profiles', {'customerId': 1, 'fatherName': 'Aslam', 'cnic': '35202-1234567-1', 'createdAt': 1});
    await a.insert('inst_guarantors', {'customerId': 1, 'name': 'Usman', 'phone': '03001234567', 'createdAt': 1});
    await a.insert('inst_categories', {'name': 'Mobile', 'idFields': '["IMEI 1","IMEI 2"]'});
    await a.insert('inst_items', {'categoryId': 1, 'brand': 'Samsung', 'model': 'A15', 'idValues': '{"IMEI 1":"356789012345678"}', 'cashPrice': 50000, 'status': 'sold'});
    await a.insert('inst_plans', {
      'planNo': 'Q-AA0001', 'customerId': 1, 'itemId': 1, 'guarantorIds': '[1]', 'cashPrice': 50000, 'advance': 10000,
      'totalPrice': 62000, 'installmentTotal': 52000, 'count': 2, 'firstDueDate': 100, 'status': 'active', 'createdAt': 2,
    });
    await a.insert('inst_schedule', {'planId': 1, 'seq': 1, 'dueDate': 100, 'amount': 26000});
    await a.insert('inst_schedule', {'planId': 1, 'seq': 2, 'dueDate': 200, 'amount': 26000});
    await a.insert('cash_transactions', {'type': 'IN', 'method': 'cash', 'amount': 10000, 'reference': 'inst-pay:1-1', 'createdAt': 3});
    await a.insert('inst_payments', {'planId': 1, 'kind': 'advance', 'amount': 10000, 'cashTxId': 1, 'paidAt': 3, 'createdAt': 3});
    await SyncQueueHelper.enqueueCashTransaction(a, 1);
    await InstSync.enqueueAll(a);
  }

  test('device A data appears on device B, linked by serverId', () async {
    await seedA();
    final docs = await _cloud(a);
    expect(docs.keys, containsAll(instPullCollections.where((c) => c != 'inst_photos' && c != 'inst_price_changes')));

    // B: customer aur cash row POS sync se pehle aa chuke (alag local ids).
    await b.insert('customers', {'name': 'Zain', 'serverId': 'customer:BBBB-1'});
    await b.insert('customers', {'name': 'Ali', 'serverId': 'customer:AAAA-1'}); // B par id 2
    await b.insert('cash_transactions', {'type': 'IN', 'method': 'cash', 'amount': 1, 'createdAt': 1});
    await b.insert('cash_transactions',
        {'type': 'IN', 'method': 'cash', 'amount': 10000, 'reference': 'inst-pay:1-1', 'createdAt': 3, 'serverId': 'cash_transaction:0000-1'});
    // B par pehle se apni "Mobile" (seed, serverId nahi) — dobara nahi banni chahiye.
    await b.insert('inst_categories', {'name': 'mobile', 'idFields': '[]'});

    await applyInstallmentChanges(b, docs, nowMs: () => 9000);

    expect((await b.query('inst_categories')).length, 1);
    final prof = (await b.query('customer_profiles')).single;
    expect(prof['customerId'], 2);
    expect(prof['cnic'], '35202-1234567-1');
    final g = (await b.query('inst_guarantors')).single;
    expect(g['customerId'], 2);
    final item = (await b.query('inst_items')).single;
    expect(item['status'], 'sold');
    expect(item['categoryId'], 1);
    final plan = (await b.query('inst_plans')).single;
    expect(plan['customerId'], 2);
    expect(plan['itemId'], item['id']);
    expect(jsonDecode(plan['guarantorIds'] as String), [g['id']]);
    expect((await b.query('inst_schedule', orderBy: 'seq')).map((r) => r['amount']), [26000.0, 26000.0]);
    final pay = (await b.query('inst_payments')).single;
    expect(pay['planId'], plan['id']);
    expect(pay['cashTxId'], 2);
    expect(pay['kind'], 'advance');

    // Dobara wahi pull: kuch dobara nahi banta (idempotent).
    await applyInstallmentChanges(b, docs, nowMs: () => 9000);
    expect((await b.query('inst_plans')).length, 1);
    expect((await b.query('inst_payments')).length, 1);
    expect((await b.query('inst_schedule')).length, 2);
  });

  test('tombstones remove the plan with its payments and schedule', () async {
    await seedA();
    await b.insert('customers', {'name': 'Ali', 'serverId': 'customer:AAAA-1'});
    await applyInstallmentChanges(b, await _cloud(a), nowMs: () => 9000);
    expect((await b.query('inst_plans')).length, 1);

    // A par plan delete (ghalti): pehle tombstone, phir local delete.
    await a.delete('sync_queue');
    await InstSync.enqueueDeleteRow(a, instPaymentType, 'inst_payments', 'id', 1);
    await InstSync.enqueueDeleteRow(a, instPlanType, 'inst_plans', 'id', 1);
    await applyInstallmentChanges(b, await _cloud(a), nowMs: () => 9000);
    expect(await b.query('inst_plans'), isEmpty);
    expect(await b.query('inst_payments'), isEmpty);
    expect(await b.query('inst_schedule'), isEmpty);
  });

  test('unpushed local edit is not overwritten by an older cloud copy', () async {
    await seedA();
    await b.insert('customers', {'name': 'Ali', 'serverId': 'customer:AAAA-1'});
    final docs = await _cloud(a);
    await applyInstallmentChanges(b, docs, nowMs: () => 9000);
    // B ne item ka note badla, abhi push nahi hua.
    final sid = (await b.query('inst_items')).single['serverId'] as String;
    await b.update('inst_items', {'note': 'B edit'});
    await SyncQueueHelper.enqueue(b, instItemType, sid, 'upsert', {'serverId': sid});
    await applyInstallmentChanges(b, docs, nowMs: () => 9000);
    expect((await b.query('inst_items')).single['note'], 'B edit');
  });

  test('photo doc id is stable and a valid Firestore id', () {
    final id = InstPhotoSync.docId('g', 'inst_guarantor:7F2A-3', 'cnicF');
    expect(id, 'inst_photo:g|inst_guarantor:7F2A-3|cnicF');
    expect(id.contains('/'), isFalse);
    expect(InstPhotoSync.maxBytes * 4 / 3 < 1000000, isTrue); // base64 Firestore doc / function limit ke andar
    expect(pushCollections[instPhotoType], 'inst_photos');
    expect(instPullCollections.last, 'inst_photos');
  });

  test('daily alert text', () {
    expect(InstDueAlert.bodyFor(dueTodayCount: 0, dueToday: 0, overdueCount: 0, overdue: 0, topNames: const []), isNull);
    final t = InstDueAlert.bodyFor(dueTodayCount: 2, dueToday: 8000, overdueCount: 1, overdue: 4000, topNames: const ['Ali', 'Usman']);
    expect(t, 'Aaj 2 qisten (Rs 8000) • 1 late (Rs 4000). Pehle: Ali, Usman. Tap karke wasooli list dekhein.');
  });
}
