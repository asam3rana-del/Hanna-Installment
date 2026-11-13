/// Hanna Installment sync ke naam (PURE — sync_push_plan / sync_pull_plan isay import karte hain).

const instProfileType = 'inst_profile';
const instGuarantorType = 'inst_guarantor';
const instCategoryType = 'inst_category';
const instItemType = 'inst_item';
const instPlanType = 'inst_plan';
const instPaymentType = 'inst_payment';
const instPhotoType = 'inst_photo';

/// entityType -> Firestore collection.
const Map<String, String> instPushCollections = {
  instProfileType: 'inst_customer_profiles',
  instGuarantorType: 'inst_guarantors',
  instCategoryType: 'inst_categories',
  instItemType: 'inst_items',
  instPlanType: 'inst_plans',
  instPaymentType: 'inst_payments',
  instPhotoType: 'inst_photos',
};

/// Pull ki tarteeb = apply ki tarteeb (parent pehle).
const List<String> instPullCollections = [
  'inst_categories',
  'inst_customer_profiles',
  'inst_guarantors',
  'inst_items',
  'inst_plans',
  'inst_payments',
  'inst_photos', // aakhir mein: owner (customer / guarantor) pehle aa chuka ho
];
