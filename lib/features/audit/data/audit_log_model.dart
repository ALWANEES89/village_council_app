import 'package:cloud_firestore/cloud_firestore.dart';

/// سجل حدث واحد من `organizations/{organizationId}/audit_logs`.
/// للقراءة فقط — يُكتب حصريًّا من Cloud Functions (Admin SDK).
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.organizationId,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    this.targetType,
    this.targetId,
    this.oldValue,
    this.newValue,
    this.createdAt,
    this.source,
    this.platform,
  });

  final String id;
  final String action;
  final String organizationId;
  final String? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String? targetType;
  final String? targetId;
  final Object? oldValue;
  final Object? newValue;
  final DateTime? createdAt;
  final String? source;
  final String? platform;

  factory AuditLogEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    return AuditLogEntry(
      id: snapshot.id,
      action: (data['action'] as String?)?.trim().isNotEmpty == true
          ? data['action'] as String
          : 'unknown',
      organizationId: data['organizationId'] as String? ??
          snapshot.reference.parent.parent?.id ??
          '',
      actorUserId: data['actorUserId'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
      targetType: data['targetType'] as String?,
      targetId: data['targetId'] as String?,
      oldValue: data['oldValue'],
      newValue: data['newValue'],
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
      source: data['source'] as String?,
      platform: data['platform'] as String?,
    );
  }
}
