import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/transaction_model.dart';
import 'financial_repository.dart';

/// Read model for the review queue. All state-changing review work is delegated
/// to a trusted callable Cloud Function through [FinancialRepository].
class FinancialReceiptRepository {
  FinancialReceiptRepository({
    FirebaseFirestore? firestore,
    FinancialRepository? financialRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _financialRepository = financialRepository ?? FinancialRepository();

  final FirebaseFirestore _firestore;
  final FinancialRepository _financialRepository;

  CollectionReference<Map<String, dynamic>> _transactions(
          String organizationId) =>
      _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('transactions');

  Stream<List<TransactionModel>> streamPending(String organizationId) {
    return _transactions(organizationId)
        .where('reviewStatus', isEqualTo: 'pending')
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(TransactionModel.fromFirestore)
            .toList(growable: false));
  }

  Future<void> approve({
    required String transactionId,
    required String organizationId,
    required String reviewedBy,
  }) {
    return _financialRepository.reviewReceipt(
      organizationId: organizationId,
      transactionId: transactionId,
      approve: true,
    );
  }

  Future<void> reject({
    required String transactionId,
    required String organizationId,
    required String reviewedBy,
    required String rejectionReason,
  }) {
    return _financialRepository.reviewReceipt(
      organizationId: organizationId,
      transactionId: transactionId,
      approve: false,
      rejectionReason: rejectionReason,
    );
  }
}
