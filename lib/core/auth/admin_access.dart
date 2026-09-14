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

  bool get _isPlainMemberRole => roleId == 'member' || role == 'member';

  bool has(String permission) {
    if (isSuperAdmin) return true;
    final hasEffectiveFullAccess =
        !_isPlainMemberRole && permissions.contains('fullAccess');
    if (permission == 'fullAccess') return hasEffectiveFullAccess;
    return hasEffectiveFullAccess || permissions.contains(permission);
  }

  // ── الأدوار ────────────────────────────────────────────────────────────
  bool get isActiveMember => status == 'active';
  bool get isSuspended => status == 'suspended';

  /// مالك المنصّة الأعلى العالمي (Global Override): مصدره الوحيد الموثوق هو
  /// مستند platform_admins/{uid} (role=system_owner, status=active,
  /// fullAccess=true) المنعكس في [isSuperAdmin]. هذه الصلاحية **عالمية** تتغلّب
  /// على أي دور محلي داخل أي مجلس. لا تعتمد على roleId/role داخل العضوية.
  bool get isPlatformOwner => isSuperAdmin;

  /// المالك الأعلى للمنصة فقط؛ لا يُستنتج من دور عضوية مجلس.
  bool get isSystemOwner => isPlatformOwner;

  bool get isPlatformAdmin => isSuperAdmin;

  /// مالك داخل المجلس (له صلاحيات كاملة داخل مجلسه).
  bool get isOrgOwner =>
      isPlatformOwner ||
      isPrimaryOwner ||
      roleId == 'owner' ||
      roleId == 'council_owner' ||
      role == 'owner' ||
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
      isPlatformOwner ||
      isOrgOwner ||
      has('roles.manage') ||
      has('changeRoles');

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

  bool get canManageFinancialSettings =>
      isPlatformOwner ||
      isOrgOwner ||
      const ['system_owner', 'chairman', 'financialManager'].contains(roleId) ||
      const ['system_owner', 'chairman', 'financialManager'].contains(role) ||
      has('fullAccess') ||
      has('payments.manage');

  /// توافق خلفي لاسم القدرة المستخدم في لوحة الإدارة.
  bool get canManageFinance => canManageFinancialSettings;

  bool get canSendCouncilNotifications =>
      isPlatformOwner ||
      isOrgOwner ||
      isChairman ||
      has('notifications.send') ||
      has('announcements.manage');

  bool get canViewFinancialReports =>
      isPlatformOwner ||
      isOrgOwner ||
      const ['chairman', 'financialManager', 'financialReviewer']
          .contains(roleId) ||
      has('reports.view') ||
      has('payments.read') ||
      canManageFinancialSettings ||
      canReviewReceipts;

  bool get canManageExpenses =>
      isPlatformOwner ||
      isOrgOwner ||
      const ['chairman', 'financialManager'].contains(roleId) ||
      has('expenses.manage') ||
      has('payments.manage');

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
  /// - المالك الأعلى العالمي يعدّل العضويات العادية في أي مجلس.
  /// - المالك الأساسي لا يعدّله أي عميل؛ نقله يتم عبر callable ذري فقط.
  bool canEditMember({
    required String targetRoleId,
    required bool targetIsPrimaryOwner,
    String targetRole = '',
  }) {
    final targetIsOwner = targetIsPrimaryOwner ||
        const {'owner', 'council_owner', 'system_owner'}
            .contains(targetRoleId) ||
        const {'owner', 'council_owner', 'system_owner'}.contains(targetRole);
    // حتى system_owner يستخدم callable ذريًا لنقل الملكية، لا تعديل العميل.
    if (targetIsOwner) return false;
    if (isPlatformOwner) return true;
    return canChangeRoles || canManageMembers;
  }
}
