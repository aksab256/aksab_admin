/// Monthly targets for sales managers (aksab_admin, HR → Sales → Managers).
///
/// Phase 1: the administration assigns each sales manager five monthly
/// indicators on the manager's own `managers` document under
/// `targets.<yyyy-MM>`. Later phases let a manager split that share across
/// their supervisors without exceeding what they received.
///
/// Field names (unified with the sales app):
/// `financialTarget`, `hoursTarget`, `invoicesTarget`, `clientsTarget`,
/// `visitsTarget`.
///
/// Deliberately NOT `locked: true`: the old rep-target flow locks the month
/// after one write, but a manager target is completed in stages (assign →
/// distribute), so the entry carries `status` + an embedded `history` list
/// instead. The legacy `invoiceTarget` reader and all achievement/
/// salary/commission math are untouched by this model.
///
/// Pure Dart: no Firestore import. Timestamps are plain [DateTime] values —
/// Firestore (and fake_cloud_firestore) store them as Timestamps.
library;

import 'package:intl/intl.dart';

/// The five monthly indicators, in canonical order.
const List<String> kManagerTargetFields = <String>[
  'financialTarget',
  'hoursTarget',
  'invoicesTarget',
  'clientsTarget',
  'visitsTarget',
];

/// Arabic labels for the five indicators (admin UI + tests).
const Map<String, String> kManagerTargetLabelsAr = <String, String>{
  'financialTarget': 'الهدف المالي (ج.م)',
  'hoursTarget': 'ساعات العمل',
  'invoicesTarget': 'عدد الفواتير',
  'clientsTarget': 'عدد العملاء',
  'visitsTarget': 'عدد الزيارات',
};

/// Status of a monthly manager target.
const String kManagerTargetStatusAssigned = 'assigned';

/// Builds a `yyyy-MM` month key. Single place for the whole admin panel so
/// every target write/read shares one format.
String managerMonthKey(DateTime date) =>
    DateFormat('yyyy-MM').format(date);

/// True for strict `yyyy-MM` keys (01–12 only).
bool isValidManagerMonthKey(String raw) =>
    RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(raw.trim());

/// Normalizes one raw indicator value: numbers stay, numeric strings parse,
/// anything else (or a negative) becomes 0. Never throws.
double normalizeTargetValue(dynamic raw) {
  double value;
  if (raw is num) {
    value = raw.toDouble();
  } else {
    value = double.tryParse(raw?.toString().trim() ?? '') ?? 0;
  }
  if (value.isNaN || value.isNegative) return 0;
  if (value.isInfinite) return 0;
  return value;
}

/// Normalizes a raw map to exactly the five canonical fields.
Map<String, double> normalizeManagerTargets(Map? raw) {
  final out = <String, double>{};
  for (final field in kManagerTargetFields) {
    out[field] = normalizeTargetValue(raw?[field]);
  }
  return out;
}

/// Validates raw dialog input. Returns an Arabic error message, or null when
/// the entry may be saved. Rules: every field must be a non-negative number,
/// and at least one indicator must be greater than zero (an all-zero month
/// is almost certainly a mistake, and it keeps empty saves out of history).
String? validateManagerTargets(Map<String, String> controllers) {
  for (final field in kManagerTargetFields) {
    final text = controllers[field]?.trim() ?? '';
    if (text.isEmpty) continue; // Empty counts as 0 (same as legacy flow).
    final parsed = double.tryParse(text);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return 'قيمة غير صالحة في ${kManagerTargetLabelsAr[field]}';
    }
    if (parsed.isNegative) {
      return 'لا يُسمح بقيم سالبة في ${kManagerTargetLabelsAr[field]}';
    }
  }
  final values = normalizeManagerTargets(controllers);
  if (values.values.every((v) => v == 0)) {
    return 'حدد قيمة واحدة على الأقل من المؤشرات الخمسة';
  }
  return null;
}

/// Builds the `targets.<month>` entry map, appending one history record.
/// Previous history is preserved (capped at 50 entries, oldest dropped).
Map<String, dynamic> buildManagerTargetEntry({
  required Map<String, dynamic> values,
  required String setByUid,
  required String setByRole,
  required DateTime now,
  List? previousHistory,
}) {
  final normalized = normalizeManagerTargets(values);
  final history = <Map<String, dynamic>>[];
  if (previousHistory != null) {
    for (final item in previousHistory) {
      if (item is Map) history.add(Map<String, dynamic>.from(item));
    }
  }
  history.add(<String, dynamic>{
    'at': now,
    'byUid': setByUid,
    'byRole': setByRole,
    'changes': normalized,
    'note': 'set',
  });
  while (history.length > 50) {
    history.removeAt(0);
  }
  return <String, dynamic>{
    ...normalized,
    'setByUid': setByUid,
    'setByRole': setByRole,
    'setAt': now,
    'updatedAt': now,
    'status': kManagerTargetStatusAssigned,
    // Reserved for later distribution phases; phase 1 only assigns.
    'distributed': <String, double>{
      for (final field in kManagerTargetFields) field: 0,
    },
    'history': history,
  };
}

/// Reads one month out of a document's `targets` map. Never throws; a missing
/// month reports `hasTarget: false` with zeroed values.
Map<String, dynamic> summarizeManagerMonth(Map? targets, String monthKey) {
  final month = (targets is Map) ? targets[monthKey] : null;
  if (month is! Map) {
    return <String, dynamic>{
      'hasTarget': false,
      'values': normalizeManagerTargets(null),
      'status': '',
      'historyCount': 0,
    };
  }
  final data = Map<String, dynamic>.from(month);
  final history = data['history'];
  return <String, dynamic>{
    'hasTarget': true,
    'values': normalizeManagerTargets(data),
    'status': data['status']?.toString() ?? '',
    'setByUid': data['setByUid']?.toString() ?? '',
    'setByRole': data['setByRole']?.toString() ?? '',
    'historyCount': history is List ? history.length : 0,
  };
}
