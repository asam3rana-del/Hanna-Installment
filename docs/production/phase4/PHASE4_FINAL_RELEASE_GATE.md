# Phase 4 — Final Commercial Release Gate

## Purpose

This phase packages the final release checklist and a read-only preflight script. It does **not** claim a production build, signing, Firebase deployment, data migration, or shop sign-off has happened.

## Source inspection at package creation

The checked project root contains `pubspec.yaml`, `pubspec.lock`, Flutter `lib/`, `test/`, `test_migration/`, Firebase rules/tests, and the earlier Phase 1–3 documentation. The checked root does **not** contain Flutter platform folders `android/`, `ios/`, or `windows/`. The current execution environment also has no `flutter`, `dart`, or `firebase` executable. Java and Node are present. Consequently, this environment cannot run Flutter analysis/tests/builds or produce a signed Android APK/AAB.

The older `PRODUCTION_RELEASE_CHECKLIST.md` includes historical status statements dated 2026-11-02/03 (including prior build/device/live Firebase claims). Those statements are not independently re-verified by this Phase 4 package and must not be treated as evidence for the exact source snapshot being released.

## Run the preflight

From the project root:

```bash
bash tools/production/release_preflight.sh
```

The script is read-only. `FAIL` means a required project file is missing. `WARN` means a release prerequisite was not verified in this environment. A clear result is only a preflight result, not certification.

## Mandatory release sequence

1. **Restore platform projects** from the intended, reviewed Flutter source branch using the project's approved Flutter version. Do not generate platform scaffolding blindly over customized native configuration. Confirm Android application ID, min/target SDK, permissions, notification/backup workers, Firebase configuration, and signing config.
2. **Pin toolchain and dependencies.** Record Flutter/Dart versions; run `flutter pub get`, verify the lockfile diff, and preserve the exact commit SHA.
3. **Automated checks.** Run `flutter analyze`, the complete `flutter test` suite (including `test_migration` if maintained as a separate suite), Firebase Emulator rules tests, and Functions tests. Save logs and CI run URLs.
4. **Staging only.** Deploy the selected Firestore rules/indexes and Functions to a dedicated staging Firebase project. Verify branch isolation, membership provisioning, offline queue/retry, duplicate collection prevention, and two-device conflict behavior. Do not deploy a draft rules file by guess.
5. **Backup recovery.** Create an encrypted off-device backup; keep its password separately. Restore into a clean test install/database. Reconcile customers, plans, payments, receipts, outstanding amounts, cash, stock (if enabled), and supplier/customer balances.
6. **Accounting acceptance.** Enter verified opening cash/bank, stock quantities and valuation, customer/supplier opening balances. Reconcile day book, sales, purchases, returns, expenses, cash/bank, P&L, and balance sheet against independently calculated shop totals.
7. **Signed release.** Build a release APK/AAB on the controlled release machine. Use the established upload keystore; back up keystore and passwords separately and securely. Never put secrets in source control or this ZIP. Verify package ID, version/build number, signature, install/upgrade path, and app data retention.
8. **Parallel run.** Keep the previous accounting system operational. Run both systems for an agreed period; investigate every mismatch before cutover. Take a fresh verified backup immediately before migration/cutover.
9. **Owner sign-off.** Record the release commit, artifact SHA-256, test/CI evidence, Firebase project/rules version, backup restore evidence, opening balances, reconciliation result, and approval date.

## No-go conditions

- Missing platform project or non-reproducible build environment.
- Any failing analysis, test, emulator rule test, or release build.
- Any duplicate/missing installment receipt or unexplained ledger/cash mismatch.
- Any cross-branch access, unprovisioned client access, or unknown active ruleset.
- Backup cannot be restored or financial totals differ.
- Keystore/recovery password not safely backed up.
- No parallel-run reconciliation and owner approval.

## Current status for this package

**NOT CLEARED FOR COMMERCIAL CUTOVER.** The platform folders and Flutter toolchain are absent in the checked workspace, and no current-source Flutter/Emulator/release build results were produced here. This phase adds a repeatable preflight and operational gate only. It does not alter live Firebase, shop records, or customer data.
