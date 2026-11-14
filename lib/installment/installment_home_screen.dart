import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../screens/cash_screen.dart';
import '../screens/expense_screen.dart';
import '../screens/login_screen.dart';
import '../screens/settings_screen.dart';
import '../services/crash_handler.dart';
import '../services/crash_reporter.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_cash_sale_screens.dart';
import 'inst_collection_screens.dart';
import 'inst_customers_screen.dart';
import 'inst_items_screen.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_purchase_screens.dart';
import 'inst_report_screens.dart';
import 'inst_update.dart';
import 'inst_repository.dart';
import 'inst_shop_tools_screen.dart';
import '../license/license_screen.dart';
import '../services/bill_reminder_service.dart';
import 'inst_ui.dart';

/// Hanna Installment ka home (login ke baad pehli screen).
///
/// Step 2 tak: Customers (CNIC + guarantor), Stock (har piece IMEI / engine no. ke saath), Categories.
/// Step 3: Nayi Qist, Qisten (aaj / late / jari), aaj ki wasooli. POS ki purani screens (cash, expense, reports...) abhi
/// "Shop tools" se khulti hain — pehli kamyab build ke baad ghair-zaroori hisse nikale jayenge.
class InstallmentHomeScreen extends StatefulWidget {
  const InstallmentHomeScreen({super.key});

  @override
  State<InstallmentHomeScreen> createState() => _InstallmentHomeScreenState();
}

