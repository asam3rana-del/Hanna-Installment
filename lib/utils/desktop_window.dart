import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PC (Windows): app band karte waqt window jitni bari / jahan thi (ya maximize), agli dafa wahin khule.
///
/// Koi naya package nahi — Windows ke user32.dll ke `GetWindowPlacement` / `SetWindowPlacement` (dart:ffi).
/// Har 3 second jagah dekh kar badli ho to SharedPreferences mein; shuru mein (pehle frame ke baad) wapas.
/// Purani jagah kisi screen par na ho (doosra monitor hata diya) to kuch nahi badalta.
class DesktopWindow {
  DesktopWindow._();

  static const _key = 'desktop_window_placement';
  static Timer? _timer;
  static String _last = '';

  static void init() {
    if (!Platform.isWindows) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _restore();
      } catch (_) {}
      _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => _save());
    });
  }

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final _findWindowEx = _user32.lookupFunction<IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
  static final _getPid = _user32
      .lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  static final _getPlacement = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<_WindowPlacement>),
      int Function(int, Pointer<_WindowPlacement>)>('GetWindowPlacement');
  static final _setPlacement = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<_WindowPlacement>),
      int Function(int, Pointer<_WindowPlacement>)>('SetWindowPlacement');
  static final _monitorFromRect =
      _user32.lookupFunction<IntPtr Function(Pointer<_Rect>, Uint32), int Function(Pointer<_Rect>, int)>('MonitorFromRect');

  /// Is process ki Flutter window.
  static int _hwnd() {
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final pidOut = calloc<Uint32>();
    try {
      var h = 0;
      for (var i = 0; i < 50; i++) {
        h = _findWindowEx(0, h, cls, nullptr);
        if (h == 0) return 0;
        _getPid(h, pidOut);
        if (pidOut.value == pid) return h;
      }
      return 0;
    } finally {
      calloc.free(cls);
      calloc.free(pidOut);
    }
  }

  static void _save() {
    try {
      final h = _hwnd();
      if (h == 0) return;
      final wp = calloc<_WindowPlacement>();
      try {
        wp.ref.length = sizeOf<_WindowPlacement>();
        if (_getPlacement(h, wp) == 0) return;
        final r = wp.ref.rcNormalPosition;
        final show = wp.ref.showCmd == 3 ? 3 : 1; // maximize yaad; minimize ko normal
        final s = '$show,${r.left},${r.top},${r.right},${r.bottom}';
        if (s == _last) return;
        _last = s;
        SharedPreferences.getInstance().then((p) => p.setString(_key, s));
      } finally {
        calloc.free(wp);
      }
    } catch (_) {}
  }

  static Future<void> _restore() async {
    final s = (await SharedPreferences.getInstance()).getString(_key);
    if (s == null) return;
    final v = s.split(',').map(int.tryParse).toList();
    if (v.length != 5 || v.any((x) => x == null)) return;
    final show = v[0]!, l = v[1]!, t = v[2]!, r = v[3]!, b = v[4]!;
    if (r - l < 600 || b - t < 400) return;
    final h = _hwnd();
    if (h == 0) return;
    final rect = calloc<_Rect>();
    final wp = calloc<_WindowPlacement>();
    try {
      rect.ref
        ..left = l
        ..top = t
        ..right = r
        ..bottom = b;
      if (_monitorFromRect(rect, 0 /* MONITOR_DEFAULTTONULL */) == 0) return; // ab woh screen nahi
      wp.ref.length = sizeOf<_WindowPlacement>();
      if (_getPlacement(h, wp) == 0) return;
      wp.ref
        ..flags = 0
        ..showCmd = show == 3 ? 3 : 1
        ..rcNormalPosition.left = l
        ..rcNormalPosition.top = t
        ..rcNormalPosition.right = r
        ..rcNormalPosition.bottom = b;
      _setPlacement(h, wp);
      _last = s;
    } finally {
      calloc.free(rect);
      calloc.free(wp);
    }
  }
}

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _WindowPlacement extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int flags;
  @Uint32()
  external int showCmd;
  external _Point ptMinPosition;
  external _Point ptMaxPosition;
  external _Rect rcNormalPosition;
}
