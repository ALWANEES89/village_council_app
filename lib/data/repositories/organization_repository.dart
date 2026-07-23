import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class OrganizationRepairFailure {
  const OrganizationRepairFailure({
    required this.operation,
    required this.collectionPath,
    required this.documentPath,
    required this.exception,
    required this.stackTrace,
  });

  final String operation;
  final String collectionPath;
  final String documentPath;
  final FirebaseException exception;
  final StackTrace stackTrace;
}

class OrganizationRepairResult {
  const OrganizationRepairResult({
    required this.succeededWrites,
    required this.failedWrites,
    this.failures = const [],
  });

  final int succeededWrites;
  final int failedWrites;
  final List<OrganizationRepairFailure> failures;

  bool get isSuccess => failedWrites == 0;
}

class OrganizationRepository {
  OrganizationRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _organizations =>
      _firestore.collection('organizations');

  Future<void> create({
    required String organizationId,
    required Map<String, dynamic> data,
  }) async {
    throw UnsupportedError(
      'Organizations must be created through bootstrapOrganization.',
    );
  }

  Future<String> createWithDefaults({
    required Map<String, dynamic> data,
    required String createdBy,
    bool assignCreatorAsChairman = false,
  }) async {
    return bootstrapOrganization(
      data: data,
      createdBy: createdBy,
      assignCreatorAsChairman: assignCreatorAsChairman,
    );
  }

  Future<String> bootstrapOrganization({
    required Map<String, dynamic> data,
    required String createdBy,
    bool assignCreatorAsChairman = false,
  }) async {
    final requestId = const Uuid().v4().replaceAll('-', '_');
    final result =
        await _functions.httpsCallable('bootstrapOrganization').call({
      'requestId': requestId,
      'officialNameArabic': data['officialNameArabic'],
      'officialNameEnglish': data['officialNameEnglish'],
      'shortName': data['shortName'],
      'phone': data['phone'],
      'email': data['email'],
      'address': data['address'],
      'googleMapsUrl': data['googleMapsUrl'],
      if (assignCreatorAsChairman) 'chairmanUserId': createdBy,
    });
    return Map<String, dynamic>.from(result.data as Map)['organizationId']
        as String;
  }

  Future<void> update({
    required String organizationId,
    required Map<String, dynamic> data,
    String? actorUserId,
  }) {
    final updates = Map<String, dynamic>.from(data)
      ..remove('organizationId')
      ..remove('createdAt')
      ..remove('joinQrData')
      ..['updatedAt'] = FieldValue.serverTimestamp();
    // توثيق الفاعل: يقرؤه auditOrganizationWrite لإظهار من عدّل بيانات المجلس.
    if (actorUserId != null) updates['updatedBy'] = actorUserId;

    if (data.containsKey('joinCode')) {
      final joinCode = _normalizeJoinCode(data['joinCode']);
      updates['joinCode'] = joinCode;
      updates['joinQrData'] = joinCode == null
          ? null
          : _buildJoinQrData(
              organizationId: organizationId,
              joinCode: joinCode,
            );
      if (joinCode == null) updates['joinQrEnabled'] = false;
    }
    return _organizations.doc(organizationId).update(updates);
  }

  Future<void> delete(String organizationId) {
    return _organizations.doc(organizationId).delete();
  }

  Future<void> setArchived(
    String organizationId, {
    required bool archived,
    String? actorUserId,
  }) {
    return update(
      organizationId: organizationId,
      data: {'status': archived ? 'archived' : 'active'},
      actorUserId: actorUserId,
    );
  }

  Future<Map<String, dynamic>?> getById(String organizationId) async {
    final snapshot = await _organizations.doc(organizationId).get();
    return _dataWithId(snapshot, organizationId);
  }

  Future<Map<String, dynamic>?> getOrganizationByJoinCode(
    String joinCode,
  ) async {
    final normalizedCode = _normalizeJoinCode(joinCode);
    if (normalizedCode == null) return null;

    final snapshot = await _organizations
        .where('joinCode', isEqualTo: normalizedCode)
        .limit(2)
        .get();
    final matches = snapshot.docs.where((document) {
      final data = document.data();
      final status = data['status'];
      return data['joinQrEnabled'] == true &&
          status != 'archived' &&
          status != 'suspended';
    }).toList();
    if (matches.length != 1) return null;
    return _dataWithId(matches.single, matches.single.id);
  }

  Stream<Map<String, dynamic>?> stream(String organizationId) {
    return _organizations
        .doc(organizationId)
        .snapshots()
        .map((snapshot) => _dataWithId(snapshot, organizationId));
  }

