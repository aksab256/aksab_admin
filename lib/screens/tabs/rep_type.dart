/// Sales-rep employment classification shared by the admin panel.
///
/// Written once on the approved `salesRep` doc itself (`repType`:
/// 'permanent' | 'freelance') during approval. Missing or unknown values
/// always count as permanent (safe default: freelance-only surfaces stay
/// hidden, and permanent-only lists keep legacy reps).
const String kRepTypePermanent = 'permanent';
const String kRepTypeFreelance = 'freelance';

/// Approval-time validation: a sales rep MUST be classified to complete
/// approval; other roles need no type. Pure function for testing.
bool isRepTypeSelectionValid({required String? role, required String? repType}) {
  if (role != 'sales_rep') return true;
  return repType == kRepTypePermanent || repType == kRepTypeFreelance;
}

/// Normalizes any stored/missing value. Unknown or missing → permanent.
String normalizeRepType(dynamic raw) =>
    raw?.toString() == kRepTypeFreelance ? kRepTypeFreelance : kRepTypePermanent;

/// Permanent reps are linked to supervisors and enter target
/// distribution/tracking; freelance reps never are.
bool isTargetEligible(dynamic repType) =>
    normalizeRepType(repType) == kRepTypePermanent;

/// Arabic display label for rep lists. Legacy docs show as unspecified
/// (but still behave as permanent everywhere it matters).
String repTypeLabelAr(dynamic repType) {
  if (repType == null || repType.toString().isEmpty) return 'غير محدد (ثابت)';
  if (repType.toString() == kRepTypeFreelance) return 'حر Freelance';
  return 'ثابت Permanent';
}
