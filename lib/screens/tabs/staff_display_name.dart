/// اسم الموظف للعرض في لوحة الإدارة.
///
/// مستندات التسجيل قد تصل بأشكال مختلفة (fullname مباشرةً أو داخل profile
/// أو بمفاتيح بديلة حسب نسخة التطبيق)، فتُقرأ كل الأشكال المعروفة قبل
/// السقوط إلى 'بدون اسم' بدل ظهور بطاقة بلا اسم.
String staffDisplayName(Map<String, dynamic> data) {
  final direct = _pickName(data);
  if (direct.isNotEmpty) return direct;
  final profile = data['profile'];
  if (profile is Map) {
    final nested = _pickName(Map<String, dynamic>.from(profile));
    if (nested.isNotEmpty) return nested;
  }
  return 'بدون اسم';
}

String _pickName(Map<String, dynamic> data) {
  for (final key in ['fullname', 'fullName', 'name', 'displayName']) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}
