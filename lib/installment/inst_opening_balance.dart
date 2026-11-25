import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../db/app_database.dart';
import '../license/license_service.dart';
import '../models/misc_entities.dart' show CashTransaction;
import '../services/session.dart';
import '../sync/sync_queue_helper.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_repository.dart';
import 'inst_sync.dart';
import 'inst_sync_names.dart';
import 'inst_ui.dart';

/// Customer ka purana baqi (software se pehle ka udhaar) aur us ki wasooli.
///
/// Baqi `customer_profiles.openingBalance` (+ `openingDue` = kab tak), wasooli `inst_customer_receipts`
/// (har wasooli ke saath cash IN row — aaj ke cash / cash book mein). Qist plan se alag: koi item / schedule nahi.
class InstReceipt {
  final int id;
  final int customerId;
  final double amount;
  final String method;
  final String note;
  final String receivedBy;
  final int paidAt;
  final int? cashTxId;

  const InstReceipt({
    required this.id,
    required this.customerId,
    required this.amount,
    this.method = 'cash',
    this.note = '',
    this.receivedBy = '',
    this.paidAt = 0,
    this.cashTxId,
  });

  factory InstReceipt.fromMap(Map<String, Object?> m) => InstReceipt(
        id: (m['id'] as num).toInt(),
        customerId: ((m['customerId'] as num?) ?? 0).toInt(),
        amount: ((m['amount'] as num?) ?? 0).toDouble(),
        method: (m['method'] as String?) ?? 'cash',
        note: (m['note'] as String?) ?? '',
        receivedBy: (m['receivedBy'] as String?) ?? '',
        paidAt: ((m['paidAt'] as num?) ?? 0).toInt(),
        cashTxId: (m['cashTxId'] as num?)?.toInt(),
      );
}

/// Ek customer ka purana baqi: kul, wasool, baqi, kab tak.
class OpeningStatus {
  final int customerId;
  final String name;
  final String phone;
  final double opening;
  final double received;
  final int due;
  const OpeningStatus({
    required this.customerId,
    this.name = '',
    this.phone = '',
    this.opening = 0,
    this.received = 0,
    this.due = 0,
  });
  double get remaining {
    final r = opening - received;
    return r > 0.005 ? r : 0;
  }

  /// Tareekh guzar gayi aur abhi baqi hai.
  bool lateOn(int today) => due > 0 && due < today && remaining > 0;
}

class InstOpeningRepository {
  InstOpeningRepository._();
  static final InstOpeningRepository instance = InstOpeningRepository._();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  static const _statusSql = '''
    SELECT c.id AS id, c.name AS name, c.phone AS phone, p.openingBalance AS opening, p.openingDue AS due,
           (SELECT COALESCE(SUM(r.amount), 0) FROM inst_customer_receipts r WHERE r.customerId = c.id) AS received
    FROM customer_profiles p JOIN customers c ON c.id = p.customerId
  ''';

  OpeningStatus _status(Map<String, Object?> r) => OpeningStatus(
        customerId: (r['id'] as num).toInt(),
        name: (r['name'] as String?) ?? '',
        phone: (r['phone'] as String?) ?? '',
        opening: ((r['opening'] as num?) ?? 0).toDouble(),
        received: ((r['received'] as num?) ?? 0).toDouble(),
        due: ((r['due'] as num?) ?? 0).toInt(),
      );

  Future<OpeningStatus> status(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('$_statusSql WHERE c.id = ?', [customerId]);
    return rows.isEmpty ? OpeningStatus(customerId: customerId) : _status(rows.first);
  }

