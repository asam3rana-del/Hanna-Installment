import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/party_photo_store.dart';
import '../services/session.dart';
import '../services/whatsapp_sender.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../widgets/party_avatar.dart';
import 'inst_customers_screen.dart';
import 'inst_items_screen.dart';
import 'inst_models.dart';
import 'inst_pdf.dart';
import 'inst_photo_widgets.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';
import 'inst_reports.dart' show profitShare;
import 'inst_repository.dart';
import 'inst_ui.dart';
import 'kyc_photo_store.dart';

String _d(int ms) => DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));
String _dt(int ms) => DateFormat('dd MMM yyyy, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));

String freqLabel(String f) => switch (f) {
      freqWeekly => Loc.t('Weekly', 'ہفتہ وار'),
      freqFortnightly => Loc.t('Every 15 days', 'ہر 15 دن'),
      _ => Loc.t('Monthly', 'ماہانہ'),
    };

String planStatusLabel(String s) => switch (s) {
      planActive => Loc.t('Active', 'جاری'),
      planCompleted => Loc.t('Completed', 'مکمل'),
      planRepossessed => Loc.t('Item taken back', 'سامان واپس'),
      planCancelled => Loc.t('Cancelled', 'منسوخ'),
      _ => s,
    };

/// Customer ko WhatsApp par qist ki yaad-dahani (late / agli qist / kul baqi).
String planReminderText(PlanView v, ShopHeader shop) {
  final st = v.status;
  final amount = st.dueNow > 0.5 ? st.dueNow : (st.next?.remaining ?? 0);
  return [
    'Assalam o Alaikum ${v.customerName},',
    'Aap ki qist (${v.plan.planNo} — ${v.itemTitle}):',
    if (st.overdue > 0.5) 'Late: Rs ${st.overdue.round()} (${st.daysLate} din)',
    if (st.next != null) 'Raqam: Rs ${amount.round()} — tareekh ${_d(st.next!.dueDate)}',
    'Kul baqi: Rs ${st.remaining.round()}',
    if (shop.name.isNotEmpty) '— ${shop.name}${shop.phone.isNotEmpty ? ' (${shop.phone})' : ''}',
  ].join('\n');
}

Future<void> remindPlan(BuildContext context, PlanView v, {String? phone}) async {
  final shop = await loadShopHeader();
  if (!context.mounted) return;
  await sendOnWhatsApp(context, phone: phone ?? v.customerPhone, text: planReminderText(v, shop));
}

/// List / customer detail mein ek plan.
class PlanTile extends StatelessWidget {
  final PlanView view;
  final bool showCustomer;
  final VoidCallback onTap;
  const PlanTile({super.key, required this.view, required this.onTap, this.showCustomer = true});

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final v = view;
    final st = v.status;
    final Color c;
    final String badge;
    if (!v.plan.isActive) {
      c = v.plan.status == planCompleted ? p.teal : p.textMuted;
      badge = planStatusLabel(v.plan.status);
    } else if (st.overdue > 0.5) {
      c = p.red;
      badge = Loc.t('${st.daysLate} days late', '${st.daysLate} دن لیٹ');
    } else if (st.dueNow > 0.5) {
      c = p.amber;
      badge = Loc.t('Due today', 'آج واجب');
    } else {
      c = p.teal;
      badge = st.next == null ? Loc.t('Paid', 'ادا') : '${Loc.t('Next', 'اگلی')} ${DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(st.next!.dueDate))}';
    }
    final progress = st.installmentTotal <= 0 ? 0.0 : (st.paid / st.installmentTotal).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (showCustomer) ...[
              PartyAvatar(isCustomer: true, partyId: v.plan.customerId, name: v.customerName, radius: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(showCustomer ? v.customerName : v.itemTitle,
                    style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${v.plan.planNo}  •  ${showCustomer ? v.itemTitle : freqLabel(v.plan.frequency)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(badge, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: p.fieldFill, color: p.teal),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${Loc.t('Paid', 'ادا')} ${instRs(st.paid)}', style: TextStyle(color: p.textMuted, fontSize: 12)),
            const Spacer(),
            Text('${Loc.t('Remaining', 'باقی')} ${instRs(st.remaining)}',
                style: TextStyle(color: st.overdue > 0.5 ? p.red : p.textDark, fontSize: 12.5, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
    );
  }
}

// ===================================================================== plans list

enum PlanFilter { dueToday, overdue, active, completed, closed, all }

class InstPlansScreen extends StatefulWidget {
  final PlanFilter initial;
  const InstPlansScreen({super.key, this.initial = PlanFilter.active});

  @override
  State<InstPlansScreen> createState() => _InstPlansScreenState();
}

class _InstPlansScreenState extends State<InstPlansScreen> {
  List<PlanView> _all = const [];
  bool _loaded = false;
  String _q = '';
  late PlanFilter _f = widget.initial;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await InstPlanRepository.instance.list();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loaded = true;
    });
  }

  bool _pass(PlanView v) {
    final active = v.plan.isActive;
    return switch (_f) {
      PlanFilter.dueToday => active && v.status.dueNow > 0.5 && v.status.overdue <= 0.5,
      PlanFilter.overdue => active && v.status.overdue > 0.5,
      PlanFilter.active => active,
      PlanFilter.completed => v.plan.status == planCompleted,
      PlanFilter.closed => v.plan.status == planRepossessed || v.plan.status == planCancelled,
      PlanFilter.all => true,
    };
  }

  String _label(PlanFilter f) => switch (f) {
        PlanFilter.dueToday => Loc.t('Due today', 'آج واجب'),
        PlanFilter.overdue => Loc.t('Late', 'لیٹ'),
        PlanFilter.active => Loc.t('Active', 'جاری'),
        PlanFilter.completed => Loc.t('Completed', 'مکمل'),
        PlanFilter.closed => Loc.t('Taken back', 'واپس'),
        PlanFilter.all => Loc.t('All', 'سب'),
      };

  Future<void> _open(PlanView v) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: v.plan.id)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final list = _all.where((v) => _pass(v) && v.matches(_q)).toList();
    if (_f == PlanFilter.overdue) list.sort((a, b) => b.status.daysLate.compareTo(a.status.daysLate));
    final sumRemaining = list.fold<double>(0, (a, v) => a + (v.plan.isActive ? v.status.remaining : 0));
    final sumOverdue = list.fold<double>(0, (a, v) => a + (v.plan.isActive ? v.status.overdue : 0));
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.teal,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewInstallmentScreen()));
          await _reload();
        },
        icon: const Icon(Icons.add_card),
        label: Text(Loc.t('New Installment', 'نئی قسط')),
      ),
      body: Column(children: [
        instHeader(context, p, Loc.t('Installments', 'قسطیں'), Loc.t('${_all.length} plans', '${_all.length} پلان')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search customer, plan no., IMEI', 'کسٹمر، پلان نمبر، IMEI سے تلاش'), suffix: const Icon(Icons.search)),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final f in PlanFilter.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: ChoiceChip(label: Text(_label(f)), selected: _f == f, onSelected: (_) => setState(() => _f = f)),
              ),
          ]),
        ),
        if (_loaded && list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Row(children: [
              Text(Loc.t('${list.length} plans', '${list.length} پلان'), style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (sumOverdue > 0.5)
                Text('${Loc.t('Late', 'لیٹ')} ${instRs(sumOverdue)}  •  ', style: TextStyle(color: p.red, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('${Loc.t('Remaining', 'باقی')} ${instRs(sumRemaining)}', style: TextStyle(color: p.textMuted, fontSize: 12)),
            ]),
          ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _all.isEmpty
                              ? Loc.t('No installment plans yet. Tap "New Installment".', 'ابھی کوئی قسط پلان نہیں۔ "نئی قسط" دبائیں۔')
                              : Loc.t('Nothing here.', 'یہاں کچھ نہیں۔'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.textMuted),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        itemBuilder: (_, i) => PlanTile(view: list[i], onTap: () => _open(list[i])),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ===================================================================== new plan

class NewInstallmentScreen extends StatefulWidget {
  final int? customerId;
  final int? itemId;
  const NewInstallmentScreen({super.key, this.customerId, this.itemId});

  @override
  State<NewInstallmentScreen> createState() => _NewInstallmentScreenState();
}

class _NewInstallmentScreenState extends State<NewInstallmentScreen> {
  static const _prefProfit = 'inst_default_profit_pct';
  static const _prefCount = 'inst_default_count';
  static const _prefRound = 'inst_default_round';
  static const _prefLateFee = 'inst_default_late_fee';
  static const _prefGrace = 'inst_default_grace';

  InstCustomerRow? _customer;
  List<Guarantor> _guarantors = const [];
  final Set<int> _gSel = {};
  InstItem? _item;

  final _cash = TextEditingController();
  final _advance = TextEditingController();
  final _profit = TextEditingController(text: '30');
  final _count = TextEditingController(text: '12');
  final _lateFee = TextEditingController();
  final _grace = TextEditingController(text: '3');
  final _note = TextEditingController();
  String _profitMode = profitPercent;
  String _freq = freqMonthly;
  int _roundTo = 10;
  String _advanceMethod = 'cash';
  late int _firstDue = dayStart(addMonthsClamped(DateTime.now(), 1));
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in [_cash, _advance, _profit, _count, _lateFee, _grace, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final pr = sp.getDouble(_prefProfit);
      if (pr != null) _profit.text = instPlain(pr);
      final ct = sp.getInt(_prefCount);
      if (ct != null) _count.text = '$ct';
      _roundTo = sp.getInt(_prefRound) ?? _roundTo;
      final lf = sp.getDouble(_prefLateFee);
      if (lf != null && lf > 0) _lateFee.text = instPlain(lf);
      final gr = sp.getInt(_prefGrace);
      if (gr != null) _grace.text = '$gr';
    } catch (_) {}
    await PartyPhotoStore.instance.ensureLoaded();
    await KycPhotoStore.instance.ensureLoaded();
    if (widget.customerId != null) {
      final rows = await InstRepository.instance.listCustomers();
      final c = rows.where((r) => r.id == widget.customerId).firstOrNull;
      if (c != null) await _setCustomer(c);
    }
    if (widget.itemId != null) {
      final items = await InstRepository.instance.items(status: itemInStock);
      final it = items.where((i) => i.id == widget.itemId).firstOrNull;
      if (it != null) _setItem(it);
    }
    if (mounted) setState(() {});
  }

  Future<void> _setCustomer(InstCustomerRow c) async {
    final g = await InstRepository.instance.guarantors(c.id);
    if (!mounted) return;
    setState(() {
      _customer = c;
      _guarantors = g;
      _gSel
        ..clear()
        ..addAll(g.map((x) => x.id!));
    });
  }

  void _setItem(InstItem it) {
    setState(() {
      _item = it;
      _cash.text = it.cashPrice > 0 ? instPlain(it.cashPrice) : '';
    });
  }

  Future<void> _reloadCustomer() async {
    final c = _customer;
    if (c == null) return;
    final rows = await InstRepository.instance.listCustomers();
    final fresh = rows.where((r) => r.id == c.id).firstOrNull;
    if (fresh == null) return;
    final keep = Set<int>.of(_gSel);
    final known = _guarantors.map((g) => g.id!).toSet();
    await _setCustomer(fresh);
    if (!mounted) return;
    // Naya bana guarantor khud select; purane jo hataye the wo hate rahein.
    setState(() {
      final all = _guarantors.map((g) => g.id!).toSet();
      _gSel
        ..clear()
        ..addAll(keep.intersection(all))
        ..addAll(all.difference(known));
    });
  }

  PlanQuote? _quote() {
    try {
      return quotePlan(
        cashPrice: instParse(_cash.text),
        advance: instParse(_advance.text),
        profitMode: _profitMode,
        profitValue: instParse(_profit.text),
        count: int.tryParse(_count.text.trim()) ?? 0,
        roundTo: _roundTo,
      );
    } catch (_) {
      return null;
    }
  }

  String? _quoteError() {
    try {
      quotePlan(
        cashPrice: instParse(_cash.text),
        advance: instParse(_advance.text),
        profitMode: _profitMode,
        profitValue: instParse(_profit.text),
        count: int.tryParse(_count.text.trim()) ?? 0,
        roundTo: _roundTo,
      );
      return null;
    } catch (e) {
      return instErr(e);
    }
  }

  // ---------------------------------------------------------------- pickers

  Future<void> _pickCustomer() async {
    final rows = await InstRepository.instance.listCustomers();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet<InstCustomerRow>(
        title: Loc.t('Choose customer', 'کسٹمر چنیں'),
        items: rows,
        matches: (r, q) => r.matches(q),
        addLabel: Loc.t('New customer', 'نیا کسٹمر'),
        tile: (r) => ListTile(
          leading: PartyAvatar(isCustomer: true, partyId: r.id, name: r.name),
          title: Text(r.name),
          subtitle: Text([if (r.profile?.cnic.isNotEmpty ?? false) r.profile!.cnic, if (r.phone.isNotEmpty) r.phone].join('  •  ')),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == _PickerSheet.addNew) {
      final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => const InstCustomerFormScreen()));
      if (id == null) return;
      final fresh = (await InstRepository.instance.listCustomers()).where((r) => r.id == id).firstOrNull;
      if (fresh != null) await _setCustomer(fresh);
      return;
    }
    if (picked is InstCustomerRow) await _setCustomer(picked);
  }

  Future<void> _pickItem() async {
    final items = await InstRepository.instance.items(status: itemInStock);
    final cats = {for (final c in await InstRepository.instance.categories()) c.id: c.name};
    if (!mounted) return;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet<InstItem>(
        title: Loc.t('Choose item (in stock)', 'سامان چنیں (اسٹاک میں)'),
        items: items,
        matches: (i, q) => i.matches(q),
        addLabel: Loc.t('Add item to stock', 'اسٹاک میں نیا سامان'),
        tile: (i) => ListTile(
          title: Text(i.title.isEmpty ? i.model : i.title),
          subtitle: Text([cats[i.categoryId] ?? '', if (i.primaryId.isNotEmpty) i.primaryId].join('  •  ')),
          trailing: Text(instRs(i.cashPrice), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == _PickerSheet.addNew) {
      final catList = await InstRepository.instance.categories();
      if (!mounted) return;
      if (catList.isEmpty) {
        instToast(context, Loc.t('Add a category first.', 'پہلے کیٹیگری بنائیں۔'));
        return;
      }
      final before = (await InstRepository.instance.items()).map((i) => i.id).toSet();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstItemFormScreen(categories: catList)));
      final after = await InstRepository.instance.items(status: itemInStock);
      final added = after.where((i) => !before.contains(i.id)).firstOrNull;
      if (added != null) _setItem(added);
      return;
    }
    if (picked is InstItem) _setItem(picked);
  }

  Future<void> _pickFirstDue() async {
    final init = DateTime.fromMillisecondsSinceEpoch(_firstDue);
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: init, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2));
    if (d != null) setState(() => _firstDue = dayStart(d));
  }

  // ---------------------------------------------------------------- save

  Future<void> _save() async {
    if (_saving) return;
    final c = _customer;
    final it = _item;
    if (c == null) return instToast(context, Loc.t('Choose a customer.', 'کسٹمر چنیں۔'));
    if (it == null) return instToast(context, Loc.t('Choose an item.', 'سامان چنیں۔'));
    final qErr = _quoteError();
    if (qErr != null) return instToast(context, qErr);
    final q = _quote()!;

    // Kaghzat / tasveerein ki kami: rokte nahi, poochte hain.
    final issues = <String>[];
    if (PartyPhotoStore.instance.pathFor(true, c.id) == null) issues.add(Loc.t('Customer photo is missing', 'کسٹمر کی تصویر نہیں'));
    if (c.profile == null || cnicDigits(c.profile!.cnic).length != 13) issues.add(Loc.t('Customer CNIC is missing', 'کسٹمر کا شناختی کارڈ نمبر نہیں'));
    if (_gSel.isEmpty) issues.add(Loc.t('No guarantor selected', 'کوئی ضامن نہیں چنا'));
    for (final g in _guarantors.where((g) => _gSel.contains(g.id))) {
      if (KycPhotoStore.instance.pathFor('g', g.id!, KycPhotoStore.photo) == null) {
        issues.add(Loc.t('Photo missing: ${g.name}', 'تصویر نہیں: ${g.name}'));
      }
    }
    if (issues.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(Loc.t('Missing documents', 'کاغذات کی کمی')),
          content: Text(issues.map((e) => '•  $e').join('\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Go back', 'واپس'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Save anyway', 'پھر بھی محفوظ'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Confirm installment', 'قسط کی تصدیق')),
        content: Text([
          '${c.name} — ${it.title.isEmpty ? it.model : it.title}',
          '${Loc.t('Total price', 'کل قیمت')}: ${instRs(q.totalPrice)}',
          if (q.advance > 0) '${Loc.t('Advance now', 'ابھی ایڈوانس')}: ${instRs(q.advance)}',
          '${q.count} × ${instRs(q.each)}${q.last != q.each ? ' (${Loc.t('last', 'آخری')} ${instRs(q.last)})' : ''}',
          '${Loc.t('First due', 'پہلی قسط')}: ${_d(_firstDue)}',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Create plan', 'پلان بنائیں'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final id = await InstPlanRepository.instance.createPlan(
        customerId: c.id,
        itemId: it.id!,
        guarantorIds: _gSel.toList(),
        cashPrice: q.cashPrice,
        advance: q.advance,
        advanceMethod: _advanceMethod,
        profitMode: _profitMode,
        profitValue: instParse(_profit.text),
        count: q.count,
        frequency: _freq,
        firstDueDate: _firstDue,
        roundTo: _roundTo,
        lateFee: instParse(_lateFee.text),
        graceDays: int.tryParse(_grace.text.trim()) ?? 0,
        note: _note.text,
      );
      try {
        final sp = await SharedPreferences.getInstance();
        if (_profitMode == profitPercent) await sp.setDouble(_prefProfit, instParse(_profit.text));
        await sp.setInt(_prefCount, q.count);
        await sp.setInt(_prefRound, _roundTo);
        await sp.setDouble(_prefLateFee, instParse(_lateFee.text));
        await sp.setInt(_prefGrace, int.tryParse(_grace.text.trim()) ?? 0);
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: id)));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        instToast(context, instErr(e));
      }
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _quote();
    final err = _quoteError();
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    void re(_) => setState(() {});
    Widget gap() => const SizedBox(height: 12);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('New Installment', 'نئی قسط'), Loc.t('Customer → item → plan', 'کسٹمر ← سامان ← پلان')),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            instSectionTitle(p, Loc.t('1. CUSTOMER', '1۔ کسٹمر')),
            _customerCard(p),
            if (_customer != null) ...[
              instSectionTitle(p, Loc.t('GUARANTORS', 'ضامن')),
              _guarantorCard(p),
            ],
            instSectionTitle(p, Loc.t('2. ITEM', '2۔ سامان')),
            _itemCard(p),
            instSectionTitle(p, Loc.t('3. PLAN', '3۔ پلان')),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: instCard(p),
              child: Column(children: [
                TextField(
                    controller: _cash,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: money,
                    onChanged: re,
                    decoration: instDeco(p, Loc.t('Cash price', 'نقد قیمت'))),
                gap(),
                TextField(
                    controller: _advance,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: money,
                    onChanged: re,
                    decoration: instDeco(p, Loc.t('Advance (down payment)', 'ایڈوانس'))),
                if (instParse(_advance.text) > 0) ...[
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش'))),
                      ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک'))),
                    ],
                    selected: {_advanceMethod},
                    onSelectionChanged: (s) => setState(() => _advanceMethod = s.first),
                  ),
                ],
                gap(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _profit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: money,
                      onChanged: re,
                      decoration: instDeco(p, _profitMode == profitPercent ? Loc.t('Profit %', 'منافع %') : Loc.t('Profit (Rs)', 'منافع (روپے)')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: profitPercent, label: Text('%')),
                      ButtonSegment(value: profitFixed, label: Text('Rs')),
                    ],
                    selected: {_profitMode},
                    onSelectionChanged: (s) => setState(() => _profitMode = s.first),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(Loc.t('Profit is on the amount left after advance.', 'منافع ایڈوانس کے بعد باقی رقم پر۔'),
                        style: TextStyle(color: p.textMuted, fontSize: 11)),
                  ),
                ),
                gap(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: re,
                      decoration: instDeco(p, Loc.t('No. of installments', 'قسطوں کی تعداد')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _freq,
                      isExpanded: true,
                      decoration: instDeco(p, Loc.t('Every', 'ہر')),
                      items: [for (final f in planFrequencies) DropdownMenuItem(value: f, child: Text(freqLabel(f)))],
                      onChanged: (v) {
                        if (v != null) setState(() => _freq = v);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  for (final n in const [3, 6, 9, 12, 18, 24])
                    ActionChip(
                      label: Text('$n'),
                      onPressed: () => setState(() => _count.text = '$n'),
                    ),
                ]),
                gap(),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickFirstDue,
                  child: InputDecorator(
                    decoration: instDeco(p, Loc.t('First installment date', 'پہلی قسط کی تاریخ'), suffix: const Icon(Icons.event)),
                    child: Text(_d(_firstDue), style: TextStyle(color: p.textDark, fontSize: 15)),
                  ),
                ),
                gap(),
                DropdownButtonFormField<int>(
                  value: _roundTo,
                  decoration: instDeco(p, Loc.t('Round installment to', 'قسط کو گول کریں')),
                  items: [
                    for (final r in const [1, 10, 50, 100, 500])
                      DropdownMenuItem(value: r, child: Text(r == 1 ? Loc.t('No rounding', 'گول نہیں') : 'Rs $r')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _roundTo = v);
                  },
                ),
                gap(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _lateFee,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: money,
                      decoration: instDeco(p, Loc.t('Late fine per qist', 'فی قسط لیٹ جرمانہ')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _grace,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: instDeco(p, Loc.t('Grace days', 'رعایتی دن')),
                    ),
                  ),
                ]),
                gap(),
                TextField(controller: _note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
              ]),
            ),
            instSectionTitle(p, Loc.t('SUMMARY', 'خلاصہ')),
            _summary(p, q, err),
            const SizedBox(height: 20),
            instPrimaryButton(
              p,
              _saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Create installment plan', 'قسط پلان بنائیں'),
              _saving ? null : _save,
              icon: Icons.add_card,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _customerCard(AppPalette p) {
    final c = _customer;
    if (c == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        icon: const Icon(Icons.person_search),
        label: Text(Loc.t('Choose customer', 'کسٹمر چنیں')),
        onPressed: _pickCustomer,
      );
    }
    final hasPhoto = PartyPhotoStore.instance.pathFor(true, c.id) != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: instCard(p),
      child: Row(children: [
        Column(children: [
          PartyAvatar(
            isCustomer: true,
            partyId: c.id,
            name: c.name,
            radius: 30,
            onTap: () async {
              await showPartyPhotoSheet(context, isCustomer: true, partyId: c.id);
              if (mounted) setState(() {});
            },
          ),
          if (!hasPhoto)
            Text(Loc.t('Tap for snap', 'تصویر لیں'), style: TextStyle(color: p.red, fontSize: 10.5, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 16)),
            if (c.profile?.fatherName.isNotEmpty ?? false)
              Text('${Loc.t('s/o', 'ولد')} ${c.profile!.fatherName}', style: TextStyle(color: p.textMuted, fontSize: 12)),
            Text(
              c.profile?.cnic.isNotEmpty ?? false ? c.profile!.cnic : Loc.t('No CNIC', 'شناختی کارڈ نہیں'),
              style: TextStyle(color: (c.profile?.cnic.isNotEmpty ?? false) ? p.textMuted : p.red, fontSize: 12),
            ),
          ]),
        ),
        TextButton(onPressed: _pickCustomer, child: Text(Loc.t('Change', 'بدلیں'))),
      ]),
    );
  }

  Widget _guarantorCard(AppPalette p) {
    final c = _customer!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: instCard(p),
      child: Column(children: [
        if (_guarantors.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, color: p.red),
              const SizedBox(width: 8),
              Expanded(child: Text(Loc.t('This customer has no guarantor.', 'اس کسٹمر کا کوئی ضامن نہیں۔'), style: TextStyle(color: p.textDark))),
            ]),
          ),
        for (final g in _guarantors)
          CheckboxListTile(
            value: _gSel.contains(g.id),
            onChanged: (v) => setState(() => v == true ? _gSel.add(g.id!) : _gSel.remove(g.id)),
            secondary: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => InstGuarantorFormScreen(customerId: c.id, existing: g)));
                await _reloadCustomer();
              },
              child: KycAvatar(owner: 'g', id: g.id!, name: g.name),
            ),
            title: Text(g.name),
            subtitle: Text(
              [
                if (g.relation.isNotEmpty) g.relation,
                if (KycPhotoStore.instance.pathFor('g', g.id!, KycPhotoStore.photo) == null) Loc.t('no photo — tap picture', 'تصویر نہیں — تصویر دبائیں'),
              ].join('  •  '),
              style: TextStyle(
                  color: KycPhotoStore.instance.pathFor('g', g.id!, KycPhotoStore.photo) == null ? p.red : p.textMuted, fontSize: 12),
            ),
          ),
        TextButton.icon(
          icon: const Icon(Icons.person_add_alt),
          label: Text(Loc.t('Add guarantor (with photo)', 'ضامن شامل کریں (تصویر کے ساتھ)')),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstGuarantorFormScreen(customerId: c.id)));
            await _reloadCustomer();
          },
        ),
      ]),
    );
  }

  Widget _itemCard(AppPalette p) {
    final it = _item;
    if (it == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        icon: const Icon(Icons.inventory_2_outlined),
        label: Text(Loc.t('Choose item from stock', 'اسٹاک سے سامان چنیں')),
        onPressed: _pickItem,
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: instCard(p),
      child: Row(children: [
        Icon(Icons.inventory_2_outlined, color: p.blue, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title.isEmpty ? it.model : it.title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
            if (it.primaryId.isNotEmpty) Text(it.primaryId, style: TextStyle(color: p.textMuted, fontSize: 12)),
            if (Session.isAdminOrManager && it.costPrice > 0)
              Text('${Loc.t('Cost', 'لاگت')} ${instRs(it.costPrice)}', style: TextStyle(color: p.textMuted, fontSize: 11.5)),
          ]),
        ),
        TextButton(onPressed: _pickItem, child: Text(Loc.t('Change', 'بدلیں'))),
      ]),
    );
  }

  Widget _summary(AppPalette p, PlanQuote? q, String? err) {
    if (q == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Text(err ?? '', style: TextStyle(color: p.textMuted)),
      );
    }
    Widget line(String a, String b, {Color? c, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: p.textMuted))),
            Text(b, style: TextStyle(color: c ?? p.textDark, fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : 14)),
          ]),
        );
    final cost = _item?.costPrice ?? 0;
    final dates = [for (var i = 0; i < q.count; i++) dueDateOf(_firstDue, _freq, i)];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: instCard(p),
      child: Column(children: [
        line(Loc.t('Cash price', 'نقد قیمت'), instRs(q.cashPrice)),
        line(Loc.t('Advance', 'ایڈوانس'), instRs(q.advance)),
        line(Loc.t('Remaining', 'باقی'), instRs(q.financed)),
        line(Loc.t('Profit', 'منافع'), '+ ${instRs(q.profit)}', c: p.teal),
        const Divider(),
        line(Loc.t('Total installment price', 'کل قسط قیمت'), instRs(q.totalPrice), bold: true),
        line(Loc.t('To pay in installments', 'قسطوں میں'), instRs(q.installmentTotal)),
        const Divider(),
        line('${q.count} × ${Loc.t('installment', 'قسط')}', instRs(q.each), c: p.navy, bold: true),
        if (q.last != q.each) line(Loc.t('Last installment', 'آخری قسط'), instRs(q.last)),
        line(Loc.t('First / last date', 'پہلی / آخری تاریخ'), '${_d(dates.first)}  →  ${_d(dates.last)}'),
        if (Session.isAdminOrManager && cost > 0) ...[
          const Divider(),
          line(Loc.t('Total profit on cost', 'لاگت پر کل منافع'), instRs(q.totalPrice - cost),
              c: q.totalPrice >= cost ? p.teal : p.red),
        ],
      ]),
    );
  }
}