class _InstallmentHomeScreenState extends State<InstallmentHomeScreen> {
  InstHomeStats _stats = const InstHomeStats();
  InstCollectionStats _col = const InstCollectionStats();

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_load);
    _load();
    // Android 13+: roz ki qist notification ke liye ijazat (pehli baar poochta hai).
    BillReminderService.requestPermission();
    // Pichhli dafa app band (crash) hui ho to log dikhao / developer ko bhejo (purane POS dashboard se).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLastCrash());
    // Naya update (har 6 ghante mein ek dafa, internet ho to).
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(seconds: 4), () {
          if (mounted) InstUpdate.checkOnStart(context);
        }));
  }

  /// Kotlin `showCrashDialog`: pichli baar crash hui ho to log dikhao (Share / Copy / Dismiss).
  Future<void> _checkLastCrash() async {
    final text = await CrashHandler.getLastCrash();
    if (text == null || !mounted) return;
    // Cloud Sync juda ho to developer ko khud (Firestore crash_reports) — dialog ka intezar kiye baghair.
    CrashReporter.uploadIfNew(text).ignore();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('App crashed last time', 'پچھلی بار ایپ کریش ہوئی تھی')),
        content: SingleChildScrollView(
          child: SelectableText(CrashHandler.preview(text), style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await launchUrl(CrashReporter.whatsAppUri(text), mode: LaunchMode.externalApplication);
              } catch (_) {}
              await CrashHandler.clearLastCrash();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(Loc.t('Send to developer', 'ڈیولپر کو بھیجیں')),
          ),
          TextButton(
            onPressed: () async {
              await Share.share(text, subject: 'Hanna Installment Crash Log');
              await CrashHandler.clearLastCrash();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(Loc.t('Share', 'شیئر کریں')),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(Loc.t('Copied', 'کاپی ہو گیا'))),
                );
              }
            },
            child: Text(Loc.t('Copy', 'کاپی')),
          ),
          TextButton(
            onPressed: () async {
              await CrashHandler.clearLastCrash();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(Loc.t('Dismiss', 'برخاست کریں')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await InstRepository.instance.homeStats();
      final c = await InstPlanRepository.instance.collectionStats();
      if (mounted) {
        setState(() {
          _stats = s;
          _col = c;
        });
      }
    } catch (_) {}
  }

  /// Dashboard se ek jagah: paise aana (qist, naqd sale, cash in) aur jana (supplier, kharcha, cash out).
  Future<void> _payReceive() async {
    final p = ThemeManager.palette;
    final mgr = Session.isAdminOrManager;
    Widget item(IconData icon, Color color, String title, String sub, Widget screen) => ListTile(
          leading: CircleAvatar(backgroundColor: color.withOpacity(0.14), child: Icon(icon, color: color)),
          title: Text(title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
          subtitle: Text(sub, style: TextStyle(color: p.textMuted, fontSize: 12)),
          trailing: Icon(Icons.chevron_right, color: p.textMuted),
          onTap: () {
            Navigator.of(context).pop();
            _push(screen);
          },
        );
    Widget head(String t, Color c) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: p.bg,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head(Loc.t('RECEIVE (MONEY IN)', 'لینا (رقم آئی)'), p.teal),
            item(Icons.request_quote_outlined, p.teal, Loc.t('Installment collection', 'قسط کی وصولی'),
                Loc.t('Pick the customer, then Receive', 'کسٹمر چنیں، پھر وصول کریں'), const InstCollectionListScreen()),
            item(Icons.point_of_sale, p.tealDark, Loc.t('Cash sale', 'نقد سیل'), Loc.t('Sell a piece for full payment', 'پوری رقم پر پیس بیچیں'),
                const InstNewCashSaleScreen()),
            item(Icons.south_west, p.blue, Loc.t('Other money in (Cash In)', 'دوسری آمد (کیش ان)'),
                Loc.t('Opening cash, owner money...', 'شروع کا کیش، مالک کی رقم...'), const CashScreen()),
            head(Loc.t('PAY (MONEY OUT)', 'دینا (رقم گئی)'), p.red),
            if (mgr)
              item(Icons.local_shipping_outlined, p.red, Loc.t('Pay supplier', 'سپلائر کو ادائیگی'),
                  Loc.t('Choose supplier, then Pay', 'سپلائر چنیں، پھر ادا کریں'), const InstSuppliersScreen()),
            item(Icons.receipt_long_outlined, p.orange, Loc.t('Expense', 'خرچہ'), Loc.t('Electricity, tea, repairs...', 'بجلی، چائے، مرمت...'),
                const ExpenseScreen()),
            item(Icons.north_east, p.purple, Loc.t('Other money out (Cash Out)', 'دوسرا خرچ (کیش آؤٹ)'),
                Loc.t('Owner withdrawal, bank deposit...', 'مالک نے نکالے، بینک میں جمع...'), const CashScreen()),
            head(Loc.t('RETURNS', 'واپسی'), p.orange),
            item(Icons.assignment_return_outlined, p.orange, Loc.t('Sale return (customer)', 'سیل واپسی (کسٹمر)'),
                Loc.t('Open the cash sale, then "Sale return"', 'نقد سیل کھولیں، پھر "سیل واپسی"'), const InstCashSalesScreen()),
            if (mgr)
              item(Icons.keyboard_return, p.navy, Loc.t('Purchase return (supplier)', 'خریداری واپسی (سپلائر)'),
                  Loc.t('Open the bill, then "Return"', 'بل کھولیں، پھر "واپس کریں"'), const InstPurchasesScreen()),
            if (mgr)
              item(Icons.undo, p.red, Loc.t('Installment item taken back', 'قسط کا سامان واپس'),
                  Loc.t('Open the plan, ⋮ menu > "Take item back"', 'پلان کھولیں، ⋮ مینو > "سامان واپس لیں"'), const InstPlansScreen()),
          ]),
        ),
      ),
    );
  }

  Future<void> _push(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    await _load();
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1000 ? 4 : (width >= 640 ? 3 : 2);
    final tiles = <_Tile>[
      _Tile(Icons.add_card, Loc.t('New Installment', 'نئی قسط'), Loc.t('Customer + item + plan', 'کسٹمر + سامان + پلان'), p.teal,
          () => _push(const NewInstallmentScreen())),
      _Tile(Icons.swap_vert_circle_outlined, Loc.t('Pay / Receive', 'لینا / دینا'), Loc.t('Collect, pay, returns', 'وصولی، ادائیگی، واپسی'), p.teal,
          _payReceive),
      _Tile(Icons.request_quote_outlined, Loc.t('Installments', 'قسطیں'), Loc.t('${_col.activePlans} active plans', '${_col.activePlans} جاری پلان'), p.navy,
          () => _push(const InstPlansScreen())),
      _Tile(Icons.point_of_sale, Loc.t('Cash Sale', 'نقد سیل'), Loc.t('Sell without installments', 'بغیر قسط بیچیں'), p.tealDark,
          () => _push(const InstCashSalesScreen())),
      _Tile(Icons.format_list_numbered, Loc.t('Collection List', 'وصولی لسٹ'), Loc.t('Who to collect from', 'کس سے کتنا لینا ہے'), p.blue,
          () => _push(const InstCollectionListScreen())),
      _Tile(Icons.report_gmailerrorred_outlined, Loc.t('Defaulters', 'ڈیفالٹرز'), Loc.t('Late + guarantor phones', 'لیٹ + ضامن کے فون'), p.red,
          () => _push(const InstDefaultersScreen())),
      if (Session.isAdminOrManager)
        _Tile(Icons.insights_outlined, Loc.t('Reports', 'رپورٹس'), Loc.t('Profit, sale, stock, dues', 'منافع، سیل، اسٹاک، قسطیں'), p.navyLight,
            () => _push(const InstReportsHubScreen())),
      _Tile(Icons.people_alt_outlined, Loc.t('Customers', 'کسٹمرز'), Loc.t('CNIC, guarantors', 'شناختی کارڈ، ضامن'), p.purple,
          () => _push(const InstCustomersScreen())),
      _Tile(Icons.inventory_2_outlined, Loc.t('Stock', 'اسٹاک'), Loc.t('Mobiles, bikes, LCDs...', 'موبائل، بائیک، ایل سی ڈی'), p.blue,
          () => _push(const InstItemsScreen())),
      if (Session.isAdminOrManager)
        _Tile(Icons.local_shipping_outlined, Loc.t('Purchases', 'خریداری'), Loc.t('Bills, suppliers, payable', 'بل، سپلائر، ادھار'), p.tealDark,
            () => _push(const InstPurchasesScreen())),
      _Tile(Icons.category_outlined, Loc.t('Categories', 'کیٹیگریز'), Loc.t('IMEI / serial fields', 'IMEI / سیریل فیلڈز'), p.amber,
          () => _push(const InstCategoriesScreen())),
      _Tile(Icons.storefront_outlined, Loc.t('Shop tools', 'دکان کے ٹولز'), Loc.t('Cash, expenses, staff, backup', 'کیش، خرچے، اسٹاف، بیک اپ'), p.orange,
          () => _push(const InstShopToolsScreen())),
      if (Session.isAdminOrManager)
        _Tile(Icons.settings_outlined, Loc.t('Settings', 'سیٹنگز'), Loc.t('Sync, backup, users', 'سنک، بیک اپ، یوزرز'), p.navyLight,
            () => _push(const SettingsScreen())),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(
          context,
          p,
          AppInfo.appName,
          '${Loc.t('Hello', 'السلام علیکم')}, ${Session.displayName.isNotEmpty ? Session.displayName : (Session.username ?? '')}',
          back: false,
          actions: [
            IconButton(
              tooltip: Loc.t('Log out', 'لاگ آؤٹ'),
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _logout,
            ),
          ],
        ),
        const LicenseBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
              Row(children: [
                Expanded(
                  child: _tapStat(p, Loc.t('Due today', 'آج کی قسطیں'), instRs(_col.dueToday),
                      Loc.t('${_col.dueTodayCount} customers', '${_col.dueTodayCount} کسٹمر'), p.amber,
                      () => _push(const InstCollectionListScreen())),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tapStat(p, Loc.t('Late', 'لیٹ'), instRs(_col.overdue),
                      Loc.t('${_col.overdueCount} customers', '${_col.overdueCount} کسٹمر'), p.red,
                      () => _push(const InstDefaultersScreen(minDays: 1))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tapStat(p, Loc.t('Collected', 'آج وصولی'), instRs(_col.collectedToday),
                      Loc.t('Receivable ${instRs(_col.receivable)}', 'کل باقی ${instRs(_col.receivable)}'), p.teal,
                      () => _push(const InstPlansScreen())),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _stat(p, Loc.t('Customers', 'کسٹمرز'), '${_stats.customers}', p.purple)),
                const SizedBox(width: 10),
                Expanded(child: _stat(p, Loc.t('In stock', 'اسٹاک میں'), '${_stats.itemsInStock}', p.blue)),
                if (Session.isAdminOrManager) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _stat(p, Loc.t('Stock cost', 'اسٹاک کی لاگت'), instRs(_stats.stockCostValue), p.amber)),
                ],
              ]),
              if (_stats.profilesWithoutGuarantor > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _push(const InstCustomersScreen(onlyWithoutGuarantor: true)),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: instCard(p),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, color: p.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            Loc.t('${_stats.profilesWithoutGuarantor} customer(s) have no guarantor',
                                '${_stats.profilesWithoutGuarantor} کسٹمر کا کوئی ضامن نہیں'),
                            style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: p.textMuted),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [for (final t in tiles) _tile(p, t)],
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tapStat(AppPalette p, String label, String value, String sub, Color c, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: instCard(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5))),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 10.5)),
          ]),
        ),
      );

  Widget _stat(AppPalette p, String label, String value, Color c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: p.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ]),
      );

  Widget _tile(AppPalette p, _Tile t) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: t.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: instCard(p, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.color.withOpacity(0.13), borderRadius: BorderRadius.circular(12)),
              child: Icon(t.icon, color: t.color, size: 26),
            ),
            const Spacer(),
            Text(t.title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
            const SizedBox(height: 2),
            Text(t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
          ]),
        ),
      );
}

class _Tile {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Tile(this.icon, this.title, this.subtitle, this.color, this.onTap);
}
