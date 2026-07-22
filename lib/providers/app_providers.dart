import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/auth/admin_access.dart';
import '../core/context/organization_context.dart';
import '../data/models/app_notification_model.dart';
import '../data/models/booking_model.dart';
import '../data/models/financial_models.dart';
import '../data/models/member_model.dart';
import '../data/models/membership_model.dart';
import '../data/models/payment_model.dart';
import '../data/models/transaction_model.dart';
import '../data/models/user_profile_model.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/financial_receipt_repository.dart';
import '../data/repositories/financial_repository.dart';
import '../data/repositories/membership_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/organization_repository.dart';
import '../data/repositories/platform_admin_repository.dart';
import '../data/repositories/role_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/firestore_service.dart';
import '../data/services/storage_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final firestoreServiceProvider = Provider((ref) => FirestoreService());
final storageServiceProvider = Provider((ref) => StorageService());

final userRepositoryProvider = Provider((ref) => UserRepository());
final membershipRepositoryProvider = Provider((ref) => MembershipRepository());
final organizationRepositoryProvider =
    Provider((ref) => OrganizationRepository());
final roleRepositoryProvider = Provider((ref) => RoleRepository());
final platformAdminRepositoryProvider =
    Provider((ref) => PlatformAdminRepository());
final financialReceiptRepositoryProvider =
    Provider((ref) => FinancialReceiptRepository());
final financialRepositoryProvider = Provider((ref) => FinancialRepository());
final bookingRepositoryProvider = Provider((ref) => BookingRepository());
final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository());

final authStateProvider = StreamProvider<User?>(
    (ref) => ref.watch(authServiceProvider).authStateChanges);

final userProfileProvider = StreamProvider.family<UserProfileModel?, String>(
  (ref, userId) => ref.watch(userRepositoryProvider).streamProfile(userId),
);

final userNotificationsProvider =
    StreamProvider.family<List<AppNotificationModel>, String>(
  (ref, userId) =>
      ref.watch(notificationRepositoryProvider).streamForUser(userId),
);

final unreadNotificationsCountProvider =
    Provider.family<int, String>((ref, userId) {
  return ref.watch(userNotificationsProvider(userId)).maybeWhen(
        data: (items) => items.where((item) => item.isUnread).length,
        orElse: () => 0,
      );
});

final organizationBookingsProvider =
    StreamProvider.family<List<BookingModel>, String>(
  (ref, organizationId) => ref
      .watch(bookingRepositoryProvider)
      .streamForOrganization(organizationId),
);

final userBookingsProvider = StreamProvider.autoDispose
    .family<List<BookingModel>, ({String organizationId, String userId})>(
  (ref, key) => ref
      .watch(bookingRepositoryProvider)
      .streamForUser(key.organizationId, key.userId),
);

final bookingAvailabilityProvider = FutureProvider.autoDispose
    .family<List<BookingModel>, ({String organizationId, int year, int month})>(
  (ref, key) => ref.watch(bookingRepositoryProvider).getAvailability(
        organizationId: key.organizationId,
        month: DateTime(key.year, key.month),
      ),
);

final pendingFinancialReceiptsProvider =
    StreamProvider.family<List<TransactionModel>, String>(
  (ref, organizationId) => ref
      .watch(financialReceiptRepositoryProvider)
      .streamPending(organizationId),
);

final organizationContextProvider =
    StateNotifierProvider<OrganizationContextNotifier, OrganizationContext>(
        (ref) {
  return OrganizationContextNotifier(
    organizationRepository: ref.watch(organizationRepositoryProvider),
    membershipRepository: ref.watch(membershipRepositoryProvider),
    roleRepository: ref.watch(roleRepositoryProvider),
  );
});

final userMembershipsProvider =
    StreamProvider.family<List<MembershipModel>, String>(
  (ref, userId) =>
      ref.watch(membershipRepositoryProvider).streamForUser(userId),
);

typedef MembershipDocumentLookup = ({
  String organizationId,
  String membershipId
});

final membershipDocumentProvider =
    StreamProvider.family<MembershipModel?, MembershipDocumentLookup>(
  (ref, lookup) => ref.watch(membershipRepositoryProvider).stream(
        organizationId: lookup.organizationId,
        membershipId: lookup.membershipId,
      ),
);

final activeUserMembershipsProvider =
    StreamProvider.family<ActiveMembershipsResult, String>(
  (ref, userId) =>
      ref.watch(membershipRepositoryProvider).streamActiveForUser(userId),
);

