# Hanna Installment — Production Fix Phase 1

Date: 2026-11-25

## Changes applied

1. `lib/installment/inst_plan_repository.dart`
   - Installment balance and plan-active status are now re-read inside the SQLite write transaction immediately before inserting payment rows.
   - Completion is decided from that same transactionally-read balance.
   - This closes the stale preflight-read window for competing writes to the same local database.

2. `lib/installment/inst_opening_balance.dart`
   - Customer opening-balance receivable is now recalculated inside the same SQLite write transaction that inserts the receipt and linked cash-in row.

3. `firebase/firestore.device-roles.rules`
   - Added `inst_customer_receipts` to cashier read/create allowlists.
   - Cashier updates to this collection are restricted to sync metadata fields only (`updatedAt`, `branchId`, `appliedOps`, `serverId`, `pushedAt`).
   - Removed the collection from the broad cashier update allowlist so that the metadata restriction is not bypassed.

4. `firebase/firestore.indexes.json`
   - Added branchId + updatedAt and branchId + pushedAt indexes for `inst_customer_receipts`.

## Important limitation

SQLite transactions protect concurrent writes on one device/database. They do not provide cross-device atomicity. Two offline devices can still independently accept payments before synchronization. True multi-device financial locking requires a trusted server-side transaction/Callable Function or a strict single-collector policy while offline. Do not treat these local changes as proof of distributed atomicity.

## Verification status

- Firestore indexes JSON parses successfully.
- Source changes were inspected after patching.
- Flutter/Dart SDK and Firebase CLI are not available in this execution environment, so `dart format`, `flutter analyze`, `flutter test`, Firestore rules emulator tests, and Android release build were not run.
- The existing cashier permissions for `inst_plans` and `inst_items` still need a field-by-field policy review against the actual sync payload schema before tightening them; broad restrictions were not guessed here.

## Required next verification

1. Run `dart format` on the two changed Dart files.
2. Run `flutter analyze` and the full `flutter test` suite.
3. Run Firebase rules tests against the emulator.
4. Deploy indexes and rules to a staging Firebase project.
5. Test same-device double collection and two-device offline collection separately.
