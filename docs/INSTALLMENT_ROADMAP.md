# Hanna Installment — roadmap

Hanna POS (AH-Developer, branch Raffey) ki copy par bana qist (installment) software. Android + Windows (+ iOS).
Naya kaam `lib/installment/` mein; POS ka purana code "Shop tools" se abhi bhi khulta hai.

## Identity (Step 1 — done)
- pubspec name: `hanna_installment` (tests ke `package:` imports bhi)
- App ID: `com.hannasolutions.installment` (Android `tools/android_fix.sh`, iOS `build.yml`)
- App name / window title: Hanna Installment; Windows zip: `Hanna-Installment-windows.zip`
- DB file: `hanna_installment.db` (demo: `hanna_installment_demo.db`) — POS ke data se alag
- Login ke baad home: `InstallmentHomeScreen`
- Firebase: is app ke liye NAYA Firebase project banayein (Settings > Cloud Sync mein us ki google-services.json).
  POS wala project (my-grocery-pos-8a444) is app mein na lagayein.

## Step 2 — done (DB v38)
- `customer_profiles` (1:1 with `customers`): walid ka naam, CNIC (13 hindse, duplicate block), phone 2, pata, rozgar, aamdani
- `inst_guarantors`: zamin (CNIC, phone, rishta, pata). Customer khud apna zamin nahi; ek banda kai logon ka zamin ho to warning
- `inst_categories`: Mobile [IMEI 1, IMEI 2], Motorcycle [Engine, Chassis, Registration], LED, Fridge, AC, Washing Machine, Laptop, Furniture, Other
- `inst_items`: har piece ki row, status in_stock / sold / returned / repossessed; IMEI / serial duplicate block (field ka naam nahi dekhta)
- CNIC / guarantor / cheque ki tasveerein: `KycPhotoStore` (sirf is device par, `kyc_photos/`)
- Tests: `test/installment_models_test.dart`; migration tests mein `_Step(38, ...)`

## Step 3 — done (DB v39)
- Tasveerein form ke andar hi (save se pehle): customer snap + CNIC aage/peeche; guarantor photo + CNIC aage/peeche
  (`inst_photo_widgets.dart` PhotoSlotBox). Guarantor card / plan par guarantor ki gol tasveer (KycAvatar)
- `inst_plans` / `inst_schedule` / `inst_payments`. Hisaab `inst_plan_math.dart` (PURE, test/installment_plan_test.dart):
  baqi = cash − advance; munafa = baqi × % (ya fixed); har qist = kul / n, 10/50/100 tak upar round, farq aakhri qist mein
- Waqfa: mahana (wahi tareekh, chhote mahine mein aakhri din) / 15 din / hafta
- Nayi Qist screen: customer (snap na ho to wahin lein) → zamin chunein (tasveer ke saath) → stock se piece → plan → summary.
  Kaghzat ki kami (photo / CNIC / zamin) par warning. Item `sold` ho jata hai
- Wasooli: pehli qist pehle; late fine ka mashwara (late fee × grace se zyada late qisten − pehle liya fine);
  har wasooli ki `cash_transactions` IN row (reference `inst-pay:<plan>-<pay>`, Day Book mein dikhti hai); WhatsApp receipt
- Plan band: poori adaigi par `completed`; admin/manager "saman wapas" (repossessed); admin "plan delete (ghalti)"
  sirf jab advance ke ilawa koi qist na li ho. Wapas liya piece item form se dobara stock mein
- Home: aaj ki qisten, late, aaj ki wasooli, kul baqi; WhatsApp yaad-dahani

## Step 4 — done (DB change nahi)
- Wasooli List (`inst_collection_screens.dart`): sirf late / aaj (late samet) / 7 din / 30 din; call, WhatsApp,
  poori list share (recovery wale ke liye)
