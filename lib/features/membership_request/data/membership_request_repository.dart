import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/services/organization_seed_service.dart';
import 'membership_request_model.dart';

class DuplicatePendingMembershipRequestException implements Exception {
  const DuplicatePendingMembershipRequestException();

  @override
  String toString() => 'A pending membership request already exists.';
}

class MembershipRequestRepository {
  MembershipRequestRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _requests(String organizationId) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('membership_requests');
  }

  Future<void> submit(MembershipRequestModel request) async {
    if (request.requestId != request.userId) {
      throw ArgumentError.value(
        request.requestId,
        'requestId',
        'Request ID must equal user ID to enforce one active request.',
      );
    }
    if (request.status != MembershipRequestStatus.pending) {
      throw ArgumentError('A new membership request must be pending.');
    }

    final reference = _requests(request.organizationId).doc(request.requestId);
    final membershipReference = _firestore
        .collection('organizations')
        .doc(request.organizationId)
        .collection('memberships')
        .doc(request.userId);
    final membershipsByUser = await _firestore
        .collection('organizations')
        .doc(request.organizationId)
        .collection('memberships')
        .where('userId', isEqualTo: request.userId)
        .get();
    if (membershipsByUser.docs.any(
      (document) => document.data()['status'] == 'active',
    )) {
      throw StateError('This user already has an active membership.');
    }
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) {
        final status = existing.data()?['status'];
        if (status == MembershipRequestStatus.pending.name) {
          throw const DuplicatePendingMembershipRequestException();
        }
      }

      final membership = await transaction.get(membershipReference);
      if (membership.exists && membership.data()?['status'] == 'active') {
        throw StateError('This user already has an active membership.');
      }

      transaction.set(reference, request.toFirestore());
    });
  }

  Future<MembershipRequestModel?> getById({
    required String organizationId,
    required String requestId,
  }) async {
    final snapshot = await _requests(organizationId).doc(requestId).get();
    if (!snapshot.exists) return null;
    return MembershipRequestModel.fromFirestore(snapshot);
  }

  Stream<MembershipRequestModel?> stream({
    required String organizationId,
    required String requestId,
  }) {
    return _requests(organizationId).doc(requestId).snapshots().map(
          (snapshot) => snapshot.exists
              ? MembershipRequestModel.fromFirestore(snapshot)
              : null,
        );
  }

  Stream<List<MembershipRequestModel>> streamForUser(String userId) {
    return _firestore
        .collectionGroup('membership_requests')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final requests =
          snapshot.docs.map(MembershipRequestModel.fromFirestore).toList();
      requests
          .sort((left, right) => right.submittedAt.compareTo(left.submittedAt));
      return requests;
    });
  }

  Stream<List<MembershipRequestModel>> streamPendingForOrganization(
    String organizationId,
  ) {
    return _requests(organizationId)
        .where('status', isEqualTo: MembershipRequestStatus.pending.name)
        .orderBy('submittedAt')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(MembershipRequestModel.fromFirestore).toList(),
        );
  }

  Future<void> approve({
    required String organizationId,
    required String requestId,
    required String reviewedBy,
  }) async {
    const assignedRoleId = 'member';
    final requestReference = _requests(organizationId).doc(requestId);
    final organizationReference =
        _firestore.collection('organizations').doc(organizationId);
    final roleReference =
        organizationReference.collection('roles').doc(assignedRoleId);
    final counterReference =
        organizationReference.collection('counters').doc('memberships');
    final historyReference = _firestore.collection('member_history').doc();

    final existingMemberships =
        await organizationReference.collection('memberships').get();
    final currentMaximum =
        existingMemberships.docs.fold<int>(0, (maximum, doc) {
      final parsed = int.tryParse(doc.data()['memberNumber']?.toString() ?? '');
      return parsed != null && parsed > maximum ? parsed : maximum;
    });

    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestReference);
      if (!requestSnapshot.exists) {
        throw StateError('Membership request does not exist.');
      }
      final request = MembershipRequestModel.fromFirestore(requestSnapshot);
      if (request.organizationId != organizationId) {
        throw StateError('Request organization does not match.');
      }
      if (request.status != MembershipRequestStatus.pending) {
        throw StateError('Only pending requests can be approved.');
      }

      final membershipReference =
          organizationReference.collection('memberships').doc(request.userId);
      final roleSnapshot = await transaction.get(roleReference);
      final roleData = roleSnapshot.data() ??
          OrganizationSeedService.instance.defaultRoles[assignedRoleId]!;
      final permissions = List<String>.from(
        roleData['permissions'] as List<dynamic>? ?? const [],
      )..sort();

      final existingMembership = await transaction.get(membershipReference);
      final existingMembershipData = existingMembership.data();

      // لا نقرأ مستند المتقدّم users/{userId}: قاعدة قراءة users تسمح لصاحب
      // المستند أو الأدمن فقط، فقراءته هنا كانت تُفشل معاملة القبول كاملةً
      // (permission-denied) لأي مراجِع ليس أدمن عامًّا (رئيس/مدير مجلس).
      final counterSnapshot = await transaction.get(counterReference);
      final storedCounter =
          counterSnapshot.data()?['lastMemberNumber'] as int? ?? 0;
      final nextMemberNumber =
          (storedCounter > currentMaximum ? storedCounter : currentMaximum) + 1;
      final existingMemberNumber =
          existingMembershipData?['memberNumber']?.toString().trim() ?? '';
      final resolvedMemberNumber = existingMemberNumber.isNotEmpty
          ? existingMemberNumber
          : nextMemberNumber.toString().padLeft(3, '0');
      final now = FieldValue.serverTimestamp();
      transaction.set(
          membershipReference,
          {
            'userId': request.userId,
            'organizationId': organizationId,
            'memberNumber': resolvedMemberNumber,
            'roleId': assignedRoleId,
            'status': 'active',
            'joinedAt': existingMembershipData?['joinedAt'] ?? now,
            'approvedBy': reviewedBy,
            'approvedAt': now,
            'isPrimary': existingMembershipData?['isPrimary'] == true,
            'permissionsSnapshot': permissions.toSet().toList(),
            'joinedReason': 'membershipRequest',
            'invitedBy': null,
            // إعادة القبول تبدأ عضوية نظيفة: نمسح كل حقول الطرد/المغادرة السابقة
            // (merge:true لا يحذفها تلقائيًّا) حتى لا تبقى بيانات طرد قديمة عالقة.
            'leftReason': null,
            'removedAt': null,
            'removedBy': null,
            'fullName': request.fullName,
            'civilId': request.civilId,
            'phone': request.phone,
            'email': request.email,
            'address': request.address,
            'createdAt': existingMembershipData?['createdAt'] ?? now,
            'updatedAt': now,
          },
          SetOptions(merge: true));
      transaction.update(requestReference, {
        'status': MembershipRequestStatus.approved.name,
        'reviewedAt': now,
        'reviewedBy': reviewedBy,
        'rejectionReason': null,
      });
      // لا نكتب مؤشّرات activeOrganizationId/primaryOrganizationId على مستند
      // المتقدّم: لا يقرؤها أي كود في التطبيق (حقول غير مستخدمة)، وكتابتها من
      // مراجِع غير مالك للمستند غير ضرورية. اعتماد العضوية يبقى ذرّيًّا وكاملًا.
      if (existingMemberNumber.isEmpty) {
        transaction.set(counterReference, {
          'lastMemberNumber': nextMemberNumber,
          'updatedAt': now,
          'updatedBy': reviewedBy,
        });
      }
      // سجل التدقيق يُكتب الآن خادميًّا عبر Cloud Functions
      // (auditMembershipRequestWrite عند تحوّل الحالة إلى approved،
      // و auditMembershipWrite عند إنشاء العضوية). member_history يبقى كسجل
      // خاص بالعضو ويُكتب من العميل.
      transaction.set(historyReference, {
        'userId': request.userId,
        'type': 'status',
        'organizationId': organizationId,
        'targetOrganizationId': null,
        'previousStatus': null,
        'newStatus': 'active',
        'previousRoleId': null,
        'newRoleId': assignedRoleId,
        'actorUserId': reviewedBy,
        'reason': 'membershipRequestApproved',
        'createdAt': now,
      });
    });
  }

  Future<void> reject({
    required String organizationId,
    required String requestId,
    required String reviewedBy,
    required String rejectionReason,
  }) async {
    final reason = rejectionReason.trim();
    if (reason.isEmpty) {
      throw ArgumentError.value(
        rejectionReason,
        'rejectionReason',
        'A rejection reason is required.',
      );
    }

    final reference = _requests(organizationId).doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data()?['status'] != 'pending') {
        throw StateError('Only pending requests can be rejected.');
      }
      transaction.update(reference, {
        'status': MembershipRequestStatus.rejected.name,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': reviewedBy,
        'rejectionReason': reason,
      });
    });
  }

  Future<void> cancel({
    required String organizationId,
    required String requestId,
    required String userId,
  }) async {
    final reference = _requests(organizationId).doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['status'] != MembershipRequestStatus.pending.name ||
          data?['userId'] != userId) {
        throw StateError('Only the owner can cancel a pending request.');
      }
      transaction.update(reference, {
        'status': MembershipRequestStatus.cancelled.name,
      });
    });
  }
}
