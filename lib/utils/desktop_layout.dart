import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// PC (Windows / Linux / Mac) par chal rahi hai?
bool get isDesktopApp => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Desktop par baqi screens beech mein 900 px tak rehti hain (form khinch kar ajeeb na lagein). Dashboard jab
/// samne ho to yeh `true` — frame poori chaurai deta hai taake PC wala dashboard (zyada columns) dikhe.
final ValueNotifier<bool> desktopWideScreen = ValueNotifier<bool>(false);

/// MaterialApp.navigatorObservers mein — dashboard (RouteAware) ko pata chale kab us ke upar nayi screen khuli / band hui.
/// Sirf PageRoute: dialog / bottom sheet khulne par dashboard chaura hi rehta hai.
final RouteObserver<PageRoute<dynamic>> desktopRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Build / dispose ke beech seedha value badalna Flutter mein mana hai — agle frame par.
void setDesktopWide(bool wide) {
  if (!isDesktopApp || desktopWideScreen.value == wide) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => desktopWideScreen.value = wide);
}

/// PC par chauri window (sidebar ke baad bhi kaafi jagah) — do column wali screens isi se faisla karti hain.
bool isDesktopWide(BuildContext context) =>
    isDesktopApp && MediaQuery.sizeOf(context).width - (desktopNavItems.value != null ? DesktopShell.width : 0) >= 880;

/// PC par cards / options ko do columns mein (bayen 1, 3, 5... dayen 2, 4, 6...). Mobile par wahi list.
List<Widget> deskTwoCols(BuildContext context, List<Widget> items, {double gap = 16}) {
  if (!isDesktopWide(context) || items.length < 2) return items;
  final left = <Widget>[];
  final right = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    (i.isEven ? left : right).add(items[i]);
  }
  return [
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
      SizedBox(width: gap),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
    ]),
  ];
}

/// PC sidebar ka ek option.
class DesktopNavItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool bottom; // neeche alag (Settings / Logout)
  final bool danger;
  const DesktopNavItem(this.icon, this.label, this.onTap, {this.bottom = false, this.danger = false});
}

/// Login ke baad dashboard yeh list bharta hai (logout par null) — null ho to sidebar nahi.
final ValueNotifier<List<DesktopNavItem>?> desktopNavItems = ValueNotifier<List<DesktopNavItem>?>(null);
final ValueNotifier<int> desktopNavSelected = ValueNotifier<int>(0);

/// Sidebar ke upar naam (dukaan ka naam set ho to wahi).
final ValueNotifier<String> desktopNavTitle = ValueNotifier<String>('');

/// Jis dashboard ne sidebar lagaya. Zabaan / theme badalne par naya dashboard pehle banta hai aur purana baad mein
/// band hota hai — purana sirf apna hi lagaya hua menu hataye, naye wala nahi.
Object? _navOwner;

void setDesktopNav(List<DesktopNavItem>? items, {required Object owner}) {
  if (!isDesktopApp) return;
  if (items != null) _navOwner = owner;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (items == null) {
      if (!identical(_navOwner, owner)) return;
      _navOwner = null;
      desktopWideScreen.value = false;
    }
    desktopNavItems.value = items;
  });
}

void selectDesktopNav(int i) {
  if (!isDesktopApp) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => desktopNavSelected.value = i);
}

