import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/financial_models.dart';
import '../models/transaction_model.dart';

typedef MemberFinancialKey = ({String organizationId, String membershipId});

class FinancialRepository {
  FinancialRepository(
      {FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  static const _uuid = Uuid();

  DocumentReference<Map<String, dynamic>> _organization(
          String organizationId) =>
      _firestore.collection('organizations').doc(organizationId);

  Stream<FinancialSettings> streamSettings(String organizationId) =>
      _organization(organizationId)
          .collection('financial_settings')
          .doc('main')
          .snapshots()
          .map((doc) => doc.exists
              ? FinancialSettings.fromFirestore(doc)
              : FinancialSettings(organizationId: organizationId));

  Stream<MemberAccount?> streamMemberAccount(MemberFinancialKey key) =>
      _organization(key.organizationId)
          .collection('member_accounts')
          .doc(key.membershipId)
          .snapshots()
          .map((doc) => doc.exists ? MemberAccount.fromFirestore(doc) : null);

  Stream<List<SubscriptionPlan>> streamPlans(String organizationId,
      {bool activeOnly = false}) {
    Query<Map<String, dynamic>> query =
        _organization(organizationId).collection('subscription_plans');
    if (activeOnly) query = query.where('active', isEqualTo: true);
    return query.orderBy('createdAt', descending: true).snapshots().map(
          (snapshot) => snapshot.docs
              .map(SubscriptionPlan.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<FinancialCharge>> streamMemberCharges(MemberFinancialKey key) =>
      _organization(key.organizationId)
          .collection('charges')
          .where('membershipId', isEqualTo: key.membershipId)
          .orderBy('dueDate', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map(FinancialCharge.fromFirestore)
              .toList(growable: false));

  Stream<List<TransactionModel>> streamPayerTransactions(
          MemberFinancialKey key) =>
      _organization(key.organizationId)
          .collection('transactions')
          .where('payerMembershipId', isEqualTo: key.membershipId)
          .orderBy('submittedAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map(TransactionModel.fromFirestore)
              .toList(growable: false));

  Future<List<MemberDirectoryEntry>> listFinancialMembers(
      String organizationId) async {
    final result = await _functions
        .httpsCallable('listFinancialMembers')
        .call<Map<String, dynamic>>({'organizationId': organizationId});
    final rows = (result.data['members'] as List<dynamic>? ?? const [])
        .whereType<Map<Object?, Object?>>();
    return rows
        .map((row) =>
            MemberDirectoryEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Stream<List<FinancialCharge>> streamOrganizationCharges(
          String organizationId) =>
      _organization(organizationId)
          .collection('charges')
          .orderBy('updatedAt', descending: true)
          .limit(500)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map(FinancialCharge.fromFirestore)
              .toList(growable: false));

  Stream<TransactionModel?> streamTransaction(
          {required String organizationId, required String transactionId}) =>
      _organization(organizationId)
          .collection('transactions')
          .doc(transactionId)
          .snapshots()
          .map(
              (doc) => doc.exists ? TransactionModel.fromFirestore(doc) : null);

  Future<List<MemberDirectoryEntry>> searchMembers({
    required String organizationId,
    required String query,
  }) async {
    final normalized = normalizeArabicSearch(query);
    if (normalized.length < 3) return const [];
    final result = await _functions
        .httpsCallable('searchCouncilMembers')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'query': normalized,
    });
    final rows = (result.data['members'] as List<dynamic>? ?? const [])
        .whereType<Map<Object?, Object?>>();
    return rows
        .map((row) =>
            MemberDirectoryEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<FinancialCharge>> getPayableCharges({
    required String organizationId,
    required List<String> membershipIds,
  }) async {
    if (membershipIds.isEmpty) return const [];
    final requestedMembershipIds = membershipIds.toSet().take(10).toList();
    final charges = <FinancialCharge>[];
    final seenTokens = <String>{};
    String? pageToken;
    var pageCount = 0;
    do {
      final result = await _functions
          .httpsCallable('getPayableCharges')
          .call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'membershipIds': requestedMembershipIds,
        'pageSize': 50,
        if (pageToken != null) 'pageToken': pageToken,
      });
      final rows = (result.data['charges'] as List<dynamic>? ?? const [])
          .whereType<Map<Object?, Object?>>();
      charges.addAll(rows.map(
          (row) => FinancialCharge.fromMap(Map<String, dynamic>.from(row))));
      final next = result.data['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
      pageCount += 1;
      if (pageToken != null && !seenTokens.add(pageToken)) {
        throw StateError('Payable charge pagination repeated a page token.');
      }
      if (pageCount > 1000) {
        throw StateError(
            'Payable charge pagination exceeded its safety limit.');
      }
    } while (pageToken != null);
    return List.unmodifiable(charges);
  }

  Future<String> getFinancialReceiptDownloadUrl({
    required String organizationId,
    required String transactionId,
  }) async {
    final result = await _functions
        .httpsCallable('getFinancialReceiptDownloadUrl')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'transactionId': transactionId,
    });
    final url = result.data['url'];
    if (url is! String || url.isEmpty) {
      throw StateError('Financial receipt download URL is missing.');
    }
    return url;
  }

  Future<String> submitReceipt({
    required String receiptId,
    required String organizationId,
    required String payerMembershipId,
    required PaymentScope paymentScope,
    required int amountDeclaredBaisa,
    required String receiptUrl,
    required String receiptStoragePath,
    required String fileName,
    required String fileType,
    required List<ReceiptAllocation> allocations,
  }) async {
    final result = await _functions
        .httpsCallable('submitFinancialReceipt')
        .call<Map<String, dynamic>>({
      'organizationId': organizationId,
      'receiptId': receiptId,
      'payerMembershipId': payerMembershipId,
      'paymentScope': paymentScope.name,
      'amountDeclaredBaisa': amountDeclaredBaisa,
      'receiptUrl': receiptUrl,
      'receiptStoragePath': receiptStoragePath,
      'fileName': fileName,
      'fileType': fileType,
      'allocations':
          allocations.map((item) => item.toMap()).toList(growable: false),
    });
    return result.data['transactionId'] as String;
  }

  Future<void> cleanupOrphanReceipt({
    required String receiptStoragePath,
  }) async {
    await _functions.httpsCallable('cleanupOrphanReceipt').call<void>({
      'receiptStoragePath': receiptStoragePath,
    });
  }

  Future<void> reviewReceipt({
    required String organizationId,
    required String transactionId,
    required bool approve,
    String? rejectionReason,
  }) async {
    await _functions.httpsCallable('reviewFinancialReceipt').call<void>({
      'organizationId': organizationId,
      'transactionId': transactionId,
      'decision': approve ? 'approve' : 'reject',
      if (!approve) 'rejectionReason': rejectionReason?.trim(),
    });
  }

  Future<void> saveSettings(FinancialSettings settings, String actorId) async {
    await _functions.httpsCallable('updateFinancialSettings').call<void>({
      'requestId': _uuid.v4(),
      'organizationId': settings.organizationId,
      'feeMode': settings.feeMode.name,
      'receiptPaymentsEnabled': settings.receiptPaymentsEnabled,
      'allowMonthlyPlans': settings.allowMonthlyPlans,
      'allowAnnualPlans': settings.allowAnnualPlans,
      'memberBookingFeeBaisa': settings.memberBookingFeeBaisa,
      'nonMemberBookingFeeBaisa': settings.nonMemberBookingFeeBaisa,
      'eventBookingFeeBaisa': settings.eventBookingFeeBaisa,
    });
  }

  Future<void> savePlan({
    required String organizationId,
    required String actorId,
    String? planId,
    required String nameArabic,
    required String descriptionArabic,
    required BillingCycle billingCycle,
    required int amountBaisa,
    required bool active,
  }) async {
    await _functions.httpsCallable('saveFinancialPlan').call<void>({
      'requestId': _uuid.v4(),
      'organizationId': organizationId,
      if (planId != null) 'planId': planId,
      'nameArabic': nameArabic.trim(),
      'descriptionArabic': descriptionArabic.trim(),
      'billingCycle': billingCycle.name,
      'amountBaisa': amountBaisa,
      'active': active,
    });
  }

  Future<void> updateMemberAccount({
    required String organizationId,
    required String membershipId,
    required String userId,
    required String actorId,
    String? planId,
    required FeeOverrideType overrideType,
    int? customAmountBaisa,
    String? exemptionReason,
  }) async {
    await _functions.httpsCallable('updateMemberFinancialAccount').call<void>({
      'requestId': _uuid.v4(),
      'organizationId': organizationId,
      'membershipId': membershipId,
      if (planId != null) 'planId': planId,
      'feeOverrideType': overrideType == FeeOverrideType.defaultFee
          ? 'default'
          : overrideType.name,
      if (overrideType == FeeOverrideType.custom)
        'customAmountBaisa': customAmountBaisa,
      if (overrideType == FeeOverrideType.exempt)
        'exemptionReason': exemptionReason?.trim(),
    });
  }

  Future<void> createManualCharge({
    required String organizationId,
    required String membershipId,
    required String userId,
    required String actorId,
    required String titleArabic,
    required String descriptionArabic,
    required int amountBaisa,
    required DateTime dueDate,
    required String idempotencyKey,
  }) async {
    await _functions.httpsCallable('createManualFinancialCharge').call<void>({
      'requestId': idempotencyKey,
      'organizationId': organizationId,
      'membershipId': membershipId,
      'titleArabic': titleArabic.trim(),
      'descriptionArabic': descriptionArabic.trim(),
      'amountBaisa': amountBaisa,
      'dueDate': dueDate.toUtc().toIso8601String(),
    });
  }
}
