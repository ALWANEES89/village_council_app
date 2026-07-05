import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/membership_model.dart';

class ActiveMembershipsResult {
  const ActiveMembershipsResult({
    required this.memberships,
    this.loadFailed = false,
  });

  final List<MembershipModel> memberships;
  final bool loadFailed;
}

class _FallbackMembershipsResult {
  const _FallbackMembershipsResult({
    required this.memberships,
    required this.failed,
  });

  final List<MembershipModel> memberships;
  final bool failed;
}

class MembershipRepository {
  MembershipRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _memberships(
    String organizationId,
  ) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('memberships');
  }

  Future<void> create(MembershipModel membership) {
    return _memberships(membership.organizationId)
        .doc(membership.id)
        .set(membership.toFirestore());
  }

  Future<void> update(MembershipModel membership) {
    return _memberships(membership.organizationId)
        .doc(membership.id)
        .update(membership.toFirestore());
  }

  Future<void> delete({
    required String organizationId,
    required String membershipId,
  }) {
    return _memberships(organizationId).doc(membershipId).delete();
  }

  Future<MembershipModel?> getById({
    required String organizationId,
    required String membershipId,
  }) async {
    final snapshot = await _memberships(organizationId).doc(membershipId).get();
    if (!snapshot.exists) return null;
    return MembershipModel.fromFirestore(snapshot);
  }

  Stream<MembershipModel?> stream({
    required String organizationId,
    required String membershipId,
  }) {
    return _memberships(organizationId).doc(membershipId).snapshots().map(
        (snapshot) =>
            snapshot.exists ? MembershipModel.fromFirestore(snapshot) : null);
  }

  Stream<List<MembershipModel>> streamForUser(String userId) {
    return _firestore
        .collectionGroup('memberships')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final memberships =
          snapshot.docs.map(MembershipModel.fromFirestore).toList();
      memberships.sort((left, right) {
        if (left.isPrimary != right.isPrimary) {
          return left.isPrimary ? -1 : 1;
        }
        return left.joinedAt.compareTo(right.joinedAt);
      });
      return memberships;
    });
  }

  Stream<ActiveMembershipsResult> streamActiveForUser(String userId) async* {
    debugPrint('[Memberships] currentUser.uid=$userId');
    var lastNonEmpty = <MembershipModel>[];
    try {
      await for (final snapshot in _firestore
          .collectionGroup('memberships')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: MembershipStatus.active.name)
          .snapshots()) {
        final primaryMemberships = await _resolveDocuments(
          snapshot.docs,
          requestedUserId: userId,
        );
        if (primaryMemberships.isNotEmpty) {
          lastNonEmpty = primaryMemberships;
          debugPrint('[Memberships] loaded via collectionGroup');
          _debugMemberships(primaryMemberships);
          yield ActiveMembershipsResult(memberships: primaryMemberships);
          continue;
        }

        final fallback = await _loadByOrganization(userId);
        if (fallback.memberships.isNotEmpty) {
          lastNonEmpty = fallback.memberships;
        }
        yield ActiveMembershipsResult(
          memberships: fallback.failed && fallback.memberships.isEmpty
              ? lastNonEmpty
              : fallback.memberships,
          loadFailed: fallback.failed,
        );
      }
    } on FirebaseException catch (error) {
      debugPrint(
        '[Memberships] collectionGroup failed '
        'code=${error.code} message=${error.message}',
      );
      final fallback = await _loadByOrganization(userId);
      if (fallback.memberships.isNotEmpty) {
        lastNonEmpty = fallback.memberships;
      }
      yield ActiveMembershipsResult(
        memberships: fallback.failed && fallback.memberships.isEmpty
            ? lastNonEmpty
            : fallback.memberships,
        loadFailed: fallback.failed,
      );
    }
  }

  Future<_FallbackMembershipsResult> _loadByOrganization(String userId) async {
    QuerySnapshot<Map<String, dynamic>> organizations;
    try {
      organizations = await _firestore
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        '[Memberships] organizations lookup failed '
        'code=${error.code} message=${error.message}\n$stackTrace',
      );
      debugPrint('[Memberships] organizations checked count=0');
      debugPrint('[Memberships] memberships found count=0');
      return const _FallbackMembershipsResult(
        memberships: [],
        failed: true,
      );
    }

    debugPrint(
      '[Memberships] organizations checked count=${organizations.docs.length}',
    );
    final documentsByPath = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    var lookupFailures = 0;
    for (final organization in organizations.docs) {
      final memberships = organization.reference.collection('memberships');
      try {
        final direct = await memberships.doc(userId).get();
        if (direct.exists) documentsByPath[direct.reference.path] = direct;
      } on FirebaseException catch (error) {
        lookupFailures++;
        debugPrint(
          '[Memberships] direct lookup failed path='
          '${memberships.path}/$userId code=${error.code} '
          'message=${error.message}',
        );
      }

      try {
        final byField =
            await memberships.where('userId', isEqualTo: userId).get();
        for (final document in byField.docs) {
          documentsByPath[document.reference.path] = document;
        }
      } on FirebaseException catch (error) {
        lookupFailures++;
        debugPrint(
          '[Memberships] userId lookup failed path=${memberships.path} '
          'code=${error.code} message=${error.message}',
        );
      }
    }

    final resolved = await _resolveDocuments(
      documentsByPath.values,
      requestedUserId: userId,
    );
    _debugMemberships(resolved);
    return _FallbackMembershipsResult(
      memberships: resolved,
      failed: lookupFailures > 0 && resolved.isEmpty,
    );
  }

  Future<List<MembershipModel>> _resolveDocuments(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> documents, {
    required String requestedUserId,
  }) async {
    final memberships = <MembershipModel>[];
    for (final document in documents) {
      if (!document.exists) continue;
      final data = document.data();
      if (data == null || data['status'] != MembershipStatus.active.name) {
        continue;
      }
      final membership = await _resolveMembership(
        document,
        requestedUserId: requestedUserId,
      );
      if (membership != null) memberships.add(membership);
    }
    memberships.sort((left, right) {
      if (left.isPrimary != right.isPrimary) return left.isPrimary ? -1 : 1;
      return left.joinedAt.compareTo(right.joinedAt);
    });
    return memberships;
  }

  Future<MembershipModel?> _resolveMembership(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String requestedUserId,
  }) async {
    final data = document.data()!;
    final storedUserId = data['userId'] as String?;
    final resolvedUserId = storedUserId?.trim().isNotEmpty == true
        ? storedUserId!.trim()
        : document.id;
    if (resolvedUserId != requestedUserId) return null;

    final parentOrganization = document.reference.parent.parent;
    final storedOrganizationId = data['organizationId'] as String?;
    final organizationId = storedOrganizationId?.trim().isNotEmpty == true
        ? storedOrganizationId!.trim()
        : parentOrganization?.id ?? '';
    if (organizationId.isEmpty) return null;

    final storedRoleId = data['roleId'] as String?;
    final roleId = storedRoleId?.trim().isNotEmpty == true
        ? storedRoleId!.trim()
        : 'member';
    var permissions = List<String>.from(
      data['permissionsSnapshot'] as List<dynamic>? ?? const [],
    );
    if (!data.containsKey('permissionsSnapshot')) {
      try {
        final role = await _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('roles')
            .doc(roleId)
            .get();
        permissions = List<String>.from(
          role.data()?['permissions'] as List<dynamic>? ?? const [],
        );
      } on FirebaseException catch (error) {
        debugPrint(
          '[Memberships] role permissions lookup failed path='
          'organizations/$organizationId/roles/$roleId '
          'code=${error.code} message=${error.message}',
        );
      }
    }

    debugPrint(
        '[Memberships] membership path found=${document.reference.path}');
    return MembershipModel.fromFirestore(document).copyWith(
      userId: resolvedUserId,
      organizationId: organizationId,
      roleId: roleId,
      permissionsSnapshot: permissions,
    );
  }

  void _debugMemberships(List<MembershipModel> memberships) {
    debugPrint('[Memberships] memberships found count=${memberships.length}');
    for (final membership in memberships) {
      debugPrint(
        '[Memberships] organizationId=${membership.organizationId} '
        'status=${membership.status.name} roleId=${membership.roleId}',
      );
    }
  }
}
