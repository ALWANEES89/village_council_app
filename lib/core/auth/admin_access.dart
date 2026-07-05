/// AdminAccess — خدمة التحكّم المركزية بالصلاحيات (Access Control Service).
///
/// مصدر واحد لكل قرارات الصلاحيات في الواجهة. الأمان الحقيقي يُفرض في
/// Firestore Rules؛ هذه الطبقة تعكس القواعد لإظهار/إخفاء عناصر الواجهة فقط.
///
/// الهرمية: system_owner (منصّة) > owner (مالك المجلس) > chairman (رئيس المجلس)
/// > admin (مدير إداري) > member (عضو) > suspended (موقوف).
///
/// القرارات تعتمد على: platform_admins (isSuperAdmin) + roleId + role +
/// permissionsSnapshot + status — **لا** على memberNumber.
class AdminAccess {
  const AdminAccess({
    this.isSuperAdmin = false,
    this.isLegacyAdmin = false,
    this.permissions = const [],
    this.roleId = '',
    this.role = '',
    this.isPrimaryOwner = false,
    this.status = '',
  });

  /// مالك المنصّة الأعلى (system_owner) أو المشرف العام (superAdmin).
  final bool isSuperAdmin;
  final bool isLegacyAdmin;
  final List<String> permissions;
  final String roleId;
  final String role;
  final bool isPrimaryOwner;

  /// حالة عضوية المستخدم في المجلس المختار (active/suspended/...).
  final String status;

  bool has(String permission) {
    return isSuperAdmin ||
        permissions.contains('fullAccess') ||
        permissions.contains(permission);
  }

  // ── الأدوار ────────────────────────────────────────────────────────────
  bool get isActiveMember => status == 'active';
  bool get isSuspended => status == 'suspended';

  /// مالك المنصّة الأعلى العالمي (Global Override): مصدره الوحيد الموثوق هو
  /// مستند platform_admins/{uid} (role=system_owner, status=active,
  /// fullAccess=true) المنعكس في [isSuperAdmin]. هذه الصلاحية **عالمية** تتغلّب
  /// على أي دور محلي داخل أي مجلس. لا تعتمد على roleId/role داخل العضوية.
  bool get isPlatformOwner => isSuperAdmin;

  /// المالك الأعلى للنظام. الصلاحية العالمية تأتي من platform_admins
  /// ([isSuperAdmin]). تُضاف حالات المالك المحلي (isPrimaryOwner/role=owner)
  /// لأغراض عرض الواجهة داخل المجلس الحالي فقط — والقرار العالمي يبقى
  /// [isPlatformOwner].
  bool get isSystemOwner =>
      isSuperAdmin ||
      isPrimaryOwner ||
      roleId == 'system_owner' ||
      role == 'system_owner' ||
      role == 'owner';

  bool get isPlatformAdmin => isSuperAdmin;

  /// مالك داخل المجلس (له صلاحيات كاملة داخل مجلسه).
  bool get isOrgOwner =>
      isSystemOwner ||
      roleId == 'owner' ||
      roleId == 'council_owner' ||
      role == 'council_owner' ||
      has('fullAccess');

  bool get isChairman => roleId == 'chairman' || role == 'chairman';
  bool get isAdminRole =>
      roleId == 'adminManager' || roleId == 'admin' || role == 'admin';

  // ── القدرات (Capabilities) ───────────────────────────────────────────────
  // كل قدرة تبدأ بتجاوز المالك الأعلى العالمي: من كان system_owner على مستوى
  // المنصّة (isPlatformOwner) يملك كل الصلاحيات في كل المجالس بغضّ النظر عن
  // دوره المحلي داخل العضوية. القرار الحقيقي يُفرض في Firestore Rules
  // (isSystemOwner)؛ هذه الطبقة تعكسه لإظهار/إخفاء عناصر الواجهة فقط.

  bool get canReviewRequests =>
      isPlatformOwner ||
      isLegacyAdmin ||
      isOrgOwner ||
      isChairman ||
      has('membershipRequests.review') ||
      has('members.approve');

  bool get canManageMembers =>
      isPlatformOwner ||
      isLegacyAdmin ||
      isOrgOwner ||
      isChairman ||
      has('members.manage') ||
      has('manageMembers') ||
      has('members.read');

  bool get canChangeRoles =>
      isPlatformOwner || isOrgOwner || has('roles.manage') || has('changeRoles');

  bool get canManageRoles => canChangeRoles;

  bool get canTransferCouncilManager =>
      isPlatformOwner || isOrgOwner || has('transferCouncilManager');

  bool get canSuspendMembers =>
      isPlatformOwner || canManageMembers || has('suspendMembers');

  bool get canCancelMemberships =>
      isPlatformOwner || canManageMembers || has('cancelMemberships');

  bool get canReviewReceipts =>
      isPlatformOwner ||
      isOrgOwner ||
      const ['chairman', 'financialManager', 'financialReviewer']
          .contains(roleId) ||
      has('receipts.review') ||
      has('manageReceipts') ||
      has('payments.approve') ||
      has('payments.reject');

  bool get canReadAudit =>
      isPlatformOwner ||
      isSuperAdmin ||
      isLegacyAdmin ||
      isOrgOwner ||
      has('viewAuditLogs') ||
      has('audit.read') ||
      canManageRoles ||
      canReviewReceipts ||
      canReviewRequests;

  /// هل يستطيع المستخدم فتح/دخول هذا المجلس؟ المالك الأعلى العالمي يفتح أي
  /// مجلس، والعضو النشط يفتح مجلسه، ومن يملك صلاحية إدارية.
  bool get canOpenCouncil =>
      isPlatformOwner || isActiveMember || canAccessGoldenAdminPanel;

  /// لوحة الإدارة الذهبية: تظهر للمالك/الرئيس/المدير أو من يملك صلاحية إدارية،
  /// ولا تظهر للعضو العادي أو الموقوف.
  bool get canAccessGoldenAdminPanel =>
      isPlatformOwner ||
      isSuperAdmin ||
      isLegacyAdmin ||
      isSystemOwner ||
      isOrgOwner ||
      isChairman ||
      isAdminRole ||
      has('fullAccess') ||
      has('adminDashboard') ||
      has('manageMembers') ||
      has('members.manage') ||
      canReviewRequests ||
      canManageMembers ||
      canManageRoles ||
      canReviewReceipts ||
      has('organization.manage') ||
      has('reports.view');

  /// توافق خلفي: نفس معنى canAccessGoldenAdminPanel.
  bool get canOpenAdmin => canAccessGoldenAdminPanel;

  /// هل يمكن للمستخدم الحالي تعديل هذا العضو الهدف؟
  /// - المالك الأعلى العالمي (platform system_owner): يعدّل أي عضو بلا استثناء.
  /// - المالك الأساسي للمجلس هدفًا: لا يعدّله إلا المالك الأعلى العالمي —
  ///   لا رئيس مجلس ولا مدير إداري (حماية من التصعيد).
  bool canEditMember({
    required String targetRoleId,
    required bool targetIsPrimaryOwner,
    String targetRole = '',
  }) {
    if (isPlatformOwner) return true; // تجاوز عالمي
    final targetIsOwner = targetIsPrimaryOwner ||
        targetRoleId == 'system_owner' ||
        targetRole == 'system_owner' ||
        targetRole == 'owner';
    if (targetIsOwner) return false; // فقط المالك الأعلى العالمي يمسّ المالك
    return canChangeRoles || canManageMembers;
  }
}
