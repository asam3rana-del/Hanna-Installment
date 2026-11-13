import 'dart:convert';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Sqflite;

import '../db/app_database.dart';
import '../models/misc_entities.dart' show CashTransaction;
import '../services/session.dart';
import '../sync/device_tag.dart';
import '../sync/sync_queue_helper.dart';
import 'inst_models.dart';
import 'inst_plan_math.dart';
import 'inst_reports.dart';
import 'inst_repository.dart';
import 'inst_sync.dart';

/// Qist plan: banana, qist lena, payment wapas, plan delete / saman wapas lena.
///
/// Har wasooli (advance bhi) ke saath ek `cash_transactions` IN row banti hai (reason `Qist: <planNo>`), taake
/// aaj ka cash / cash register poora ho; wo row POS ke sync se doosre devices par bhi jati hai. Qist ka munafa
/// "income" nahi likha jata (wasooli udhaar ki wapsi hai) — munafa installment reports mein alag dikhega.
class InstPlan {
  final int id;
  final String planNo;
  final int customerId;
  final int itemId;
  final List<int> guarantorIds;
  final double cashPrice;
  final double costPrice;
  final double advance;
  final String profitMode;
  final double profitValue;
  final double profit;
  final double totalPrice;
  final double installmentTotal;
  final int count;
  final String frequency;
  final int firstDueDate;
  final int roundTo;
  final double lateFee;
  final int graceDays;
  final String status;
  final String note;
  final String createdBy;
  final int createdAt;
  final int closedAt;

  const InstPlan({
    required this.id,
    required this.planNo,
    required this.customerId,
    required this.itemId,
    required this.guarantorIds,
    required this.cashPrice,
    required this.costPrice,
    required this.advance,
    required this.profitMode,
    required this.profitValue,
    required this.profit,
    required this.totalPrice,
    required this.installmentTotal,
    required this.count,
    required this.frequency,
    required this.firstDueDate,
    required this.roundTo,
    required this.lateFee,
    required this.graceDays,
    required this.status,
    required this.note,
    required this.createdBy,
    required this.createdAt,
    required this.closedAt,
  });

  bool get isActive => status == planActive;

  factory InstPlan.fromMap(Map<String, Object?> m) {
    double d(String k) => ((m[k] as num?) ?? 0).toDouble();
    int i(String k) => ((m[k] as num?) ?? 0).toInt();
    String s(String k) => (m[k] as String?) ?? '';
    return InstPlan(
      id: i('id'),
      planNo: s('planNo'),
      customerId: i('customerId'),
      itemId: i('itemId'),
      guarantorIds: parseIdList(s('guarantorIds')),
      cashPrice: d('cashPrice'),
      costPrice: d('costPrice'),
      advance: d('advance'),
      profitMode: s('profitMode'),
      profitValue: d('profitValue'),
      profit: d('profit'),
      totalPrice: d('totalPrice'),
      installmentTotal: d('installmentTotal'),
      count: i('count'),
      frequency: s('frequency'),
      firstDueDate: i('firstDueDate'),
      roundTo: i('roundTo'),
      lateFee: d('lateFee'),
      graceDays: i('graceDays'),
      status: s('status'),
      note: s('note'),
      createdBy: s('createdBy'),
      createdAt: i('createdAt'),
      closedAt: i('closedAt'),
    );
  }
}

class InstPayment {
  final int id;
  final int planId;
  final String kind;
  final double amount;
  final double fine;
  final String method;
  final String note;
  final int? cashTxId;
  final String receivedBy;
  final int paidAt;
  const InstPayment({
    required this.id,
    required this.planId,
    required this.kind,
    required this.amount,
    required this.fine,
    required this.method,
    required this.note,
    required this.cashTxId,
    required this.receivedBy,
    required this.paidAt,
  });

  factory InstPayment.fromMap(Map<String, Object?> m) => InstPayment(
        id: ((m['id'] as num?) ?? 0).toInt(),
        planId: ((m['planId'] as num?) ?? 0).toInt(),
        kind: (m['kind'] as String?) ?? payInstallment,
        amount: ((m['amount'] as num?) ?? 0).toDouble(),
        fine: ((m['fine'] as num?) ?? 0).toDouble(),
        method: (m['method'] as String?) ?? 'cash',
        note: (m['note'] as String?) ?? '',
        cashTxId: (m['cashTxId'] as num?)?.toInt(),
        receivedBy: (m['receivedBy'] as String?) ?? '',
        paidAt: ((m['paidAt'] as num?) ?? 0).toInt(),
      );
}

