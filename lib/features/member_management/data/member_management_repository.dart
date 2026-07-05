import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/membership_model.dart';
import '../../../data/repositories/notification_repository.dart';
import 'member_management_models.dart';

class MemberManagementRepository {
  MemberManagementRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  late final NotificationRepository _notifications =
      NotificationRepository(firestore: _firestore);

  CollectionReference<Map<String, dynamic>> _memberships(
    String organizationId,
  ) =>
      _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('memberships');

  CollectionReference<Map<String, dynamic>> get _history =>
      _firestore.collection('member_history');

  Future<MemberPage> getPage({
    required String organizationId,
    required MemberListFilter filter,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _memberships(organizationId);
    query = query.orderBy(
      _sortFieldPath(filter.sortField),
      descending: filter.descending,
    );
    if (startAfter != null) query = query.startAfterDocument(startAfter);

    final snapshot = await query.limit(limit).get();
    final members = await Future.wait(
      snapshot.docs.map((document) => _loadMember(organizationId, document)),
    );
    final search = filter.search.trim().toLowerCase();
    final filtered = members.where((member) {
      final matchesStatus =
          filter.status == null || member.membership.status == filter.status;
      final matchesRole =
          filter.roleId == null || member.membership.roleId == filter.roleId;
      final matchesSearch = search.isEmpty ||
          member.fullName.toLowerCase().contains(search) ||
          member.civilId.toLowerCase().contains(search) ||
          member.phone.toLowerCase().contains(search) ||
          member.membership.memberNumber.toLowerCase().contains(search);
      return matchesStatus && matchesRole && matchesSearch;
    }).toList();

    return MemberPage(
      members: filtered,
      nextCursor: snapshot.docs.isEmpty ? startAfter : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<ManagedMember?> getById({
    required String organizationId,
    required String userId,
  }) async {
    final document = await _memberships(organizationId).doc(userId).get();
    if (!document.exists) return null;
    return _loadMember(organizationId, document);
  }

  Stream<List<MemberHistoryEvent>> historyStream(String userId) {
    return _history
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(MemberHistoryEvent.fromFirestore).toList(),
        );
  }

  Future<void> activate({
    required String organizationId,
    required String userId,
    required String actorUserId,
  }) {
    return _changeStatus(
      organizationId: organizationId,
      userId: userId,
      actorUserId: actorUserId,
      newStatus: MembershipStatus.active,
    );
  }

  Future<void> suspend({
    required String organizationId,
    required String userId,
    required String actorUserId,
    String? reason,
  }) {
    return _changeStatus(
      organizationId: organizationId,
      userId: userId,
      actorUserId: actorUserId,
      newStatus: MembershipStatus.suspended,
      reason: reason,
    );
  }

  Future<void> changeRole({
    required String organizationId,
    required String userId,
    required String newRoleId,
    required String actorUserId,
  }) async {
    final membershipReference = _memberships(organizationId).doc(userId);
    debugPrint('[Members] role update path=${membershipReference.path}');
    final roleReference = _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('roles')
        .doc(newRoleId);
    final historyReference = _history.doc();
    final notificationId = 'membershipRoleChanged_$userId';
    final notificationReference = _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId);
    var changed = false;

    await _firestore.runTransaction((transaction) async {
      final membership = await transaction.get(membershipReference);
      final role = await transaction.get(roleReference);
      if (!membership.exists) throw StateError('Membership does not exist.');
      if (!role.exists) throw StateError('Role does not exist.');

      final previousRoleId = membership.data()?['roleId'] as String?;
      if (previousRoleId == newRoleId) return;
      changed = true;
      final permissions = List<String>.from(
        role.data()?['permissions'] as List<dynamic>? ?? const [],
      )..sort();
      transaction.update(membershipReference, {
        'roleId': newRoleId,
        'permissionsSnapshot': permissions.toSet().toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actorUserId,
      });
      transaction.set(historyReference, {
        'userId': userId,
        'type': MemberHistoryType.role.name,
        'organizationId': organizationId,
        'targetOrganizationId': null,
        'previousStatus': null,
        'newStatus': null,
        'previousRoleId': previousRoleId,
        'newRoleId': newRoleId,
        'actorUserId': actorUserId,
        'reason': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationReference, {
        'notificationId': notificationId,
        'userId': userId,
        'organizationId': organizationId,
        'title': 'تم تحديث دورك في المجلس',
        'body': 'تم تغيير دورك وصلاحياتك في المجلس.',
        'type': 'membershipRoleChanged',
        'relatedEntityType': 'membership',
        'relatedEntityId': userId,
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
        'createdByUserId': actorUserId,
      });
    });
    if (!changed) return;
  }

  bool _isPrimaryOwner(Map<String, dynamic>? data) {
    if (data == null) return false;
    return data['isPrimaryOwner'] == true ||
        data['roleId'] == 'system_owner' ||
        data['role'] == 'system_owner' ||
        data['role'] == 'owner';
  }

  /// نقل رئاسة المجلس: يرقّي عضواً نشطاً إلى رئيس المجلس (roleId: chairman)،
  /// ويخفّض الرئيس السابق إلى عضو — مع عدم المساس بالمالك الأساسي إطلاقاً.
  /// سجل الأحداث يُكتب خادميًّا عبر Cloud Function (auditMembershipWrite).
  Future<void> transferCouncilPresident({
    required String organizationId,
    required String newPresidentUserId,
    required String actorUserId,
  }) async {
    final memberships = _memberships(organizationId);
    final rolesCollection = _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('roles');
    final chairmanRoleReference = rolesCollection.doc('chairman');
    final memberRoleReference = rolesCollection.doc('member');
    final newPresidentReference = memberships.doc(newPresidentUserId);
    final historyReference = _history.doc();

    // قراءة الرؤساء الحاليين قبل المعاملة (لا يمكن الاستعلام داخل transaction).
    final currentChairmen =
        await memberships.where('roleId', isEqualTo: 'chairman').get();

    String? demotedUserId;
    await _firestore.runTransaction((transaction) async {
      final newSnapshot = await transaction.get(newPresidentReference);
      if (!newSnapshot.exists) {
        throw StateError('Target membership does not exist.');
      }
      final newData = newSnapshot.data()!;
      if (newData['status'] != MembershipStatus.active.name) {
        throw StateError('Only an active member can become president.');
      }
      if (_isPrimaryOwner(newData)) {
        throw StateError('The primary owner is already above the president.');
      }
      final chairmanRole = await transaction.get(chairmanRoleReference);
      final memberRole = await transaction.get(memberRoleReference);
      final chairmanPermissions = List<String>.from(
        chairmanRole.data()?['permissions'] as List<dynamic>? ?? const [],
      )..sort();
      final memberPermissions = List<String>.from(
        memberRole.data()?['permissions'] as List<dynamic>? ?? const [],
      )..sort();
      final now = FieldValue.serverTimestamp();

      // خفض الرئيس الحالي (أول chairman ليس هو الجديد وليس المالك الأساسي).
      for (final document in currentChairmen.docs) {
        if (document.id == newPresidentUserId) continue;
        if (_isPrimaryOwner(document.data())) continue; // لا نمسّ المالك أبدًا
        transaction.update(memberships.doc(document.id), {
          'roleId': 'member',
          'role': 'member',
          'permissionsSnapshot': memberPermissions.toSet().toList(),
          'updatedAt': now,
          'updatedBy': actorUserId,
        });
        demotedUserId = document.id;
        break; // رئيس واحد فقط
      }

      // ترقية الرئيس الجديد.
      transaction.update(newPresidentReference, {
        'roleId': 'chairman',
        'role': 'president',
        'permissionsSnapshot': chairmanPermissions.toSet().toList(),
        'updatedAt': now,
        'updatedBy': actorUserId,
      });
      transaction.set(historyReference, {
        'userId': newPresidentUserId,
        'type': MemberHistoryType.role.name,
        'organizationId': organizationId,
        'targetOrganizationId': null,
        'previousStatus': null,
        'newStatus': null,
        'previousRoleId': newData['roleId'],
        'newRoleId': 'chairman',
        'actorUserId': actorUserId,
        'reason': 'transferCouncilPresident',
        'createdAt': now,
      });
    });

    await _notifySafely(
      userId: newPresidentUserId,
      organizationId: organizationId,
      title: 'تم تعيينك رئيساً للمجلس',
      body: 'تم تعيينك رئيساً للمجلس.',
      type: 'councilPresidentAssigned',
      relatedEntityId: newPresidentUserId,
      actorUserId: actorUserId,
    );
    final demoted = demotedUserId;
    if (demoted != null) {
      await _notifySafely(
        userId: demoted,
        organizationId: organizationId,
        title: 'تم تغيير رئاسة المجلس',
        body: 'تم نقل رئاسة المجلس إلى عضو آخر.',
        type: 'councilPresidentChanged',
        relatedEntityId: demoted,
        actorUserId: actorUserId,
      );
    }
  }

  /// تحديث دور وصلاحيات عضو (من شاشة تعديل الصلاحيات). يحمي المالك الأساسي،
  /// ويمنع إسناد system_owner من التطبيق. السجل يُكتب خادميًّا عبر CF.
  Future<void> updateMemberPermissions({
    required String organizationId,
    required String userId,
    required String newRoleId,
    required List<String> permissions,
    required String actorUserId,
  }) async {
    if (newRoleId == 'system_owner') {
      throw StateError('Cannot assign system_owner from the app.');
    }
    final reference = _memberships(organizationId).doc(userId);
    final historyReference = _history.doc();
    final sorted = permissions.toSet().toList()..sort();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw StateError('Membership does not exist.');
      final data = snapshot.data()!;
      if (_isPrimaryOwner(data)) {
        throw StateError('Cannot edit the primary owner from the app.');
      }
      final previousRoleId = data['roleId'] as String?;
      transaction.update(reference, {
        'roleId': newRoleId,
        'permissionsSnapshot': sorted,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actorUserId,
      });
      transaction.set(historyReference, {
        'userId': userId,
        'type': MemberHistoryType.role.name,
        'organizationId': organizationId,
        'targetOrganizationId': null,
        'previousStatus': null,
        'newStatus': null,
        'previousRoleId': previousRoleId,
        'newRoleId': newRoleId,
        'actorUserId': actorUserId,
        'reason': 'updateMemberPermissions',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    await _notifySafely(
      userId: userId,
      organizationId: organizationId,
      title: 'تم تحديث صلاحياتك',
      body: 'تم تحديث دورك وصلاحياتك في المجلس.',
      type: 'membershipPermissionsUpdated',
      relatedEntityId: userId,
      actorUserId: actorUserId,
    );
  }

  Future<void> transferOrganization({
    required String sourceOrganizationId,
    required String targetOrganizationId,
    required String userId,
    required String actorUserId,
    String targetRoleId = 'member',
  }) async {
    if (sourceOrganizationId == targetOrganizationId) {
      throw ArgumentError('Source and target organizations must differ.');
    }
    final sourceReference = _memberships(sourceOrganizationId).doc(userId);
    final targetReference = _memberships(targetOrganizationId).doc(userId);
    final roleReference = _firestore
        .collection('organizations')
        .doc(targetOrganizationId)
        .collection('roles')
        .doc(targetRoleId);
    final historyReference = _history.doc();

    await _firestore.runTransaction((transaction) async {
      final source = await transaction.get(sourceReference);
      final target = await transaction.get(targetReference);
      final role = await transaction.get(roleReference);
      if (!source.exists) throw StateError('Source membership does not exist.');
      if (target.exists) throw StateError('Target membership already exists.');
      if (!role.exists) throw StateError('Target role does not exist.');

      final sourceData = source.data()!;
      final permissions = List<String>.from(
        role.data()?['permissions'] as List<dynamic>? ?? const [],
      )..sort();
      final now = FieldValue.serverTimestamp();
      transaction.set(targetReference, {
        ...sourceData,
        'organizationId': targetOrganizationId,
        'memberNumber': _temporaryMemberNumber(userId),
        'roleId': targetRoleId,
        'status': MembershipStatus.active.name,
        'joinedAt': now,
        'approvedBy': actorUserId,
        'approvedAt': now,
        'isPrimary': false,
        'permissionsSnapshot': permissions.toSet().toList(),
        'joinedReason': 'organizationTransfer',
        'leftReason': null,
      });
      transaction.delete(sourceReference);
      transaction.set(historyReference, {
        'userId': userId,
        'type': MemberHistoryType.organization.name,
        'organizationId': sourceOrganizationId,
        'targetOrganizationId': targetOrganizationId,
        'previousStatus': sourceData['status'],
        'newStatus': MembershipStatus.active.name,
        'previousRoleId': sourceData['roleId'],
        'newRoleId': targetRoleId,
        'actorUserId': actorUserId,
        'reason': 'organizationTransfer',
        'createdAt': now,
      });
    });
  }

  Future<void> _notifySafely({
    required String userId,
    required String organizationId,
    required String title,
    required String body,
    required String type,
    required String relatedEntityId,
    required String actorUserId,
  }) async {
    try {
      await _notifications.createForUser(
        userId: userId,
        organizationId: organizationId,
        title: title,
        body: body,
        type: type,
        relatedEntityType: 'membership',
        relatedEntityId: relatedEntityId,
        createdByUserId: actorUserId,
      );
    } on FirebaseException catch (error) {
      debugPrint('[Notifications] membership event skipped: ${error.code}');
    }
  }

  Future<void> remove({
    required String organizationId,
    required String userId,
    required String actorUserId,
    String? reason,
  }) async {
    final membershipReference = _memberships(organizationId).doc(userId);
    debugPrint('[Members] membership removal path=${membershipReference.path}');
    final requestReference = _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('membership_requests')
        .doc(userId);
    final historyReference = _history.doc();
    await _firestore.runTransaction((transaction) async {
      final membership = await transaction.get(membershipReference);
      if (!membership.exists) throw StateError('Membership does not exist.');
      final request = await transaction.get(requestReference);
      final data = membership.data()!;
      final now = FieldValue.serverTimestamp();
      transaction.update(membershipReference, {
        'status': MembershipStatus.removed.name,
        'removedAt': now,
        'removedBy': actorUserId,
        'leftReason': reason,
        'updatedAt': now,
      });
      if (request.exists && request.data()?['status'] == 'approved') {
        transaction.update(requestReference, {
          'status': 'cancelled',
          'cancelledAt': now,
          'cancelledBy': actorUserId,
        });
      }
      transaction.set(historyReference, {
        'userId': userId,
        'type': MemberHistoryType.removed.name,
        'organizationId': organizationId,
        'targetOrganizationId': null,
        'previousStatus': data['status'],
        'newStatus': MembershipStatus.removed.name,
        'previousRoleId': data['roleId'],
        'newRoleId': null,
        'actorUserId': actorUserId,
        'reason': reason,
        'createdAt': now,
      });
    });
    await _notifySafely(
      userId: userId,
      organizationId: organizationId,
      title: 'تمت إزالة العضوية',
      body: 'تمت إزالة عضويتك من المجلس.',
      type: 'membershipRemoved',
      relatedEntityId: userId,
      actorUserId: actorUserId,
    );
  }

  Future<void> _changeStatus({
    required String organizationId,
    required String userId,
    required String actorUserId,
    required MembershipStatus newStatus,
    String? reason,
  }) async {
    final membershipReference = _memberships(organizationId).doc(userId);
    final historyReference = _history.doc();
    await _firestore.runTransaction((transaction) async {
      final membership = await transaction.get(membershipReference);
      if (!membership.exists) throw StateError('Membership does not exist.');
      final previousStatus = membership.data()?['status'] as String?;
      if (previousStatus == newStatus.name) return;
      transaction.update(membershipReference, {
        'status': newStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actorUserId,
      });
      transaction.set(historyReference, {
        'userId': userId,
        'type': MemberHistoryType.status.name,
        'organizationId': organizationId,
        'targetOrganizationId': null,
        'previousStatus': previousStatus,
        'newStatus': newStatus.name,
        'previousRoleId': null,
        'newRoleId': null,
        'actorUserId': actorUserId,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<ManagedMember> _loadMember(
    String organizationId,
    DocumentSnapshot<Map<String, dynamic>> membershipDocument,
  ) async {
    final membership = MembershipModel.fromFirestore(membershipDocument);
    final membershipData = membershipDocument.data() ?? const {};
    final results = await Future.wait([
      _safeDocumentData(_firestore.collection('users').doc(membership.userId)),
      _safeDocumentData(
        _firestore.collection('members').doc(membership.userId),
      ),
      _safeDocumentData(
        _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('roles')
            .doc(membership.roleId),
      ),
    ]);
    final userData = results[0];
    final legacyData = results[1];
    final roleData = results[2];
    return ManagedMember(
      membership: membership,
      personalData: {
        ...membershipData,
        ...legacyData,
        ...userData,
      },
      roleData: roleData,
    );
  }

  Future<Map<String, dynamic>> _safeDocumentData(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      return (await reference.get()).data() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  String _sortFieldPath(MemberSortField field) {
    return switch (field) {
      MemberSortField.joinedAt => 'joinedAt',
      MemberSortField.memberNumber => 'memberNumber',
      MemberSortField.status => 'status',
      MemberSortField.role => 'roleId',
    };
  }

  String _temporaryMemberNumber(String userId) {
    final userPart = userId.length <= 6 ? userId : userId.substring(0, 6);
    final timePart =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'TMP-$userPart-$timePart';
  }
}
