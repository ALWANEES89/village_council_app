import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/council_management_models.dart';

class CouncilManagementRepository {
  CouncilManagementRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  CollectionReference<Map<String, dynamic>> _expenses(String organizationId) =>
      _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('expenses');

  Stream<List<CouncilExpense>> streamExpenses(String organizationId) =>
      _expenses(organizationId)
          .orderBy('expenseDate', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map(CouncilExpense.fromFirestore)
              .toList(growable: false));

  Future<int> sendCouncilNotification({
    required String requestId,
    required String organizationId,
    required String title,
    required String body,
  }) async {
    if (organizationId.trim().isEmpty ||
        requestId.trim().isEmpty ||
        title.trim().isEmpty ||
        body.trim().isEmpty) {
      throw ArgumentError('Organization, title, and body are required.');
    }
    final result = await _functions
        .httpsCallable('sendCouncilNotification')
        .call<Map<String, dynamic>>({
      'requestId': requestId,
      'organizationId': organizationId,
      'title': title.trim(),
      'body': body.trim(),
    });
    return result.data['deliveredCount'] as int? ?? 0;
  }

  Future<String> createExpense({
    required String requestId,
    required String organizationId,
    required String title,
    required String category,
    required int amountBaisa,
    required DateTime expenseDate,
    String note = '',
    String supplier = '',
    String invoiceNumber = '',
    String attachmentStoragePath = '',
  }) async {
    final result = await _functions
        .httpsCallable('createCouncilExpense')
        .call<Map<String, dynamic>>({
      'requestId': requestId,
      'organizationId': organizationId,
      'title': title.trim(),
      'category': category,
      'amountBaisa': amountBaisa,
      'expenseDate': _dateOnly(expenseDate),
      'note': note.trim(),
      'supplier': supplier.trim(),
      'invoiceNumber': invoiceNumber.trim(),
      'attachmentStoragePath': attachmentStoragePath,
    });
    return result.data['expenseId'] as String;
  }

  Future<CouncilFinancialReport> getFinancialReport({
    required String organizationId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final result = await _functions
        .httpsCallable('getCouncilFinancialReport')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      if (startDate != null) 'startDate': _dateOnly(startDate),
      if (endDate != null) 'endDate': _dateOnly(endDate),
    });
    return CouncilFinancialReport.fromMap(result.data);
  }

  Future<void> updateExpense({
    required String organizationId,
    required String expenseId,
    required String title,
    required String category,
    required int amountBaisa,
    required DateTime expenseDate,
    String note = '',
    String supplier = '',
    String invoiceNumber = '',
    String attachmentStoragePath = '',
  }) =>
      _functions.httpsCallable('updateCouncilExpense').call<void>({
        'organizationId': organizationId,
        'expenseId': expenseId,
        'action': 'update',
        'title': title.trim(),
        'category': category,
        'amountBaisa': amountBaisa,
        'expenseDate': _dateOnly(expenseDate),
        'note': note.trim(),
        'supplier': supplier.trim(),
        'invoiceNumber': invoiceNumber.trim(),
        'attachmentStoragePath': attachmentStoragePath,
      });

  Future<void> cancelExpense({
    required String organizationId,
    required String expenseId,
  }) =>
      _functions.httpsCallable('updateCouncilExpense').call<void>({
        'organizationId': organizationId,
        'expenseId': expenseId,
        'action': 'cancel',
      });

  Future<CouncilActivityDetail> getActivityDetail({
    required String organizationId,
    required String entityType,
    required String entityId,
  }) async {
    final result = await _functions
        .httpsCallable('getCouncilActivityDetail')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'entityType': entityType,
      'entityId': entityId,
    });
    return CouncilActivityDetail.fromMap(result.data);
  }

  String _dateOnly(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
