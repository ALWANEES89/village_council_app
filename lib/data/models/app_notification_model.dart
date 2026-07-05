import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotificationModel {
  const AppNotificationModel({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.relatedEntityType,
    required this.relatedEntityId,
    required this.status,
    required this.createdAt,
    this.organizationId,
    this.readAt,
    this.createdByUserId,
  });

  final String notificationId;
  final String userId;
  final String? organizationId;
  final String title;
  final String body;
  final String type;
  final String relatedEntityType;
  final String relatedEntityId;
  final String status;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? createdByUserId;

  bool get isUnread => status == 'unread';

  factory AppNotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    DateTime? date(dynamic value) => value is Timestamp ? value.toDate() : null;
    return AppNotificationModel(
      notificationId: data['notificationId'] as String? ?? document.id,
      userId: data['userId'] as String? ?? '',
      organizationId: data['organizationId'] as String?,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'general',
      relatedEntityType: data['relatedEntityType'] as String? ?? '',
      relatedEntityId: data['relatedEntityId'] as String? ?? '',
      status: data['status'] as String? ?? 'unread',
      createdAt:
          date(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      readAt: date(data['readAt']),
      createdByUserId: data['createdByUserId'] as String?,
    );
  }
}
