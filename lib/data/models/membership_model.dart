import 'package:cloud_firestore/cloud_firestore.dart';

enum MembershipStatus {
  pending,
  active,
  suspended,
  rejected,
  resigned,
  removed,
  cancelled,
}

class MembershipModel {
  final String id;
  final String userId;
  final String organizationId;
  final String memberNumber;
  final String roleId;
  // تسمية الدور الوصفية (owner/president/...) بجانب roleId. للعرض والتمييز؛
  // الأمان يعتمد على roleId + permissionsSnapshot + platform_admins.
  final String role;
  final MembershipStatus status;
  final DateTime joinedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final bool isPrimary;
  // المالك الأساسي للمجلس؛ system_owner منصة منفصل، مع حماية صيغة legacy.
  final bool isPrimaryOwner;
  final List<String> permissionsSnapshot;
  final String? joinedReason;
  final String? invitedBy;
  final String? leftReason;

  const MembershipModel({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.memberNumber,
    required this.roleId,
    this.role = '',
    required this.status,
    required this.joinedAt,
    this.approvedBy,
    this.approvedAt,
    required this.isPrimary,
    this.isPrimaryOwner = false,
    this.permissionsSnapshot = const [],
    this.joinedReason,
    this.invitedBy,
    this.leftReason,
  });

  // هل هذه العضوية هي المالك الأساسي للنظام؟ (لا تعتمد على memberNumber).
  bool get isOwnerMembership =>
      isPrimaryOwner ||
      const {'owner', 'council_owner', 'system_owner'}.contains(roleId) ||
      const {'owner', 'council_owner', 'system_owner'}.contains(role);

  factory MembershipModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return MembershipModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      organizationId: data['organizationId'] ?? '',
      memberNumber: data['memberNumber'] ?? '',
      roleId: data['roleId'] ?? 'member',
      role: data['role'] as String? ?? '',
      isPrimaryOwner: data['isPrimaryOwner'] == true,
      status: MembershipStatus.values.firstWhere(
        (status) => status.name == (data['status'] ?? 'pending'),
        orElse: () => MembershipStatus.pending,
      ),
      joinedAt: _optionalDateTime(data['joinedAt']) ??
          _optionalDateTime(data['approvedAt']) ??
          _optionalDateTime(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      approvedBy: data['approvedBy'],
      approvedAt: _optionalDateTime(data['approvedAt']),
      isPrimary: data['isPrimary'] ?? false,
      permissionsSnapshot: List<String>.from(
        data['permissionsSnapshot'] as List<dynamic>? ?? const [],
      ),
      joinedReason: data['joinedReason'],
      invitedBy: data['invitedBy'],
      leftReason: data['leftReason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'organizationId': organizationId,
      'memberNumber': memberNumber,
      'roleId': roleId,
      'role': role,
      'isPrimaryOwner': isPrimaryOwner,
      'status': status.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'approvedBy': approvedBy,
      'approvedAt': approvedAt == null ? null : Timestamp.fromDate(approvedAt!),
      'isPrimary': isPrimary,
      'permissionsSnapshot': permissionsSnapshot,
      'joinedReason': joinedReason,
      'invitedBy': invitedBy,
      'leftReason': leftReason,
    };
  }

  MembershipModel copyWith({
    String? id,
    String? userId,
    String? organizationId,
    String? memberNumber,
    String? roleId,
    String? role,
    MembershipStatus? status,
    DateTime? joinedAt,
    String? approvedBy,
    DateTime? approvedAt,
    bool? isPrimary,
    bool? isPrimaryOwner,
    List<String>? permissionsSnapshot,
    String? joinedReason,
    String? invitedBy,
    String? leftReason,
  }) {
    return MembershipModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      memberNumber: memberNumber ?? this.memberNumber,
      roleId: roleId ?? this.roleId,
      role: role ?? this.role,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      isPrimary: isPrimary ?? this.isPrimary,
      isPrimaryOwner: isPrimaryOwner ?? this.isPrimaryOwner,
      permissionsSnapshot: permissionsSnapshot ?? this.permissionsSnapshot,
      joinedReason: joinedReason ?? this.joinedReason,
      invitedBy: invitedBy ?? this.invitedBy,
      leftReason: leftReason ?? this.leftReason,
    );
  }

  bool get isApproved =>
      status == MembershipStatus.active && approvedAt != null;
}

DateTime? _optionalDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