  Stream<List<Map<String, dynamic>>> streamAll() {
    return _organizations.snapshots().map((snapshot) {
      final organizations = snapshot.docs
          .map((document) => _dataWithId(document, document.id)!)
          .where((organization) => organization['status'] == 'active')
          .toList();
      organizations.sort((left, right) {
        final leftName = _sortName(left);
        final rightName = _sortName(right);
        return leftName.compareTo(rightName);
      });
      return organizations;
    });
  }

  Stream<List<Map<String, dynamic>>> streamAllIncludingInactive() {
    return _organizations.snapshots().map((snapshot) {
      final organizations = snapshot.docs
          .map((document) => _dataWithId(document, document.id)!)
          .toList();
      organizations
          .sort((left, right) => _sortName(left).compareTo(_sortName(right)));
      return organizations;
    });
  }

  Future<Map<String, int>> getOrganizationCounts(String organizationId) async {
    final reference = _organizations.doc(organizationId);
    final results = await Future.wait([
      reference
          .collection('memberships')
          .where('status', isEqualTo: 'active')
          .get(),
      reference
          .collection('membership_requests')
          .where('status', isEqualTo: 'pending')
          .get(),
    ]);
    return {
      'members': results[0].docs.length,
      'requests': results[1].docs.length,
    };
  }

  /// Creates any missing documents required by an organization without
  /// changing or deleting documents that already exist.
  Future<OrganizationRepairResult> repairOrganizationStructure(
    String organizationId,
  ) async {
    final normalizedId = organizationId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        organizationId,
        'organizationId',
        'Organization ID cannot be empty.',
      );
    }
    final response =
        await _functions.httpsCallable('repairOrganizationStructure').call({
      'organizationId': normalizedId,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    return OrganizationRepairResult(
      succeededWrites: data['createdCount'] as int? ?? 0,
      failedWrites: 0,
    );
  }

  Future<OrganizationRepairResult> repairAllOrganizationStructures() async {
    QuerySnapshot<Map<String, dynamic>> organizations;
    try {
      organizations = await _organizations.get();
    } on FirebaseException catch (exception, stackTrace) {
      _logFirebaseFailure(
        operation: 'list-organizations',
        collectionPath: _organizations.path,
        documentPath: '${_organizations.path}/*',
        exception: exception,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    var succeededWrites = 0;
    var failedWrites = 0;
    final failures = <OrganizationRepairFailure>[];
    for (final organization in organizations.docs) {
      final result = await repairOrganizationStructure(organization.id);
      succeededWrites += result.succeededWrites;
      failedWrites += result.failedWrites;
      failures.addAll(result.failures);
    }
    return OrganizationRepairResult(
      succeededWrites: succeededWrites,
      failedWrites: failedWrites,
      failures: List.unmodifiable(failures),
    );
  }

  OrganizationRepairFailure _logFirebaseFailure({
    required String operation,
    String? collectionPath,
    String? documentPath,
    DocumentReference<Map<String, dynamic>>? reference,
    required FirebaseException exception,
    required StackTrace stackTrace,
  }) {
    final resolvedCollectionPath = collectionPath ?? reference!.parent.path;
    final resolvedDocumentPath = documentPath ?? reference!.path;
    debugPrint('Firestore repair failure:');
    debugPrint('operation: $operation');
    debugPrint('collection path: $resolvedCollectionPath');
    debugPrint('document path: $resolvedDocumentPath');
    debugPrint('exception.code: ${exception.code}');
    debugPrint('exception.message: ${exception.message}');
    debugPrint('stackTrace: $stackTrace');
    return OrganizationRepairFailure(
      operation: operation,
      collectionPath: resolvedCollectionPath,
      documentPath: resolvedDocumentPath,
      exception: exception,
      stackTrace: stackTrace,
    );
  }

  Map<String, dynamic>? _dataWithId(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String organizationId,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final resolvedOrganizationId =
        data['organizationId'] as String? ?? organizationId;
    final joinCode = _normalizeJoinCode(data['joinCode']);
    return {
      ...data,
      'organizationId': resolvedOrganizationId,
      'joinCode': joinCode,
      'joinQrData': data['joinQrData'] ??
          (joinCode == null
              ? null
              : _buildJoinQrData(
                  organizationId: resolvedOrganizationId,
                  joinCode: joinCode,
                )),
      'joinQrEnabled': data['joinQrEnabled'] == true,
    };
  }

  String _sortName(Map<String, dynamic> organization) {
    final arabicName = organization['officialNameArabic'];
    if (arabicName is String) return arabicName;
    final shortName = organization['shortName'];
    if (shortName is String) return shortName;
    return organization['organizationId'] as String? ?? '';
  }

  String? _normalizeJoinCode(dynamic value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _buildJoinQrData({
    required String organizationId,
    required String joinCode,
  }) {
    return Uri(
      scheme: 'communityos',
      host: 'join',
      queryParameters: {
        'organizationId': organizationId,
        'joinCode': joinCode,
      },
    ).toString();
  }
}
