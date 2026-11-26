// Hanna Installment collections + sync heartbeat (branch_sync) under the LIVE firebase/firestore.rules,
// and the installment cashier limits under firebase/firestore.device-roles.rules. Emulator only.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs } from 'firebase/firestore';

const liveRules = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
const roleRules = readFileSync(new URL('../firestore.device-roles.rules', import.meta.url), 'utf8');

// Every installment collection the app syncs (lib/installment/inst_sync_names.dart).
const INST = ['inst_customer_profiles', 'inst_guarantors', 'inst_categories', 'inst_items', 'inst_plans', 'inst_payments',
  'inst_photos', 'inst_price_changes', 'inst_cash_sales', 'inst_suppliers', 'inst_purchases', 'inst_supplier_payments',
  'inst_purchase_returns', 'inst_customer_receipts'];

let live;
let roles;
before(async () => {
  live = await initializeTestEnvironment({ projectId: 'demo-ah-inst-live', firestore: { rules: liveRules, host: '127.0.0.1', port: 8080 } });
  roles = await initializeTestEnvironment({ projectId: 'demo-ah-inst-roles', firestore: { rules: roleRules, host: '127.0.0.1', port: 8080 } });
});
after(async () => {
  await live.cleanup();
  await roles.cleanup();
});

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'branch_members/u1'), { branchId: 'b1' });
    await setDoc(doc(db, 'branch_members/u2'), { branchId: 'b2' });
    await setDoc(doc(db, 'branch_members/u-cash'), { branchId: 'b1', role: 'cashier' });
    await setDoc(doc(db, 'branch_members/u-mgr'), { branchId: 'b1', role: 'manager' });
    await setDoc(doc(db, 'branch_members/u-typo'), { branchId: 'b1', role: 'Cashier ' });
    await setDoc(doc(db, 'branch_members/u-unknown'), { branchId: 'b1', role: 'casher' });
    await setDoc(doc(db, 'branch_members/u-MGR'), { branchId: 'b1', role: ' Manager' });
    for (const c of INST) {
      await setDoc(doc(db, `${c}/own`), { branchId: 'b1', updatedAt: 1 });
      await setDoc(doc(db, `${c}/foreign`), { branchId: 'b2', updatedAt: 1 });
    }
    await setDoc(doc(db, 'inst_customer_receipts/r1'), {
      branchId: 'b1', serverId: 'inst_customer_receipt:T-1', customerServerId: 'customer:T-1', amount: 500, method: 'cash',
      note: '', receivedBy: 'asam', paidAt: 1, createdAt: 1, updatedAt: 1,
    });
    await setDoc(doc(db, 'branch_sync/b2'), { branchId: 'b2', at: 1, n: 1 });
    await setDoc(doc(db, 'inst_payments/p1'), { branchId: 'b1', serverId: 'inst_payment:T-1', kind: 'installment', amount: 5000, updatedAt: 1 });
    await setDoc(doc(db, 'inst_cash_sales/s1'), { branchId: 'b1', serverId: 'inst_cash_sale:T-1', price: 30000, updatedAt: 1 });
    await setDoc(doc(db, 'inst_plans/pl1'), { branchId: 'b1', serverId: 'inst_plan:T-1', status: 'active', installmentTotal: 52000, closedAt: 0, updatedAt: 1 });
    await setDoc(doc(db, 'inst_items/i1'), { branchId: 'b1', serverId: 'inst_item:T-1', status: 'in_stock', costPrice: 40000, cashPrice: 48000, updatedAt: 1 });
    await setDoc(doc(db, 'inst_customer_profiles/c1'), { branchId: 'b1', serverId: 'customer:T-1', cnic: '35202', openingBalance: 0, updatedAt: 1 });
  });
}
beforeEach(async () => {
  await seed(live);
  await seed(roles);
});

const liveAs = (uid) => live.authenticatedContext(uid).firestore();
const rolesAs = (uid) => roles.authenticatedContext(uid).firestore();

// ------------------------------------------------------------------ live rules: installment collections

test('every installment collection: own branch readable, other branch not', async () => {
  const db = liveAs('u1');
  for (const c of INST) {
    await assertSucceeds(getDoc(doc(db, `${c}/own`)));
    await assertFails(getDoc(doc(db, `${c}/foreign`)));
  }
});

test('every installment collection: pull query (branchId == own) works, other branch query fails', async () => {
  const db = liveAs('u1');
  for (const c of INST) {
    await assertSucceeds(getDocs(query(collection(db, c), where('branchId', '==', 'b1'))));
    await assertFails(getDocs(query(collection(db, c), where('branchId', '==', 'b2'))));
  }
});

