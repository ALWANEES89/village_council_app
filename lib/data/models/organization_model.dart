import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationModel {
  const OrganizationModel({
    required this.organizationId,
    required this.officialNameArabic,
    required this.officialNameEnglish,
    required this.shortName,
    required this.status,
    required this.profilePublished,
    required this.schemaVersion,
    required this.navigationEnabled,
    required this.primaryColor,
    required this.secondaryColor,
    required this.description,
    this.logoUrl,
  });

  static const productionOrganizationId = 'rahmat_general_council';

  static const production = OrganizationModel(
    organizationId: productionOrganizationId,
    officialNameArabic: 'مجلس سيح الرحمات العام',
    officialNameEnglish: 'Saih Al Rahmat General Council',
    shortName: 'سيح الرحمات',
    status: 'active',
    profilePublished: true,
    schemaVersion: 1,
    navigationEnabled: true,
    primaryColor: '#6A1BFF',
    secondaryColor: '#9C4DFF',
    description: {
      'ar': 'المجلس الرسمي لإدارة شؤون أعضاء مجلس سيح الرحمات العام.',
      'en': 'Official council management platform.',
    },
  );

  final String organizationId;
  final String officialNameArabic;
  final String officialNameEnglish;
  final String shortName;
  final String status;
  final bool profilePublished;
  final int schemaVersion;
  final bool navigationEnabled;
  final String primaryColor;
  final String secondaryColor;
  final Map<String, String> description;
  final String? logoUrl;

  Map<String, dynamic> toFirestore() {
    return {
      'organizationId': organizationId,
      'officialNameArabic': officialNameArabic,
      'officialNameEnglish': officialNameEnglish,
      'shortName': shortName,
      'status': status,
      'profilePublished': profilePublished,
      'schemaVersion': schemaVersion,
      'navigationEnabled': navigationEnabled,
      'primaryColor': primaryColor,
      'secondaryColor': secondaryColor,
      'description': description,
      'logoUrl': logoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
