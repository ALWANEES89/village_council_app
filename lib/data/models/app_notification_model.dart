import 'package:cloud_firestore/cloud_firestore.dart';

({int amountBaisa, String bodyTemplate})? parseLegacyNotificationAmount(
  String body,
) {
  final match = RegExp(r'(\d+)\s*بيسة').firstMatch(body);
  final amount = match == null ? null : int.tryParse(match.group(1)!);
  if (match == null || amount == null) return null;
  return (
    amountBaisa: amount,
    bodyTemplate: body.replaceRange(match.start, match.end, '{amount}'),
  );
}

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
    this.amountBaisa,
    this.currencyCode,
    this.bodyTemplate,
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
  final int? amountBaisa;
  final String? currencyCode;
  final String? bodyTemplate;

  bool get isUnread => status == 'unread';
  bool get hasStructuredOmrAmount =>
      amountBaisa != null &&
      currencyCode == 'OMR' &&
      bodyTemplate?.contains('{amount}') == true;

  factory AppNotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    DateTime? date(dynamic value) => value is Timestamp ? value.toDate() : null;
    int? integer(dynamic value) {
      if (value is int) return value;
      if (value is num && value.isFinite && value == value.roundToDouble()) {
        return value.toInt();
      }
      if (value is String) return int.tryParse(value);
      return null;
    }

    final body = data['body'] as String? ?? '';
    var amountBaisa = integer(data['amountBaisa']);
    var currencyCode = data['currencyCode'] as String?;
    var bodyTemplate = data['bodyTemplate'] as String?;
    if (amountBaisa == null ||
        currencyCode != 'OMR' ||
        bodyTemplate?.contains('{amount}') != true) {
      final legacy = parseLegacyNotificationAmount(body);
      if (legacy != null) {
        amountBaisa = legacy.amountBaisa;
        currencyCode = 'OMR';
        bodyTemplate = legacy.bodyTemplate;
      }
    }
    return AppNotificationModel(
      notificationId: data['notificationId'] as String? ?? document.id,
      userId: data['userId'] as String? ?? '',
      organizationId: data['organizationId'] as String?,
      title: data['title'] as String? ?? '',
      body: body,
      type: data['type'] as String? ?? 'general',
      relatedEntityType: data['relatedEntityType'] as String? ?? '',
      relatedEntityId: data['relatedEntityId'] as String? ?? '',
      status: data['status'] as String? ?? 'unread',
      createdAt:
          date(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      readAt: date(data['readAt']),
      createdByUserId: data['createdByUserId'] as String?,
      amountBaisa: amountBaisa,
      currencyCode: currencyCode,
      bodyTemplate: bodyTemplate,
    );
  }
}
