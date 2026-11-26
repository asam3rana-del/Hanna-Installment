import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tools/deploy_rules_live.sh ke andar rules ki do copies hain (Termux se deploy ke liye).
/// Rules file badle aur script purani reh jaye to deploy chupke se purani rules laga deta
/// (jaise inst_customer_receipts / branch_sync gayab). Ye test us farq ko pakadta hai.
void main() {
  List<String> heredocs(String script) {
    final out = <String>[];
    final lines = script.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains("<<'AHRULES_EOF'")) continue;
      final buf = <String>[];
      for (i++; i < lines.length && lines[i] != 'AHRULES_EOF'; i++) {
        buf.add(lines[i]);
      }
      out.add(buf.join('\n').trim());
    }
    return out;
  }

  test('deploy_rules_live.sh ki rules = firebase/*.rules', () {
    final docs = heredocs(File('tools/deploy_rules_live.sh').readAsStringSync());
    expect(docs, hasLength(2));
    expect(docs[0], File('firebase/firestore.rules').readAsStringSync().trim(),
        reason: 'rollback copy purani — script dobara banayein');
    expect(docs[1], File('firebase/firestore.device-roles.rules').readAsStringSync().trim(),
        reason: 'roles copy purani — script dobara banayein');
  });
}