  /// Jin ka purana baqi abhi reh gaya (pehle wo jin ki tareekh guzar gayi / qareeb hai).
  Future<List<OpeningStatus>> withRemaining() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('$_statusSql WHERE p.openingBalance > 0 ORDER BY c.name COLLATE NOCASE');
    final out = rows.map(_status).where((s) => s.remaining > 0).toList();
    out.sort((a, b) {
      final ad = a.due == 0 ? 1 << 62 : a.due;
      final bd = b.due == 0 ? 1 << 62 : b.due;
      return ad.compareTo(bd);
    });
    return out;
  }

  /// Sab customers ka bacha hua purana baqi (Home ka "Receivable" + Late).
  Future<({double remaining, double late, int lateCount, double receivedToday})> totals({required int today}) async {
    final list = await withRemaining();
    double rem = 0, late = 0;
    var lateCount = 0;
    for (final s in list) {
      rem += s.remaining;
      if (s.lateOn(today)) {
        late += s.remaining;
        lateCount++;
      }
    }
    final db = await AppDatabase.instance.database;
    final end = DateTime.fromMillisecondsSinceEpoch(today).add(const Duration(days: 1)).millisecondsSinceEpoch;
    final got = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS v FROM inst_customer_receipts WHERE paidAt >= ? AND paidAt < ?', [today, end]);
    return (remaining: rem, late: late, lateCount: lateCount, receivedToday: ((got.first['v'] as num?) ?? 0).toDouble());
  }

  Future<List<InstReceipt>> receipts(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_customer_receipts',
        where: 'customerId = ?', whereArgs: [customerId], orderBy: 'paidAt DESC, id DESC');
    return rows.map(InstReceipt.fromMap).toList();
  }

  /// Purane baqi mein se wasooli (baqi se zyada nahi). Saath cash IN row.
  Future<int> receive({
    required int customerId,
    required double amount,
    String method = 'cash',
    String note = '',
    int? paidAt,
  }) async {
    await LicenseService.instance.requireWritable();
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Raqam likhein.');
    final db = await AppDatabase.instance.database;
    final now = _now();
    final at = paidAt ?? now;
    late int id;
    await db.transaction((txn) async {
      // Recalculate outstanding opening balance within the same write transaction
      // that inserts the receipt, preventing stale preflight checks on one database.
      final rows = await txn.rawQuery('''$_statusSql WHERE c.id = ?''', [customerId]);
      if (rows.isEmpty) throw ArgumentError('Customer nahi mila.');
      final st = _status(rows.first);
      if (st.remaining <= 0) throw ArgumentError('Is customer ka koi purana baqi nahi.');
      if (amount > st.remaining + 0.005) {
        throw ArgumentError('Raqam purane baqi (${instRs(st.remaining)}) se zyada hai.');
      }
      id = await txn.insert('inst_customer_receipts', {
        'customerId': customerId,
        'amount': amount,
        'method': method == 'bank' ? 'bank' : 'cash',
        'note': note.trim(),
        'receivedBy': Session.username ?? '',
        'paidAt': at,
        'createdAt': now,
        'updatedAt': now,
      });
      final cash = CashTransaction(
        type: 'IN',
        method: method == 'bank' ? 'bank' : 'cash',
        amount: amount,
        reason: 'Purana baqi: ${st.name}',
        reference: 'inst-open:$id',
        createdAt: at,
        updatedAt: now,
      );
      final cashId = await txn.insert('cash_transactions', cash.toMap()..remove('id'));
      await SyncQueueHelper.enqueueCashTransaction(txn, cashId);
      await txn.update('inst_customer_receipts', {'cashTxId': cashId}, where: 'id = ?', whereArgs: [id]);
      await InstSync.enqueueCustomerReceipt(txn, id);
    });
    InstRepository.instance.changes.value++;
    return id;
  }

  /// Ghalat wasooli wapas (saath wali cash row bhi). Sirf Admin / Manager.
  Future<void> delete(InstReceipt r) async {
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager wasooli mita sakta hai.');
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instCustomerReceiptType, 'inst_customer_receipts', 'id', r.id);
      await txn.delete('inst_customer_receipts', where: 'id = ?', whereArgs: [r.id]);
      await _deleteCash(txn, r.id, r.cashTxId);
    });
    InstRepository.instance.changes.value++;
  }

  Future<void> _deleteCash(DatabaseExecutor txn, int id, int? cashTxId) async {
    await SyncQueueHelper.deleteCashTransactionsByReference(txn, 'inst-open:$id');
    if (cashTxId == null) return;
    final rows = await txn.query('cash_transactions', where: 'id = ?', whereArgs: [cashTxId], limit: 1);
    if (rows.isEmpty) return;
    final row = Map<String, Object?>.from(rows.first);
    if (!(row['reference'] as String? ?? '').startsWith('inst-open:')) return;
    await txn.delete('cash_transactions', where: 'id = ?', whereArgs: [cashTxId]);
    await SyncQueueHelper.enqueueDelete(txn, 'cash_transaction', SyncQueueHelper.cashTransactionEntityId(row));
  }
}

