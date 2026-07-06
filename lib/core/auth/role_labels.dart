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

/// أدوار "غير مميّزة" — عندها لا يُعتمد على roleId وحده لعرض الدور، بل يُفحص
/// permissionsSnapshot الفعلي حتى لا يُعرض "عضو" لمن يملك صلاحيات إدارية.
const _nonPrivilegedRoleIds = <String>{'member', 'suspended', ''};

/// الصلاحيات (permissionsSnapshot) التي تدل على أن العضو ليس عضوًا عاديًا.
/// المصدر الرسمي لهذه المفاتيح هو ما تفرضه Firestore Rules + منطق
/// notifyOrganizationReviewers + AdminAccess. أي وجود لأحدها = صلاحيات إدارية.
const _managerPermissions = <String>{
  'members.manage',
  'members.approve',
  'membershipRequests.review',
  'roles.manage',
  'receipts.review',
  'payments.approve',
  'payments.reject',
  'payments.manage',
  'bookings.approve',
  'bookings.manage',
  'settings.manage',
  'organization.manage',
  'audit.read',
  'audit.view',
  'notifications.send',
  // توافق خلفي مع مفاتيح قديمة (camelCase).
  'manageMembers',
  'changeRoles',
  'adminDashboard',
  'suspendMembers',
  'cancelMemberships',
};

/// يُرجع اسم الدور بالعربية اعتمادًا على `roleId` ثم `role`، ثم `fallback`
/// (اسم الدور من مستند الدور إن وُجد)، وأخيرًا "عضو".
///
/// ملاحظة: هذه الدالة تعرض التسمية الاسمية فقط (لا تفحص الصلاحيات الفعلية).
/// لعرض دور العضو داخل مجلس استخدم [effectiveRoleLabelArabic] حتى يتطابق
/// الدور المعروض مع صلاحياته الفعلية (permissionsSnapshot).
String roleLabelArabic(String? roleId, {String? role, String? fallback}) {
  final byRoleId = roleId != null ? _roleLabels[roleId] : null;
  if (byRoleId != null) return byRoleId;
  final byRole = role != null ? _roleLabels[role] : null;
  if (byRole != null) return byRole;
  if (fallback != null && fallback.trim().isNotEmpty) return fallback;
  return 'عضو';
}

/// الدور الفعلي المعروض داخل مجلس — **المصدر الموحّد لعرض دور العضو**.
///
/// يوازن الدور الاسمي (`roleId`/`role`) مع الصلاحيات الفعلية
/// (`permissions` = permissionsSnapshot) التي تُفرض بها القدرات وتُرسَل بها
/// إشعارات المراجعة. القاعدة:
///  1) دور مميّز صريح (adminManager/chairman/owner/…) ← يُعرض كما هو.
///  2) دور غير مميّز (member/فارغ) لكن صلاحياته إدارية ← لا يُعرض "عضو":
///       - fullAccess               → "مدير (صلاحيات كاملة)"
///       - أي صلاحية إدارية أخرى     → "مدير (صلاحيات مخصّصة)"
///  3) خلاف ذلك ← التسمية الاسمية ([roleLabelArabic]) ثم "عضو".
///
/// بهذا يستحيل أن يظهر "عضو" لمن يملك صلاحيات مدير داخل نفس المجلس.
String effectiveRoleLabelArabic(
  String? roleId, {
  String? role,
  String? fallback,
  List<String> permissions = const [],
}) {
  // 1) دور مميّز صريح تُعرض تسميته مباشرة (يعكس تعيينًا رسميًّا).
  final explicit = _privilegedRoleLabel(roleId) ?? _privilegedRoleLabel(role);
  if (explicit != null) return explicit;

  // 2) دور غير مميّز: افحص الصلاحيات الفعلية قبل الحكم بأنه "عضو".
  if (permissions.contains('fullAccess')) {
    return 'مدير (صلاحيات كاملة)';
  }
  if (permissions.any(_managerPermissions.contains)) {
    return 'مدير (صلاحيات مخصّصة)';
  }

  // 3) عضو عادي فعلًا.
  return roleLabelArabic(roleId, role: role, fallback: fallback);
}

/// هل يملك العضو صلاحيات إدارية فعليّة اعتمادًا على permissionsSnapshot؟
bool hasManagerPermissions(List<String> permissions) {
  return permissions.contains('fullAccess') ||
      permissions.any(_managerPermissions.contains);
}

/// يُرجع تسمية الدور إن كان `value` دورًا **مميّزًا** صريحًا (غير member/suspended)،
/// وإلا null للسماح بالرجوع إلى فحص الصلاحيات.
String? _privilegedRoleLabel(String? value) {
  if (value == null || _nonPrivilegedRoleIds.contains(value)) return null;
  return _roleLabels[value];
}
