import 'package:cloud_firestore/cloud_firestore.dart';

class PlatformAdminRepository {
  PlatformAdminRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _admin(String userId) =>
      _firestore.collection('platform_admins').doc(userId);

  /// مالك المنصّة الأعلى: system_owner (نشط) أو superAdmin (نشط + fullAccess).
  /// يُنشأ فقط من Console/Admin SDK — لا من الواجهة.
  Future<bool> isActiveSuperAdmin(String userId) async {
    final snapshot = await _admin(userId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return false;
    final isActive = data['status'] == 'active';
    if (!isActive) return false;
    return data['role'] == 'system_owner' ||
        (data['role'] == 'superAdmin' && data['fullAccess'] == true);
  }

  Stream<Map<String, dynamic>?> stream(String userId) =>
      _admin(userId).snapshots().map((snapshot) => snapshot.data());

  Future<void> setOrganizationNotifications({
    required String userId,
    required String organizationId,
    required bool enabled,
  }) {
    return _admin(userId).update({
      'notificationPreferences.$organizationId': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
