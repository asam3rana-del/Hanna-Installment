# Phase 3 — Security, Sync & Backup Hardening

## Scope

This phase adds regression coverage and an operational verification gate for:

- Firestore branch isolation across all synced collections, including the 14 Hanna Installment collections.
- Server-provisioned `branch_members/{uid}` membership; clients must not self-provision or change membership.
- `branch_sync/{branchId}` heartbeat isolation and its existing three-field allowlist (`branchId`, `at`, `n`).
- Existing sync queue idempotency, concurrent sync guard, offline retry behavior, and backup/restore drills.

## Changes in this phase

1. Expanded `firebase/rules-tests/branch_isolation.test.js` so its all-collection matrix also covers every installment collection declared by `firebase/firestore.rules`.
2. Added emulator tests for heartbeat read/write isolation, cross-branch denial, unprovisioned users, and unexpected heartbeat fields.
3. Added this release gate so a test suite is not confused with a successful production deployment.

## Required commands (run from project root)

```bash
cd firebase/rules-tests
npm ci
npm test
```

Then from project root:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Manual two-device drill

Use two test devices signed into separate accounts provisioned to the SAME test branch. Create one test customer and one test installment plan on device A, collect a uniquely identified payment on A, then sync device B twice. Confirm B displays exactly one payment and the same outstanding balance. Repeat with device B offline during the initial collection, reconnect, and verify no duplicate receipt or cash entry appears.

Repeat with a second test branch and verify that neither device can read or mutate the other branch's records. Never run this drill against live customer data.

## Backup / restore drill

1. Export an encrypted backup to off-device storage.
2. Record the backup timestamp and file size; do not store the password in the same location.
3. Restore into a clean test installation/database, not over the live shop database.
4. Compare customer count, active plan count, payment count, total collected, outstanding total, cash balance, and supplier balance.
5. Re-open the restored database and repeat the comparison after a full sync.

## Release blockers

- Any failing Firestore emulator rule test.
- Any duplicate payment/receipt after repeat sync or retry.
- Any cross-branch read/write success.
- Any backup restore mismatch in counts or financial totals.
- Missing off-device backup or unavailable recovery password.
- Flutter analyze/test/release build not completed on the release machine.

## Deployment warning

Do not deploy rules from this package automatically. The app has multiple rules variants (`firestore.rules`, `firestore.device-roles.rules`, and `firestore.staff-claims.rules`). Confirm which ruleset is currently active in the Firebase project, run the emulator suite against that exact ruleset, and obtain an explicit production deployment approval. `staff-claims.rules` is a separate migration target, not a drop-in replacement for the baseline rules.

## Status

This phase adds test coverage and runbooks only. It does not claim that emulator tests, Flutter tests, restore drills, or live Firebase deployment have passed. Execute the commands and drills above before production approval.
