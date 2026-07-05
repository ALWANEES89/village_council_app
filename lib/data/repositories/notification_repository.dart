import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  Future<void> createForUser({
    required String userId,
    required String title,
    required String body,
    required String type,
    required String relatedEntityType,
    required String relatedEntityId,
    String? organizationId,
    String? createdByUserId,
  }) async {
    final notificationId = _notificationId(type, relatedEntityId);
    final reference = _notifications(userId).doc(notificationId);
    try {
      await reference.set({
        'notificationId': notificationId,
        'userId': userId,
        if (organizationId != null) 'organizationId': organizationId,
        'title': title,
        'body': body,
        'type': type,
        'relatedEntityType': relatedEntityType,
        'relatedEntityId': relatedEntityId,
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
        if (createdByUserId != null) 'createdByUserId': createdByUserId,
      });
    } on FirebaseException catch (error) {
      debugPrint(
        '[Notifications] create skipped user=$userId id=$notificationId '
        'code=${error.code}',
      );
    }
  }

  Future<void> notifyOrganizationReviewers({
    required String organizationId,
    required List<String> permissions,
    required String title,
    required String body,
    required String type,
    required String relatedEntityType,
    required String relatedEntityId,
    String? createdByUserId,
  }) async {
    try {
      final memberships = await _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('memberships')
          .where('status', isEqualTo: 'active')
          .get();
      final recipients = <String>{};
      for (final membership in memberships.docs) {
        final data = membership.data();
        final snapshot = List<String>.from(
          data['permissionsSnapshot'] as List<dynamic>? ?? const [],
        );
        if (snapshot.contains('fullAccess') ||
            snapshot.any(permissions.contains)) {
          final userId = data['userId'] as String? ?? membership.id;
          if (userId.isNotEmpty) recipients.add(userId);
        }
      }
      await _addEnabledSuperAdmins(organizationId, recipients);
      recipients.remove(createdByUserId);
      for (final userId in recipients) {
        await createForUser(
          userId: userId,
          organizationId: organizationId,
          title: title,
          body: body,
          type: type,
          relatedEntityType: relatedEntityType,
          relatedEntityId: relatedEntityId,
          createdByUserId: createdByUserId,
        );
      }
    } on FirebaseException catch (error) {
      debugPrint(
        '[Notifications] recipient resolution failed code=${error.code} '
        'message=${error.message}',
      );
    }
  }

  Future<void> _addEnabledSuperAdmins(
    String organizationId,
    Set<String> recipients,
  ) async {
    try {
      final admins = await _firestore.collection('platform_admins').get();
      for (final admin in admins.docs) {
        final data = admin.data();
        final preferences = data['notificationPreferences'];
        if (data['role'] == 'superAdmin' &&
            data['status'] == 'active' &&
            preferences is Map &&
            preferences[organizationId] == true) {
          recipients.add(admin.id);
        }
      }
    } on FirebaseException catch (error) {
      debugPrint('[Notifications] super-admin lookup skipped: ${error.code}');
    }
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

  String _notificationId(String type, String entityId) {
    return '${type}_$entityId'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }
}
