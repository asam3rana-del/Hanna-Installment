import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../sync/device_tag.dart';
import '../sync/sync_queue_dao.dart';
import '../sync/sync_queue_helper.dart';
import '../sync/sync_types.dart';
import 'inst_photo_sync.dart' show applyInstallmentPhotos;
import 'inst_sync_names.dart';

export 'inst_sync_names.dart';

/// Hanna Installment Step 5 — qist ke data ka Firestore sync (POS ke sync engine ke andar).
///
/// Push: har local write ke saath (usi transaction mein) [InstSync] ka `enqueueX` — POS ka `sync_queue` /
/// `SyncApi.push` hi document likhta hai (last-write-wins, tombstone delete). Pull: `SyncApi.pull` neeche wali
/// collections bhi laata hai, aur `applyRestOfServerChanges` aakhir mein [applyInstallmentChanges] chalata hai.
///
/// Local ids har device par alag — is liye har reference doosre record ki `serverId` se:
///   profile -> customerServerId, guarantor -> customerServerId, item -> categoryServerId,
///   plan -> customerServerId + itemServerId + guarantorServerIds (+ poora schedule plan ke andar),
///   payment -> planServerId + cashServerId (saath wali cash_transactions row, jo POS khud sync karta hai).
/// Tasveerein sync NAHI hoti (Firebase Spark par Storage nahi) — sirf is device par.