String _date(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

int _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
}

/// "Purana baqi wasool karein" dialog. Kamyab => true.
Future<bool> showReceiveOpeningDialog(BuildContext context, OpeningStatus st) async {
  final amount = TextEditingController(text: instPlain(st.remaining));
  final note = TextEditingController();
  var method = 'cash';
  var busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(Loc.t('Receive old balance', 'پرانا بقایا وصول کریں')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(st.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${Loc.t('Remaining', 'باقی')}: ${instRs(st.remaining)}'
                '${st.due > 0 ? '  •  ${Loc.t('due', 'تاریخ')} ${_date(st.due)}' : ''}'),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: Loc.t('Amount', 'رقم'), prefixText: 'Rs '),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'نقد'))),
                ButtonSegment(value: 'bank', label: Text(Loc.t('Bank / JazzCash', 'بینک / جاز کیش'))),
              ],
              selected: {method},
              onSelectionChanged: (v) => setS(() => method = v.first),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: Loc.t('Note (optional)', 'نوٹ (اختیاری)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setS(() => busy = true);
                    try {
                      await InstOpeningRepository.instance.receive(
                        customerId: st.customerId,
                        amount: instParse(amount.text),
                        method: method,
                        note: note.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setS(() => busy = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e is ArgumentError ? '${e.message}' : '$e')));
                      }
                    }
                  },
            child: Text(Loc.t('Receive', 'وصول کریں')),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  note.dispose();
  if (ok == true && context.mounted) {
    instToast(context, Loc.t('Received.', 'وصول ہو گیا۔'));
  }
  return ok == true;
}

/// Customer detail par: purana baqi, wasool, baqi + "Receive" + har wasooli (tareekh ke saath).
/// Purana baqi na ho to kuch nahi dikhata.
class InstOpeningCard extends StatefulWidget {
  final int customerId;
  const InstOpeningCard({super.key, required this.customerId});

  @override
  State<InstOpeningCard> createState() => _InstOpeningCardState();
}