- Defaulters: 1/7/15/30/60/90+ din late; aakhri adaigi; zamin ki tasveer + call + WhatsApp (zamin ko bhi)
- Reports (admin/manager): is mahine / pichhle / is saal / tareekhen — wasooli (qist, advance, fine, cash/bank, roz ka chart),
  naye plan (nakd / qist maliyat, khareed, mutawaqqa munafa), mukammal / wapas, kul baqi aging (1-30/31-60/61-90/90+), stock.
  Hisaab `inst_reports.dart` (PURE, test/installment_reports_test.dart)
- PDF (`inst_pdf.dart`, Urdu POS slips jaisa): plan statement A4 — customer + zamin ki tasveer, CNIC tasveerein, saman ke
  IMEI/serial, schedule, wasooliyan, dastakhat; receipt A5 customer ki tasveer ke saath. Android par seedha customer ki WhatsApp chat
- Yaad-dahani ka text ek jagah (`planReminderText` / `remindPlan`)

## Step 5 — done (DB change nahi)
- Sync (`inst_sync.dart`, naam `inst_sync_names.dart`): 6 Firestore collections — inst_customer_profiles,
  inst_guarantors, inst_categories, inst_items, inst_plans (schedule plan ke andar), inst_payments.
  Har write ke saath usi transaction mein queue; references serverId se (local ids har device par alag).
  Category id naam se (`inst_category:mobile`) — har device ki pehle se bani "Mobile" ek hi doc.
  Pull apply POS ke `applyRestOfServerChanges` ke aakhir mein; anpushed local edit purani cloud copy se nahi badalti.
  Wasooli ki cash row POS ke cash_transactions sync se; payment `cashServerId` se judti hai.
  Doosre device ki payment hatane par cash row `cashTxId` se bhi hat'ti hai.
  "Force full push" (resyncAllLocalData) qist data bhi bhejta hai. Test: test/installment_sync_test.dart
- Plan number mein device tag ke 2 harf (`Q-7F0012`) — do devices ke number na takrayein
- Rules (firestore*.rules + deploy_rules_live.sh), indexes (branchId+updatedAt / branchId+pushedAt har collection),
  functions/src/syncLogic.ts (cashier: profile/zamin/saman/plan/wasooli upsert) — sab mein 6 collections
- Deploy scripts mein project ka naam ab lazmi; POS ka project (my-grocery-pos-8a444) dene par ruk jate hain
- Roz subah 9 ke baad notification (`inst_due_alert.dart`): aaj ki / late qisten + naam; tap = Wasooli List
- Shop tools ab saaf list (`inst_shop_tools_screen.dart`): cash, kharche, day book, register, workers, kiraya, bills,
  backup, users, recycle bin. Purana POS dashboard sirf admin ke liye "Advanced" mein

## Firebase setup (naya project, ek dafa)
1. console.firebase.google.com par naya project (maslan `hanna-installment`), Firestore (production mode), Authentication > Anonymous ON
2. Android app add: package `com.hannasolutions.installment`, google-services.json download
3. App: Settings > Cloud Sync Setup mein google-services.json + branch code; device ka UID `branch_members/{uid}` mein (`branchId`)
4. Rules: `bash deploy_rules_live.sh roles <project-id>`; indexes: `bash deploy_indexes.sh <project-id>`
   (ya Console mein firebase/firestore.rules paste + indexes haath se)

## Step 6 — done
- Tasveeron ka sync Storage ke baghair (`inst_photo_sync.dart`): har tasveer ek `inst_photos` document mein base64 JPEG
  (doc id `inst_photo:<c|g>|<ownerServerId>|<kind>`). Customer chehra (PartyPhotoStore, kind `face`), CNIC aage/peeche,
  cheque, guarantor ki tasveer. CNIC tasveer ab 1100px q75. 600 KB se bari file upload nahi hoti.
  Stores ka `onLocalChange` -> queue; pull par `saveBytes` (dobara upload nahi); wahi size ho to dobara nahi likhti.
  Guarantor delete: pehle tasveerein (cloud tombstone), phir guarantor. "Force full push" ke baad sab tasveerein bhi
  (`SyncQueueHelper.afterResync`). Rules / indexes / functions mein `inst_photos` (function payload limit is type ke liye 1,000,000)