final organizationsProvider = StreamProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(organizationRepositoryProvider).streamAll(),
);

final organizationDetailsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, organizationId) =>
      ref.watch(organizationRepositoryProvider).getById(organizationId),
);

final currentMemberProvider = FutureProvider<MemberModel?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.read(authServiceProvider).getCurrentMember();
});

final adminAccessProvider = FutureProvider<AdminAccess>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const AdminAccess();
  final organizationContext = ref.watch(organizationContextProvider);
  MemberModel? member;
  try {
    member = await ref.watch(currentMemberProvider.future);
  } catch (_) {}
  var isSuperAdmin = false;
  try {
    isSuperAdmin = await ref
        .read(platformAdminRepositoryProvider)
        .isActiveSuperAdmin(user.uid);
  } catch (_) {}
  final membership = organizationContext.currentMembership;
  return AdminAccess(
    isSuperAdmin: isSuperAdmin,
    isLegacyAdmin: member?.isAdmin == true,
    permissions: organizationContext.permissions,
    roleId: membership?.roleId ?? '',
    role: membership?.role ?? '',
    isPrimaryOwner: membership?.isPrimaryOwner ?? false,
    status: membership?.status.name ?? '',
  );
});

final currentPlatformAdminProvider =
    StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(platformAdminRepositoryProvider).stream(user.uid);
});

final memberStreamProvider = StreamProvider.family<MemberModel?, String>(
  (ref, memberId) => ref.watch(firestoreServiceProvider).memberStream(memberId),
);
final memberPaymentsProvider =
    StreamProvider.family<List<PaymentModel>, MemberFinancialKey>(
  (ref, key) => ref.watch(firestoreServiceProvider).memberPaymentsStream(
        memberId: key.membershipId,
        organizationId: key.organizationId,
      ),
);
final memberTransactionsProvider =
    StreamProvider.family<List<TransactionModel>, String>(
  (ref, memberId) =>
      ref.watch(firestoreServiceProvider).memberTransactionsStream(memberId),
);
final totalPaidThisYearProvider =
    FutureProvider.family<double, String>((ref, memberId) {
  return ref
      .watch(firestoreServiceProvider)
      .getTotalPaidThisYear(memberId, DateTime.now().year);
});
final financialSettingsProvider =
    StreamProvider.autoDispose.family<FinancialSettings, String>(
  (ref, organizationId) =>
      ref.watch(financialRepositoryProvider).streamSettings(organizationId),
);
final subscriptionPlansProvider =
    StreamProvider.autoDispose.family<List<SubscriptionPlan>, String>(
  (ref, organizationId) =>
      ref.watch(financialRepositoryProvider).streamPlans(organizationId),
);
final memberAccountProvider =
    StreamProvider.autoDispose.family<MemberAccount?, MemberFinancialKey>(
  (ref, key) => ref.watch(financialRepositoryProvider).streamMemberAccount(key),
);
final memberChargesProvider = StreamProvider.autoDispose
    .family<List<FinancialCharge>, MemberFinancialKey>(
  (ref, key) => ref.watch(financialRepositoryProvider).streamMemberCharges(key),
);
final payerFinancialTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, MemberFinancialKey>(
  (ref, key) =>
      ref.watch(financialRepositoryProvider).streamPayerTransactions(key),
);
final financialMemberDirectoryProvider =
    FutureProvider.autoDispose.family<List<MemberDirectoryEntry>, String>(
  (ref, organizationId) => ref
      .watch(financialRepositoryProvider)
      .listFinancialMembers(organizationId),
);
final organizationChargesProvider =
    StreamProvider.autoDispose.family<List<FinancialCharge>, String>(
  (ref, organizationId) => ref
      .watch(financialRepositoryProvider)
      .streamOrganizationCharges(organizationId),
);

typedef FinancialTransactionKey = ({
  String organizationId,
  String transactionId
});

final financialTransactionProvider = StreamProvider.autoDispose
    .family<TransactionModel?, FinancialTransactionKey>(
  (ref, key) => ref.watch(financialRepositoryProvider).streamTransaction(
        organizationId: key.organizationId,
        transactionId: key.transactionId,
      ),
);

class UploadState {
  const UploadState({this.isUploading = false, this.progress = 0, this.error});
  final bool isUploading;
  final double progress;
  final String? error;

