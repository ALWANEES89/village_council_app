import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/transaction_model.dart';

class _LinkedPayment {
  const _LinkedPayment({
    required this.paymentId,
    required this.amountDeclared,
    required this.receiptUrl,
  });

  final String paymentId;
  final dynamic amountDeclared;
  final String? receiptUrl;
}

class FinancialReceiptRepository {
  FinancialReceiptRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _transactions(
    String organizationId,
  ) =>
      _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('transactions');

  Stream<List<TransactionModel>> streamPending(String organizationId) {
    return _transactions(organizationId)
        .where('reviewStatus', isEqualTo: 'pending')
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(TransactionModel.fromFirestore).toList());
  }

  Future<void> approve({
    required String transactionId,
    required String organizationId,
    required String reviewedBy,
  }) async {
    final transactionReference =
        _transactions(organizationId).doc(transactionId);
    // The council transaction, audit log and notification are written
    // atomically. The root (legacy) payment is updated separately as a
    // best-effort step so a stale payment cannot fail the approval.
    final linkedPayment =
        await _firestore.runTransaction<_LinkedPayment?>((transaction) async {
      final snapshot = await transaction.get(transactionReference);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['reviewStatus'] != 'pending' ||
          data?['status'] != 'pendingReview') {
        throw StateError('Receipt is no longer pending review.');
      }
      final resolvedOrganizationId = data!['organizationId'] as String;
      final userId = (data['userId'] ?? data['memberId']) as String;
      final paymentId = data['paymentId'] as String?;
      final now = FieldValue.serverTimestamp();
      transaction.update(transactionReference, {
        'status': 'approved',
        'currentStatus': TransactionStatus.approved.name,
        'reviewStatus': 'approved',
        'reviewedBy': reviewedBy,
        'reviewedAt': now,
        'rejectionReason': null,
      });
      // ملاحظة: سجل التدقيق (audit_logs) يُكتب الآن خادميًّا عبر Cloud Function
      // (auditTransactionWrite) اعتمادًا على تغيّر reviewStatus. لم يعد العميل
      // يكتب audit_logs (ممنوع في Firestore Rules).
      transaction.set(
        _firestore
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc('receiptApproved_$transactionId'),
        {
          'notificationId': 'receiptApproved_$transactionId',
          'title': 'تم اعتماد الإيصال',
          'body': 'تم استلام دفعك واعتماد الإيصال. شكرًا لك.',
          'type': 'receiptApproved',
          'userId': userId,
          'organizationId': resolvedOrganizationId,
          'relatedEntityType': 'receipt',
          'relatedEntityId': transactionId,
          'status': 'unread',
          'createdAt': now,
          'readAt': null,
          'createdByUserId': reviewedBy,
        },
      );
      if (paymentId == null || paymentId.isEmpty) return null;
      return _LinkedPayment(
        paymentId: paymentId,
        amountDeclared: data['amountDeclared'],
        receiptUrl: data['receiptUrl'] as String?,
      );
    });

    // Best-effort: reflect the approval on the legacy root payment. A stale
    // payment (e.g. missing organizationId) must not fail the approval, whose
    // authoritative record is the council transaction updated above.
    if (linkedPayment != null) {
      final paymentReference =
          _firestore.collection('payments').doc(linkedPayment.paymentId);
      try {
        final paymentSnapshot = await paymentReference.get();
        if (paymentSnapshot.exists) {
          await paymentReference.update({
            'status': 'paid',
            if (linkedPayment.amountDeclared != null)
              'amountPaid': linkedPayment.amountDeclared,
            'paidDate': FieldValue.serverTimestamp(),
            if (linkedPayment.receiptUrl != null)
              'receiptUrl': linkedPayment.receiptUrl,
            'transactionId': transactionId,
          });
        }
      } on FirebaseException catch (error) {
        debugPrint(
          '[Receipts] legacy payment update failed after approval '
          'paymentId=${linkedPayment.paymentId} code=${error.code} '
          'message=${error.message}',
        );
      }
    }
  }

  Future<void> reject({
    required String transactionId,
    required String organizationId,
    required String reviewedBy,
    required String rejectionReason,
  }) async {
    final reason = rejectionReason.trim();
    final transactionReference =
        _transactions(organizationId).doc(transactionId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(transactionReference);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['reviewStatus'] != 'pending' ||
          data?['status'] != 'pendingReview') {
        throw StateError('Receipt is no longer pending review.');
      }
      final resolvedOrganizationId = data!['organizationId'] as String;
      final userId = (data['userId'] ?? data['memberId']) as String;
      final now = FieldValue.serverTimestamp();
      transaction.update(transactionReference, {
        'status': 'rejected',
        'currentStatus': TransactionStatus.rejected.name,
        'reviewStatus': 'rejected',
        'reviewedBy': reviewedBy,
        'reviewedAt': now,
        'rejectionReason': reason,
      });
      transaction.set(
        _firestore
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc('receiptRejected_$transactionId'),
        {
          'notificationId': 'receiptRejected_$transactionId',
          'title': 'تم رفض الإيصال',
          'body': reason.isEmpty
              ? 'تعذر اعتماد الإيصال. يرجى مراجعة بيانات الدفع.'
              : reason,
          'type': 'receiptRejected',
          'userId': userId,
          'organizationId': resolvedOrganizationId,
          'relatedEntityType': 'receipt',
          'relatedEntityId': transactionId,
          'status': 'unread',
          'createdAt': now,
          'readAt': null,
          'createdByUserId': reviewedBy,
        },
      );
    });
  }
}
