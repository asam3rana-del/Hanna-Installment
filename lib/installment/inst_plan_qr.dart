import 'package:flutter/material.dart';

import '../utils/loc.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_scan.dart';
import 'inst_ui.dart';

// ================================================================== pure (test/plan_qr_test.dart)

/// Customer ke QR mein kya likha ho: `HQ:<planNo>` (HQ = Hanna Qist). Raseed / statement / khata card par chhapta hai.
String instPlanQrData(String planNo) => 'HQ:${planNo.trim()}';

/// Scan / likha hua text plan number hai? `HQ:Q-7F0012` ya seedha `Q-7F0012` (chhote harf bhi). Nahi => null.
String? planNoFromScan(String raw) {
  var v = raw.trim();
  if (v.toUpperCase().startsWith('HQ:')) v = v.substring(3).trim();
  v = v.toUpperCase();
  return RegExp(r'^Q-[A-Z0-9]{3,20}$').hasMatch(v) ? v : null;
}

// ================================================================== scan -> receive

/// Plan number se plan kholo (Receive dialog ke saath). Na mile to toast. true = khula.
Future<bool> openPlanByNo(BuildContext context, String planNo, {bool receive = true}) async {
  final id = await InstPlanRepository.instance.planIdForNo(planNo);
  if (!context.mounted) return false;
  if (id == null) {
    instToast(context, '${Loc.t('Plan not found', 'پلان نہیں ملا')}: $planNo');
    return false;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: id, openReceive: receive)));
  return true;
}

/// Camera se customer ka QR (raseed / khata card) scan -> us plan ki wasooli. PC par: plan no. likhne ka dialog
/// (USB 2D scanner bhi wahi likhta hai).
Future<void> scanPlanQrAndReceive(BuildContext context) async {
  String? no;
  if (instHasCamera) {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => InstBarcodeScanPage(
              accept: (v) => planNoFromScan(v) != null,
              hint: Loc.t('Hold the customer QR (receipt / card) inside the box', 'کسٹمر کا QR (رسید / کارڈ) خانے کے اندر رکھیں'),
              notFound: Loc.t('Not a customer QR', 'کسٹمر QR نہیں'),
            )));
    if (code == null) return;
    no = planNoFromScan(code);
  } else {
    final c = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Customer QR / plan no.', 'کسٹمر QR / پلان نمبر')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: Loc.t('Scan with scanner or type Q-....', 'اسکینر سے اسکین یا Q-.... لکھیں')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Loc.t('Cancel', 'منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(Loc.t('Open', 'کھولیں'))),
        ],
      ),
    );
    c.dispose();
    if (t == null) return;
    no = planNoFromScan(t);
    if (no == null && context.mounted) {
      instToast(context, Loc.t('Not a plan number.', 'یہ پلان نمبر نہیں۔'));
      return;
    }
  }
  if (no == null || !context.mounted) return;
  await openPlanByNo(context, no);
}
