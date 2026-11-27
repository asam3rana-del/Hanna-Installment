import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_installment/installment/inst_plan_qr.dart';

/// Customer ka QR (raseed / statement / khata card): `HQ:<planNo>`; scan / likha hua text plan no. mein.
void main() {
  test('QR data HQ: prefix ke saath', () {
    expect(instPlanQrData('Q-7F0012'), 'HQ:Q-7F0012');
    expect(instPlanQrData(' Q-7F0012 '), 'HQ:Q-7F0012');
  });

  test('scan se plan number: HQ:, seedha, chhote harf, spaces', () {
    expect(planNoFromScan('HQ:Q-7F0012'), 'Q-7F0012');
    expect(planNoFromScan('hq:q-7f0012'), 'Q-7F0012');
    expect(planNoFromScan('  Q-AB0003 \n'), 'Q-AB0003');
    expect(planNoFromScan(planNoFromScan(instPlanQrData('Q-7F0012'))!), 'Q-7F0012');
  });

  test('IMEI / serial / ghalat text plan nahi', () {
    expect(planNoFromScan('356789012345678'), isNull);
    expect(planNoFromScan('JA05E1234567'), isNull);
    expect(planNoFromScan('Q-'), isNull);
    expect(planNoFromScan('HQ:'), isNull);
    expect(planNoFromScan('Q-12 34'), isNull);
    expect(planNoFromScan(''), isNull);
  });
}