/// Search wali list (customer / item chunne ke liye). "Naya" dabane par [addNew] wapas.
class _PickerSheet<T> extends StatefulWidget {
  static const addNew = '__add_new__';
  final String title;
  final List<T> items;
  final bool Function(T, String) matches;
  final Widget Function(T) tile;
  final String addLabel;
  const _PickerSheet({super.key, required this.title, required this.items, required this.matches, required this.tile, required this.addLabel});

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final list = widget.items.where((e) => widget.matches(e, _q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 17))),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(widget.addLabel),
                  onPressed: () => Navigator.pop(context, _PickerSheet.addNew),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: instDeco(p, Loc.t('Search', 'تلاش'), suffix: const Icon(Icons.search)),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(Loc.t('Nothing found.', 'کچھ نہیں ملا۔'), style: TextStyle(color: p.textMuted)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => InkWell(onTap: () => Navigator.pop(context, list[i]), child: widget.tile(list[i])),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ===================================================================== plan detail

class InstPlanDetailScreen extends StatefulWidget {
  final int planId;
  const InstPlanDetailScreen({super.key, required this.planId});

  @override
  State<InstPlanDetailScreen> createState() => _InstPlanDetailScreenState();
}

class _InstPlanDetailScreenState extends State<InstPlanDetailScreen> {
  PlanView? _v;
  List<Guarantor> _g = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final v = await InstPlanRepository.instance.view(widget.planId);
    var g = const <Guarantor>[];
    if (v != null) {
      final all = await InstRepository.instance.guarantors(v.plan.customerId);
      g = all.where((x) => v.plan.guarantorIds.contains(x.id)).toList();
    }
    await KycPhotoStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _v = v;
      _g = g;
      _loaded = true;
    });
  }

  Future<String> _receipt(PlanView v, InstPayment pay) async {
    final shop = await loadShopHeader();
    // Payment ke waqt ka baqi: is payment ke baad wali qist-payments ko wapas jor kar.
    final later = v.payments
        .where((x) => x.kind == payInstallment && (x.paidAt > pay.paidAt || (x.paidAt == pay.paidAt && x.id > pay.id)))
        .fold<double>(0, (a, x) => a + x.amount);
    final remaining = v.status.remaining + later;
    final next = v.status.next;
    return receiptText(
      shopName: [shop.name, shop.phone].where((s) => s.isNotEmpty).join(' — '),
      planNo: v.plan.planNo,
      customerName: v.customerName,
      itemTitle: v.itemTitle,
      amount: pay.amount,
      fine: pay.fine,
      method: pay.method,
      paidAt: pay.paidAt,
      remaining: remaining,
      nextDue: later > 0 ? null : next?.dueDate,
      nextAmount: next?.remaining ?? 0,
      kind: pay.kind,
    );
  }

  /// Is payment ke foran baad kitna baqi tha (baad wali qist-payments wapas jor kar).
  double _remainingAfter(PlanView v, InstPayment pay) =>
      v.status.remaining +
      v.payments
          .where((x) => x.kind == payInstallment && (x.paidAt > pay.paidAt || (x.paidAt == pay.paidAt && x.id > pay.id)))
          .fold<double>(0, (a, x) => a + x.amount);

  Future<void> _sendReceipt(PlanView v, InstPayment pay) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(Loc.t('PDF receipt (with photo)', 'PDF رسید (تصویر کے ساتھ)')),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(Loc.t('Text message', 'سادہ میسج')),
            onTap: () => Navigator.pop(ctx, 'text'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'pdf') {
      await InstPdf.sendReceipt(context, v, pay, remainingAfter: _remainingAfter(v, pay));
      return;
    }
    final text = await _receipt(v, pay);
    if (!mounted) return;
    await sendOnWhatsApp(context, phone: v.customerPhone, text: text);
  }

  Future<void> _remind(PlanView v) => remindPlan(context, v);

  Future<void> _receive(PlanView v) async {
    final st = v.status;
    final today = dayStart(DateTime.now());
    final suggest = st.dueNow > 0.5 ? st.dueNow : (st.next?.remaining ?? st.remaining);
    final fine = suggestedFine(status: st, lateFee: v.plan.lateFee, graceDays: v.plan.graceDays, today: today, finesAlreadyTaken: v.finesTaken);
    final res = await showDialog<_ReceiveResult>(
      context: context,
      builder: (_) => _ReceiveDialog(defaultAmount: suggest, max: st.remaining, suggestedFine: fine),
    );
    if (res == null || !mounted) return;
    try {
      final payId = await InstPlanRepository.instance.receive(v.plan.id, amount: res.amount, fine: res.fine, method: res.method, note: res.note);
      await _reload();
      if (!mounted) return;
      final fresh = _v;
      final pay = fresh?.payments.where((x) => x.id == payId).firstOrNull;
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(Loc.t('Received', 'وصول ہو گیا')),
          content: Text('${instRs(res.amount + res.fine)}\n${Loc.t('Remaining', 'باقی')}: ${instRs(fresh?.status.remaining ?? 0)}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Close', 'بند'))),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send),
              label: Text(Loc.t('WhatsApp receipt', 'واٹس ایپ رسید')),
            ),
          ],
        ),
      );
      if (send == true && fresh != null && pay != null && mounted) await _sendReceipt(fresh, pay);
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _deletePayment(InstPayment pay) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Remove this payment?', 'یہ وصولی ہٹائیں؟')),
        content: Text('${instRs(pay.amount + pay.fine)} — ${_dt(pay.paidAt)}\n${Loc.t('Its cash entry will also be removed.', 'اس کی کیش انٹری بھی ہٹ جائے گی۔')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Remove', 'ہٹائیں'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InstPlanRepository.instance.deletePayment(pay);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _menu(String action, PlanView v) async {
    if (action == 'repossess') {
      final note = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(Loc.t('Take item back?', 'سامان واپس لیں؟')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(Loc.t('Plan will close. Money already received stays in record.', 'پلان بند ہو جائے گا۔ وصول شدہ رقم ریکارڈ میں رہے گی۔')),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(hintText: Loc.t('Reason / condition of item', 'وجہ / سامان کی حالت'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Take back', 'واپس لیں'))),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await InstPlanRepository.instance.repossess(v.plan.id, note: note.text);
        await _reload();
      } catch (e) {
        if (mounted) instToast(context, instErr(e));
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(Loc.t('Delete this plan?', 'یہ پلان حذف کریں؟')),
          content: Text(Loc.t('Only for a plan made by mistake. Item goes back to stock; the advance cash entry is removed.',
              'صرف غلطی سے بنا پلان۔ سامان اسٹاک میں واپس، ایڈوانس کی کیش انٹری ہٹ جائے گی۔')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Delete', 'حذف'))),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await InstPlanRepository.instance.deletePlan(v.plan.id);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) instToast(context, instErr(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final v = _v;
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: v != null && v.plan.isActive
          ? FloatingActionButton.extended(
              backgroundColor: p.teal,
              foregroundColor: Colors.white,
              onPressed: () => _receive(v),
              icon: const Icon(Icons.payments_outlined),
              label: Text(Loc.t('Receive Qist', 'قسط وصول کریں')),
            )
          : null,
      body: Column(children: [
        instHeader(
          context,
          p,
          v == null ? Loc.t('Plan', 'پلان') : '${v.plan.planNo}  •  ${v.customerName}',
          v == null ? '' : planStatusLabel(v.plan.status),
          actions: [
            if (v != null && v.plan.isActive)
              IconButton(
                  tooltip: Loc.t('Send reminder', 'یاد دہانی بھیجیں'),
                  icon: const Icon(Icons.notifications_active_outlined, color: Colors.white),
                  onPressed: () => _remind(v)),
            if (v != null)
              IconButton(
                  tooltip: Loc.t('PDF statement', 'PDF اسٹیٹمنٹ'),
                  icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
                  onPressed: () => InstPdf.sendStatement(context, v)),
            if (v != null && (Session.isAdminOrManager))
              PopupMenuButton<String>(
                iconColor: Colors.white,
                onSelected: (a) => _menu(a, v),
                itemBuilder: (_) => [
                  if (v.plan.isActive) PopupMenuItem(value: 'repossess', child: Text(Loc.t('Take item back', 'سامان واپس لیں'))),
                  if (Session.isAdmin) PopupMenuItem(value: 'delete', child: Text(Loc.t('Delete plan (mistake)', 'پلان حذف (غلطی)'))),
                ],
              ),
          ],
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : v == null
                  ? Center(child: Text(Loc.t('Plan not found.', 'پلان نہیں ملا۔'), style: TextStyle(color: p.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
                        _people(p, v),
                        const SizedBox(height: 12),
                        _totals(p, v),
                        instSectionTitle(p, Loc.t('SCHEDULE', 'قسطوں کا شیڈول')),
                        Container(
                          decoration: instCard(p),
                          child: Column(children: [for (final l in v.status.lines) _line(p, l)]),
                        ),
                        instSectionTitle(p, Loc.t('PAYMENTS', 'وصولیاں')),
                        if (v.payments.isEmpty)
                          Text(Loc.t('No payment yet.', 'ابھی کوئی وصولی نہیں۔'), style: TextStyle(color: p.textMuted)),
                        for (final pay in v.payments) _payment(p, v, pay),
                        if (v.plan.note.isNotEmpty) ...[
                          instSectionTitle(p, Loc.t('NOTE', 'نوٹ')),
                          Text(v.plan.note, style: TextStyle(color: p.textDark)),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${Loc.t('Created', 'بنایا')} ${_dt(v.plan.createdAt)}${v.plan.createdBy.isNotEmpty ? ' • ${v.plan.createdBy}' : ''}',
                          style: TextStyle(color: p.textMuted, fontSize: 11),
                        ),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _people(AppPalette p, PlanView v) {
    final it = v.item;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: instCard(p, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PartyAvatar(
            isCustomer: true,
            partyId: v.plan.customerId,
            name: v.customerName,
            radius: 32,
            onTap: () async {
              await showPartyPhotoSheet(context, isCustomer: true, partyId: v.plan.customerId);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstCustomerDetailScreen(customerId: v.plan.customerId)));
                await _reload();
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.customerName, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 17)),
                if (v.customerPhone.isNotEmpty) Text(v.customerPhone, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
              ]),
            ),
          ),
          if (v.customerPhone.isNotEmpty)
            IconButton(
              icon: Icon(Icons.call_outlined, color: p.teal),
              onPressed: () async {
                try {
                  await launchUrl(Uri(scheme: 'tel', path: v.customerPhone.replaceAll(RegExp(r'[^0-9+]'), '')));
                } catch (_) {}
              },
            ),
        ]),
        const Divider(height: 22),
        Row(children: [
          Icon(Icons.inventory_2_outlined, color: p.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.itemTitle, style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
              if (it != null)
                for (final e in it.idValues.entries) Text('${e.key}: ${e.value}', style: TextStyle(color: p.textMuted, fontSize: 12)),
            ]),
          ),
        ]),
        if (_g.isNotEmpty) ...[
          const Divider(height: 22),
          Text(Loc.t('Guarantors', 'ضامن'), style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 10, children: [
            for (final g in _g)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => InstGuarantorFormScreen(customerId: v.plan.customerId, existing: g)));
                  await _reload();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  KycAvatar(owner: 'g', id: g.id!, name: g.name, radius: 22),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
                    if (g.phone.isNotEmpty) Text(g.phone, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                  ]),
                ]),
              ),
          ]),
        ] else if (v.plan.isActive) ...[
          const Divider(height: 22),
          Text(Loc.t('No guarantor on this plan', 'اس پلان پر کوئی ضامن نہیں'), style: TextStyle(color: p.red, fontSize: 12.5)),
        ],
      ]),
    );
  }

  Widget _totals(AppPalette p, PlanView v) {
    final st = v.status;
    Widget box(String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: instCard(p),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 17)),
              ),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        box(Loc.t('Total price', 'کل قیمت'), instRs(v.plan.totalPrice), p.textDark),
        const SizedBox(width: 10),
        box(Loc.t('Received', 'وصول'), instRs(st.paid + v.advancePaid), p.teal),
        const SizedBox(width: 10),
        box(Loc.t('Remaining', 'باقی'), instRs(st.remaining), p.navy),
      ]),
      if (v.plan.isActive && (st.overdue > 0.5 || st.next != null)) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (st.overdue > 0.5 ? p.red : p.teal).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(st.overdue > 0.5 ? Icons.warning_amber_rounded : Icons.event_available, color: st.overdue > 0.5 ? p.red : p.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                st.overdue > 0.5
                    ? Loc.t('Late: ${instRs(st.overdue)} (${st.overdueCount} qist, ${st.daysLate} days)',
                        'لیٹ: ${instRs(st.overdue)} (${st.overdueCount} قسط، ${st.daysLate} دن)')
                    : Loc.t('Next: ${instRs(st.next!.remaining)} on ${_d(st.next!.dueDate)}',
                        'اگلی: ${instRs(st.next!.remaining)} — ${_d(st.next!.dueDate)}'),
                style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        '${Loc.t('Cash', 'نقد')} ${instRs(v.plan.cashPrice)}  •  ${Loc.t('Advance', 'ایڈوانس')} ${instRs(v.plan.advance)}  •  '
        '${v.plan.count} × ${freqLabel(v.plan.frequency)}'
        '${v.finesTaken > 0 ? '  •  ${Loc.t('Fines', 'جرمانہ')} ${instRs(v.finesTaken)}' : ''}',
        style: TextStyle(color: p.textMuted, fontSize: 11.5),
      ),
      if (Session.isAdminOrManager && v.plan.costPrice > 0)
        Text(
          '${Loc.t('Profit', 'منافع')}: ${instRs(profitShare(collected: st.paid + v.advancePaid, totalPrice: v.plan.totalPrice, costPrice: v.plan.costPrice) ?? 0)}'
          ' ${Loc.t('received of', 'وصول، کل')} ${instRs(v.plan.totalPrice - v.plan.costPrice)}',
          style: TextStyle(color: p.textMuted, fontSize: 11.5),
        ),
    ]);
  }

  Widget _line(AppPalette p, ScheduleLine l) {
    final (Color c, String label) = switch (l.state) {
      InstallmentState.paid => (p.teal, Loc.t('Paid', 'ادا')),
      InstallmentState.partial => (p.amber, Loc.t('Part paid', 'کچھ ادا')),
      InstallmentState.dueToday => (p.amber, Loc.t('Today', 'آج')),
      InstallmentState.overdue => (p.red, Loc.t('Late', 'لیٹ')),
      InstallmentState.upcoming => (p.textMuted, Loc.t('Upcoming', 'آنے والی')),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withOpacity(0.6)))),
      child: Row(children: [
        SizedBox(width: 30, child: Text('${l.seq}', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold))),
        Expanded(child: Text(_d(l.dueDate), style: TextStyle(color: p.textDark))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(instRs(l.amount), style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
          if (l.paid > 0.5 && l.state != InstallmentState.paid)
            Text('${Loc.t('paid', 'ادا')} ${instRs(l.paid)}', style: TextStyle(color: p.textMuted, fontSize: 11)),
        ]),
        const SizedBox(width: 10),
        Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _payment(AppPalette p, PlanView v, InstPayment pay) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: instCard(p),
        child: Row(children: [
          Icon(pay.kind == payAdvance ? Icons.savings_outlined : Icons.payments_outlined, color: p.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${pay.kind == payAdvance ? Loc.t('Advance', 'ایڈوانس') : Loc.t('Qist', 'قسط')}  ${instRs(pay.amount)}'
                '${pay.fine > 0 ? '  + ${Loc.t('fine', 'جرمانہ')} ${instRs(pay.fine)}' : ''}',
                style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600),
              ),
              Text(
                '${_dt(pay.paidAt)}  •  ${pay.method == 'bank' ? Loc.t('Bank', 'بینک') : Loc.t('Cash', 'کیش')}'
                '${pay.receivedBy.isNotEmpty ? '  •  ${pay.receivedBy}' : ''}${pay.note.isNotEmpty ? '\n${pay.note}' : ''}',
                style: TextStyle(color: p.textMuted, fontSize: 11.5),
              ),
            ]),
          ),
          IconButton(
            tooltip: Loc.t('WhatsApp receipt', 'واٹس ایپ رسید'),
            icon: Icon(Icons.send_outlined, color: p.teal),
            onPressed: () => _sendReceipt(v, pay),
          ),
          if (Session.isAdminOrManager && pay.kind == payInstallment)
            IconButton(icon: Icon(Icons.delete_outline, color: p.textMuted), onPressed: () => _deletePayment(pay)),
        ]),
      );
}

