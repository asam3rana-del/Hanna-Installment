import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_terms.dart';
import 'inst_ui.dart';
import 'kyc_photo_store.dart';

/// Plan ke dastakhat KycPhotoStore mein: owner 'p', id = plan id.
const planSignCustomer = 'signC';
const planSignGuarantor = 'signG';

/// Anguthe ke nishan ki tasveer (kaghaz par siyahi se laga kar camera se): owner 'p', id = plan id.
const planThumbCustomer = 'thumbC';
const planThumbGuarantor = 'thumbG';

/// Anguthe ki tasveer lo: mobile par camera, PC par file. Cancel => null. (Chhoti: 900px, sync ke liye.)
Future<String?> pickThumbPhoto(BuildContext context) async {
  ImageSource src = ImageSource.gallery;
  if (KycPhotoStore.cameraAvailable) {
    final s = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(Loc.t('Camera', 'کیمرہ')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(Loc.t('Gallery', 'گیلری')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (s == null) return null;
    src = s;
  }
  return KycPhotoStore.pickTemp(src, maxSide: 900);
}

/// Anguthe ka khaana: tasveer ho to dikhata hai, warna "tasveer lein" button.
class ThumbPhotoTile extends StatelessWidget {
  final String label;
  final String? path;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  const ThumbPhotoTile({super.key, required this.label, required this.path, required this.onPick, this.onClear});

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final has = path != null && File(path!).existsSync();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: instCard(p),
      child: Row(children: [
        InkWell(
          onTap: onPick,
          child: Container(
            width: 72,
            height: 88,
            decoration: BoxDecoration(border: Border.all(color: p.textMuted, width: 1.2), borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: has
                ? Image.file(File(path!), fit: BoxFit.cover)
                : Icon(Icons.fingerprint, size: 40, color: p.textMuted),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                Loc.t('Put an ink thumb mark on paper, then take its photo. Optional.',
                    'کاغذ پر سیاہی سے انگوٹھا لگائیں، پھر اس کی تصویر لیں۔ اختیاری۔'),
                style: TextStyle(color: p.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.fingerprint, size: 18),
                label: Text(has ? Loc.t('Retake', 'دوبارہ لیں') : Loc.t('Thumb photo', 'انگوٹھے کی تصویر')),
              ),
              if (has && onClear != null)
                TextButton(onPressed: onClear, child: Text(Loc.t('Remove', 'ہٹائیں'))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Ungli / stylus se dastakhat (Step 32). Bina package: lakeeren yaad, PNG mein save.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Size size = Size.zero;

  bool get isEmpty => strokes.every((s) => s.length < 2);

  void start(Offset o) {
    strokes.add([o]);
    notifyListeners();
  }

  void add(Offset o) {
    if (strokes.isEmpty) return;
    strokes.last.add(o);
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  /// Safed pass-e-manzar par kaali lakeeren, temp folder mein PNG. Khali => null.
  Future<String?> toPngFile(String name) async {
    if (isEmpty || size.isEmpty) return null;
    const scale = 2.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(scale);
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _paintStrokes(c, strokes);
    final img = await rec.endRecording().toImage((size.width * scale).round(), (size.height * scale).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, '${name}_${DateTime.now().millisecondsSinceEpoch}.png'));
    await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return f.path;
  }
}

void _paintStrokes(Canvas c, List<List<Offset>> strokes) {
  final paint = Paint()
    ..color = const Color(0xFF111111)
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.length < 2) continue;
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (final o in s.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    c.drawPath(path, paint);
  }
}

class _SigPainter extends CustomPainter {
  final SignatureController ctrl;
  _SigPainter(this.ctrl) : super(repaint: ctrl);

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, ctrl.strokes);

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}

/// Dastakhat ka dabba: label, saaf karne ka button.
class SignaturePad extends StatelessWidget {
  final SignatureController controller;
  final String label;
  const SignaturePad({super.key, required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold))),
        TextButton.icon(
          onPressed: controller.clear,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(Loc.t('Clear', 'صاف کریں')),
        ),
      ]),
      Container(
        height: 170,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (ctx, box) {
          controller.size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => controller.start(d.localPosition),
            onPanUpdate: (d) => controller.add(d.localPosition),
            child: CustomPaint(painter: _SigPainter(controller), size: Size.infinite),
          );
        }),
      ),
    ]);
  }
}