  UploadState copyWith({bool? isUploading, double? progress, String? error}) =>
      UploadState(
        isUploading: isUploading ?? this.isUploading,
        progress: progress ?? this.progress,
        error: error,
      );
}

class UploadNotifier extends StateNotifier<UploadState> {
  UploadNotifier(this._storageService, this._financialRepository)
      : super(const UploadState());

  final StorageService _storageService;
  final FinancialRepository _financialRepository;

  Future<bool> uploadReceipt({
    required dynamic file,
    required String organizationId,
    required String membershipId,
    required PaymentScope paymentScope,
    required int amountDeclaredBaisa,
    required List<ReceiptAllocation> allocations,
  }) async {
    state = const UploadState(isUploading: true);
    String? uploadedReceiptPath;
    try {
      final ownerUserId = FirebaseAuth.instance.currentUser?.uid;
      if (ownerUserId == null) throw StateError('User is not authenticated.');
      if (organizationId.isEmpty ||
          membershipId.isEmpty ||
          allocations.isEmpty) {
        throw StateError('Missing financial receipt data.');
      }
      final receiptId = const Uuid().v4();
      final upload = await _storageService.uploadReceipt(
        file: file,
        memberId: ownerUserId,
        organizationId: organizationId,
        receiptId: receiptId,
        onProgress: (progress) => state = state.copyWith(progress: progress),
      );
      uploadedReceiptPath = upload.fullPath;
      await _financialRepository.submitReceipt(
        receiptId: receiptId,
        organizationId: organizationId,
        payerMembershipId: membershipId,
        paymentScope: paymentScope,
        amountDeclaredBaisa: amountDeclaredBaisa,
        receiptStoragePath: upload.fullPath,
        fileName: upload.fileName,
        fileType: upload.fileType,
        allocations: allocations,
      );
      debugPrint('[Receipts] submitted successfully');
      state = const UploadState();
      return true;
    } catch (error) {
      if (uploadedReceiptPath != null) {
        try {
          await _financialRepository.cleanupOrphanReceipt(
            receiptStoragePath: uploadedReceiptPath,
          );
        } catch (cleanupError) {
          debugPrint(
              '[Receipts] deferred orphan cleanup type=${cleanupError.runtimeType}');
        }
      }
      debugPrint('[Receipts] upload failed type=${error.runtimeType}');
      state = const UploadState(
        error: 'تعذر إرسال الإيصال. تحقق من الملف والمبلغ ثم حاول مجددًا.',
      );
      return false;
    }
  }
}

final uploadProvider =
    StateNotifierProvider<UploadNotifier, UploadState>((ref) {
  return UploadNotifier(ref.watch(storageServiceProvider),
      ref.watch(financialRepositoryProvider));
});

class OtpState {
  const OtpState(
      {this.isLoading = false, this.codeSent = false, this.phone, this.error});
  final bool isLoading;
  final bool codeSent;
  final String? phone;
  final String? error;

  OtpState copyWith(
          {bool? isLoading, bool? codeSent, String? phone, String? error}) =>
      OtpState(
        isLoading: isLoading ?? this.isLoading,
        codeSent: codeSent ?? this.codeSent,
        phone: phone ?? this.phone,
        error: error,
      );
}

class OtpNotifier extends StateNotifier<OtpState> {
  OtpNotifier(this._authService) : super(const OtpState());
  final AuthService _authService;

  Future<void> sendOtp(String phone) async {
    state = OtpState(codeSent: true, phone: phone);
  }

  Future<MemberModel?> verifyOtp(String password) async {
    state = state.copyWith(isLoading: true);
    final phone = state.phone;
    if (phone == null || phone.isEmpty) {
      state = state.copyWith(
          isLoading: false, error: 'انتهت الجلسة. أعد إدخال رقم الهاتف.');
      return null;
    }
    try {
      final member = await _authService.signInWithPhoneAndPassword(
          phone: phone, password: password);
      if (member == null) {
        state = state.copyWith(
            isLoading: false, error: 'رقم الهاتف أو كلمة المرور غير صحيحة.');
        return null;
      }
      state = const OtpState();
      return member;
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'تعذر تسجيل الدخول. حاول مرة أخرى.');
      return null;
    }
  }
}

final otpProvider = StateNotifierProvider<OtpNotifier, OtpState>(
  (ref) => OtpNotifier(ref.watch(authServiceProvider)),
);
