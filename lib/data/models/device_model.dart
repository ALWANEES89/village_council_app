import 'package:cloud_firestore/cloud_firestore.dart';

enum DevicePlatform {
  android,
  ios,
  web,
  windows,
  macos,
}

class DeviceModel {
  final String deviceId;
  final String userId;
  final DevicePlatform platform;
  final String? manufacturer;
  final String? model;
  final String? deviceName;
  final String operatingSystem;
  final String appVersion;
  final String? firebaseInstallationId;
  final String? fcmToken;
  final String languageCode;
  final String timezone;
  final DateTime lastLoginAt;
  final DateTime lastSeenAt;
  final DateTime createdAt;
  final bool isActive;
  final bool isTrusted;
  final bool notificationsEnabled;

  const DeviceModel({
    required this.deviceId,
    required this.userId,
    required this.platform,
    required this.manufacturer,
    required this.model,
    required this.deviceName,
    required this.operatingSystem,
    required this.appVersion,
    required this.firebaseInstallationId,
    required this.fcmToken,
    required this.languageCode,
    required this.timezone,
    required this.lastLoginAt,
    required this.lastSeenAt,
    required this.createdAt,
    required this.isActive,
    required this.isTrusted,
    required this.notificationsEnabled,
  });

  factory DeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return DeviceModel(
      deviceId: data['deviceId'] ?? doc.id,
      userId: data['userId'] ?? '',
      platform: DevicePlatform.values.firstWhere(
        (platform) => platform.name == (data['platform'] ?? 'android'),
        orElse: () => DevicePlatform.android,
      ),
      manufacturer: data['manufacturer'],
      model: data['model'],
      deviceName: data['deviceName'],
      operatingSystem: data['operatingSystem'] ?? '',
      appVersion: data['appVersion'] ?? '',
      firebaseInstallationId: data['firebaseInstallationId'],
      fcmToken: data['fcmToken'],
      languageCode: data['languageCode'] ?? 'ar',
      timezone: data['timezone'] ?? 'Asia/Muscat',
      lastLoginAt:
          _requiredDateTime(data['lastLoginAt'], 'lastLoginAt', doc.id),
      lastSeenAt: _requiredDateTime(data['lastSeenAt'], 'lastSeenAt', doc.id),
      createdAt: _requiredDateTime(data['createdAt'], 'createdAt', doc.id),
      isActive: data['isActive'] ?? true,
      isTrusted: data['isTrusted'] ?? false,
      notificationsEnabled: data['notificationsEnabled'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'deviceId': deviceId,
      'userId': userId,
      'platform': platform.name,
      'manufacturer': manufacturer,
      'model': model,
      'deviceName': deviceName,
      'operatingSystem': operatingSystem,
      'appVersion': appVersion,
      'firebaseInstallationId': firebaseInstallationId,
      'fcmToken': fcmToken,
      'languageCode': languageCode,
      'timezone': timezone,
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'lastSeenAt': Timestamp.fromDate(lastSeenAt),
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'isTrusted': isTrusted,
      'notificationsEnabled': notificationsEnabled,
    };
  }

  bool get canReceiveNotifications =>
      isActive && notificationsEnabled && fcmToken?.isNotEmpty == true;
}

DateTime _requiredDateTime(dynamic value, String field, String documentId) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;

  throw StateError(
    'Device $documentId is missing the required $field timestamp.',
  );
}
