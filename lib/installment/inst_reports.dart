import 'dart:math' as math;

import 'inst_plan_math.dart';

/// Hanna Installment Step 4 — reports ka hisaab. Sab PURE (test/installment_reports_test.dart).

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Late raqam kitne din se late hai, us ke hisaab se (har qist apne din se).
class AgingBuckets {
  final double notLate; // baqi jo abhi late nahi (aaj / aane wali)
  final double d1to30;
  final double d31to60;
  final double d61to90;
  final double d90plus;
  const AgingBuckets({this.notLate = 0, this.d1to30 = 0, this.d31to60 = 0, this.d61to90 = 0, this.d90plus = 0});

  double get late => _r2(d1to30 + d31to60 + d61to90 + d90plus);
  double get total => _r2(notLate + late);
}

int daysBetween(int fromDay, int toDay) =>
    DateTime.fromMillisecondsSinceEpoch(toDay).difference(DateTime.fromMillisecondsSinceEpoch(fromDay)).inHours ~/ 24;

AgingBuckets agingOf(Iterable<PlanStatus> statuses, int today) {
  double n = 0, a = 0, b = 0, c = 0, d = 0;
  for (final s in statuses) {
    for (final l in s.lines) {
      final rem = l.remaining;
      if (rem <= 0.5) continue;
      if (l.dueDate >= today) {
        n += rem;
        continue;
      }
      final days = daysBetween(l.dueDate, today);
      if (days <= 30) {
        a += rem;
      } else if (days <= 60) {
        b += rem;
      } else if (days <= 90) {
        c += rem;
      } else {
        d += rem;
      }
    }
  }
  return AgingBuckets(notLate: _r2(n), d1to30: _r2(a), d31to60: _r2(b), d61to90: _r2(c), d90plus: _r2(d));
}

/// Report ke liye ek wasooli (DB row ka saada roop).
class PayRow {
  final int paidAt;
  final String kind;
  final double amount;
  final double fine;
  final String method;
  const PayRow({required this.paidAt, required this.kind, required this.amount, this.fine = 0, this.method = 'cash'});
}

/// Report ke liye ek plan (DB row ka saada roop).
class PlanRow {
  final int createdAt;
  final double cashPrice;
  final double costPrice;
  final double totalPrice;
  final double advance;
  final String status;
  const PlanRow({
    required this.createdAt,
    required this.cashPrice,
    required this.costPrice,
    required this.totalPrice,
    required this.advance,
    required this.status,
  });
}

class PeriodReport {
  final double collectedInstallments;
  final double collectedAdvance;
  final double collectedFines;
  final double cashIn;
  final double bankIn;
  final int paymentCount;
  final int newPlans;
  final double newCashValue;
  final double newTotalValue;
  final double newCost;

  /// Naye plans ka kul munafa (qist qeemat − khareed). Khareed na likhi ho (0) to woh plan is mein nahi.
  final double newExpectedProfit;
  final int completed;
  final int repossessed;

  /// Din (din ki shuruaat) -> us din ki kul wasooli (fine samet).
  final Map<int, double> byDay;

  const PeriodReport({
    required this.collectedInstallments,
    required this.collectedAdvance,
    required this.collectedFines,
    required this.cashIn,
    required this.bankIn,
    required this.paymentCount,
    required this.newPlans,
    required this.newCashValue,
    required this.newTotalValue,
    required this.newCost,
    required this.newExpectedProfit,
    required this.completed,
    required this.repossessed,
    required this.byDay,
  });

  double get collectedTotal => _r2(collectedInstallments + collectedAdvance + collectedFines);
}

/// [from] shamil, [to] shamil nahi (millis).
PeriodReport periodReport({
  required List<PayRow> payments,
  required List<PlanRow> plans,
  required List<(int, String)> closures, // (closedAt, status)
  required int from,
  required int to,
}) {
  double inst = 0, adv = 0, fine = 0, cash = 0, bank = 0;
  var count = 0;
  final byDay = <int, double>{};
  for (final p in payments) {
    if (p.paidAt < from || p.paidAt >= to) continue;
    count++;
    if (p.kind == payAdvance) {
      adv += p.amount;
    } else {
      inst += p.amount;
    }
    fine += p.fine;
    final t = p.amount + p.fine;
    if (p.method == 'bank') {
      bank += t;
    } else {
      cash += t;
    }
    final day = dayStart(DateTime.fromMillisecondsSinceEpoch(p.paidAt));
    byDay[day] = _r2((byDay[day] ?? 0) + t);
  }
  var n = 0;
  double cv = 0, tv = 0, cost = 0, profit = 0;
  for (final p in plans) {
    if (p.createdAt < from || p.createdAt >= to) continue;
    n++;
    cv += p.cashPrice;
    tv += p.totalPrice;
    cost += p.costPrice;
    if (p.costPrice > 0) profit += p.totalPrice - p.costPrice;
  }
  var done = 0, back = 0;
  for (final (at, st) in closures) {
    if (at < from || at >= to) continue;
    if (st == planCompleted) done++;
    if (st == planRepossessed) back++;
  }
  return PeriodReport(
    collectedInstallments: _r2(inst),
    collectedAdvance: _r2(adv),
    collectedFines: _r2(fine),
    cashIn: _r2(cash),
    bankIn: _r2(bank),
    paymentCount: count,
    newPlans: n,
    newCashValue: _r2(cv),
    newTotalValue: _r2(tv),
    newCost: _r2(cost),
    newExpectedProfit: _r2(profit),
    completed: done,
    repossessed: back,
    byDay: byDay,
  );
}

/// Mahine ki shuruaat / agle mahine ki shuruaat.
(int, int) monthRange(DateTime d) =>
    (DateTime(d.year, d.month, 1).millisecondsSinceEpoch, DateTime(d.year, d.month + 1, 1).millisecondsSinceEpoch);

/// [today] se [days] din aage tak (aaj shamil) ki na-adaa qisten — wasooli list ke liye.
double dueWithin(PlanStatus s, int today, int days) {
  final end = DateTime.fromMillisecondsSinceEpoch(today).add(Duration(days: days)).millisecondsSinceEpoch;
  var v = 0.0;
  for (final l in s.lines) {
    if (l.state == InstallmentState.paid) continue;
    if (l.dueDate < end) v += l.remaining;
  }
  return _r2(math.max(0, v));
}