// ===================================================================== receive dialog

class _ReceiveResult {
  final double amount;
  final double fine;
  final String method;
  final String note;
  const _ReceiveResult(this.amount, this.fine, this.method, this.note);
}

class _ReceiveDialog extends StatefulWidget {
  final double defaultAmount;
  final double max;
  final double suggestedFine;
  const _ReceiveDialog({required this.defaultAmount, required this.max, required this.suggestedFine});

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final _amount = TextEditingController(text: instPlain(widget.defaultAmount.clamp(0, widget.max).toDouble()));
  late final _fine = TextEditingController(text: widget.suggestedFine > 0 ? instPlain(widget.suggestedFine) : '');
  final _note = TextEditingController();
  String _method = 'cash';
  String? _error;

  void _ok() {
    final a = instParse(_amount.text);
    final f = instParse(_fine.text);
    if (a <= 0 && f <= 0) return setState(() => _error = Loc.t('Enter amount', 'رقم لکھیں'));
    if (a > widget.max + 0.5) return setState(() => _error = Loc.t('More than remaining (${instRs(widget.max)})', 'باقی (${instRs(widget.max)}) سے زیادہ'));
    Navigator.pop(context, _ReceiveResult(a, f, _method, _note.text));
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Text(Loc.t('Receive installment', 'قسط وصول کریں')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money,
            decoration: instDeco(p, Loc.t('Amount', 'رقم')),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${Loc.t('Remaining', 'باقی')}: ${instRs(widget.max)}', style: TextStyle(color: p.textMuted, fontSize: 11.5)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fine,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money,
            decoration: instDeco(p, Loc.t('Late fine (optional)', 'لیٹ جرمانہ (اختیاری)')),
          ),
          if (widget.suggestedFine > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${Loc.t('Suggested', 'تجویز')}: ${instRs(widget.suggestedFine)}', style: TextStyle(color: p.red, fontSize: 11.5)),
            ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش'))),
              ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک'))),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: p.red))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(Loc.t('Cancel', 'منسوخ'))),
        FilledButton(onPressed: _ok, child: Text(Loc.t('Receive', 'وصول'))),
      ],
    );
  }
}
