import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/desktop_layout.dart';

/// PC (Windows) ki pakki cloud pehchan.
///
/// Masla: phone par Firebase ka anonymous login app band / khulne par yaad rehta hai, is liye Device ID
/// (UID) hamesha wahi. Windows par Firebase plugin ye login bharose se yaad nahi rakhta (ya der se bahal karta
/// hai) — app har dafa naya anonymous login karti thi aur har roz nayi Device ID ban jati thi, phir
/// `branch_members` mein purani ID hone se sync "permission-denied".
///
/// Hal: PC par Firebase ka Email / Password user. Console > Authentication mein ek dafa user banayein; us
/// ka UID kabhi nahi badalta (dobara install / naya PC bhi). Email + password yahan Windows Credential
/// Manager (flutter_secure_storage) mein rehte hain.
class PcCloudLogin {
  PcCloudLogin._();

  static bool get supported => isDesktopApp;

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _kEmail = 'pc_cloud_login.email';
  static const String _kPassword = 'pc_cloud_login.password';

  static Future<({String email, String password})?> get() async {
    if (!supported) return null;
    try {
      final email = (await _storage.read(key: _kEmail))?.trim() ?? '';
      final password = await _storage.read(key: _kPassword) ?? '';
      if (email.isEmpty || password.isEmpty) return null;
      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String email, String password) async {
    await _storage.write(key: _kEmail, value: email.trim());
    await _storage.write(key: _kPassword, value: password);
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _kEmail);
      await _storage.delete(key: _kPassword);
    } catch (_) {}
  }
}

/// Desktop par purana Firebase login app khulne ke thori der baad bahal hota hai — `currentUser` foran
/// null aata hai. Pehle event tak (zyada se zyada 3 second) ruko, taake bila wajah naya login na bane.
Future<User?> restoredFirebaseUser(FirebaseAuth auth) async {
  final now = auth.currentUser;
  if (now != null || !isDesktopApp) return now;
  try {
    return await auth.authStateChanges().first.timeout(const Duration(seconds: 3));
  } catch (_) {
    return auth.currentUser;
  }
}
