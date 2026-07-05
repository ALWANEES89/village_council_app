import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/member_model.dart';
import '../models/payment_model.dart';
import '../models/transaction_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Members ──────────────────────────────────────────────
  Stream<MemberModel?> memberStream(String memberId) {
    return _db
        .collection('members')
        .doc(memberId)
        .snapshots()
        .map((doc) => doc.exists ? MemberModel.fromFirestore(doc) : null);
  }

  Future<List<MemberModel>> getAllMembers() async {
    final snap = await _db.collection('members').orderBy('fullName').get();
    return snap.docs.map(MemberModel.fromFirestore).toList();
  }

  // ── Payments ──────────────────────────────────────────────
  Stream<List<PaymentModel>> memberPaymentsStream(String memberId) {
    return _db
        .collection('payments')
        .where('memberId', isEqualTo: memberId)
        .orderBy('year', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PaymentModel.fromFirestore).toList());
  }

  Future<PaymentModel?> getPayment(String paymentId) async {
    final doc = await _db.collection('payments').doc(paymentId).get();
    if (!doc.exists) return null;
    return PaymentModel.fromFirestore(doc);
  }

  Future<double> getTotalPaidThisYear(String memberId, int year) async {
    final snap = await _db
        .collection('payments')
        .where('memberId', isEqualTo: memberId)
        .where('year', isEqualTo: year)
        .where('status', isEqualTo: PaymentStatus.paid.name)
        .get();
    return snap.docs
        .map((d) => (d.data()['amount'] as num).toDouble())
        .fold<double>(0.0, (a, b) => a + b);
  }

  Future<void> updatePaymentStatus(String paymentId, PaymentStatus status,
      {String? receiptUrl, String? transactionId}) async {
    final updates = <String, dynamic>{'status': status.name};
    if (receiptUrl != null) updates['receiptUrl'] = receiptUrl;
    if (transactionId != null) updates['transactionId'] = transactionId;
    if (status == PaymentStatus.paid) {
      updates['paidDate'] = Timestamp.fromDate(DateTime.now());
    }
    await _db.collection('payments').doc(paymentId).update(updates);
  }

  // ── Transactions ──────────────────────────────────────────
  Future<String> createTransaction(TransactionModel tx) async {
    final ref = tx.id.isEmpty
        ? _db.collection('transactions').doc()
        : _db.collection('transactions').doc(tx.id);
    await ref.set(tx.toFirestore());
    return ref.id;
  }

  Future<String> createOrganizationReceiptTransaction({
    required String transactionId,
    required String organizationId,
    required String userId,
    required String membershipId,
    required String receiptStoragePath,
    required String receiptUrl,
    required String fileName,
    required String fileType,
    required int fileSize,
    String? paymentId,
    String? memberName,
    String? memberNumber,
    String? memberPhone,
    double? amountDeclared,
    String? paymentPeriod,
  }) async {
    final reference = _db
        .collection('organizations')
        .doc(organizationId)
        .collection('transactions')
        .doc(transactionId);
    final now = FieldValue.serverTimestamp();
    await reference.set({
      'transactionId': transactionId,
      'organizationId': organizationId,
      'userId': userId,
      'memberId': userId,
      'membershipId': membershipId,
      'uploadedByUserId': userId,
      'receiptStoragePath': receiptStoragePath,
      'receiptUrl': receiptUrl,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'status': 'pendingReview',
      'reviewStatus': 'pending',
      'currentStatus': TransactionStatus.submitted.name,
      'timeline': const [],
      'submittedAt': now,
      'createdAt': now,
      if (paymentId?.isNotEmpty == true) 'paymentId': paymentId,
      'memberName': memberName ?? '',
      'memberNumber': memberNumber ?? '',
      if (memberPhone?.isNotEmpty == true) 'memberPhone': memberPhone,
      if (amountDeclared != null) 'amountDeclared': amountDeclared,
      if (paymentPeriod?.isNotEmpty == true) 'paymentPeriod': paymentPeriod,
    });
    return reference.id;
  }

  Future<TransactionModel?> getTransactionById(String transactionId) async {
    final doc = await _db.collection('transactions').doc(transactionId).get();
    if (!doc.exists) return null;
    return TransactionModel.fromFirestore(doc);
  }

  Stream<TransactionModel?> transactionStream(String transactionId) {
    return _db
        .collection('transactions')
        .doc(transactionId)
        .snapshots()
        .map((doc) => doc.exists ? TransactionModel.fromFirestore(doc) : null);
  }

  Stream<TransactionModel?> organizationTransactionStream({
    required String organizationId,
    required String transactionId,
  }) {
    return _db
        .collection('organizations')
        .doc(organizationId)
        .collection('transactions')
        .doc(transactionId)
        .snapshots()
        .map((doc) => doc.exists ? TransactionModel.fromFirestore(doc) : null);
  }

  Stream<List<TransactionModel>> memberTransactionsStream(String memberId) {
    return _db
        .collectionGroup('transactions')
        .where('userId', isEqualTo: memberId)
        .snapshots()
        .map((snap) {
      final items = snap.docs.map(TransactionModel.fromFirestore).toList();
      items
          .sort((left, right) => right.submittedAt.compareTo(left.submittedAt));
      return items;
    });
  }

  Stream<List<TransactionModel>> pendingTransactionsStream() {
    return _db
        .collection('transactions')
        .where('currentStatus', isEqualTo: TransactionStatus.submitted.name)
        .orderBy('submittedAt')
        .snapshots()
        .map((snap) => snap.docs.map(TransactionModel.fromFirestore).toList());
  }

  Future<void> approveTransaction({
    required String transactionId,
    required String paymentId,
    required String adminName,
  }) async {
    final now = DateTime.now();
    final newEvent = TransactionEvent(
      status: TransactionStatus.approved,
      timestamp: now,
      adminName: adminName,
    );
    await _db.collection('transactions').doc(transactionId).update({
      'currentStatus': TransactionStatus.approved.name,
      'timeline': FieldValue.arrayUnion([newEvent.toMap()]),
    });
    await updatePaymentStatus(paymentId, PaymentStatus.paid,
        transactionId: transactionId);
  }

  Future<void> rejectTransaction({
    required String transactionId,
    required String paymentId,
    required String adminName,
    required String reason,
  }) async {
    final now = DateTime.now();
    final newEvent = TransactionEvent(
      status: TransactionStatus.rejected,
      timestamp: now,
      adminName: adminName,
      note: reason,
    );
    await _db.collection('transactions').doc(transactionId).update({
      'currentStatus': TransactionStatus.rejected.name,
      'rejectionReason': reason,
      'timeline': FieldValue.arrayUnion([newEvent.toMap()]),
    });
    await updatePaymentStatus(paymentId, PaymentStatus.rejected);
  }

  // ── Admin Stats ────────────────────────────────────────────
  Future<Map<String, dynamic>> getAdminStats(int year, int month) async {
    final allMembers = await getAllMembers();
    final paymentsSnap = await _db
        .collection('payments')
        .where('year', isEqualTo: year)
        .where('month', isEqualTo: month)
        .get();
    final payments = paymentsSnap.docs.map(PaymentModel.fromFirestore).toList();

    final totalCollected = payments
        .where((p) => p.status == PaymentStatus.paid)
        .fold<double>(0.0, (total, payment) => total + payment.amount);

    final paidMemberIds = payments
        .where((p) => p.status == PaymentStatus.paid)
        .map((p) => p.memberId)
        .toSet();

    return {
      'totalCollected': totalCollected,
      'committedCount': paidMemberIds.length,
      'lateCount': allMembers.length - paidMemberIds.length,
      'totalMembers': allMembers.length,
    };
  }
}
