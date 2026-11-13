import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_plan_math.dart';
import 'package:hanna_installment/installment/inst_reports.dart';

void main() {
  int day(int y, int m, int d) => dayStart(DateTime(y, m, d));

  test('aging buckets per installment due date', () {
    final today = day(2026, 11, 13);
    final sched = [
      (day(2026, 7, 1), 1000.0), // 135 din -> 90+
      (day(2026, 9, 1), 1000.0), // 73 -> 61-90
      (day(2026, 10, 1), 1000.0), // 43 -> 31-60
      (day(2026, 11, 1), 1000.0), // 12 -> 1-30
      (day(2026, 11, 13), 1000.0), // aaj -> late nahi
      (day(2026, 12, 1), 1000.0), // aane wali
    ];
    final st = planStatus(schedule: sched, paidInstallments: 500, today: today);
    final a = agingOf([st], today);
    expect(a.d90plus, 500); // pehli qist ka aadha ada
    expect(a.d61to90, 1000);
    expect(a.d31to60, 1000);
    expect(a.d1to30, 1000);
    expect(a.notLate, 2000);
    expect(a.late, 3500);
    expect(a.total, 5500);
  });

  test('period report: only rows inside the period', () {
    final (from, to) = monthRange(DateTime(2026, 11, 20));
    expect(DateTime.fromMillisecondsSinceEpoch(from), DateTime(2026, 11, 1));
    expect(DateTime.fromMillisecondsSinceEpoch(to), DateTime(2026, 12, 1));
    final nov5 = DateTime(2026, 11, 5, 14).millisecondsSinceEpoch;
    final r = periodReport(
      payments: [
        PayRow(paidAt: nov5, kind: payAdvance, amount: 10000),
        PayRow(paidAt: nov5, kind: payInstallment, amount: 4000, fine: 200, method: 'bank'),
        PayRow(paidAt: DateTime(2026, 10, 30).millisecondsSinceEpoch, kind: payInstallment, amount: 999),
      ],
      plans: [
        PlanRow(createdAt: nov5, cashPrice: 50000, costPrice: 42000, totalPrice: 62000, advance: 10000, status: planActive),
        PlanRow(createdAt: nov5, cashPrice: 20000, costPrice: 0, totalPrice: 25000, advance: 0, status: planActive),
        PlanRow(createdAt: DateTime(2026, 12, 2).millisecondsSinceEpoch, cashPrice: 1, costPrice: 0, totalPrice: 1, advance: 0, status: planActive),
      ],
      closures: [(nov5, planCompleted), (nov5, planRepossessed), (DateTime(2026, 9, 1).millisecondsSinceEpoch, planCompleted)],
      from: from,
      to: to,
    );
    expect(r.collectedAdvance, 10000);
    expect(r.collectedInstallments, 4000);
    expect(r.collectedFines, 200);
    expect(r.collectedTotal, 14200);
    expect(r.cashIn, 10000);
    expect(r.bankIn, 4200);
    expect(r.paymentCount, 2);
    expect(r.newPlans, 2);
    expect(r.newCashValue, 70000);
    expect(r.newTotalValue, 87000);
    expect(r.newExpectedProfit, 20000); // sirf jis ki khareed likhi (62000 − 42000)
    expect(r.completed, 1);
    expect(r.repossessed, 1);
    expect(r.byDay[day(2026, 11, 5)], 14200);
  });

  test('dueWithin includes late and the next N days', () {
    final today = day(2026, 11, 13);
    final st = planStatus(
      schedule: [(day(2026, 11, 1), 1000.0), (day(2026, 11, 18), 1000.0), (day(2026, 12, 20), 1000.0)],
      paidInstallments: 0,
      today: today,
    );
    expect(dueWithin(st, today, 7), 2000);
    expect(dueWithin(st, today, 1), 1000);
    expect(dueWithin(st, today, 60), 3000);
  });
}
