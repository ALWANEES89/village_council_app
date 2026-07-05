import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile_model.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<void> create({
    required String userId,
    required Map<String, dynamic> data,
  }) {
    final now = FieldValue.serverTimestamp();
    return _users.doc(userId).set({
      ...data,
      'userId': userId,
      'createdAt': data['createdAt'] ?? now,
      'updatedAt': data['updatedAt'] ?? now,
    });
  }

  Future<void> update({
    required String userId,
    required Map<String, dynamic> data,
  }) {
    final updates = Map<String, dynamic>.from(data)
      ..remove('userId')
      ..remove('createdAt')
      ..['updatedAt'] = FieldValue.serverTimestamp();
    return _users.doc(userId).update(updates);
  }

  Future<void> delete(String userId) {
    return _users.doc(userId).delete();
  }

  Future<Map<String, dynamic>?> getById(String userId) async {
    final snapshot = await _users.doc(userId).get();
    return _dataWithId(snapshot, userId);
  }

  Stream<Map<String, dynamic>?> stream(String userId) {
    return _users
        .doc(userId)
        .snapshots()
        .map((snapshot) => _dataWithId(snapshot, userId));
  }

  Stream<UserProfileModel?> streamProfile(String userId) {
    return _users.doc(userId).snapshots().map(
          (snapshot) =>
              snapshot.exists ? UserProfileModel.fromFirestore(snapshot) : null,
        );
  }

  Future<void> saveProfile(UserProfileModel profile) async {
    final now = FieldValue.serverTimestamp();
    final reference = _users.doc(profile.userId);
    final legacyReference =
        _firestore.collection('members').doc(profile.userId);
    final results = await Future.wait([reference.get(), legacyReference.get()]);
    final batch = _firestore.batch();
    batch.set(
      reference,
      {
        ...profile.toFirestore(),
        'updatedAt': now,
        if (!results[0].exists) 'createdAt': now,
      },
      SetOptions(merge: true),
    );
    if (results[1].exists && profile.photoUrl?.trim().isNotEmpty == true) {
      batch.update(legacyReference, {'photoUrl': profile.photoUrl});
    }
    await batch.commit();
  }

  Map<String, dynamic>? _dataWithId(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String userId,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return {...data, 'userId': data['userId'] ?? userId};
  }
}