/// PC: bayen taraf hamesha nazar aane wala menu (har screen par) — mobile ki tarah wapas dashboard jana nahi parta.
/// MaterialApp.builder mein Navigator ke bahar lagta hai; [navy] / [ink] rang palette se.
class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key, required this.child, required this.navy, required this.title});
  final Widget child;
  final Color navy;
  final String title;

  static const double width = 232;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return child;
    return ValueListenableBuilder<List<DesktopNavItem>?>(
      valueListenable: desktopNavItems,
      child: child,
      builder: (context, items, c) {
        if (items == null || items.isEmpty || MediaQuery.sizeOf(context).width < 900) return c!;
        return Row(children: [
          SizedBox(width: width, child: _Sidebar(items: items, navy: navy, title: title)),
          Expanded(child: c!),
        ]);
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.navy, required this.title});
  final List<DesktopNavItem> items;
  final Color navy;
  final String title;

  Widget _item(int i, DesktopNavItem it, int selected) {
    final sel = i == selected;
    final fg = it.danger ? const Color(0xFFFF8A8A) : (sel ? Colors.white : Colors.white70);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: sel ? Colors.white.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            it.onTap(); // pehle (wapas dashboard + nayi screen), phir highlight — dashboard ka "0" is ke baad na aaye
            if (!it.danger) selectDesktopNav(i);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(it.icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 14, fontWeight: sel ? FontWeight.bold : FontWeight.w500)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = <(int, DesktopNavItem)>[];
    final bottom = <(int, DesktopNavItem)>[];
    for (var i = 0; i < items.length; i++) {
      (items[i].bottom ? bottom : top).add((i, items[i]));
    }
    return Material(
      color: navy,
      child: SafeArea(
        right: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([desktopNavSelected, desktopNavTitle]),
          builder: (context, _) {
           final selected = desktopNavSelected.value;
           return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: const Color(0xFF5B2A86), borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(desktopNavTitle.value.isNotEmpty ? desktopNavTitle.value : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
            ),
            Divider(color: Colors.white.withOpacity(0.12), height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [for (final (i, it) in top) _item(i, it, selected)]),
            ),
            if (bottom.isNotEmpty) ...[
              Divider(color: Colors.white.withOpacity(0.12), height: 1),
              const SizedBox(height: 6),
              for (final (i, it) in bottom) _item(i, it, selected),
              const SizedBox(height: 10),
            ],
          ]);
          },
        ),
      ),
    );
  }
}

/// PC par screen do hisson mein: [left] bayen, [right] dayen (har ek apni column). Mobile / patli window par
/// pehle left phir right (pehle jaisa). Forms aur detail screens ke liye.
/// [leftTail]: PC par bayen column ke neeche; mobile par sab se aakhir mein (mobile ki purani tarteeb qaim).
List<Widget> deskSplit(BuildContext context, List<Widget> left, List<Widget> right,
    {List<Widget> leftTail = const [], double gap = 20, int leftFlex = 1, int rightFlex = 1}) {
  if (!isDesktopWide(context)) return [...left, ...right, ...leftTail];
  return [
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: leftFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, ...leftTail])),
      SizedBox(width: gap),
      Expanded(flex: rightFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
    ]),
  ];
}

/// `ListView.builder` jaisa, magar PC par chaurai ke hisaab se 2-3 cards ek line mein (har card kam se kam
/// [minItemWidth]). Mobile par bilkul ListView.builder. RefreshIndicator ke andar bhi chalta hai.
class DeskListView extends StatelessWidget {
  const DeskListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.minItemWidth = 440,
    this.maxColumns = 3,
    this.gap = 12,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  final double minItemWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) {
      return ListView.builder(padding: padding, itemCount: itemCount, itemBuilder: itemBuilder);
    }
    return LayoutBuilder(builder: (context, cons) {
      final cols = (cons.maxWidth / minItemWidth).floor().clamp(1, maxColumns);
      if (cols <= 1) {
        return ListView.builder(padding: padding, itemCount: itemCount, itemBuilder: itemBuilder);
      }
      final rows = (itemCount + cols - 1) ~/ cols;
      return ListView.builder(
        padding: padding,
        itemCount: rows,
        itemBuilder: (context, r) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var j = 0; j < cols; j++) ...[
            if (j > 0) SizedBox(width: gap),
            Expanded(child: r * cols + j < itemCount ? itemBuilder(context, r * cols + j) : const SizedBox.shrink()),
          ],
        ]),
      );
    });
  }
}