String _s(Object? v) => v is String ? v : '';
String? _sn(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
double _d(Object? v) => v is num ? v.toDouble() : 0.0;
int _i(Object? v) => v is num ? v.toInt() : 0;

Map<String, Object?> _stamp(Map<String, Object?> m) =>
    {...m, 'updatedAt': SyncQueueHelper.nowMs(), 'branchId': SyncQueueHelper.branchId(), '_deleted': false};

Future<Map<String, Object?>?> _row(DatabaseExecutor ex, String table, String col, Object value) async {
  final r = await ex.query(table, where: '$col = ?', whereArgs: [value], limit: 1);
  return r.isEmpty ? null : Map<String, Object?>.from(r.first);
}

class InstSync {
  InstSync._();

  /// Pull apply hone ke baad (InstRepository screens ko refresh karta hai).
  static void Function()? onApplied;

  static String _own(String prefix, Map<String, Object?> row) {
    final sid = row['serverId'];
    if (sid is String && sid.trim().isNotEmpty) return sid;
    return '$prefix${DeviceTag.current}-${row['id']}';
  }

  /// Category ki id naam se (har device par pehle se bani "Mobile" ek hi doc bane, dobara nahi).
  static String categoryId(Map<String, Object?> row) {
    final sid = row['serverId'];
    if (sid is String && sid.trim().isNotEmpty) return sid;
    final key = _s(row['name']).trim().toLowerCase().replaceAll(RegExp(r'[\s/]+'), '_');
    return 'inst_category:$key';
  }

  static Future<void> _stampServerId(DatabaseExecutor ex, String table, String keyCol, Object key, String sid) =>
      ex.update(table, {'serverId': sid}, where: '$keyCol = ? AND (serverId IS NULL OR serverId != ?)', whereArgs: [key, sid]);

  /// Customer ki serverId (na ho to customer ko queue kar ke stamp — POS ka apna tareeqa).
  static Future<String?> customerServerId(DatabaseExecutor ex, int customerId) async {
    var c = await _row(ex, 'customers', 'id', customerId);
    if (c == null) return null;
    if (_sn(c['serverId']) == null) {
      await SyncQueueHelper.enqueueCustomer(ex, customerId);
      c = await _row(ex, 'customers', 'id', customerId);
    }
    return _sn(c?['serverId']);
  }

  // ================================================================ push

  static Future<void> enqueueProfile(DatabaseExecutor ex, int customerId) async {
    final p = await _row(ex, 'customer_profiles', 'customerId', customerId);
    if (p == null) return;
    final csid = await customerServerId(ex, customerId);
    if (csid == null) return;
    final eid = 'inst_profile:$csid';
    await _stampServerId(ex, 'customer_profiles', 'customerId', customerId, eid);
    await SyncQueueHelper.enqueue(ex, instProfileType, eid, 'upsert', _stamp({
      'serverId': eid,
      'customerServerId': csid,
      for (final k in const ['fatherName', 'cnic', 'phone2', 'address', 'occupation', 'workAddress', 'note']) k: _s(p[k]),
      'monthlyIncome': _d(p['monthlyIncome']),
      'createdAt': _i(p['createdAt']),
    }));
  }

  static Future<void> enqueueGuarantor(DatabaseExecutor ex, int id) async {
    final g = await _row(ex, 'inst_guarantors', 'id', id);
    if (g == null) return;
    final csid = await customerServerId(ex, _i(g['customerId']));
    if (csid == null) return;
    final eid = _own('inst_guarantor:', g);
    await _stampServerId(ex, 'inst_guarantors', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instGuarantorType, eid, 'upsert', _stamp({
      'serverId': eid,
      'customerServerId': csid,
      for (final k in const ['name', 'fatherName', 'cnic', 'phone', 'address', 'relation', 'occupation']) k: _s(g[k]),
      'createdAt': _i(g['createdAt']),
    }));
  }

  static Future<void> enqueueCategory(DatabaseExecutor ex, int id) async {
    final c = await _row(ex, 'inst_categories', 'id', id);
    if (c == null) return;
    final eid = categoryId(c);
    await _stampServerId(ex, 'inst_categories', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instCategoryType, eid, 'upsert', _stamp({
      'serverId': eid,
      'name': _s(c['name']),
      'idFields': _s(c['idFields']),
      'sortOrder': _i(c['sortOrder']),
      'createdAt': _i(c['createdAt']),
    }));
  }

  static Future<String?> _categoryServerId(DatabaseExecutor ex, int categoryId) async {
    final c = await _row(ex, 'inst_categories', 'id', categoryId);
    if (c == null) return null;
    if (_sn(c['serverId']) == null) await enqueueCategory(ex, categoryId);
    return _sn((await _row(ex, 'inst_categories', 'id', categoryId))?['serverId']);
  }

  static Future<String?> itemServerId(DatabaseExecutor ex, int itemId) async {
    final it = await _row(ex, 'inst_items', 'id', itemId);
    if (it == null) return null;
    final sid = _sn(it['serverId']);
    if (sid != null) return sid;
    await enqueueItem(ex, itemId);
    return _sn((await _row(ex, 'inst_items', 'id', itemId))?['serverId']);
  }

  static Future<void> enqueueItem(DatabaseExecutor ex, int id) async {
    final it = await _row(ex, 'inst_items', 'id', id);
    if (it == null) return;
    final cat = await _categoryServerId(ex, _i(it['categoryId']));
    final eid = _own('inst_item:', it);
    await _stampServerId(ex, 'inst_items', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instItemType, eid, 'upsert', _stamp({
      'serverId': eid,
      'categoryServerId': cat,
      for (final k in const ['brand', 'model', 'color', 'idValues', 'supplier', 'note', 'status']) k: _s(it[k]),
      'costPrice': _d(it['costPrice']),
      'cashPrice': _d(it['cashPrice']),
      'warrantyMonths': _i(it['warrantyMonths']),
      'purchaseDate': _i(it['purchaseDate']),
      'createdAt': _i(it['createdAt']),
    }));
  }

  static Future<String?> planServerId(DatabaseExecutor ex, int planId) async {
    final p = await _row(ex, 'inst_plans', 'id', planId);
    if (p == null) return null;
    final sid = _sn(p['serverId']);
    if (sid != null) return sid;
    await enqueuePlan(ex, planId);
    return _sn((await _row(ex, 'inst_plans', 'id', planId))?['serverId']);
  }

  static Future<void> enqueuePlan(DatabaseExecutor ex, int id) async {
    final p = await _row(ex, 'inst_plans', 'id', id);
    if (p == null) return;
    final csid = await customerServerId(ex, _i(p['customerId']));
    final isid = await itemServerId(ex, _i(p['itemId']));
    if (csid == null || isid == null) return;
    final gIds = <String>[];
    try {
      final raw = jsonDecode(_s(p['guarantorIds']));
      if (raw is List) {
        for (final g in raw) {
          if (g is! num) continue;
          final gr = await _row(ex, 'inst_guarantors', 'id', g.toInt());
          if (gr == null) continue;
          if (_sn(gr['serverId']) == null) await enqueueGuarantor(ex, g.toInt());
          final sid = _sn((await _row(ex, 'inst_guarantors', 'id', g.toInt()))?['serverId']);
          if (sid != null) gIds.add(sid);
        }
      }
    } catch (_) {}
    final sched = [
      for (final r in await ex.query('inst_schedule', where: 'planId = ?', whereArgs: [id], orderBy: 'seq'))
        {'seq': _i(r['seq']), 'dueDate': _i(r['dueDate']), 'amount': _d(r['amount'])}
    ];
    final eid = _own('inst_plan:', p);
    await _stampServerId(ex, 'inst_plans', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPlanType, eid, 'upsert', _stamp({
      'serverId': eid,
      'customerServerId': csid,
      'itemServerId': isid,
      'guarantorServerIds': gIds,
      'schedule': sched,
      for (final k in const ['planNo', 'profitMode', 'frequency', 'status', 'note', 'createdBy']) k: _s(p[k]),
      for (final k in const ['cashPrice', 'costPrice', 'advance', 'profitValue', 'profit', 'totalPrice', 'installmentTotal', 'lateFee'])
        k: _d(p[k]),
      for (final k in const ['count', 'firstDueDate', 'roundTo', 'graceDays', 'createdAt', 'closedAt']) k: _i(p[k]),
    }));
  }

  static Future<void> enqueuePayment(DatabaseExecutor ex, int id) async {
    final pay = await _row(ex, 'inst_payments', 'id', id);
    if (pay == null) return;
    final psid = await planServerId(ex, _i(pay['planId']));
    if (psid == null) return;
    String? cashSid;
    final cashId = pay['cashTxId'];
    if (cashId is num) {
      final cash = await _row(ex, 'cash_transactions', 'id', cashId.toInt());
      if (cash != null) cashSid = SyncQueueHelper.cashTransactionEntityId(cash);
    }
    final eid = _own('inst_payment:', pay);
    await _stampServerId(ex, 'inst_payments', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPaymentType, eid, 'upsert', _stamp({
      'serverId': eid,
      'planServerId': psid,
      'cashServerId': cashSid,
      for (final k in const ['kind', 'method', 'note', 'receivedBy']) k: _s(pay[k]),
      'amount': _d(pay['amount']),
      'fine': _d(pay['fine']),
      'paidAt': _i(pay['paidAt']),
      'createdAt': _i(pay['createdAt']),
    }));
  }

  /// Delete se PEHLE bulayein (row se serverId chahiye). serverId na ho (kabhi push hi nahi hua) to kuch nahi.
  static Future<void> enqueueDeleteRow(DatabaseExecutor ex, String type, String table, String keyCol, Object key) async {
    final r = await _row(ex, table, keyCol, key);
    final sid = _sn(r?['serverId']);
    if (sid == null) return;
    await SyncQueueHelper.enqueueDelete(ex, type, sid);
  }

  /// "Force full push": sab qist data dobara queue (parent pehle).
  static Future<void> enqueueAll(DatabaseExecutor ex) async {
    if ((await ex.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_plans'")).isEmpty) return;
    for (final r in await ex.query('inst_categories', columns: ['id'])) {
      await enqueueCategory(ex, _i(r['id']));
    }
    for (final r in await ex.query('customer_profiles', columns: ['customerId'])) {
      await enqueueProfile(ex, _i(r['customerId']));
    }
    for (final r in await ex.query('inst_guarantors', columns: ['id'])) {
      await enqueueGuarantor(ex, _i(r['id']));
    }
    for (final r in await ex.query('inst_items', columns: ['id'])) {
      await enqueueItem(ex, _i(r['id']));
    }
    for (final r in await ex.query('inst_plans', columns: ['id'])) {
      await enqueuePlan(ex, _i(r['id']));
    }
    for (final r in await ex.query('inst_payments', columns: ['id'])) {
      await enqueuePayment(ex, _i(r['id']));
    }
  }
}

// ================================================================== pull / apply

Future<int?> _localIdBySid(DatabaseExecutor db, String table, String sid, {String idCol = 'id'}) async {
  final r = await _row(db, table, 'serverId', sid);
  return r == null ? null : _i(r[idCol]);
}

/// [docs] = collection -> documents (PullResult.installment). Ek hi transaction mein (db = txn).
Future<void> applyInstallmentChanges(DatabaseExecutor db, Map<String, List<SyncDoc>> docs, {required int Function() nowMs}) async {
  if (docs.values.every((l) => l.isEmpty)) return;
  if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_plans'")).isEmpty) return;
  final q = SyncQueueDao(db);
  List<SyncDoc> of(String c) => docs[c] ?? const [];
  Future<bool> pending(String type, String sid) async => await q.pendingCountForEntity(type, sid) > 0;

  // ---- categories (naam se bhi milate hain: dono device par pehle se bani "Mobile")
  for (final d in of('inst_categories')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instCategoryType, sid)) continue;
    var local = await _row(db, 'inst_categories', 'serverId', sid);
    if (d['_deleted'] == true) {
      if (local != null) {
        final used = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_items WHERE categoryId = ?', [local['id']])) ?? 0;
        if (used == 0) await db.delete('inst_categories', where: 'id = ?', whereArgs: [local['id']]);
      }
      continue;
    }
    final name = _s(d['name']).trim();
    if (name.isEmpty) continue;
    local ??= (await db.rawQuery(
            'SELECT * FROM inst_categories WHERE LOWER(TRIM(name)) = ? AND (serverId IS NULL OR serverId = \'\') LIMIT 1',
            [name.toLowerCase()]))
        .firstOrNull;
    final values = {
      'name': name,
      'idFields': _s(d['idFields']).isEmpty ? '[]' : _s(d['idFields']),
      'sortOrder': _i(d['sortOrder']),
      'updatedAt': _i(d['updatedAt']),
      'serverId': sid,
    };
    if (local == null) {
      await db.insert('inst_categories', {...values, 'createdAt': _i(d['createdAt']) == 0 ? nowMs() : _i(d['createdAt'])});
    } else {
      await db.update('inst_categories', values, where: 'id = ?', whereArgs: [local['id']]);
    }
  }

  // ---- profiles
  for (final d in of('inst_customer_profiles')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instProfileType, sid)) continue;
    final cid = await _localIdBySid(db, 'customers', _s(d['customerServerId']));
    if (d['_deleted'] == true) {
      if (cid != null) await db.delete('customer_profiles', where: 'customerId = ?', whereArgs: [cid]);
      continue;
    }
    if (cid == null) continue; // customer abhi is device par nahi
    final values = <String, Object?>{
      for (final k in const ['fatherName', 'cnic', 'phone2', 'address', 'occupation', 'workAddress', 'note']) k: _s(d[k]),
      'monthlyIncome': _d(d['monthlyIncome']),
      'updatedAt': _i(d['updatedAt']),
      'serverId': sid,
    };
    if (await _row(db, 'customer_profiles', 'customerId', cid) == null) {
      await db.insert('customer_profiles', {...values, 'customerId': cid, 'createdAt': _i(d['createdAt'])});
    } else {
      await db.update('customer_profiles', values, where: 'customerId = ?', whereArgs: [cid]);
    }
  }

  // ---- guarantors
  for (final d in of('inst_guarantors')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instGuarantorType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_guarantors', sid);
    if (d['_deleted'] == true) {
      if (localId != null) await db.delete('inst_guarantors', where: 'id = ?', whereArgs: [localId]);
      continue;
    }
    final cid = await _localIdBySid(db, 'customers', _s(d['customerServerId']));
    final name = _s(d['name']).trim();
    if (cid == null || name.isEmpty) continue;
    final values = <String, Object?>{
      'customerId': cid,
      for (final k in const ['name', 'fatherName', 'cnic', 'phone', 'address', 'relation', 'occupation']) k: _s(d[k]),
      'updatedAt': _i(d['updatedAt']),
    };
    if (localId == null) {
      await db.insert('inst_guarantors', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      await db.update('inst_guarantors', values, where: 'id = ?', whereArgs: [localId]);
    }
  }

  // ---- items
  for (final d in of('inst_items')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instItemType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_items', sid);
    if (d['_deleted'] == true) {
      if (localId != null) {
        final used = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_plans WHERE itemId = ?', [localId])) ?? 0;
        if (used == 0) await db.delete('inst_items', where: 'id = ?', whereArgs: [localId]);
      }
      continue;
    }
    final catSid = _sn(d['categoryServerId']);
    var catId = catSid == null ? null : await _localIdBySid(db, 'inst_categories', catSid);
    catId ??= _i((await db.rawQuery('SELECT id FROM inst_categories ORDER BY sortOrder LIMIT 1')).firstOrNull?['id']);
    final model = _s(d['model']).trim();
    if (model.isEmpty) continue;
    final status = _s(d['status']);
    final values = <String, Object?>{
      'categoryId': catId,
      for (final k in const ['brand', 'color', 'supplier', 'note']) k: _s(d[k]),
      'model': model,
      'idValues': _s(d['idValues']).isEmpty ? '{}' : _s(d['idValues']),
      'status': const {'in_stock', 'sold', 'returned', 'repossessed'}.contains(status) ? status : 'in_stock',
      'costPrice': _d(d['costPrice']),
      'cashPrice': _d(d['cashPrice']),
      'warrantyMonths': _i(d['warrantyMonths']),
      'purchaseDate': _i(d['purchaseDate']),
      'updatedAt': _i(d['updatedAt']),
    };
    if (localId == null) {
      await db.insert('inst_items', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      await db.update('inst_items', values, where: 'id = ?', whereArgs: [localId]);
    }
  }

  // ---- plans (+ schedule)
  for (final d in of('inst_plans')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instPlanType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_plans', sid);
    if (d['_deleted'] == true) {
      if (localId != null) {
        await db.delete('inst_payments', where: 'planId = ?', whereArgs: [localId]);
        await db.delete('inst_schedule', where: 'planId = ?', whereArgs: [localId]);
        await db.delete('inst_plans', where: 'id = ?', whereArgs: [localId]);
      }
      continue;
    }
    final cid = await _localIdBySid(db, 'customers', _s(d['customerServerId']));
    final iid = await _localIdBySid(db, 'inst_items', _s(d['itemServerId']));
    if (cid == null || iid == null) continue;
    final gLocal = <int>[];
    final gs = d['guarantorServerIds'];
    if (gs is List) {
      for (final g in gs) {
        if (g is! String) continue;
        final id = await _localIdBySid(db, 'inst_guarantors', g);
        if (id != null) gLocal.add(id);
      }
    }
    final values = <String, Object?>{
      'customerId': cid,
      'itemId': iid,
      'guarantorIds': jsonEncode(gLocal),
      for (final k in const ['planNo', 'profitMode', 'frequency', 'status', 'note', 'createdBy']) k: _s(d[k]),
      for (final k in const ['cashPrice', 'costPrice', 'advance', 'profitValue', 'profit', 'totalPrice', 'installmentTotal', 'lateFee'])
        k: _d(d[k]),
      for (final k in const ['count', 'firstDueDate', 'roundTo', 'graceDays', 'closedAt']) k: _i(d[k]),
      'updatedAt': _i(d['updatedAt']),
    };
    final int planId;
    if (localId == null) {
      planId = await db.insert('inst_plans', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      planId = localId;
      await db.update('inst_plans', values, where: 'id = ?', whereArgs: [localId]);
    }
    final sched = d['schedule'];
    if (sched is List && sched.isNotEmpty) {
      await db.delete('inst_schedule', where: 'planId = ?', whereArgs: [planId]);
      for (final s in sched) {
        if (s is! Map) continue;
        await db.insert('inst_schedule', {'planId': planId, 'seq': _i(s['seq']), 'dueDate': _i(s['dueDate']), 'amount': _d(s['amount'])},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  // ---- payments (cash row POS sync se pehle hi aa chuki hoti hai: cashServerId se jodo)
  for (final d in of('inst_payments')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instPaymentType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_payments', sid);
    if (d['_deleted'] == true) {
      if (localId != null) await db.delete('inst_payments', where: 'id = ?', whereArgs: [localId]);
      continue;
    }
    final pid = await _localIdBySid(db, 'inst_plans', _s(d['planServerId']));
    if (pid == null) continue;
    final cashSid = _sn(d['cashServerId']);
    final cashId = cashSid == null ? null : await _localIdBySid(db, 'cash_transactions', cashSid);
    final kind = _s(d['kind']) == 'advance' ? 'advance' : 'installment';
    final values = <String, Object?>{
      'planId': pid,
      'kind': kind,
      'amount': _d(d['amount']),
      'fine': _d(d['fine']),
      'method': _s(d['method']) == 'bank' ? 'bank' : 'cash',
      'note': _s(d['note']),
      'receivedBy': _s(d['receivedBy']),
      'paidAt': _i(d['paidAt']),
      'cashTxId': cashId,
    };
    if (localId == null) {
      await db.insert('inst_payments', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      await db.update('inst_payments', values, where: 'id = ?', whereArgs: [localId]);
    }
  }
  // ---- tasveerein (files; customers / guarantors upar aa chuke)
  await applyInstallmentPhotos(db, of('inst_photos'));
  InstSync.onApplied?.call();
}
