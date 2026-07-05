import 'package:cloud_firestore/cloud_firestore.dart';

import 'audit_log_model.dart';

/// طلب استعلام سجل الأحداث. المعرّف الوحيد للمجلس + نطاق زمني + حد،
/// حتى يبقى الاستعلام الخادمي بسيطًا وآمنًا (بدون فهارس مركّبة). بقية الفلاتر
/// (action / actorRole / targetType / الاسم) تُطبَّق في الواجهة على النتائج.
class AuditLogQuery {
  const AuditLogQuery({
    required this.organizationId,
    this.from,
    this.to,
    this.limit = 200,
  });

  final String organizationId;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is AuditLogQuery &&
      other.organizationId == organizationId &&
      other.from == from &&
      other.to == to &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(organizationId, from, to, limit);
}

class AuditLogRepository {
  AuditLogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _auditLogs(String organizationId) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('audit_logs');
  }

  /// يبثّ آخر سجلّات مجلس واحد بترتيب زمني تنازلي.
  /// المجلس محدّد بالمسار، فلا يمكن تسريب سجلات مجلس آخر.
  Stream<List<AuditLogEntry>> stream(AuditLogQuery query) {
    Query<Map<String, dynamic>> firestoreQuery =
        _auditLogs(query.organizationId).orderBy('createdAt', descending: true);

    // نطاق على نفس حقل الترتيب (createdAt) — لا يتطلب فهرسًا مركّبًا.
    if (query.from != null) {
      firestoreQuery = firestoreQuery.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(query.from!),
      );
    }
    if (query.to != null) {
      firestoreQuery = firestoreQuery.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(query.to!),
      );
    }

    return firestoreQuery.limit(query.limit).snapshots().map(
          (snapshot) =>
              snapshot.docs.map(AuditLogEntry.fromFirestore).toList(),
        );
  }
}
