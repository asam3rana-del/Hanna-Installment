#!/data/data/com.termux/files/usr/bin/env bash
# Hanna Installment: LIVE Firestore rules — device roles (cashier server par roka jata hai).
#   bash /sdcard/Download/deploy_rules_live.sh            -> device-roles rules publish
#   bash /sdcard/Download/deploy_rules_live.sh rollback   -> purani (sirf branch) rules wapas
# Role na likha ho = admin (aaj jaisa). Sirf branch_members/{uid}.role = "cashier" wale devices par pabandi.
set -e
# NOTE: niche wali dono rules firebase/firestore.rules aur firebase/firestore.device-roles.rules ki hoo-ba-hoo
# copy hain. Rules file badlein to ye script bhi dobara banayein (test/rules_script_sync_test.dart CI mein pakadta hai).
MODE="${1:-roles}"
PROJECT="${2:-}"
# Hanna Installment: project ka naam LAZMI (POS ka live project my-grocery-pos-8a444 galti se na badle).
[ -n "$PROJECT" ] || { echo "Usage: bash deploy_rules_live.sh roles <installment-firebase-project-id>"; exit 1; }
[ "$PROJECT" != "my-grocery-pos-8a444" ] || { echo "Ye Hanna POS ka project hai — Installment ka naya project dein"; exit 1; }
command -v firebase >/dev/null 2>&1 || { echo "firebase CLI nahi mila"; exit 1; }
WORK="$HOME/ah_rules_deploy"
rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"
printf '{\n  "firestore": { "rules": "firestore.rules" }\n}\n' > firebase.json
if [ "$MODE" = "rollback" ]; then
cat > firestore.rules <<'AHRULES_EOF'
rules_version = '2';

