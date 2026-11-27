import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_installment/installment/inst_reports.dart';

/// Munafa history (v52): saman badalne / qisten dobara banane se pichhle mahinon ka munafa nahi badalta, aur plan
/// poora hone par kul munafa = qeemat − khareed − chhoot.
void main() {
  PlanPay pay(int at, double a, {bool disc = false}) => (paidAt: at, amount: a, discount: disc);
  double sum(List<PlanPay> ps, List<double?> rs) {
    var v = 0.0;
    for (var i = 0; i < ps.length; i++) {
      v += ps[i].amount * (rs[i] ?? 0) - (ps[i].discount ? ps[i].amount : 0);
    }
    return v;
  }

  test('history khaali => purana tareeqa (qeemat − khareed) ÷ qeemat', () {
    final r = planPayRates(totalPrice: 1000, costPrice: 800, history: const [], pays: [pay(1, 400)]);
    expect(r.single, closeTo(0.2, 1e-9));
    expect(planPayRates(totalPrice: 1000, costPrice: 0, history: const [], pays: [pay(1, 400)]).single, isNull);
  });

  test('saman badla: purani wasooli 20% par jami, baqi (300 − 80) ÷ 800', () {
    final before = [pay(10, 400)];
    final h = freezeProfitHistory(totalPrice: 1000, costPrice: 800, history: const [], pays: before, now: 50);
    expect(h.single.until, 50);
    expect(h.single.rate, closeTo(0.2, 1e-9));
    final after = [...before, pay(60, 300), pay(70, 500)];
    final r = planPayRates(totalPrice: 1200, costPrice: 900, history: h, pays: after);
    expect(r[0], closeTo(0.2, 1e-9));
    expect(r[1], closeTo(220 / 800, 1e-9));
    expect(sum(after, r), closeTo(300, 1e-6));
  });

  test('do dafa badla + chhoot: kul munafa = qeemat − khareed − chhoot', () {
    var pays = [pay(10, 300)];
    var h = freezeProfitHistory(totalPrice: 1000, costPrice: 800, history: const [], pays: pays, now: 20); // 60
    pays = [...pays, pay(30, 200)];
    h = freezeProfitHistory(totalPrice: 1100, costPrice: 800, history: h, pays: pays, now: 40); // 2nd change
    expect(h.length, 2);
    // Teesra plan: 1,300 qeemat, 950 khareed (munafa 350). Baqi 800: 750 + 50 chhoot.
    pays = [...pays, pay(50, 750), pay(60, 50, disc: true)];
    final r = planPayRates(totalPrice: 1300, costPrice: 950, history: h, pays: pays);
    expect(sum(pays, r), closeTo(350 - 50, 1e-6));
    expect(planRealizedProfit(totalPrice: 1300, costPrice: 950, history: h, pays: pays), closeTo(300, 0.01));
  });

  test('der se sync hui purani payment / hati hui payment ke baad bhi kul barabar', () {
    final h = freezeProfitHistory(totalPrice: 1000, costPrice: 800, history: const [], pays: [pay(10, 400)], now: 50);
    // Doosri device ki purani payment (paidAt 20) baad mein aayi: purani rate par, baqi rate khud theek.
    final pays = [pay(10, 400), pay(20, 100), pay(60, 700)];
    final r = planPayRates(totalPrice: 1200, costPrice: 900, history: h, pays: pays);
    expect(r[1], closeTo(0.2, 1e-9));
    expect(sum(pays, r), closeTo(300, 1e-6));
    // Purani payment hat gayi: customer dobara deta hai — phir bhi 300.
    final pays2 = [pay(20, 100), pay(60, 1100)];
    expect(sum(pays2, planPayRates(totalPrice: 1200, costPrice: 900, history: h, pays: pays2)), closeTo(300, 1e-6));
  });

  test('pichhle jam ke baad koi wasooli nahi => history wahi; encode / parse', () {
    final h = freezeProfitHistory(totalPrice: 1000, costPrice: 800, history: const [], pays: const [], now: 5);
    expect(h, isEmpty);
    final h1 = [const ProfitSeg(50, 0.2), const ProfitSeg(90, null)];
    final back = parseProfitHistory(encodeProfitHistory(h1));
    expect(back.length, 2);
    expect(back[0].rate, 0.2);
    expect(back[1].rate, isNull);
    expect(parseProfitHistory('ghalat'), isEmpty);
    expect(encodeProfitHistory(const []), '');
  });

  test('report: di gayi rate purane tareeqe ki jagah', () {
    final rep = profitReport(payments: const [
      ProfitPayRow(paidAt: 10, amount: 400, totalPrice: 1200, costPrice: 900, rate: 0.2, rateGiven: true),
      ProfitPayRow(paidAt: 11, amount: 100, totalPrice: 1200, costPrice: 900, rateGiven: true), // khareed maloom nahi thi
      ProfitPayRow(paidAt: 12, amount: 100, totalPrice: 1000, costPrice: 800),
    ], expenses: const [], from: 0, to: 100);
    expect(rep.realizedProfit, closeTo(80 + 20, 0.01));
    expect(rep.collectedWithoutCost, 100);
  });
}
