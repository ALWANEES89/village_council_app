import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification_model.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _notifications(String userId) =>
      _firestore.collection('users').doc(userId).collection('notifications');

  Stream<List<AppNotificationModel>> streamForUser(String userId) {
    return _notifications(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final items =
          snapshot.docs.map(AppNotificationModel.fromFirestore).toList();
      items.sort((left, right) {
        if (left.isUnread != right.isUnread) return left.isUnread ? -1 : 1;
        return right.createdAt.compareTo(left.createdAt);
      });
      return items;
    });
  }

  Future<void> markAsRead(String userId, String notificationId) {
    return _notifications(userId).doc(notificationId).update({
      'status': 'read',
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead(String userId) async {
    final unread =
        await _notifications(userId).where('status', isEqualTo: 'unread').get();
    for (var start = 0; start < unread.docs.length; start += 400) {
      final batch = _firestore.batch();
      for (final document in unread.docs.skip(start).take(400)) {
        batch.update(document.reference, {
          'status': 'read',
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }
}