// Baseline rules for the shared multi-branch Firestore project.
//
// What this enforces:
//   - Nobody unauthenticated can read or write anything (blocks the public-internet
//     default-deny gap that an empty/missing rules file would otherwise leave open).
//   - Every write to a synced collection must carry a non-empty "branchId" field that
//     matches the document's existing branchId (so a client can't silently switch a
//     record from one branch to another, and can't write a document with no branchId
//     at all going forward).
//   - A signed-in user may only read/create/update/delete documents whose branchId
//     matches THEIR OWN branch, per the server-side branch_members/{uid} mapping —
//     not whatever branchId their client's BuildConfig happens to send. This closes
//     the gap where a modified/rogue client could claim any branchId.
//   - branch_members/{uid} itself is never writable by clients (admin/console only),
//     so a user cannot grant themselves access to another branch.
//
// Setup required before deploying:
//   Create one document per staff member at branch_members/{uid} with the shape
//   { branchId: "dusri-branch" }, where {uid} is that user's Firebase Auth UID
//   (via Firebase console or a small admin script — NOT from the app itself).
service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    // The branch this signed-in user is provisioned for, per server-side mapping.
    function myBranchId() {
      return get(/databases/$(database)/documents/branch_members/$(request.auth.uid)).data.branchId;
    }

    function isMyBranch(branchId) {
      return isSignedIn()
          && exists(/databases/$(database)/documents/branch_members/$(request.auth.uid))
          && branchId == myBranchId();
    }

    // Reads of a document that does not exist yet (resource == null) must not error out:
    // the sync push reads each doc inside a transaction before creating it, and
    // resource.data.* on a missing doc makes the rule fail with PERMISSION_DENIED.
    // A provisioned member may read "nothing"; an existing doc must be in their branch.
    function canRead() {
      return isSignedIn()
          && exists(/databases/$(database)/documents/branch_members/$(request.auth.uid))
          && (resource == null || resource.data.branchId == myBranchId());
    }

    function hasBranchId() {
      return request.resource.data.branchId is string
          && request.resource.data.branchId.size() > 0;
    }

    function branchIdUnchanged() {
      return !resource.data.keys().hasAny(['branchId'])
          || request.resource.data.branchId == resource.data.branchId;
    }

    // FIX (missing collections — Zakat/Units/Categories/Returns/Stock/App Settings
    // couldn't actually sync): SyncApi.kt has synced these collections for a while
    // (see its class doc comment at the top of that file), but this allowlist was
    // never updated to match — so every push/pull for units, categories, zakat
    // years/payments, returns, stock_movements, and app_settings was being silently
    // rejected by these rules with PERMISSION_DENIED, even though the app-side sync
    // code for them was working correctly. Added here so they actually reach
    // Firestore like every other synced entity.
    function isSyncedCollection(collection) {
      return collection in ['customers', 'suppliers', 'products', 'users',
                             'sales', 'purchases', 'payments', 'expenses',
                             'cash_transactions', 'cash_register',
                             'units', 'categories', 'zakat_years', 'zakat_payments',
                             'returns', 'stock_movements', 'app_settings',
                             'shell_customers', 'shell_transactions', 'shop_empty_shell_log',
                             'workers', 'worker_attendance', 'worker_advances',
                             'worker_salary_payments', 'shop_rents', 'shop_rent_ledger',
                             'utility_bills', 'utility_bill_payments',
                             // Hanna Installment
                             'inst_customer_profiles', 'inst_guarantors', 'inst_categories', 'inst_items', 'inst_plans', 'inst_payments', 'inst_photos', 'inst_price_changes', 'inst_cash_sales', 'inst_suppliers', 'inst_purchases', 'inst_supplier_payments', 'inst_purchase_returns', 'inst_customer_receipts'];
    }

    // Server-side record of which branch each staff UID belongs to.
    // Clients can read only their own membership doc; never write.
    match /branch_members/{uid} {
      allow read: if isSignedIn() && request.auth.uid == uid;
      allow write: if false;
    }

    // Due Reminders follow-up log (collection due_followups): same branch rules as every
    // synced collection, plus field validation. due_followups is deliberately NOT in
    // isSyncedCollection() above — Firestore ORs matching rules, so leaving it there would
    // let the generic rule below bypass validFollowup().
    function validFollowup() {
      let d = request.resource.data;
      return hasBranchId()
          && d.method in ['whatsapp', 'call', 'visit', 'sms', 'note']
          && d.outcome in ['sent', 'paid', 'promised', 'partial',
                           'no_answer', 'refused', 'dispute', 'note']
          && (d.get('amount', null) == null || (d.amount is number && d.amount >= 0))
          && (d.get('promiseDate', null) == null || d.promiseDate is number)
          && (d.get('nextFollowUp', null) == null || d.nextFollowUp is number)
          && (!('note' in d) || d.note == null || (d.note is string && d.note.size() <= 500));
    }

    match /due_followups/{docId} {
      allow read: if canRead();
      allow create: if isMyBranch(request.resource.data.branchId) && validFollowup();
      allow update: if isMyBranch(resource.data.branchId)
                     && branchIdUnchanged() && validFollowup();
      allow delete: if isMyBranch(resource.data.branchId);
    }

    match /{collection}/{docId} {
      allow read: if isSyncedCollection(collection) && canRead();
      allow create: if isSignedIn() && isSyncedCollection(collection)
                     && hasBranchId() && isMyBranch(request.resource.data.branchId);
      allow update: if isSignedIn() && isSyncedCollection(collection)
                     && hasBranchId() && branchIdUnchanged()
                     && isMyBranch(resource.data.branchId);
      allow delete: if isSignedIn() && isSyncedCollection(collection)
                     && isMyBranch(resource.data.branchId);
    }

    // Sync heartbeat: har branch ka ek chhota document (branch_sync/{branchId}). Push karne wala device ise
    // badalta hai; baqi devices pehle sirf yahi parh kar dekhte hain ke poori pull ki zaroorat hai ya nahi
    // (Firestore ki daily read limit bachane ke liye). Sirf apni branch ka, sirf yahi teen fields.
    match /branch_sync/{bid} {
      allow read: if isMyBranch(bid);
      allow write: if isMyBranch(bid)
                   && request.resource.data.branchId == bid
                   && request.resource.data.keys().hasOnly(['branchId', 'at', 'n']);
    }

    // Crash reports: app ki ghalti (stack trace) developer ko — sirf banana, branch member device, chhota text,
    // apna uid. Padhna / badalna / mitana app se nahi (sirf Firebase console). lib/services/crash_reporter.dart.
    match /crash_reports/{docId} {
      allow create: if isSignedIn()
                    && exists(/databases/$(database)/documents/branch_members/$(request.auth.uid))
                    && request.resource.data.keys().hasOnly(['text', 'at', 'device', 'branchId', 'app', 'uid'])
                    && request.resource.data.text is string
                    && request.resource.data.text.size() <= 8000
                    && request.resource.data.uid == request.auth.uid;
      allow read, update, delete: if false;
    }

    // Deny everything else by default.
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
AHRULES_EOF
  echo "ROLLBACK: purani branch-only rules -> $PROJECT"