test('every installment collection: create needs own branchId; missing / other branch rejected', async () => {
  const db = liveAs('u1');
  for (const c of INST) {
    await assertSucceeds(setDoc(doc(db, `${c}/new`), { branchId: 'b1', updatedAt: 2 }));
    await assertFails(setDoc(doc(db, `${c}/wrong`), { branchId: 'b2', updatedAt: 2 }));
    await assertFails(setDoc(doc(db, `${c}/none`), { updatedAt: 2 }));
  }
});

test('every installment collection: a record cannot be moved to another branch; foreign records untouchable', async () => {
  const db = liveAs('u1');
  for (const c of INST) {
    await assertSucceeds(updateDoc(doc(db, `${c}/own`), { updatedAt: 3 }));
    await assertFails(updateDoc(doc(db, `${c}/own`), { branchId: 'b2' }));
    await assertFails(updateDoc(doc(db, `${c}/foreign`), { updatedAt: 3 }));
    await assertFails(deleteDoc(doc(db, `${c}/foreign`)));
  }
});

test('unauthenticated and unprovisioned devices get nothing', async () => {
  const anon = live.unauthenticatedContext().firestore();
  const stranger = liveAs('not-a-member');
  for (const c of INST) {
    await assertFails(getDoc(doc(anon, `${c}/own`)));
    await assertFails(getDoc(doc(stranger, `${c}/own`)));
    await assertFails(setDoc(doc(stranger, `${c}/new`), { branchId: 'b1' }));
  }
});

test('sync push reads a not-yet-existing receipt before creating it (resource == null)', async () => {
  await assertSucceeds(getDoc(doc(liveAs('u1'), 'inst_customer_receipts/not-yet')));
  await assertFails(getDoc(doc(liveAs('not-a-member'), 'inst_customer_receipts/not-yet')));
});

// ------------------------------------------------------------------ live rules: branch_sync heartbeat

test('heartbeat: own branch read / write with exactly branchId, at, n', async () => {
  const db = liveAs('u1');
  await assertSucceeds(getDoc(doc(db, 'branch_sync/b1'))); // not yet there
  await assertSucceeds(setDoc(doc(db, 'branch_sync/b1'), { branchId: 'b1', at: 123, n: 7 }));
  await assertSucceeds(getDoc(doc(db, 'branch_sync/b1')));
  await assertSucceeds(setDoc(doc(db, 'branch_sync/b1'), { branchId: 'b1', at: 456, n: 8 }));
});

test('heartbeat: other branch, wrong branchId, extra fields are rejected', async () => {
  const db = liveAs('u1');
  await assertFails(getDoc(doc(db, 'branch_sync/b2')));
  await assertFails(setDoc(doc(db, 'branch_sync/b2'), { branchId: 'b2', at: 1, n: 1 }));
  await assertFails(setDoc(doc(db, 'branch_sync/b1'), { branchId: 'b2', at: 1, n: 1 }));
  await assertFails(setDoc(doc(db, 'branch_sync/b1'), { branchId: 'b1', at: 1, n: 1, extra: 'x' }));
  await assertFails(getDoc(doc(live.unauthenticatedContext().firestore(), 'branch_sync/b1')));
});

// ------------------------------------------------------------------ device-roles rules: installment cashier

test('roles: cashier can record a new old-balance receipt in own branch', async () => {
  const db = rolesAs('u-cash');
  await assertSucceeds(getDoc(doc(db, 'inst_customer_receipts/r1')));
  await assertSucceeds(setDoc(doc(db, 'inst_customer_receipts/r2'), {
    branchId: 'b1', serverId: 'inst_customer_receipt:T-2', customerServerId: 'customer:T-1', amount: 200, method: 'cash',
    note: '', receivedBy: 'cash', paidAt: 2, createdAt: 2, updatedAt: 2,
  }));
  await assertFails(setDoc(doc(db, 'inst_customer_receipts/r3'), { branchId: 'b2', amount: 1 }));
});

test('roles: cashier cannot change a receipt amount, only sync metadata; cannot delete or tombstone it', async () => {
  const db = rolesAs('u-cash');
  await assertFails(updateDoc(doc(db, 'inst_customer_receipts/r1'), { amount: 5 }));
  await assertFails(updateDoc(doc(db, 'inst_customer_receipts/r1'), { customerServerId: 'customer:T-9' }));
  await assertSucceeds(updateDoc(doc(db, 'inst_customer_receipts/r1'), { updatedAt: 9 }));
  await assertFails(updateDoc(doc(db, 'inst_customer_receipts/r1'), { _deleted: true, updatedAt: 10 }));
  await assertFails(deleteDoc(doc(db, 'inst_customer_receipts/r1')));
});

test('roles: cashier cannot touch supplier side (suppliers, purchases, supplier payments, purchase returns)', async () => {
  const db = rolesAs('u-cash');
  for (const c of ['inst_suppliers', 'inst_purchases', 'inst_supplier_payments', 'inst_purchase_returns']) {
    await assertFails(setDoc(doc(db, `${c}/new`), { branchId: 'b1', updatedAt: 2 }));
    await assertFails(updateDoc(doc(db, `${c}/own`), { updatedAt: 2 }));
  }
});

