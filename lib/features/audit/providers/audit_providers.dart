import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/membership_model.dart';
import '../data/audit_log_model.dart';
import '../data/audit_log_repository.dart';

final auditLogRepositoryProvider = Provider((ref) => AuditLogRepository());

/// سجلّات مجلس واحد (بثّ حيّ). المفتاح يتضمن organizationId فيتغيّر الاشتراك
/// عند تبديل المجلس فقط.
final auditLogsProvider =
    StreamProvider.family<List<AuditLogEntry>, AuditLogQuery>((ref, query) {
  return ref.watch(auditLogRepositoryProvider).stream(query);
});

/// هل تمنح هذه العضوية صلاحية قراءة سجل الأحداث؟
/// مطابقة تمامًا لقاعدة Firestore لقراءة audit_logs:
/// canManageRoles ∪ canReviewReceipts ∪ canReviewMembershipRequests.
bool membershipCanReadAudit(MembershipModel membership) {
  if (membership.status != MembershipStatus.active) return false;
  const financeRoles = ['chairman', 'financialManager', 'financialReviewer'];
  const auditPermissions = {
    'fullAccess',
    'roles.manage',
    'receipts.review',
    'payments.approve',
    'payments.reject',
    'membershipRequests.review',
    'membership_requests.review',
    'memberships.review',
    'members.approve',
    'members.manage',
  };
  if (financeRoles.contains(membership.roleId)) return true;
  return membership.permissionsSnapshot.any(auditPermissions.contains);
}
