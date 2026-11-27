import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/user_repository.dart';

/// Dukaan ka apna logo (Step 31): receipt / plan PDF / reports ke upar. Is device ki app folder mein copy; setting
/// `shop_logo_path`. (Har device par ek dafa — tasveer cloud par nahi jati.)
class ShopLogo {
  ShopLogo._();
  static const _key = 'shop_logo_path';

  static Future<String?> path() async {
    try {
      final v = (await UserRepository.instance.getSetting(_key))?.trim() ?? '';
      if (v.isEmpty || !await File(v).exists()) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Gallery se chunein; chhota kar ke app folder mein. null = chuna nahi.
  static Future<String?> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 90);
    if (x == null) return null;
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'shop'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(x.path).toLowerCase();
    final dest = p.join(dir.path, 'logo_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}');
    await File(x.path).copy(dest);
    final old = await path();
    await UserRepository.instance.setSetting(_key, dest);
    if (old != null && old != dest) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    return dest;
  }

  static Future<void> remove() async {
    final old = await path();
    await UserRepository.instance.setSetting(_key, '');
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }
}

/// Dukaan ka online payment QR (JazzCash / Easypaisa / Raast / bank app se screenshot). Receipt aur statement par
/// "Scan to pay" ke saath chhapta hai. Setting `shop_pay_qr_path` — har device par ek dafa (logo ki tarah).
/// Paise aane par entry khud nahi hoti: dukaandar tasdeeq kar ke "Receive" dabaye.
class ShopPayQr {
  ShopPayQr._();
  static const _key = 'shop_pay_qr_path';

  static Future<String?> path() async {
    try {
      final v = (await UserRepository.instance.getSetting(_key))?.trim() ?? '';
      if (v.isEmpty || !await File(v).exists()) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Gallery se QR ki tasveer (screenshot). QR saaf rahe: 1000px, quality 95.
  static Future<String?> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000, maxHeight: 1000, imageQuality: 95);
    if (x == null) return null;
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'shop'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(x.path).toLowerCase();
    final dest = p.join(dir.path, 'payqr_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}');
    await File(x.path).copy(dest);
    final old = await path();
    await UserRepository.instance.setSetting(_key, dest);
    if (old != null && old != dest) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    return dest;
  }

  static Future<void> remove() async {
    final old = await path();
    await UserRepository.instance.setSetting(_key, '');
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }
}