/// Plan banne se pehle iqrar nama: khulasa + sharait + customer (aur zamin) ke dastakhat.
class AgreementSignResult {
  final String? customerSig;
  final String? guarantorSig;
  final String? customerThumb;
  final String? guarantorThumb;
  const AgreementSignResult(this.customerSig, this.guarantorSig, {this.customerThumb, this.guarantorThumb});
}

class InstAgreementSignScreen extends StatefulWidget {
  final String customerName;
  final String? guarantorName;
  final List<String> summary;
  const InstAgreementSignScreen({super.key, required this.customerName, this.guarantorName, required this.summary});

  @override
  State<InstAgreementSignScreen> createState() => _InstAgreementSignScreenState();
}

class _InstAgreementSignScreenState extends State<InstAgreementSignScreen> {
  final _c = SignatureController();
  final _g = SignatureController();
  List<String> _terms = const [];
  bool _busy = false;
  String? _thumbC;
  String? _thumbG;

  @override
  void initState() {
    super.initState();
    InstTerms.load().then((t) {
      if (mounted) setState(() => _terms = InstTerms.lines(t));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _g.dispose();
    super.dispose();
  }

  Future<void> _done(bool signed) async {
    if (_busy) return;
    // Dastakhat ya anguthe ki tasveer — dono mein se ek zaroori (un parh customer sirf angutha).
    if (signed && _c.isEmpty && _thumbC == null) {
      instToast(context, Loc.t('Customer signature or thumb photo is required.', 'کسٹمر کے دستخط یا انگوٹھے کی تصویر ضروری ہے۔'));
      return;
    }
    setState(() => _busy = true);
    final cs = signed && !_c.isEmpty ? await _c.toPngFile('sigC') : null;
    final gs = signed && widget.guarantorName != null && !_g.isEmpty ? await _g.toPngFile('sigG') : null;
    if (mounted) {
      Navigator.pop(
          context,
          AgreementSignResult(cs, gs,
              customerThumb: signed ? _thumbC : null, guarantorThumb: signed && widget.guarantorName != null ? _thumbG : null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Agreement', 'اقرار نامہ'), Loc.t('Read, then sign', 'پڑھیں، پھر دستخط کریں')),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: instCard(p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in widget.summary)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l, style: TextStyle(color: p.textDark))),
              ]),
            ),
            if (_terms.isNotEmpty) ...[
              instSectionTitle(p, Loc.t('TERMS', 'شرائط')),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: instCard(p),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final t in _terms)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(t, style: TextStyle(color: p.textDark, height: 1.5))),
                  const SizedBox(height: 6),
                  Text(Loc.t('I have read and accept the above terms.', 'میں نے اوپر دی گئی شرائط پڑھ کر قبول کیں۔'),
                      style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            SignaturePad(controller: _c, label: '${Loc.t('Customer signature', 'کسٹمر کے دستخط')}: ${widget.customerName}'),
            const SizedBox(height: 8),
            ThumbPhotoTile(
              label: '${Loc.t('Customer thumb', 'کسٹمر کا انگوٹھا')}: ${widget.customerName}',
              path: _thumbC,
              onPick: () async {
                final v = await pickThumbPhoto(context);
                if (v != null && mounted) setState(() => _thumbC = v);
              },
              onClear: () => setState(() => _thumbC = null),
            ),
            if (widget.guarantorName != null) ...[
              const SizedBox(height: 14),
              SignaturePad(controller: _g, label: '${Loc.t('Guarantor signature', 'ضامن کے دستخط')}: ${widget.guarantorName}'),
              const SizedBox(height: 8),
              ThumbPhotoTile(
                label: '${Loc.t('Guarantor thumb', 'ضامن کا انگوٹھا')}: ${widget.guarantorName}',
                path: _thumbG,
                onPick: () async {
                  final v = await pickThumbPhoto(context);
                  if (v != null && mounted) setState(() => _thumbG = v);
                },
                onClear: () => setState(() => _thumbG = null),
              ),
            ],
            const SizedBox(height: 20),
            instPrimaryButton(p, _busy ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Signed — create plan', 'دستخط ہو گئے — پلان بنائیں'),
                _busy ? null : () => _done(true),
                icon: Icons.draw_outlined),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _done(false),
              child: Text(Loc.t('Create without signature (sign on paper)', 'بغیر دستخط بنائیں (کاغذ پر دستخط)')),
            ),
          ]),
        ),
      ]),
    );
  }
}
