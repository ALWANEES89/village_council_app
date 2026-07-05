import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../data/models/member_model.dart';
import '../data/models/membership_model.dart';
import '../data/models/payment_model.dart';
import '../data/models/transaction_model.dart';
import '../data/models/user_profile_model.dart';
import '../data/services/auth_service.dart';
import '../data/services/firestore_service.dart';
import '../data/services/storage_service.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/membership_repository.dart';
import '../data/repositories/organization_repository.dart';
import '../data/repositories/role_repository.dart';
import '../data/repositories/platform_admin_repository.dart';
import '../data/repositories/financial_receipt_repository.dart';
import '../data/repositories/booking_repository.dart';
import '../data/models/booking_model.dart';
import '../data/models/app_notification_model.dart';
import '../data/repositories/notification_repository.dart';
import '../core/context/organization_context.dart';
import '../core/auth/admin_access.dart';

// ── Services ──────────────────────────────────────────────────────────────────
final authServiceProvider = Provider((ref) => AuthService());
final firestoreServiceProvider = Provider((ref) => FirestoreService());
final storageServiceProvider = Provider((ref) => StorageService());

// â”€â”€ Repositories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
final userRepositoryProvider = Provider((ref) => UserRepository());
final userProfileProvider =
    StreamProvider.family<UserProfileModel?, String>((ref, userId) {
  return ref.watch(userRepositoryProvider).streamProfile(userId);
});
final membershipRepositoryProvider = Provider((ref) => MembershipRepository());
final organizationRepositoryProvider =
    Provider((ref) => OrganizationRepository());
final roleRepositoryProvider = Provider((ref) => RoleRepository());
final platformAdminRepositoryProvider =
    Provider((ref) => PlatformAdminRepository());
final financialReceiptRepositoryProvider =
    Provider((ref) => FinancialReceiptRepository());
final bookingRepositoryProvider = Provider((ref) => BookingRepository());
final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository());

final userNotificationsProvider =
    StreamProvider.family<List<AppNotificationModel>, String>((ref, userId) {
  return ref.watch(notificationRepositoryProvider).streamForUser(userId);
});

final unreadNotificationsCountProvider =
    Provider.family<int, String>((ref, userId) {
  return ref.watch(userNotificationsProvider(userId)).maybeWhen(
        data: (items) => items.where((item) => item.isUnread).length,
        orElse: () => 0,
      );
});

final organizationBookingsProvider =
    StreamProvider.family<List<BookingModel>, String>((ref, organizationId) {
  return ref
      .watch(bookingRepositoryProvider)
      .streamForOrganization(organizationId);
});

final pendingFinancialReceiptsProvider =
    StreamProvider.family<List<TransactionModel>, String>(
        (ref, organizationId) {
  return ref
      .watch(financialReceiptRepositoryProvider)
      .streamPending(organizationId);
});

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
    StreamProvider.family<List<MembershipModel>, String>((ref, userId) {
  return ref.watch(membershipRepositoryProvider).streamForUser(userId);
});

typedef MembershipDocumentLookup = ({
  String organizationId,
  String membershipId,
});

final membershipDocumentProvider =
    StreamProvider.family<MembershipModel?, MembershipDocumentLookup>(
        (ref, lookup) {
  return ref.watch(membershipRepositoryProvider).stream(
        organizationId: lookup.organizationId,
        membershipId: lookup.membershipId,
      );
});

final activeUserMembershipsProvider =
    StreamProvider.family<ActiveMembershipsResult, String>((ref, userId) {
  return ref.watch(membershipRepositoryProvider).streamActiveForUser(userId);
});

final organizationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(organizationRepositoryProvider).streamAll();
});

final organizationDetailsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, organizationId) {
  return ref.watch(organizationRepositoryProvider).getById(organizationId);
});

// ── Auth State ────────────────────────────────────────────────────────────────
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

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
  } catch (_) {
    // Super Admin claims and profile flags can still grant platform access.
  }
  var isSuperAdmin = false;
  try {
    isSuperAdmin = await ref
        .read(platformAdminRepositoryProvider)
        .isActiveSuperAdmin(user.uid);
  } catch (_) {
    // A failed platform lookup must not elevate access.
  }
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