/// Ek plan aur us ka sab kuch — detail screen / list ke liye.
class PlanView {
  final InstPlan plan;
  final String customerName;
  final String customerPhone;
  final InstItem? item;
  final List<(int, double)> schedule;
  final List<InstPayment> payments;
  final PlanStatus status;

  const PlanView({
    required this.plan,
    required this.customerName,
    required this.customerPhone,
    required this.item,
    required this.schedule,
    required this.payments,
    required this.status,
  });

  double get finesTaken => payments.fold<double>(0, (a, p) => a + p.fine);
  double get advancePaid => payments.where((p) => p.kind == payAdvance).fold<double>(0, (a, p) => a + p.amount);
  String get itemTitle => item == null ? '' : (item!.title.isEmpty ? item!.model : item!.title);

  /// Customer / plan no / item / IMEI.
  bool matches(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    if ('$customerName ${plan.planNo} $customerPhone'.toLowerCase().contains(t)) return true;
    return item?.matches(t) ?? false;
  }
}

class InstPlanRepository {
  InstPlanRepository._();
  static final InstPlanRepository instance = InstPlanRepository._();

  int _now() => DateTime.now().millisecondsSinceEpoch;
  void _changed() => InstRepository.instance.changes.value++;

  // ================================================================ create

  /// Naya plan. Item `sold` ho jata hai, schedule banta hai, advance (agar ho) wasool + cash IN.
  /// Wapas: plan id.
  Future<int> createPlan({
    required int customerId,
    required int itemId,
    required List<int> guarantorIds,
    required double cashPrice,
    required double advance,
    required String advanceMethod,
    required String profitMode,
    required double profitValue,
    required int count,
    required String frequency,
    required int firstDueDate,
    required int roundTo,
    required double lateFee,
    required int graceDays,
    String note = '',
  }) async {
    final q = quotePlan(
      cashPrice: cashPrice,
      advance: advance,
      profitMode: profitMode,
      profitValue: profitValue,
      count: count,
      roundTo: roundTo,
    );
    if (!planFrequencies.contains(frequency)) throw ArgumentError('Qist ka waqfa chunein.');
    if (firstDueDate <= 0) throw ArgumentError('Pehli qist ki tareekh chunein.');
    if (lateFee < 0 || graceDays < 0) throw ArgumentError('Late fine minus nahi ho sakta.');
    final db = await AppDatabase.instance.database;
    final now = _now();
    final id = await db.transaction((txn) async {
      final cust = await txn.query('customers', columns: ['id', 'name'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (cust.isEmpty) throw ArgumentError('Customer nahi mila.');
      final items = await txn.query('inst_items', where: 'id = ?', whereArgs: [itemId], limit: 1);
      if (items.isEmpty) throw ArgumentError('Saman nahi mila.');
      final item = InstItem.fromMap(items.first);
      if (!item.inStock) throw ArgumentError('Ye piece stock mein nahi (pehle bik chuka / wapas).');
      final planId = await txn.insert('inst_plans', {
        'planNo': '',
        'customerId': customerId,
        'itemId': itemId,
        'guarantorIds': jsonEncode(guarantorIds.toSet().toList()),
        'cashPrice': q.cashPrice,
        'costPrice': item.costPrice,
        'advance': q.advance,
        'profitMode': profitMode,
        'profitValue': profitValue,
        'profit': q.profit,
        'totalPrice': q.totalPrice,
        'installmentTotal': q.installmentTotal,
        'count': q.count,
        'frequency': frequency,
        'firstDueDate': firstDueDate,
        'roundTo': roundTo,
        'lateFee': lateFee,
        'graceDays': graceDays,
        'status': planActive,
        'note': note.trim(),
        'createdBy': Session.username ?? '',
        'createdAt': now,
        'updatedAt': now,
      });
      // Device tag ke 2 harf: do devices ke plan number aapas mein na takrayein (Q-7F0012).
      final tag = DeviceTag.current.length >= 2 ? DeviceTag.current.substring(0, 2) : DeviceTag.current;
      final planNo = 'Q-$tag${planId.toString().padLeft(4, '0')}';
      await txn.update('inst_plans', {'planNo': planNo}, where: 'id = ?', whereArgs: [planId]);
      final amounts = q.amounts;
      for (var i = 0; i < amounts.length; i++) {
        await txn.insert('inst_schedule', {
          'planId': planId,
          'seq': i + 1,
          'dueDate': dueDateOf(firstDueDate, frequency, i),
          'amount': amounts[i],
        });
      }
      await txn.update('inst_items', {'status': itemSold, 'updatedAt': now}, where: 'id = ?', whereArgs: [itemId]);
      await InstSync.enqueueItem(txn, itemId);
      await InstSync.enqueuePlan(txn, planId);
      if (q.advance > 0) {
        await _insertPayment(txn,
            planId: planId, planNo: planNo, kind: payAdvance, amount: q.advance, fine: 0, method: advanceMethod, note: '', paidAt: now);
      }
      return planId;
    });
    _changed();
    return id;
  }

  Future<int> _insertPayment(
    DatabaseExecutor txn, {
    required int planId,
    required String planNo,
    required String kind,
    required double amount,
    required double fine,
    required String method,
    required String note,
    required int paidAt,
  }) async {
    final now = _now();
    final payId = await txn.insert('inst_payments', {
      'planId': planId,
      'kind': kind,
      'amount': amount,
      'fine': fine,
      'method': method,
      'note': note.trim(),
      'receivedBy': Session.username ?? '',
      'paidAt': paidAt,
      'createdAt': now,
    });
    final total = amount + fine;
    if (total > 0) {
      final cash = CashTransaction(
        type: 'IN',
        method: method,
        amount: total,
        reason: kind == payAdvance ? 'Qist advance: $planNo' : 'Qist: $planNo${fine > 0 ? ' (fine ${fine.round()})' : ''}',
        reference: 'inst-pay:$planId-$payId',
        createdAt: now,
        updatedAt: now,
      );
      final cashId = await txn.insert('cash_transactions', cash.toMap()..remove('id'));
      await SyncQueueHelper.enqueueCashTransaction(txn, cashId);
      await txn.update('inst_payments', {'cashTxId': cashId}, where: 'id = ?', whereArgs: [payId]);
    }
    await InstSync.enqueuePayment(txn, payId);
    return payId;
  }

  /// Wasooli ki cash row hatao: is device par bani ho to reference se, doosre device se aayi ho to cashTxId se.
  /// Dono raste POS ke sync delete ke saath (doosre devices se bhi hat'ti hai).
  Future<void> _deleteCash(DatabaseExecutor txn, int planId, int payId, int? cashTxId) async {
    await SyncQueueHelper.deleteCashTransactionsByReference(txn, 'inst-pay:$planId-$payId');
    if (cashTxId == null) return;
    final rows = await txn.query('cash_transactions', where: 'id = ?', whereArgs: [cashTxId], limit: 1);
    if (rows.isEmpty) return;
    final row = Map<String, Object?>.from(rows.first);
    if (!(row['reference'] as String? ?? '').startsWith('inst-pay:')) return; // kisi aur ki row nahi chhedte
    await txn.delete('cash_transactions', where: 'id = ?', whereArgs: [cashTxId]);
    await SyncQueueHelper.enqueueDelete(txn, 'cash_transaction', SyncQueueHelper.cashTransactionEntityId(row));
  }

  // ================================================================ read

  Future<PlanView?> view(int planId, {int? today}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_plans', where: 'id = ?', whereArgs: [planId], limit: 1);
    if (rows.isEmpty) return null;
    return (await _views(db, rows, today ?? dayStart(DateTime.now()))).first;
  }

  /// Saare plans (naye pehle). [customerId] do to sirf us ke.
  Future<List<PlanView>> list({int? customerId, int? today}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_plans',
        where: customerId == null ? null : 'customerId = ?',
        whereArgs: customerId == null ? null : [customerId],
        orderBy: 'createdAt DESC');
    return _views(db, rows, today ?? dayStart(DateTime.now()));
  }

  Future<List<PlanView>> _views(DatabaseExecutor db, List<Map<String, Object?>> rows, int today) async {
    if (rows.isEmpty) return const [];
    final plans = rows.map(InstPlan.fromMap).toList();
    final ids = plans.map((p) => p.id).join(',');
    final sched = <int, List<(int, double)>>{};
    for (final r in await db.rawQuery('SELECT planId, dueDate, amount FROM inst_schedule WHERE planId IN ($ids) ORDER BY planId, seq')) {
      sched.putIfAbsent((r['planId'] as num).toInt(), () => []).add(((r['dueDate'] as num).toInt(), (r['amount'] as num).toDouble()));
    }
    final pays = <int, List<InstPayment>>{};
    for (final r in await db.rawQuery('SELECT * FROM inst_payments WHERE planId IN ($ids) ORDER BY paidAt DESC, id DESC')) {
      final p = InstPayment.fromMap(r);
      pays.putIfAbsent(p.planId, () => []).add(p);
    }
    final custIds = plans.map((p) => p.customerId).toSet().join(',');
    final cust = <int, (String, String)>{
      for (final r in await db.rawQuery('SELECT id, name, phone FROM customers WHERE id IN ($custIds)'))
        (r['id'] as num).toInt(): ((r['name'] as String?) ?? '', (r['phone'] as String?) ?? '')
    };
    final itemIds = plans.map((p) => p.itemId).toSet().join(',');
    final items = <int, InstItem>{
      for (final r in await db.rawQuery('SELECT * FROM inst_items WHERE id IN ($itemIds)')) (r['id'] as num).toInt(): InstItem.fromMap(r)
    };
    return [
      for (final p in plans)
        () {
          final pp = pays[p.id] ?? const <InstPayment>[];
          final paidInst = pp.where((x) => x.kind == payInstallment).fold<double>(0, (a, x) => a + x.amount);
          final s = sched[p.id] ?? const <(int, double)>[];
          return PlanView(
            plan: p,
            customerName: cust[p.customerId]?.$1 ?? '?',
            customerPhone: cust[p.customerId]?.$2 ?? '',
            item: items[p.itemId],
            schedule: s,
            payments: pp,
            status: planStatus(schedule: s, paidInstallments: paidInst, today: today),
          );
        }()
    ];
  }

  /// Item par chalne wala plan (item form se "plan dekhein").
  Future<int?> planIdForItem(int itemId) async {
    final db = await AppDatabase.instance.database;
    final r = await db.query('inst_plans', columns: ['id'], where: 'itemId = ?', whereArgs: [itemId], orderBy: 'createdAt DESC', limit: 1);
    return r.isEmpty ? null : (r.first['id'] as num).toInt();
  }

  // ================================================================ collect

  /// Qist wasool. [amount] qist mein jata hai, [fine] alag. Baqi se zyada => [ArgumentError].
  /// Poora adaa ho jaye to plan `completed`. Wapas: payment id.
  Future<int> receive(int planId, {required double amount, double fine = 0, String method = 'cash', String note = '', int? paidAt}) async {
    if (!amount.isFinite || amount < 0 || !fine.isFinite || fine < 0) throw ArgumentError('Raqam theek nahi.');
    if (amount <= 0 && fine <= 0) throw ArgumentError('Raqam likhein.');
    if (method != 'cash' && method != 'bank') throw ArgumentError('Cash ya Bank chunein.');
    final v = await view(planId);
    if (v == null) throw ArgumentError('Plan nahi mila.');
    if (!v.plan.isActive) throw ArgumentError('Ye plan band hai (${v.plan.status}).');
    if (amount > v.status.remaining + 0.5) {
      throw ArgumentError('Baqi sirf ${v.status.remaining.round()} hai — is se zyada nahi le sakte.');
    }
    final db = await AppDatabase.instance.database;
    final when = paidAt ?? _now();
    final id = await db.transaction((txn) async {
      final payId = await _insertPayment(txn,
          planId: planId, planNo: v.plan.planNo, kind: payInstallment, amount: amount, fine: fine, method: method, note: note, paidAt: when);
      if (v.status.remaining - amount <= 0.5) {
        await txn.update('inst_plans', {'status': planCompleted, 'closedAt': _now(), 'updatedAt': _now()},
            where: 'id = ?', whereArgs: [planId]);
        await InstSync.enqueuePlan(txn, planId);
      }
      return payId;
    });
    _changed();
    return id;
  }

  /// Galat entry wapas (sirf admin / manager). Saath wali cash row bhi hat'ti hai. Advance wapas nahi hota
  /// (us ke liye plan delete). Completed plan dobara active.
  Future<void> deletePayment(InstPayment p) async {
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager payment hata sakta hai.');
    if (p.kind == payAdvance) throw ArgumentError('Advance plan ke saath hai — plan delete karein.');
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instPaymentType, 'inst_payments', 'id', p.id);
      await txn.delete('inst_payments', where: 'id = ?', whereArgs: [p.id]);
      await _deleteCash(txn, p.planId, p.id, p.cashTxId);
      final n = await txn.update('inst_plans', {'status': planActive, 'closedAt': 0, 'updatedAt': _now()},
          where: "id = ? AND status = '$planCompleted'", whereArgs: [p.planId]);
      if (n > 0) await InstSync.enqueuePlan(txn, p.planId);
    });
    _changed();
  }

  // ================================================================ close

  /// Ghalat bana plan mitao (sirf admin; advance ke ilawa koi qist na li ho). Item wapas stock, advance ki cash row bhi.
  Future<void> deletePlan(int planId) async {
    if (!Session.isAdmin) throw ArgumentError('Sirf Admin plan delete kar sakta hai.');
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final n = Sqflite.firstIntValue(await txn.rawQuery(
              "SELECT COUNT(*) FROM inst_payments WHERE planId = ? AND kind = '$payInstallment'", [planId])) ??
          0;
      if (n > 0) throw ArgumentError('Is plan ki $n qist(en) wasool ho chuki hain — pehle wo hatayein, ya "Saman wapas" karein.');
      final plan = await txn.query('inst_plans', where: 'id = ?', whereArgs: [planId], limit: 1);
      if (plan.isEmpty) return;
      final itemId = (plan.first['itemId'] as num).toInt();
      for (final r in await txn.query('inst_payments', columns: ['id', 'cashTxId'], where: 'planId = ?', whereArgs: [planId])) {
        final pid = (r['id'] as num).toInt();
        await InstSync.enqueueDeleteRow(txn, instPaymentType, 'inst_payments', 'id', pid);
        await _deleteCash(txn, planId, pid, (r['cashTxId'] as num?)?.toInt());
      }
      await InstSync.enqueueDeleteRow(txn, instPlanType, 'inst_plans', 'id', planId);
      await txn.delete('inst_payments', where: 'planId = ?', whereArgs: [planId]);
      await txn.delete('inst_schedule', where: 'planId = ?', whereArgs: [planId]);
      await txn.delete('inst_plans', where: 'id = ?', whereArgs: [planId]);
      await txn.update('inst_items', {'status': itemInStock, 'updatedAt': _now()}, where: 'id = ?', whereArgs: [itemId]);
      await InstSync.enqueueItem(txn, itemId);
    });
    _changed();
  }

  /// Qist na dene par saman wapas liya (admin / manager). Plan band (`repossessed`), item `repossessed`.
  /// Wasool shuda raqam wapas nahi hoti (record mein rehti hai).
  Future<void> repossess(int planId, {String note = ''}) async {
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager saman wapas le sakta hai.');
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final plan = await txn.query('inst_plans', where: 'id = ?', whereArgs: [planId], limit: 1);
      if (plan.isEmpty) throw ArgumentError('Plan nahi mila.');
      if (plan.first['status'] != planActive) throw ArgumentError('Sirf chalta hua plan.');
      final oldNote = (plan.first['note'] as String?) ?? '';
      await txn.update(
          'inst_plans',
          {
            'status': planRepossessed,
            'closedAt': _now(),
            'updatedAt': _now(),
            if (note.trim().isNotEmpty) 'note': [oldNote, 'Wapas: ${note.trim()}'].where((s) => s.isNotEmpty).join('\n'),
          },
          where: 'id = ?',
          whereArgs: [planId]);
      final itemId = (plan.first['itemId'] as num).toInt();
      await txn.update('inst_items', {'status': itemRepossessed, 'updatedAt': _now()}, where: 'id = ?', whereArgs: [itemId]);
      await InstSync.enqueuePlan(txn, planId);
      await InstSync.enqueueItem(txn, itemId);
    });
    _changed();
  }

  // ================================================================ reports

  /// [from]..[to] (to shamil nahi) ki report. Plans / wasooli DB se saada rows mein, hisaab [periodReport] mein.
  Future<PeriodReport> report({required int from, required int to}) async {
    final db = await AppDatabase.instance.database;
    final pays = [
      for (final r in await db.rawQuery(
          'SELECT paidAt, kind, amount, fine, method FROM inst_payments WHERE paidAt >= ? AND paidAt < ?', [from, to]))
        PayRow(
          paidAt: (r['paidAt'] as num).toInt(),
          kind: (r['kind'] as String?) ?? payInstallment,
          amount: ((r['amount'] as num?) ?? 0).toDouble(),
          fine: ((r['fine'] as num?) ?? 0).toDouble(),
          method: (r['method'] as String?) ?? 'cash',
        )
    ];
    final plans = [
      for (final r in await db.rawQuery(
          'SELECT createdAt, cashPrice, costPrice, totalPrice, advance, status FROM inst_plans WHERE createdAt >= ? AND createdAt < ?',
          [from, to]))
        PlanRow(
          createdAt: (r['createdAt'] as num).toInt(),
          cashPrice: ((r['cashPrice'] as num?) ?? 0).toDouble(),
          costPrice: ((r['costPrice'] as num?) ?? 0).toDouble(),
          totalPrice: ((r['totalPrice'] as num?) ?? 0).toDouble(),
          advance: ((r['advance'] as num?) ?? 0).toDouble(),
          status: (r['status'] as String?) ?? planActive,
        )
    ];
    final closures = [
      for (final r in await db.rawQuery(
          'SELECT closedAt, status FROM inst_plans WHERE closedAt >= ? AND closedAt < ?', [from, to]))
        ((r['closedAt'] as num).toInt(), (r['status'] as String?) ?? '')
    ];
    return periodReport(payments: pays, plans: plans, closures: closures, from: from, to: to);
  }

  /// Munafa (Step 9): muddat ki wasooli ka munafe wala hissa + fine − kharche (expenses table: salary / kiraya / bills samet).
  Future<ProfitReport> profit({required int from, required int to}) async {
    final db = await AppDatabase.instance.database;
    final pays = [
      for (final r in await db.rawQuery('''
        SELECT p.paidAt AS paidAt, p.amount AS amount, p.fine AS fine, pl.totalPrice AS totalPrice, pl.costPrice AS costPrice
        FROM inst_payments p JOIN inst_plans pl ON pl.id = p.planId
        WHERE p.paidAt >= ? AND p.paidAt < ?
      ''', [from, to]))
        ProfitPayRow(
          paidAt: (r['paidAt'] as num).toInt(),
          amount: ((r['amount'] as num?) ?? 0).toDouble(),
          fine: ((r['fine'] as num?) ?? 0).toDouble(),
          totalPrice: ((r['totalPrice'] as num?) ?? 0).toDouble(),
          costPrice: ((r['costPrice'] as num?) ?? 0).toDouble(),
        )
    ];
    final ex = [
      for (final r in await db.rawQuery('SELECT createdAt, category, amount FROM expenses WHERE createdAt >= ? AND createdAt < ?', [from, to]))
        ((r['createdAt'] as num).toInt(), (r['category'] as String?) ?? '', ((r['amount'] as num?) ?? 0).toDouble())
    ];
    return profitReport(payments: pays, expenses: ex, from: from, to: to);
  }

  // ================================================================ home

  Future<InstCollectionStats> collectionStats({int? today}) async {
    final t = today ?? dayStart(DateTime.now());
    final views = (await list(today: t)).where((v) => v.plan.isActive).toList();
    double dueToday = 0, overdue = 0, receivable = 0;
    var dueTodayCount = 0, overdueCount = 0;
    for (final v in views) {
      receivable += v.status.remaining;
      if (v.status.overdue > 0.5) {
        overdue += v.status.overdue;
        overdueCount++;
      }
      final todayLine = v.status.lines.where((l) => l.dueDate == t && l.state != InstallmentState.paid);
      if (todayLine.isNotEmpty) {
        dueToday += todayLine.fold<double>(0, (a, l) => a + l.remaining);
        dueTodayCount++;
      }
    }
    final db = await AppDatabase.instance.database;
    final end = DateTime.fromMillisecondsSinceEpoch(t).add(const Duration(days: 1)).millisecondsSinceEpoch;
    final got = await db.rawQuery('SELECT COALESCE(SUM(amount + fine), 0) AS v FROM inst_payments WHERE paidAt >= ? AND paidAt < ?', [t, end]);
    return InstCollectionStats(
      activePlans: views.length,
      dueToday: dueToday,
      dueTodayCount: dueTodayCount,
      overdue: overdue,
      overdueCount: overdueCount,
      receivable: receivable,
      collectedToday: ((got.first['v'] as num?) ?? 0).toDouble(),
    );
  }
}

class InstCollectionStats {
  final int activePlans;
  final double dueToday;
  final int dueTodayCount;
  final double overdue;
  final int overdueCount;
  final double receivable;
  final double collectedToday;
  const InstCollectionStats({
    this.activePlans = 0,
    this.dueToday = 0,
    this.dueTodayCount = 0,
    this.overdue = 0,
    this.overdueCount = 0,
    this.receivable = 0,
    this.collectedToday = 0,
  });
}