else
cat > firestore.rules <<'AHRULES_EOF'
rules_version = '2';

// DEVICE ROLES (no Cloud Functions / no billing card needed).
// Same as firestore.rules, plus an OPTIONAL `role` field on each device's branch_members/{uid} document, set by
// the owner in the Firebase console (admin | manager | cashier). A document WITHOUT `role` behaves exactly like
// today (full access), so rolling this out cannot break an existing device; only devices you mark
// role = "cashier" are restricted:
//   - read only the till collections (no users / suppliers / purchases / payroll / rent / utility / zakat)
//   - create/update only sales, payments, expenses, cash, returns, stock movements, shell, customers, cash_register,
//     due_followups; products only stock/updatedAt/appliedOps (increments), customers never creditLimit /
//     openingBalance / stuckBalance
//   - never delete and never write a tombstone (_deleted: true) - this app deletes by tombstone, not real delete
// The role belongs to the DEVICE (its anonymous UID), not to a person. Clients cannot write branch_members.
// Residual risk: a modified cashier app can still write wrong amounts inside its own branch (rules cannot
// validate a sale against its stock / balance changes) and can read product cost.

// Baseline rules for the shared multi-branch Firestore project.
//
// What this enforces:
//   - Nobody unauthenticated can read or write anything (blocks the public-internet
//     default-deny gap that an empty/missing rules file would otherwise leave open).
//   - Every write to a synced collection must carry a non-empty "branchId" field that
//     matches the document's existing branchId (so a client can't silently switch a
//     record from one branch to another, and can't write a document with no branchId
//     at all going forward).
//   - A signed-in user may only read/create/update/delete documents whose branchId
//     matches THEIR OWN branch, per the server-side branch_members/{uid} mapping —
//     not whatever branchId their client's BuildConfig happens to send. This closes
//     the gap where a modified/rogue client could claim any branchId.
//   - branch_members/{uid} itself is never writable by clients (admin/console only),
//     so a user cannot grant themselves access to another branch.
//
// Setup required before deploying:
//   Create one document per staff member at branch_members/{uid} with the shape
//   { branchId: "dusri-branch" }, where {uid} is that user's Firebase Auth UID
//   (via Firebase console or a small admin script — NOT from the app itself).
service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    // The branch this signed-in user is provisioned for, per server-side mapping.
    function myBranchId() {
      return get(/databases/$(database)/documents/branch_members/$(request.auth.uid)).data.branchId;
    }

    function isMyBranch(branchId) {
      return isSignedIn()
          && exists(/databases/$(database)/documents/branch_members/$(request.auth.uid))
          && branchId == myBranchId();
    }

    // Role of this device ('admin' when the field is missing = today's behaviour). Only call after membership exists.
    function myRole() {
      return get(/databases/$(database)/documents/branch_members/$(request.auth.uid)).data.get('role', 'admin');
    }
    // FIX (role ki spelling ghalat = poori ijazat): ab sirf saaf "admin" / "manager" (chhote-bade harf / khali jagah
    // maaf) ko poori ijazat; koi bhi aur likha role ("Cashier ", "casher", "staff") = cashier jaisi pabandi.
    // Role ka khaana hi na ho = admin (aaj jaisa, rollout safe).
    function isCashier() {
      let r = string(myRole()).lower().trim();
      return !(r in ['admin', 'manager']);
    }
    // Sync push har write mein ye meta fields bhi likhta hai.
    function onlyMeta(extra) {
      return changedKeys().hasOnly(['updatedAt', 'upsertAt', 'pushedAt', 'branchId', 'appliedOps', 'serverId'].concat(extra));
    }

    function notTombstone() { return request.resource.data.get('_deleted', false) != true; }
    function changedKeys() { return request.resource.data.diff(resource.data).affectedKeys(); }

    function cashierReadable(collection) {
      return collection in ['customers', 'products', 'sales', 'payments', 'expenses', 'cash_transactions',
                            'cash_register', 'units', 'categories', 'returns', 'stock_movements',
                            'app_settings', 'shell_customers', 'shell_transactions', 'shop_empty_shell_log',
                            'inst_customer_profiles', 'inst_customer_receipts', 'inst_guarantors', 'inst_categories', 'inst_items', 'inst_plans', 'inst_payments', 'inst_photos', 'inst_price_changes', 'inst_cash_sales'];
      // inst_suppliers / inst_purchases / inst_supplier_payments / inst_purchase_returns: sirf Admin / Manager (header ke mutabiq).
    }
    function cashierMayCreate(collection) {
      return notTombstone() && collection in ['customers', 'sales', 'payments', 'expenses', 'cash_transactions',
                            'cash_register', 'returns', 'stock_movements', 'shell_customers',
                            'shell_transactions', 'shop_empty_shell_log',
                            'inst_customer_profiles', 'inst_customer_receipts', 'inst_guarantors', 'inst_categories', 'inst_items', 'inst_plans', 'inst_payments', 'inst_photos', 'inst_price_changes', 'inst_cash_sales'];
    }
    function cashierMayUpdate(collection) {
      return notTombstone() && (
        (collection == 'products'
          && changedKeys().hasOnly(['stock', 'updatedAt', 'branchId', 'appliedOps', 'serverId', 'pushedAt']))
        || (collection == 'customers'
          && !changedKeys().hasAny(['creditLimit', 'openingBalance', 'stuckBalance', '_deleted']))
        // Installment: cashier paise ka purana record nahi badal sakta — wasooli / payment / naqd sale sirf meta.
        || (collection in ['inst_customer_receipts', 'inst_payments', 'inst_cash_sales'] && onlyMeta([]))
        // Plan: sirf poora adaa hone par "completed" (raqam / qisten / munafa nahi; "repossessed" nahi).
        || (collection == 'inst_plans' && onlyMeta(['status', 'closedAt'])
            && request.resource.data.get('status', 'active') in ['active', 'completed'])
        // Piece: sirf bikne par "sold" (qeemat / khareed nahi; stock wapsi manager karta hai).
        || (collection == 'inst_items' && onlyMeta(['status'])
            && request.resource.data.get('status', '') == 'sold')
        // Customer profile: purana baqi aur block sirf manager.
        || (collection == 'inst_customer_profiles'
            && !changedKeys().hasAny(['openingBalance', 'openingDue', 'blockedReason', 'blockedAt', '_deleted']))
        || collection in ['sales', 'payments', 'expenses', 'cash_transactions', 'cash_register', 'returns',
                          'stock_movements', 'shell_customers', 'shell_transactions', 'shop_empty_shell_log',
                          'inst_guarantors', 'inst_categories', 'inst_photos', 'inst_price_changes']);
    }

    // Reads of a document that does not exist yet (resource == null) must not error out:
    // the sync push reads each doc inside a transaction before creating it, and
    // resource.data.* on a missing doc makes the rule fail with PERMISSION_DENIED.
    // A provisioned member may read "nothing"; an existing doc must be in their branch.
    function canRead() {
      return isSignedIn()
          && exists(/databases/$(database)/documents/branch_members/$(request.auth.uid))
          && (resource == null || resource.data.branchId == myBranchId());
    }

    function hasBranchId() {
      return request.resource.data.branchId is string
          && request.resource.data.branchId.size() > 0;
    }

    function branchIdUnchanged() {
      return !resource.data.keys().hasAny(['branchId'])
          || request.resource.data.branchId == resource.data.branchId;
    }

    // FIX (missing collections — Zakat/Units/Categories/Returns/Stock/App Settings
    // couldn't actually sync): SyncApi.kt has synced these collections for a while
    // (see its class doc comment at the top of that file), but this allowlist was
    // never updated to match — so every push/pull for units, categories, zakat
    // years/payments, returns, stock_movements, and app_settings was being silently
    // rejected by these rules with PERMISSION_DENIED, even though the app-side sync
    // code for them was working correctly. Added here so they actually reach
    // Firestore like every other synced entity.
    function isSyncedCollection(collection) {
      return collection in ['customers', 'suppliers', 'products', 'users',
                             'sales', 'purchases', 'payments', 'expenses',
                             'cash_transactions', 'cash_register',
                             'units', 'categories', 'zakat_years', 'zakat_payments',
                             'returns', 'stock_movements', 'app_settings',
                             'shell_customers', 'shell_transactions', 'shop_empty_shell_log',
                             'workers', 'worker_attendance', 'worker_advances',
                             'worker_salary_payments', 'shop_rents', 'shop_rent_ledger',
                             'utility_bills', 'utility_bill_payments',
                             // Hanna Installment
                             'inst_customer_profiles', 'inst_customer_receipts', 'inst_guarantors', 'inst_categories', 'inst_items', 'inst_plans', 'inst_payments', 'inst_photos', 'inst_price_changes', 'inst_cash_sales', 'inst_suppliers', 'inst_purchases', 'inst_supplier_payments', 'inst_purchase_returns'];
    }

    // Server-side record of which branch each staff UID belongs to.
    // Clients can read only their own membership doc; never write.
    match /branch_members/{uid} {
      allow read: if isSignedIn() && request.auth.uid == uid;
      allow write: if false;
    }

    // Due Reminders follow-up log (collection due_followups): same branch rules as every
    // synced collection, plus field validation. due_followups is deliberately NOT in
    // isSyncedCollection() above — Firestore ORs matching rules, so leaving it there would
    // let the generic rule below bypass validFollowup().
    function validFollowup() {
      let d = request.resource.data;
      return hasBranchId()
          && d.method in ['whatsapp', 'call', 'visit', 'sms', 'note']
          && d.outcome in ['sent', 'paid', 'promised', 'partial',
                           'no_answer', 'refused', 'dispute', 'note']
          && (d.get('amount', null) == null || (d.amount is number && d.amount >= 0))
          && (d.get('promiseDate', null) == null || d.promiseDate is number)
          && (d.get('nextFollowUp', null) == null || d.nextFollowUp is number)
          && (!('note' in d) || d.note == null || (d.note is string && d.note.size() <= 500));
    }

    match /due_followups/{docId} {
      allow read: if canRead();
      allow create: if isMyBranch(request.resource.data.branchId) && validFollowup();
      allow update: if isMyBranch(resource.data.branchId)
                     && branchIdUnchanged() && validFollowup();
      allow delete: if isMyBranch(resource.data.branchId) && !isCashier();
    }

    match /{collection}/{docId} {
      allow read: if isSyncedCollection(collection) && canRead()
                   && (!isCashier() || cashierReadable(collection));
      allow create: if isSignedIn() && isSyncedCollection(collection)
                     && hasBranchId() && isMyBranch(request.resource.data.branchId)
                     && (!isCashier() || cashierMayCreate(collection));
      allow update: if isSignedIn() && isSyncedCollection(collection)
                     && hasBranchId() && branchIdUnchanged()
                     && isMyBranch(resource.data.branchId)
                     && (!isCashier() || cashierMayUpdate(collection));
      allow delete: if isSignedIn() && isSyncedCollection(collection)
                     && isMyBranch(resource.data.branchId) && !isCashier();
    }

    // Sync heartbeat (firestore.rules jaisa): har branch ka ek chhota marker; har role ki device parh / badal sake
    // (cashier bhi push karta hai), sirf apni branch ka, sirf yahi teen fields.
    match /branch_sync/{bid} {
      allow read: if isMyBranch(bid);
      allow write: if isMyBranch(bid)
                   && request.resource.data.branchId == bid
                   && request.resource.data.keys().hasOnly(['branchId', 'at', 'n']);
    }

    // Crash reports: app ki ghalti (stack trace) developer ko — sirf banana, branch member device, chhota text,
    // apna uid. Padhna / badalna / mitana app se nahi (sirf Firebase console). lib/services/crash_reporter.dart.
    match /crash_reports/{docId} {
      allow create: if isSignedIn()
                    && exists(/databases/$(database)/documents/branch_members/$(request.auth.uid))
                    && request.resource.data.keys().hasOnly(['text', 'at', 'device', 'branchId', 'app', 'uid'])
                    && request.resource.data.text is string
                    && request.resource.data.text.size() <= 8000
                    && request.resource.data.uid == request.auth.uid;
      allow read, update, delete: if false;
    }

    // Deny everything else by default.
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
AHRULES_EOF
  echo "DEVICE ROLES rules -> $PROJECT"
fi
firebase deploy --only firestore:rules --project "$PROJECT"
echo
echo "Ho gaya. Ab dono phone par Sync Now — admin device par sab pehle jaisa hona chahiye."