test('roles: manager keeps full access to receipts in own branch, never another branch', async () => {
  const db = rolesAs('u-mgr');
  await assertSucceeds(updateDoc(doc(db, 'inst_customer_receipts/r1'), { amount: 450 }));
  await assertSucceeds(updateDoc(doc(db, 'inst_customer_receipts/r1'), { _deleted: true }));
  await assertFails(getDoc(doc(db, 'inst_customer_receipts/foreign')));
});

test('roles: heartbeat works for every role in its own branch', async () => {
  for (const uid of ['u-cash', 'u-mgr']) {
    const db = rolesAs(uid);
    await assertSucceeds(setDoc(doc(db, 'branch_sync/b1'), { branchId: 'b1', at: 5, n: 5 }));
    await assertSucceeds(getDoc(doc(db, 'branch_sync/b1')));
    await assertFails(getDoc(doc(db, 'branch_sync/b2')));
  }
});

// ------------------------------------------------------------------ device-roles: cashier ke paise wale record

test('roles: cashier payment / naqd sale ki raqam nahi badal sakta, sirf sync meta', async () => {
  const db = rolesAs('u-cash');
  await assertFails(updateDoc(doc(db, 'inst_payments/p1'), { amount: 1 }));
  await assertSucceeds(updateDoc(doc(db, 'inst_payments/p1'), { updatedAt: 2, pushedAt: 2 }));
  await assertFails(updateDoc(doc(db, 'inst_cash_sales/s1'), { price: 1 }));
  await assertFails(updateDoc(doc(db, 'inst_cash_sales/s1'), { returnedAt: 5, refund: 30000 }));
  await assertSucceeds(updateDoc(doc(db, 'inst_cash_sales/s1'), { updatedAt: 2 }));
});

test('roles: cashier plan ko sirf "completed" kar sakta hai; raqam / repossessed nahi', async () => {
  const db = rolesAs('u-cash');
  await assertFails(updateDoc(doc(db, 'inst_plans/pl1'), { installmentTotal: 1 }));
  await assertFails(updateDoc(doc(db, 'inst_plans/pl1'), { status: 'repossessed' }));
  await assertSucceeds(updateDoc(doc(db, 'inst_plans/pl1'), { status: 'completed', closedAt: 9, updatedAt: 9 }));
});

test('roles: cashier piece ko sirf "sold" kar sakta hai; qeemat / stock wapsi nahi', async () => {
  const db = rolesAs('u-cash');
  await assertFails(updateDoc(doc(db, 'inst_items/i1'), { costPrice: 1 }));
  await assertFails(updateDoc(doc(db, 'inst_items/i1'), { cashPrice: 1, updatedAt: 2 }));
  await assertSucceeds(updateDoc(doc(db, 'inst_items/i1'), { status: 'sold', updatedAt: 2 }));
  await assertFails(updateDoc(doc(db, 'inst_items/i1'), { status: 'in_stock', updatedAt: 3 }));
});

test('roles: cashier customer ka purana baqi / block nahi badal sakta, baaqi profile haan', async () => {
  const db = rolesAs('u-cash');
  await assertFails(updateDoc(doc(db, 'inst_customer_profiles/c1'), { openingBalance: 50000 }));
  await assertFails(updateDoc(doc(db, 'inst_customer_profiles/c1'), { blockedReason: 'x', blockedAt: 1 }));
  await assertSucceeds(updateDoc(doc(db, 'inst_customer_profiles/c1'), { cnic: '35202-1234567-1', updatedAt: 2 }));
});

test('roles: cashier supplier side parh bhi nahi sakta (khareed qeemat / dena)', async () => {
  const db = rolesAs('u-cash');
  for (const c of ['inst_suppliers', 'inst_purchases', 'inst_supplier_payments', 'inst_purchase_returns']) {
    await assertFails(getDoc(doc(db, `${c}/own`)));
  }
  await assertSucceeds(getDoc(doc(db, 'inst_plans/own')));
});

test('roles: role ki spelling ghalat => cashier jaisi pabandi (fail-closed); " Manager" = manager', async () => {
  for (const uid of ['u-typo', 'u-unknown']) {
    const db = rolesAs(uid);
    await assertFails(updateDoc(doc(db, 'inst_payments/p1'), { amount: 1 }));
    await assertFails(getDoc(doc(db, 'inst_suppliers/own')));
  }
  const mgr = rolesAs('u-MGR');
  await assertSucceeds(updateDoc(doc(mgr, 'inst_payments/p1'), { amount: 4500 }));
  await assertSucceeds(getDoc(doc(mgr, 'inst_suppliers/own')));
});
