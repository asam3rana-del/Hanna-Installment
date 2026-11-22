import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

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
