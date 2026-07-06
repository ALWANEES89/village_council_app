import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/member_model.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  String _normalizePhone(String phone) {
    var p = phone.trim().replaceAll(' ', '');
    if (p.startsWith('+')) return p;
    if (p.startsWith('968')) return '+$p';
    return '+968$p';
  }

  String _phoneToEmail(String phone) {
    final normalized = _normalizePhone(phone);
    final digits = normalized.replaceAll('+', '');
    return '$digits@alrahmat.local';
  }

  Future<MemberModel?> signInWithPhoneAndPassword({
    required String phone,
    required String password,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final email = _phoneToEmail(normalizedPhone);

    final userCred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (userCred.user == null) return null;

    return _getAuthenticatedAccount(
      user: userCred.user!,
      normalizedPhone: normalizedPhone,
    );
  }

  Future<UserCredential> createLoginForMember({
    required String phone,
    required String password,
  }) async {
    final email = _phoneToEmail(phone);

    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> resetMemberPassword({
    required String phone,
  }) async {
    final email = _phoneToEmail(phone);
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<MemberModel?> getMemberByPhone(String phone) async {
    final normalizedPhone = _normalizePhone(phone);

    final query = await _db
        .collection('members')
        .where('phone', isEqualTo: normalizedPhone)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    return MemberModel.fromFirestore(query.docs.first);
  }

  Future<MemberModel?> getCurrentMember() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return null;

    final phoneDigits = user.email!.split('@').first;
    final phone = '+$phoneDigits';

    return _getAuthenticatedAccount(user: user, normalizedPhone: phone);
  }

  Future<MemberModel?> _getAuthenticatedAccount({
    required User user,
    required String normalizedPhone,
  }) async {
    var hasSuperAdminClaim = false;
    try {
      final token = await user.getIdTokenResult();
      hasSuperAdminClaim = token.claims?['superAdmin'] == true;
    } catch (_) {
      // Firestore profile fallback remains available.
    }
    final memberSnapshot = await _db.collection('members').doc(user.uid).get();
    if (memberSnapshot.exists) {
      final member = MemberModel.fromFirestore(memberSnapshot);
      final userAccount = await _getUserAccount(user.uid);
      if ((hasSuperAdminClaim || userAccount?.isAdmin == true) &&
          !member.isAdmin) {
        return _withAdminAccess(member);
      }
      return member;
    }

    final userAccount = await _getUserAccount(user.uid);
    if (userAccount != null) {
      return hasSuperAdminClaim && !userAccount.isAdmin
          ? _withAdminAccess(userAccount)
          : userAccount;
    }

    // Backward compatibility for legacy accounts whose member document ID is
    // different from their Firebase Authentication UID.
    return getMemberByPhone(normalizedPhone);
  }

  MemberModel _withAdminAccess(MemberModel member) {
    return MemberModel(
      id: member.id,
      fullName: member.fullName,
      civilId: member.civilId,
      phone: member.phone,
      memberNumber: member.memberNumber,
      status: member.status,
      isAdmin: true,
      joinDate: member.joinDate,
      fcmToken: member.fcmToken,
    );
  }

  Future<MemberModel?> _getUserAccount(String userId) async {
    final snapshot = await _db.collection('users').doc(userId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;

    final createdAt = data['createdAt'];
    return MemberModel(
      id: userId,
      fullName: data['fullName'] as String? ?? '',
      civilId: data['civilId'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      memberNumber: '',
      status: MemberStatus.pending,
      isAdmin:
          data['isSuperAdmin'] == true || data['platformRole'] == 'superAdmin',
      joinDate: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      fcmToken: data['fcmToken'] as String?,
    );
  }

  Future<void> updateFcmToken(String memberId, String token) async {
    await _db.collection('members').doc(memberId).update({'fcmToken': token});
  }

  Future<void> signOut() async {
    // احذف توكن هذا الجهاز أولًا (والمستخدم ما زال مصادَقًا) حتى لا تصل إشعاراته
    // للمستخدم التالي على نفس الجهاز. أفضل جهد: لا يعطّل تسجيل الخروج.
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await NotificationService.instance.deleteTokenForUser(uid);
    }
    await _auth.signOut();
  }
}
