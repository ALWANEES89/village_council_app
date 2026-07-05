/// خريطة أسماء الأدوار العربية — المصدر الوحيد لعرض الدور في كل الواجهات.
/// لا تُعرض `roleId`/`role` الخام (مثل system_owner) للمستخدم إطلاقًا.
const _roleLabels = <String, String>{
  'system_owner': 'المالك الأعلى',
  'owner': 'مالك المجلس',
  'council_owner': 'مالك المجلس',
  'chairman': 'رئيس المجلس',
  'council_chairman': 'رئيس المجلس',
  'council_president': 'رئيس المجلس',
  'president': 'رئيس المجلس',
  'adminManager': 'مدير إداري',
  'admin': 'مدير إداري',
  'financialManager': 'المدير المالي',
  'financialReviewer': 'المراجع المالي',
  'secretary': 'أمين السر',
  'member': 'عضو',
  'suspended': 'موقوف',
  'superAdmin': 'مشرف المنصّة',
};

/// يُرجع اسم الدور بالعربية اعتمادًا على `roleId` ثم `role`، ثم `fallback`
/// (اسم الدور من مستند الدور إن وُجد)، وأخيرًا "عضو".
String roleLabelArabic(String? roleId, {String? role, String? fallback}) {
  final byRoleId = roleId != null ? _roleLabels[roleId] : null;
  if (byRoleId != null) return byRoleId;
  final byRole = role != null ? _roleLabels[role] : null;
  if (byRole != null) return byRole;
  if (fallback != null && fallback.trim().isNotEmpty) return fallback;
  return 'عضو';
}
