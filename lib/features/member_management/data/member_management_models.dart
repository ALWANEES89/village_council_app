import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/models/membership_model.dart';

enum MemberSortField { joinedAt, memberNumber, status, role }

class MemberListFilter {
  final String search;
  final MembershipStatus? status;
  final String? roleId;
  final MemberSortField sortField;
  final bool descending;

  const MemberListFilter({
    this.search = '',
    this.status,
    this.roleId,
    this.sortField = MemberSortField.joinedAt,
    this.descending = true,
  });

  MemberListFilter copyWith({
    String? search,
    MembershipStatus? status,
    bool clearStatus = false,
    String? roleId,
    bool clearRole = false,
    MemberSortField? sortField,
    bool? descending,
  }) {
    return MemberListFilter(
      search: search ?? this.search,
      status: clearStatus ? null : status ?? this.status,
      roleId: clearRole ? null : roleId ?? this.roleId,
      sortField: sortField ?? this.sortField,
      descending: descending ?? this.descending,
    );
  }
}

class ManagedMember {
  final MembershipModel membership;
  final Map<String, dynamic> personalData;
  final Map<String, dynamic> roleData;

  const ManagedMember({
    required this.membership,
    required this.personalData,
    required this.roleData,
  });

  String get userId => membership.userId;
  String get fullName => personalData['fullName'] as String? ?? '';
  String get civilId => personalData['civilId'] as String? ?? '';
  String get phone => personalData['phone'] as String? ?? '';
  String get email => personalData['email'] as String? ?? '';
  String get address => personalData['address'] as String? ?? '';

  String get roleName {
    final value = roleData['roleName'];
    if (value is Map && value['ar'] is String) return value['ar'] as String;
    if (value is String && value.isNotEmpty) return value;
    return membership.roleId;
  }
}

class MemberPage {
  final List<ManagedMember> members;
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;
  final bool hasMore;

  const MemberPage({
    required this.members,
    required this.nextCursor,
    required this.hasMore,
  });
}

enum MemberHistoryType { status, role, organization, removed }

class MemberHistoryEvent {
  final String id;
  final String userId;
  final MemberHistoryType type;
  final String? organizationId;
  final String? targetOrganizationId;
  final String? previousStatus;
  final String? newStatus;
  final String? previousRoleId;
  final String? newRoleId;
  final String actorUserId;
  final String? reason;
  final DateTime? createdAt;

  const MemberHistoryEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.organizationId,
    required this.targetOrganizationId,
    required this.previousStatus,
    required this.newStatus,
    required this.previousRoleId,
    required this.newRoleId,
    required this.actorUserId,
    required this.reason,
    required this.createdAt,
  });

  factory MemberHistoryEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final typeName = data['type'] as String? ?? 'status';
    return MemberHistoryEvent(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      type: MemberHistoryType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => MemberHistoryType.status,
      ),
      organizationId: data['organizationId'] as String?,
      targetOrganizationId: data['targetOrganizationId'] as String?,
      previousStatus: data['previousStatus'] as String?,
      newStatus: data['newStatus'] as String?,
      previousRoleId: data['previousRoleId'] as String?,
      newRoleId: data['newRoleId'] as String?,
      actorUserId: data['actorUserId'] as String? ?? '',
      reason: data['reason'] as String?,
      createdAt: _dateTime(data['createdAt']),
    );
  }
}

DateTime? _dateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