// ── Member Data ───────────────────────────────────────────────────────────────
final memberStreamProvider =
    StreamProvider.family<MemberModel?, String>((ref, memberId) {
  return ref.watch(firestoreServiceProvider).memberStream(memberId);
});

final memberPaymentsProvider =
    StreamProvider.family<List<PaymentModel>, String>((ref, memberId) {
  return ref.watch(firestoreServiceProvider).memberPaymentsStream(memberId);
});

final memberTransactionsProvider =
    StreamProvider.family<List<TransactionModel>, String>((ref, memberId) {
  return ref.watch(firestoreServiceProvider).memberTransactionsStream(memberId);
});

final totalPaidThisYearProvider =
    FutureProvider.family<double, String>((ref, memberId) async {
  return ref.watch(firestoreServiceProvider).getTotalPaidThisYear(
        memberId,
        DateTime.now().year,
      );
});

// ── Admin ─────────────────────────────────────────────────────────────────────
final pendingTransactionsProvider =
    StreamProvider<List<TransactionModel>>((ref) {
  return ref.watch(firestoreServiceProvider).pendingTransactionsStream();
});

final adminStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final now = DateTime.now();
  return ref.watch(firestoreServiceProvider).getAdminStats(now.year, now.month);
});

// ── Receipt Upload State ──────────────────────────────────────────────────────
class UploadState {
  final bool isUploading;
  final double progress;
  final String? error;

  const UploadState({
    this.isUploading = false,
    this.progress = 0,
    this.error,
  });

  UploadState copyWith({bool? isUploading, double? progress, String? error}) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      error: error,
    );
  }
}

class UploadNotifier extends StateNotifier<UploadState> {
  UploadNotifier(
    this._firestoreService,
    this._storageService,
    this._notificationRepository,
  ) : super(const UploadState());

  final FirestoreService _firestoreService;
  final StorageService _storageService;
  final NotificationRepository _notificationRepository;

