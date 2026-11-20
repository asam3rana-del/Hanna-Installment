import 'package:flutter/material.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_customers_screen.dart';
import 'inst_models.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

/// Dashboard ka search (Step 30): customer ka naam / CNIC / phone / khata no. likhte hi neeche nateeje; tap = customer
/// (sab plans, history). Customers ki list ek dafa parhte hain, data badle to dobara.
class InstHomeSearch extends StatefulWidget {
  const InstHomeSearch({super.key});

  @override
  State<InstHomeSearch> createState() => _InstHomeSearchState();
}

class _InstHomeSearchState extends State<InstHomeSearch> {
  final _q = TextEditingController();
  List<InstCustomerRow>? _all;

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_invalidate);
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_invalidate);
    _q.dispose();
    super.dispose();
  }

  void _invalidate() => _all = null;

  Future<void> _ensure() async {
    if (_all != null) return;
    final rows = await InstRepository.instance.listCustomers();
    if (mounted) setState(() => _all = rows);
  }

  Future<void> _open(InstCustomerRow c) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstCustomerDetailScreen(customerId: c.id)));
    if (mounted) setState(() => _q.clear());
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _q.text.trim();
    final all = _all;
    final hits = q.length < 2 || all == null ? const <InstCustomerRow>[] : all.where((c) => c.matches(q)).take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _q,
        textInputAction: TextInputAction.search,
        decoration: instDeco(p, Loc.t('Search customer: name, CNIC, phone, khata no.', 'کسٹمر تلاش: نام، شناختی کارڈ، فون، کھاتہ نمبر'),
            suffix: q.isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    tooltip: Loc.t('Clear', 'صاف'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _q.clear()),
                  )),
        onTap: _ensure,
        onChanged: (_) async {
          await _ensure();
          if (mounted) setState(() {});
        },
      ),
      if (q.length >= 2)
        Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: instCard(p),
          child: all == null
              ? const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
              : hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(Loc.t('No customer found.', 'کوئی کسٹمر نہیں ملا۔'), style: TextStyle(color: p.textMuted)),
                    )
                  : Column(children: [
                      for (final c in hits)
                        ListTile(
                          dense: true,
                          onTap: () => _open(c),
                          leading: Icon(
                            (c.profile?.isBlocked ?? false) ? Icons.block : Icons.person_outline,
                            color: (c.profile?.isBlocked ?? false) ? p.red : p.navy,
                          ),
                          title: Text(c.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            [
                              if (c.phone.isNotEmpty) c.phone,
                              if ((c.profile?.cnic ?? '').isNotEmpty) c.profile!.cnic,
                              if ((c.profile?.khataNo ?? '').isNotEmpty) '${Loc.t('Khata', 'کھاتہ')} ${c.profile!.khataNo}',
                            ].join('  •  '),
                            style: TextStyle(color: p.textMuted, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                    ]),
        ),
      const SizedBox(height: 14),
    ]);
  }
}