- Privacy policy (`tools/deploy_privacy_site.sh <project-id>`) Installment ke liye: CNIC, zamin, tasveerein, IMEI, sync
  mein tasveerein. `AppInfo.privacyPolicyUrl` = https://hanna-installment.web.app/privacy.html (project id alag ho to badlein)

## Step 7 — done
- `docs/PLAY_STORE_LISTING.md`: naam / short / full description (English + Urdu), graphics + screenshots list,
  Data safety jadwal, content rating, foreground service declaration, Financial features declaration ka mashwara,
  reviewer note, release checklist. Asal nukta: app "loan app" nahi — listing mein loan / qarz / credit alfaaz nahi
- `READ_CONTACTS` hataya (`tools/android_fix.sh`, `tools:node="remove"` bhi) — Pakistan mein loan apps ko contacts mana

## Pehli green build — 2026-11-13 (repo asam3rana-del/Hanna-Installment, branch Raffey)
- Analyze + saare tests paas; app phone par chal gayi. Ek test fix: installment_sync_test mein `singleInstance: false`
  (warna dono `:memory:` ek hi DB)

## Step 8 — done: grocery screens ka safaya
- 57 UI files mitai (sale, purchase, items/product, stock (adjust/taking/audit/report/rebuild), rate tools, bulk translate,
  bill scan, party dashboard/ledger, POS reports/balance sheet/monthly, history, receivables, shell ledger, setup guide,
  purana POS dashboard, Amanat/Loan, POS udhaar wasooli (collection hub / queue / due reminders / payments)) + services/collection_actions
- Raste band: Settings se Parties/Items/Reports/Sale/Purchase/Shell Ledger/Setup guide; POS ki Sale + credit-limit settings
  `_posFeatures = false` ke peeche; Day Book se bill nahi khulta; customer screen se POS "Ledger" hata; Shop tools se "Advanced"
- POS udhaar (DueAlertService.checkAndNotify) aur Amanat/Loan (ReturnAlertService) notifications band; qist + bills + backup chalti
- Crash dialog (pichhli crash ka log / developer ko bhejna) ab Installment Home par
- DB / sync / repositories / helper code NAHI hataya — sync engine aur tests un par chalte hain; app mein nazar nahi aate
- `import-zip.yml`: zip mein `.import-delete.txt` ho to us ki files repo se mitata hai (rsync khud nahi mitata).
  Workflow file bot update nahi kar sakta — user ne haath se paste ki

## Step 9 — done (DB v40)
- Munafa (Reports, admin/manager): har wasooli mein munafe ka hissa = raqam × (qist qeemat − khareed) ÷ qist qeemat
  ("installment method"; gol aakhir mein) + late fine − kharche (expenses table: salary / kiraya / bills samet, category wise)
  = khalis munafa. Khareed na likhi ho to us wasooli ka munafa nahi ginta (alag batata hai). Plan screen: munafa ab tak / kul.
  `profitShare` / `profitReport` PURE (test/installment_reports_test.dart)
- Rate badlein (Stock screen ka 💲 button, admin/manager): category + search se pieces, ±% / ±Rs / naya rate, gol karna,
  "khareed bhi badlein" (default band), preview + stock maliyat ka farq. Sirf in_stock; bane plan nahi badalte.
  `inst_price_changes` table (v40) + sync (`inst_price_change`, sirf admin/manager functions mein); item form par "Rate history";
  form se qeemat badlo to bhi record. Reports > Stock: naqd qeemat par maliyat, stock mein munafa, muddat ki rate tabdeeliyan

## Abhi baqi
- Installment ka alag icon + feature graphic