  Future<bool> uploadReceipt({
    required dynamic file,
    required String memberId,
    required String memberName,
    required String paymentId,
    required String periodLabel,
    String? organizationId,
    String? membershipId,
    double? amountDeclared,
    String? paymentPeriod,
    String? memberNumber,
    String? memberPhone,
  }) async {
    state = const UploadState(isUploading: true, progress: 0);
    try {
      if (organizationId == null || organizationId.trim().isEmpty) {
        throw StateError('Missing organization context.');
      }
      // الإيصال يخصّ دائمًا المستخدم المسجّل الحالي. قواعد Storage وقواعد إنشاء
      // معاملة Firestore تشترطان أن يكون المالك == auth.uid، لذا لا نثق بأي
      // معرّف ممرّر (قد يكون معرّف مستند members قديمًا مختلفًا عن الـ uid،
      // فيسبّب firebase_storage/unauthorized). المصدر الموثوق الوحيد للهوية.
      final ownerUserId = FirebaseAuth.instance.currentUser?.uid;
      if (ownerUserId == null) {
        throw StateError('User is not authenticated.');
      }
      // تحقّق تشخيصي (debug فقط): يؤكّد أن مالك الإيصال = auth.uid وأنه قد يختلف
      // عن أي معرّف عضو قديم مُمرّر من الشاشة.
      debugPrint('[Receipts] auth.uid=$ownerUserId passedMemberId=$memberId '
          'match=${ownerUserId == memberId} org=$organizationId');
      final receiptId = const Uuid().v4();
      final upload = await _storageService.uploadReceipt(
        file: file,
        memberId: ownerUserId,
        organizationId: organizationId,
        receiptId: receiptId,
        onProgress: (p) => state = state.copyWith(progress: p),
      );

      final txId = await _firestoreService.createOrganizationReceiptTransaction(
        transactionId: receiptId,
        organizationId: organizationId,
        userId: ownerUserId,
        membershipId: membershipId ?? ownerUserId,
        receiptStoragePath: upload.fullPath,
        receiptUrl: upload.url,
        fileName: upload.fileName,
        fileType: upload.fileType,
        fileSize: upload.fileSize,
        paymentId: paymentId,
        memberName: memberName,
        memberNumber: memberNumber,
        memberPhone: memberPhone,
        amountDeclared: amountDeclared,
        paymentPeriod: paymentPeriod,
      );
      debugPrint('[Receipts] transaction created id=$txId '
          'userId=uploadedByUserId=$ownerUserId (== auth.uid)');

      // The transaction is the authoritative result. Notifications and the
      // legacy payment mirror must never turn a successful submission into a
      // reported upload failure.
      await _notificationRepository.notifyOrganizationReviewers(
        organizationId: organizationId,
        permissions: const [
          'receipts.review',
          'payments.approve',
          'payments.reject',
        ],
        title: 'إيصال جديد للمراجعة',
        body: 'تم إرسال إيصال دفع جديد للمراجعة.',
        type: 'receiptSubmitted',
        relatedEntityType: 'receipt',
        relatedEntityId: txId,
        createdByUserId: ownerUserId,
      );
      await _notificationRepository.createForUser(
        userId: ownerUserId,
        organizationId: organizationId,
        title: 'تم إرسال الإيصال للمراجعة',
        body: 'إيصالك قيد مراجعة مسؤول المالية.',
        type: 'receiptReceived',
        relatedEntityType: 'receipt',
        relatedEntityId: txId,
        createdByUserId: ownerUserId,
      );

      if (paymentId.isNotEmpty) {
        try {
          await _firestoreService.updatePaymentStatus(
            paymentId,
            PaymentStatus.pending,
            receiptUrl: upload.url,
            transactionId: txId,
          );
        } catch (error, stackTrace) {
          // The organization transaction is authoritative for review.
          debugPrint(
            '[Upload] legacy payment update skipped: $error\n$stackTrace',
          );
        }
      }

      state = const UploadState();
      return true;
    } catch (e, stackTrace) {
      debugPrint('[Upload] receipt upload failed: $e\n$stackTrace');
      state = UploadState(error: e.toString());
      return false;
    }
  }
}

final uploadProvider =
    StateNotifierProvider<UploadNotifier, UploadState>((ref) {
  return UploadNotifier(
    ref.watch(firestoreServiceProvider),
    ref.watch(storageServiceProvider),
    ref.watch(notificationRepositoryProvider),
  );
});

// ── OTP State ─────────────────────────────────────────────────────────────────
class OtpState {
  final bool isLoading;
  final bool codeSent;
  final String? phone;
  final String? error;

  const OtpState({
    this.isLoading = false,
    this.codeSent = false,
    this.phone,
    this.error,
  });

  OtpState copyWith({
    bool? isLoading,
    bool? codeSent,
    String? phone,
    String? error,
  }) {
    return OtpState(
      isLoading: isLoading ?? this.isLoading,
      codeSent: codeSent ?? this.codeSent,
      phone: phone ?? this.phone,
      error: error,
    );
  }
}

class OtpNotifier extends StateNotifier<OtpState> {
  OtpNotifier(this._authService) : super(const OtpState());

  final AuthService _authService;

  Future<void> sendOtp(String phone) async {
    state = OtpState(
      isLoading: false,
      codeSent: true,
      phone: phone,
    );
  }

  Future<MemberModel?> verifyOtp(String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final phone = state.phone;

      if (phone == null || phone.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error:
              'انتهت الجلسة. يرجى إعادة إدخال رقم الهاتف والمحاولة مرة أخرى.',
        );
        return null;
      }

      final member = await _authService.signInWithPhoneAndPassword(
        phone: phone,
        password: password,
      );

      if (member == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'رقم الهاتف أو كلمة المرور غير صحيحة. يرجى المحاولة مجددًا.',
        );
        return null;
      }

      state = const OtpState();
      return member;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'تعذر تسجيل الدخول. حاول مرة أخرى.',
      );
      return null;
    }
  }
}

final otpProvider = StateNotifierProvider<OtpNotifier, OtpState>((ref) {
  return OtpNotifier(ref.watch(authServiceProvider));
});
