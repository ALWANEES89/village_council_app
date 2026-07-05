import 'package:cloud_firestore/cloud_firestore.dart';

class RoleRepository {
  RoleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _roles(String organizationId) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('roles');
  }

  Future<void> create({
    required String organizationId,
    required String roleId,
    required Map<String, dynamic> data,
    String? actorUserId,
  }) {
    final now = FieldValue.serverTimestamp();
    return _roles(organizationId).doc(roleId).set({
      ...data,
      'roleId': roleId,
      'createdAt': data['createdAt'] ?? now,
      'updatedAt': data['updatedAt'] ?? now,
      // توثيق الفاعل حتى يظهر actorName/actorRole في سجل الأحداث الخادمي.
      if (actorUserId != null) 'createdBy': actorUserId,
      if (actorUserId != null) 'updatedBy': actorUserId,
    });
  }

  Future<void> update({
    required String organizationId,
    required String roleId,
    required Map<String, dynamic> data,
    String? actorUserId,
  }) {
    final updates = Map<String, dynamic>.from(data)
      ..remove('roleId')
      ..remove('createdAt')
      ..['updatedAt'] = FieldValue.serverTimestamp();
    // توثيق الفاعل: يقرؤه auditRoleWrite لإظهار من غيّر الصلاحيات.
    if (actorUserId != null) updates['updatedBy'] = actorUserId;
    return _roles(organizationId).doc(roleId).update(updates);
  }

  Future<void> delete({
    required String organizationId,
    required String roleId,
  }) {
    return _roles(organizationId).doc(roleId).delete();
  }

  Future<Map<String, dynamic>?> getById({
    required String organizationId,
    required String roleId,
  }) async {
    final snapshot = await _roles(organizationId).doc(roleId).get();
    return _dataWithId(snapshot, roleId);
  }

  Stream<Map<String, dynamic>?> stream({
    required String organizationId,
    required String roleId,
  }) {
    return _roles(organizationId)
        .doc(roleId)
        .snapshots()
        .map((snapshot) => _dataWithId(snapshot, roleId));
  }

  Stream<List<Map<String, dynamic>>> streamAll(String organizationId) {
    return _roles(organizationId).orderBy('roleId').snapshots().map(
          (snapshot) => snapshot.docs
              .map((document) => _dataWithId(document, document.id)!)
              .toList(),
        );
  }

  Map<String, dynamic>? _dataWithId(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String roleId,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return {...data, 'roleId': data['roleId'] ?? roleId};
  }
}