class _InstOpeningCardState extends State<InstOpeningCard> {
  OpeningStatus? _st;
  List<InstReceipt> _list = const [];

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final st = await InstOpeningRepository.instance.status(widget.customerId);
    final list = await InstOpeningRepository.instance.receipts(widget.customerId);
    if (!mounted) return;
    setState(() {
      _st = st;
      _list = list;
    });
  }

  Future<void> _delete(InstReceipt r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Delete this receipt?', 'یہ وصولی مٹائیں؟')),
        content: Text('${instRs(r.amount)} • ${_date(r.paidAt)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('No', 'نہیں'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Delete', 'مٹائیں'))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await InstOpeningRepository.instance.delete(r);
    } catch (e) {
      if (mounted) instToast(context, e is ArgumentError ? '${e.message}' : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null || st.opening <= 0) return const SizedBox.shrink();
    final p = ThemeManager.palette;
    final late = st.lateOn(_today());
    Widget line(String a, String b, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: p.textMuted))),
            Text(b, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      instSectionTitle(p, Loc.t('OLD BALANCE (BEFORE SOFTWARE)', 'پرانا بقایا (سافٹ ویئر سے پہلے)')),
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          line(Loc.t('Old balance', 'پرانا بقایا'), instRs(st.opening), p.textDark),
          line(Loc.t('Received', 'وصول'), instRs(st.received), p.teal),
          line(Loc.t('Remaining', 'باقی'), instRs(st.remaining), st.remaining > 0 ? p.red : p.teal),
          if (st.due > 0)
            line(Loc.t('Pay by', 'ادائیگی کی تاریخ'), '${_date(st.due)}${late ? '  (${Loc.t('LATE', 'لیٹ')})' : ''}',
                late ? p.red : p.textDark),
          if (st.remaining > 0) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.payments_outlined),
              label: Text(Loc.t('Receive old balance', 'پرانا بقایا وصول کریں')),
              onPressed: () => showReceiveOpeningDialog(context, st),
            ),
          ],
          if (_list.isNotEmpty) ...[
            const Divider(height: 22),
            for (final r in _list)
              Row(children: [
                Expanded(
                  child: Text(
                    '${_date(r.paidAt)}${r.method == 'bank' ? ' • ${Loc.t('Bank', 'بینک')}' : ''}${r.note.isEmpty ? '' : ' • ${r.note}'}',
                    style: TextStyle(color: p.textMuted, fontSize: 13),
                  ),
                ),
                Text(instRs(r.amount), style: TextStyle(color: p.teal, fontWeight: FontWeight.w600)),
                if (Session.isAdminOrManager)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, size: 20, color: p.textMuted),
                    onPressed: () => _delete(r),
                  ),
              ]),
          ],
        ]),
      ),
    ]);
  }
}

/// Pay / Receive > "Purana baqi wasool": jin ka purana baqi reh gaya, tap => wasool karein.
class InstOpeningDueScreen extends StatefulWidget {
  const InstOpeningDueScreen({super.key});

  @override
  State<InstOpeningDueScreen> createState() => _InstOpeningDueScreenState();
}

class _InstOpeningDueScreenState extends State<InstOpeningDueScreen> {
  List<OpeningStatus>? _list;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_load);
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await InstOpeningRepository.instance.withRemaining();
    if (mounted) setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _q.text.trim().toLowerCase();
    final list = (_list ?? const <OpeningStatus>[])
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.phone.contains(q))
        .toList();
    final total = list.fold<double>(0, (a, s) => a + s.remaining);
    final today = _today();
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: Text(Loc.t('Old balance — receive', 'پرانا بقایا — وصولی'))),
      body: _list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: Loc.t('Name / phone', 'نام / فون')),
              ),
              const SizedBox(height: 10),
              Text('${list.length} ${Loc.t('customers', 'کسٹمر')} • ${Loc.t('Remaining', 'باقی')} ${instRs(total)}',
                  style: TextStyle(color: p.textMuted)),
              const SizedBox(height: 8),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    Loc.t('No old balance left. Add it in the customer form (Edit customer > Old balance).',
                        'کوئی پرانا بقایا باقی نہیں۔ کسٹمر فارم میں ڈالیں (کسٹمر تبدیل کریں > پرانا بقایا)۔'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textMuted),
                  ),
                ),
              for (final s in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: instCard(p),
                  child: ListTile(
                    title: Text(s.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      if (s.phone.isNotEmpty) s.phone,
                      if (s.due > 0) '${Loc.t('by', 'تک')} ${_date(s.due)}${s.lateOn(today) ? ' (${Loc.t('LATE', 'لیٹ')})' : ''}',
                    ].join('  •  ')),
                    trailing: Text(instRs(s.remaining), style: TextStyle(color: p.red, fontWeight: FontWeight.bold)),
                    onTap: () => showReceiveOpeningDialog(context, s),
                  ),
                ),
            ]),
    );
  }
}
