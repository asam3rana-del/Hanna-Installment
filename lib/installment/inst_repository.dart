import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../db/app_database.dart';
import '../db/party_repository.dart';
import '../models/party.dart';
import 'inst_models.dart';
import 'inst_sync.dart';

/// Hanna Installment ka data: customer profile (CNIC...), guarantor, category, item.
///
/// Customer ki asal row POS wali `customers` table mein [PartyRepository.saveCustomer] se banti hai — is tarah
/// customer ka ledger / payment / statement / sync sab pehle jaisa chalta hai. Yahan sirf izafi maloomat.
class InstRepository {
  InstRepository._() {
    // Doosre device se qist data aane par screens refresh.
    InstSync.onApplied = () => changes.value++;
  }
  static final InstRepository instance = InstRepository._();

  /// Kuch bhi badle to barhta hai — screens sun kar dobara load karti hain.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  int _now() => DateTime.now().millisecondsSinceEpoch;
  void _changed() => changes.value++;

  // ================================================================ customers

  /// Saare customers (POS wale bhi) + un ki profile + guarantor count. Naam ke hisaab se.
  Future<List<InstCustomerRow>> listCustomers() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id AS id, c.name AS name, c.phone AS phone,
             p.customerId AS pCustomerId, p.fatherName, p.cnic, p.phone2, p.address, p.occupation,
             p.workAddress, p.monthlyIncome, p.note, p.createdAt, p.updatedAt,
             (SELECT COUNT(*) FROM inst_guarantors g WHERE g.customerId = c.id) AS gCount
      FROM customers c
      LEFT JOIN customer_profiles p ON p.customerId = c.id
      WHERE c.kind = '' OR c.kind IS NULL
      ORDER BY c.name COLLATE NOCASE ASC
    ''');
    return [
      for (final r in rows)
        InstCustomerRow(
          id: (r['id'] as num).toInt(),
          name: (r['name'] as String?) ?? '',
          phone: (r['phone'] as String?) ?? '',
          profile: r['pCustomerId'] == null ? null : CustomerProfile.fromMap({...r, 'customerId': r['pCustomerId']}),
          guarantorCount: ((r['gCount'] as num?) ?? 0).toInt(),
        )
    ];
  }

  Future<Customer?> customer(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<CustomerProfile?> profile(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customer_profiles', where: 'customerId = ?', whereArgs: [customerId], limit: 1);
    return rows.isEmpty ? null : CustomerProfile.fromMap(rows.first);
  }

  /// Is CNIC wala koi aur customer? Mila to us ka naam. Khali CNIC => null.
  Future<String?> customerWithCnic(String cnic, {int? exceptCustomerId}) async {
    final d = cnicDigits(cnic);
    if (d.length != 13) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.name AS name, p.cnic AS cnic FROM customer_profiles p
      JOIN customers c ON c.id = p.customerId
      WHERE p.customerId != ? AND p.cnic != ''
    ''', [exceptCustomerId ?? -1]);
    for (final r in rows) {
      if (cnicDigits((r['cnic'] as String?) ?? '') == d) return (r['name'] as String?) ?? '';
    }
    return null;
  }

  /// Naya customer (POS `customers` row + profile). [ArgumentError] = galat input (message dikhayein).
  Future<int> addCustomer({required String name, required String phone, required CustomerProfile profile}) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Customer ka naam likhein.');
    _validateProfile(phone, profile);
    final dup = await customerWithCnic(profile.cnic);
    if (dup != null) throw ArgumentError('Ye CNIC pehle se "$dup" ke naam par darj hai.');
    final id = await PartyRepository.instance.saveCustomer(Customer(name: n, phone: phone.trim()));
    await _writeProfile(id, profile, isNew: true);
    _changed();
    return id;
  }

  Future<void> updateCustomer(Customer existing, {required String name, required String phone, required CustomerProfile profile}) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Customer ka naam likhein.');
    if (existing.id == null) throw ArgumentError('Customer nahi mila.');
    _validateProfile(phone, profile);
    final dup = await customerWithCnic(profile.cnic, exceptCustomerId: existing.id);
    if (dup != null) throw ArgumentError('Ye CNIC pehle se "$dup" ke naam par darj hai.');
    if (n != existing.name || phone.trim() != existing.phone) {
      await PartyRepository.instance.updateCustomer(existing.copyWith(name: n, phone: phone.trim()));
    }
    await _writeProfile(existing.id!, profile, isNew: false);
    _changed();
  }

  void _validateProfile(String phone, CustomerProfile p) {
    if (!phoneValid(phone)) throw ArgumentError('Phone number theek nahi (03xx xxxxxxx).');
    if (!phoneValid(p.phone2)) throw ArgumentError('Doosra phone number theek nahi (03xx xxxxxxx).');
    if (!cnicValid(p.cnic)) throw ArgumentError('CNIC ke poore 13 hindse likhein.');
  }

  Future<void> _writeProfile(int customerId, CustomerProfile p, {required bool isNew}) async {
    final db = await AppDatabase.instance.database;
    final now = _now();
    final old = isNew ? null : await profile(customerId);
    final row = CustomerProfile(
      customerId: customerId,
      fatherName: p.fatherName.trim(),
      cnic: p.cnic.trim().isEmpty ? '' : formatCnic(p.cnic),
      phone2: p.phone2.trim(),
      address: p.address.trim(),
      occupation: p.occupation.trim(),
      workAddress: p.workAddress.trim(),
      monthlyIncome: p.monthlyIncome < 0 ? 0 : p.monthlyIncome,
      note: p.note.trim(),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    ).toMap();
    await db.transaction((txn) async {
      if (old == null) {
        await txn.insert('customer_profiles', row);
      } else {
        await txn.update('customer_profiles', row, where: 'customerId = ?', whereArgs: [customerId]);
      }
      await InstSync.enqueueProfile(txn, customerId);
    });
  }

  // ================================================================ guarantors

  Future<List<Guarantor>> guarantors(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_guarantors', where: 'customerId = ?', whereArgs: [customerId], orderBy: 'id ASC');
    return rows.map(Guarantor.fromMap).toList();
  }

  /// Naya / purana guarantor save. Wapas: id.
  Future<int> saveGuarantor(Guarantor g) async {
    if (g.name.trim().isEmpty) throw ArgumentError('Guarantor ka naam likhein.');
    if (!phoneValid(g.phone)) throw ArgumentError('Guarantor ka phone number theek nahi (03xx xxxxxxx).');
    if (!cnicValid(g.cnic)) throw ArgumentError('Guarantor ki CNIC ke poore 13 hindse likhein.');
    final db = await AppDatabase.instance.database;
    // Customer khud apna zamin nahi ho sakta.
    final own = await profile(g.customerId);
    if (own != null && cnicDigits(g.cnic).length == 13 && cnicDigits(own.cnic) == cnicDigits(g.cnic)) {
      throw ArgumentError('Guarantor ki CNIC customer ki apni CNIC hai — koi aur banda chunein.');
    }
    final now = _now();
    final row = Guarantor(
      id: g.id,
      customerId: g.customerId,
      name: g.name.trim(),
      fatherName: g.fatherName.trim(),
      cnic: g.cnic.trim().isEmpty ? '' : formatCnic(g.cnic),
      phone: g.phone.trim(),
      address: g.address.trim(),
      relation: g.relation.trim(),
      occupation: g.occupation.trim(),
      createdAt: g.createdAt == 0 ? now : g.createdAt,
      updatedAt: now,
    ).toMap();
    final id = await db.transaction((txn) async {
      int id;
      if (g.id == null) {
        id = await txn.insert('inst_guarantors', row..remove('id'));
      } else {
        await txn.update('inst_guarantors', row, where: 'id = ?', whereArgs: [g.id]);
        id = g.id!;
      }
      await InstSync.enqueueGuarantor(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  Future<void> deleteGuarantor(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instGuarantorType, 'inst_guarantors', 'id', id);
      await txn.delete('inst_guarantors', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  /// Ye CNIC kitne customers ka zamin hai (ek banda bohat logon ka zamin ho to khatra). Customer naam wapas.
  Future<List<String>> guaranteesByCnic(String cnic, {int? exceptGuarantorId}) async {
    final d = cnicDigits(cnic);
    if (d.length != 13) return const [];
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT g.id AS id, g.cnic AS cnic, c.name AS name FROM inst_guarantors g
      JOIN customers c ON c.id = g.customerId WHERE g.cnic != ''
    ''');
    return [
      for (final r in rows)
        if ((r['id'] as num).toInt() != (exceptGuarantorId ?? -1) && cnicDigits((r['cnic'] as String?) ?? '') == d)
          (r['name'] as String?) ?? ''
    ];
  }

  // ================================================================ categories

  Future<List<InstCategory>> categories() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_categories', orderBy: 'sortOrder ASC, name COLLATE NOCASE ASC');
    return rows.map(InstCategory.fromMap).toList();
  }

  Future<int> saveCategory(InstCategory c) async {
    final name = c.name.trim();
    if (name.isEmpty) throw ArgumentError('Category ka naam likhein.');
    final db = await AppDatabase.instance.database;
    final clash = await db.rawQuery(
        'SELECT id FROM inst_categories WHERE LOWER(TRIM(name)) = ? AND id != ? LIMIT 1', [name.toLowerCase(), c.id ?? -1]);
    if (clash.isNotEmpty) throw ArgumentError('"$name" naam ki category pehle se hai.');
    final now = _now();
    final id = await db.transaction((txn) async {
      int id;
      if (c.id == null) {
        final maxOrder = Sqflite.firstIntValue(await txn.rawQuery('SELECT COALESCE(MAX(sortOrder), 0) FROM inst_categories')) ?? 0;
        id = await txn.insert(
            'inst_categories',
            InstCategory(name: name, idFields: c.idFields, sortOrder: maxOrder + 1, createdAt: now, updatedAt: now).toMap()
              ..remove('id'));
      } else {
        await txn.update('inst_categories', c.copyWith(name: name, updatedAt: now).toMap(), where: 'id = ?', whereArgs: [c.id]);
        id = c.id!;
      }
      await InstSync.enqueueCategory(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  /// Is category mein saman ho to delete nahi (pehle saman doosri category mein karein).
  Future<void> deleteCategory(int id) async {
    final db = await AppDatabase.instance.database;
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_items WHERE categoryId = ?', [id])) ?? 0;
    if (n > 0) throw ArgumentError('Is category mein $n saman hai — pehle us ko hatayein ya category badlein.');
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instCategoryType, 'inst_categories', 'id', id);
      await txn.delete('inst_categories', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  // ================================================================ items

  Future<List<InstItem>> items({int? categoryId, String? status}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (categoryId != null) {
      where.add('categoryId = ?');
      args.add(categoryId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    final rows = await db.query('inst_items',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'createdAt DESC');
    return rows.map(InstItem.fromMap).toList();
  }

  /// Naya / purana piece save. Ek hi IMEI / serial do pieces par nahi (duplicate => [ArgumentError]).
  Future<int> saveItem(InstItem item) async {
    if (item.model.trim().isEmpty) throw ArgumentError('Model / naam likhein.');
    if (item.cashPrice < 0 || item.costPrice < 0) throw ArgumentError('Qeemat minus nahi ho sakti.');
    final db = await AppDatabase.instance.database;
    final cat = await db.query('inst_categories', where: 'id = ?', whereArgs: [item.categoryId], limit: 1);
    if (cat.isEmpty) throw ArgumentError('Category chunein.');
    final dup = findDuplicateId(item, await items());
    if (dup != null) throw ArgumentError('$dup pehle se kisi aur piece par darj hai.');
    final now = _now();
    final clean = item.copyWith(
      brand: item.brand.trim(),
      model: item.model.trim(),
      color: item.color.trim(),
      supplier: item.supplier.trim(),
      note: item.note.trim(),
      idValues: {
        for (final e in item.idValues.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim()
      },
      updatedAt: now,
    );
    final id = await db.transaction((txn) async {
      int id;
      if (item.id == null) {
        id = await txn.insert('inst_items', clean.toMap()..remove('id')..['createdAt'] = now);
      } else {
        await txn.update('inst_items', clean.toMap(), where: 'id = ?', whereArgs: [item.id]);
        id = item.id!;
      }
      await InstSync.enqueueItem(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  /// Sirf stock wala piece delete (bika hua piece qist ke record ka hissa hai).
  Future<void> deleteItem(InstItem item) async {
    if (item.id == null) return;
    if (!item.inStock) throw ArgumentError('Ye piece stock mein nahi (bik chuka / wapas) — delete nahi ho sakta.');
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instItemType, 'inst_items', 'id', item.id!);
      await txn.delete('inst_items', where: 'id = ?', whereArgs: [item.id]);
    });
    _changed();
  }

  // ================================================================ home stats

  Future<InstHomeStats> homeStats() async {
    final db = await AppDatabase.instance.database;
    int count(List<Map<String, Object?>> r) => ((r.first.values.first as num?) ?? 0).toInt();
    double sum(List<Map<String, Object?>> r) => ((r.first.values.first as num?) ?? 0).toDouble();
    final customers = count(await db.rawQuery("SELECT COUNT(*) FROM customers WHERE kind = '' OR kind IS NULL"));
    final inStock = count(await db.rawQuery("SELECT COUNT(*) FROM inst_items WHERE status = 'in_stock'"));
    final stockValue = sum(await db.rawQuery("SELECT COALESCE(SUM(costPrice), 0) FROM inst_items WHERE status = 'in_stock'"));
    final noGuarantor = count(await db.rawQuery('''
      SELECT COUNT(*) FROM customer_profiles p
      WHERE NOT EXISTS (SELECT 1 FROM inst_guarantors g WHERE g.customerId = p.customerId)
    '''));
    return InstHomeStats(customers: customers, itemsInStock: inStock, stockCostValue: stockValue, profilesWithoutGuarantor: noGuarantor);
  }
}

class InstHomeStats {
  final int customers;
  final int itemsInStock;
  final double stockCostValue;
  final int profilesWithoutGuarantor;
  const InstHomeStats({
    this.customers = 0,
    this.itemsInStock = 0,
    this.stockCostValue = 0,
    this.profilesWithoutGuarantor = 0,
  });
}
