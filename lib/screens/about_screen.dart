import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../utils/loc.dart';

/// About / Privacy / Support — Play Store policy: privacy policy ka link app ke andar bhi hona chahiye,
/// aur data delete karwane ka tareeqa.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Loc.t('Could not open: $uri', 'نہیں کھل سکا: $uri'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final build = AppInfo.build.isEmpty ? '' : ' (build ${AppInfo.build})';
    return Scaffold(
      appBar: AppBar(title: Text(Loc.t('About', 'ایپ کے بارے میں'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/images/logo.png', width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.apps, size: 56)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppInfo.appName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(Loc.t('Installment shop management', 'قسط کی دکان کا انتظام'),
                      style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 3),
                  Text('${AppInfo.business} · ${AppInfo.developer}',
                      style: const TextStyle(color: Color(0xFFB8901F), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(AppInfo.address, style: Theme.of(context).textTheme.bodySmall),
                  Text('${AppInfo.appId}$build', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(Loc.t('Privacy Policy', 'پرائیویسی پالیسی')),
          subtitle: const Text(AppInfo.privacyPolicyUrl),
          onTap: () => _open(context, Uri.parse(AppInfo.privacyPolicyUrl)),
        ),
        ListTile(
          leading: const Icon(Icons.chat_outlined),
          title: Text(Loc.t('WhatsApp support', 'واٹس ایپ سپورٹ')),
          subtitle: const Text(AppInfo.supportPhone),
          onTap: () => _open(context, Uri.parse('https://wa.me/${AppInfo.supportWhatsAppIntl}')),
        ),
        ListTile(
          leading: const Icon(Icons.call_outlined),
          title: Text(Loc.t('Call support', 'سپورٹ کو کال')),
          subtitle: const Text(AppInfo.supportPhone),
          onTap: () => _open(context, Uri(scheme: 'tel', path: AppInfo.supportPhone)),
        ),
        ListTile(
          leading: const Icon(Icons.email_outlined),
          title: Text(Loc.t('Email support', 'ای میل سپورٹ')),
          subtitle: const Text(AppInfo.supportEmail),
          onTap: () => _open(context, Uri(scheme: 'mailto', path: AppInfo.supportEmail, query: 'subject=Hanna Installment support')),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined),
          title: Text(Loc.t('Delete my data', 'میرا ڈیٹا ختم کریں')),
          subtitle: Text(Loc.t(
            'Records can be deleted inside the app. To delete your shop\'s cloud data or a staff account, '
                'message us from the owner\'s number with your shop / branch name — done within 30 days.',
            'ریکارڈ ایپ کے اندر حذف کیے جا سکتے ہیں۔ کلاؤڈ ڈیٹا یا اسٹاف اکاؤنٹ ختم کروانے کے لیے مالک کے نمبر سے '
                'دکان / برانچ کے نام کے ساتھ رابطہ کریں — 30 دن کے اندر ختم کر دیا جائے گا۔',
          )),
          isThreeLine: true,
          onTap: () => _open(
            context,
            Uri(scheme: 'mailto', path: AppInfo.supportEmail, query: 'subject=Hanna Installment - delete my data'),
          ),
        ),
      ]),
    );
  }
}
