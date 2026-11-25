import 'package:flutter/material.dart';

import '../utils/loc.dart';
import 'inst_models.dart';
import 'inst_pdf.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';
import 'inst_ui.dart';

/// Har list ka Excel (CSV) / PDF export — Customers, Installments, Collection, Defaulters, Stock.
/// [InstPdf.shareTable] format poochta hai; PC par file `Documents\Hanna Installment Exports` mein ban kar khulti hai.

String _d(int ms) {
  if (ms <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}-${t.year}';
}

String _stamp() {
  final n = DateTime.now();
  return '${Loc.t('Made', 'بنایا')} ${_d(n.millisecondsSinceEpoch)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

String _planStatus(PlanView v) => v.plan.status == planCompleted
    ? Loc.t('Completed', 'مکمل')
    : v.plan.status == planRepossessed
        ? Loc.t('Taken back', 'واپس لیا')
        : v.status.daysLate > 0
            ? Loc.t('Late', 'لیٹ')
            : Loc.t('Running', 'جاری');

/// Plans ki list (Installments / Collection / Defaulters).
Future<void> exportPlans(BuildContext context, {required String base, required String title, required List<PlanView> plans}) {
  final total = plans.fold<double>(0, (a, v) => a + v.plan.totalPrice);
  final paid = plans.fold<double>(0, (a, v) => a + v.advancePaid + v.status.paid);
  final left = plans.where((v) => v.plan.isActive).fold<double>(0, (a, v) => a + v.status.remaining);
  final late = plans.where((v) => v.plan.isActive).fold<double>(0, (a, v) => a + v.status.overdue);
  return InstPdf.shareTable(
    context,
    base: base,
    title: title,
    sub: _stamp(),
    summary: [
      (Loc.t('Plans', 'پلان'), '${plans.length}'),
      (Loc.t('Total sale', 'کل سیل'), instRs(total)),
      (Loc.t('Received', 'وصول'), instRs(paid)),
      (Loc.t('Remaining', 'باقی'), instRs(left)),
      (Loc.t('Late amount', 'لیٹ رقم'), instRs(late)),
    ],
    headers: [
      Loc.t('Plan', 'پلان'),
      Loc.t('Customer', 'کسٹمر'),
      Loc.t('Phone', 'فون'),
      Loc.t('Item', 'سامان'),
      Loc.t('Total', 'کل'),
      Loc.t('Paid', 'ادا'),
      Loc.t('Remaining', 'باقی'),
      Loc.t('Late Rs', 'لیٹ رقم'),
      Loc.t('Days late', 'دن لیٹ'),
      Loc.t('Next due', 'اگلی تاریخ'),
      Loc.t('Status', 'حالت'),
    ],
    rows: [
      for (final v in plans)
        [
          v.plan.planNo,
          v.customerName,
          v.customerPhone,
          v.itemTitle,
          instRs(v.plan.totalPrice),
          instRs(v.advancePaid + v.status.paid),
          instRs(v.status.remaining),
          instRs(v.status.overdue),
          v.status.daysLate > 0 ? '${v.status.daysLate}' : '',
          v.status.next == null ? '' : _d(v.status.next!.dueDate),
          _planStatus(v),
        ]
    ],
    flex: const [2, 3, 3, 3, 2, 2, 2, 2, 1, 2, 2],
    right: const {4, 5, 6, 7, 8},
  );
}

/// Customers ki list.
Future<void> exportCustomers(BuildContext context, List<InstCustomerRow> list) => InstPdf.shareTable(
      context,
      base: 'Customers',
      title: Loc.t('Customers', 'کسٹمرز'),
      sub: _stamp(),
      summary: [(Loc.t('Customers', 'کسٹمرز'), '${list.length}')],
      headers: [
        Loc.t('Name', 'نام'),
        Loc.t('Father / husband', 'والد / شوہر'),
        Loc.t('Phone', 'فون'),
        Loc.t('CNIC', 'شناختی کارڈ'),
        Loc.t('Khata no.', 'کھاتہ نمبر'),
        Loc.t('Address', 'پتہ'),
        Loc.t('Guarantors', 'ضامن'),
        Loc.t('Blacklisted', 'بلیک لسٹ'),
      ],
      rows: [
        for (final r in list)
          [
            r.name,
            r.profile?.fatherName ?? '',
            r.phone,
            r.profile?.cnic ?? '',
            r.profile?.khataNo ?? '',
            r.profile?.address ?? '',
            '${r.guarantorCount}',
            (r.profile?.isBlocked ?? false) ? Loc.t('Yes', 'ہاں') : '',
          ]
      ],
      flex: const [3, 3, 2, 3, 1, 4, 1, 1],
      right: const {6},
    );

/// Stock (har piece).
Future<void> exportItems(BuildContext context, List<InstItem> items, Map<int?, String> catName, {required bool showCost}) {
  final inStock = items.where((i) => i.status == itemInStock).toList();
  return InstPdf.shareTable(
    context,
    base: 'Stock',
    title: Loc.t('Stock', 'اسٹاک'),
    sub: _stamp(),
    summary: [
      (Loc.t('Pieces in list', 'لسٹ میں پیس'), '${items.length}'),
      (Loc.t('In stock', 'اسٹاک میں'), '${inStock.length}'),
      if (showCost) (Loc.t('Stock cost', 'اسٹاک کی لاگت'), instRs(inStock.fold<double>(0, (a, i) => a + i.costPrice))),
    ],
    headers: [
      Loc.t('Category', 'کیٹیگری'),
      Loc.t('Item', 'سامان'),
      Loc.t('Color', 'رنگ'),
      Loc.t('IMEI / serial', 'IMEI / سیریل'),
      if (showCost) Loc.t('Cost', 'لاگت'),
      Loc.t('Cash price', 'نقد قیمت'),
      Loc.t('Status', 'حالت'),
      Loc.t('Purchase date', 'خریداری'),
    ],
    rows: [
      for (final i in items)
        [
          catName[i.categoryId] ?? '',
          i.title,
          i.color,
          i.idValues.entries.where((e) => e.value.trim().isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' | '),
          if (showCost) instRs(i.costPrice),
          instRs(i.cashPrice),
          i.status == itemInStock ? Loc.t('In stock', 'اسٹاک میں') : Loc.t('Sold / out', 'بک گیا'),
          _d(i.purchaseDate),
        ]
    ],
    flex: showCost ? const [2, 3, 1, 4, 2, 2, 2, 2] : const [2, 3, 1, 4, 2, 2, 2],
    right: showCost ? const {4, 5} : const {4},
  );
}
