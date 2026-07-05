import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/membership_request_model.dart';
import '../data/membership_request_repository.dart';

final membershipRequestRepositoryProvider =
    Provider((ref) => MembershipRequestRepository());

final userMembershipRequestsProvider =
    StreamProvider.family<List<MembershipRequestModel>, String>((ref, userId) {
  return ref.watch(membershipRequestRepositoryProvider).streamForUser(userId);
});

final pendingMembershipRequestsProvider =
    StreamProvider.family<List<MembershipRequestModel>, String>(
        (ref, organizationId) {
  return ref
      .watch(membershipRequestRepositoryProvider)
      .streamPendingForOrganization(organizationId);
});

class MembershipRequestSubmissionState {
  final bool isSubmitting;
  final bool isSubmitted;
  final String? error;

  const MembershipRequestSubmissionState({
    this.isSubmitting = false,
    this.isSubmitted = false,
    this.error,
  });
}

class MembershipRequestSubmissionNotifier
    extends StateNotifier<MembershipRequestSubmissionState> {
  MembershipRequestSubmissionNotifier(this._repository)
      : super(const MembershipRequestSubmissionState());

  final MembershipRequestRepository _repository;

  Future<bool> submit(MembershipRequestModel request) async {
    state = const MembershipRequestSubmissionState(isSubmitting: true);
    try {
      await _repository.submit(request);
      state = const MembershipRequestSubmissionState(isSubmitted: true);
      return true;
    } on DuplicatePendingMembershipRequestException {
      state = const MembershipRequestSubmissionState(
        error: 'لديك طلب انضمام قيد المراجعة لهذا المجلس',
      );
      return false;
    } on StateError {
      state = const MembershipRequestSubmissionState(
        error: 'لديك عضوية نشطة في هذا المجلس',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('[JoinRequest] submit failed: $error\n$stackTrace');
      state = const MembershipRequestSubmissionState(
        error: 'تعذر إرسال طلب الانضمام. حاول مرة أخرى.',
      );
      return false;
    }
  }

  void reset() {
    state = const MembershipRequestSubmissionState();
  }
}

final membershipRequestSubmissionProvider = StateNotifierProvider<
    MembershipRequestSubmissionNotifier, MembershipRequestSubmissionState>(
  (ref) => MembershipRequestSubmissionNotifier(
    ref.watch(membershipRequestRepositoryProvider),
  ),
);
