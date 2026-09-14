import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/domain/membership/join_council_routing.dart';
import 'package:village_council_app/features/membership_request/data/membership_request_model.dart';
import 'package:village_council_app/features/membership_request/data/membership_request_repository.dart';
import 'package:village_council_app/features/membership_request/presentation/join_request_screen.dart';
import 'package:village_council_app/features/membership_request/providers/membership_request_providers.dart';

class _DuplicatePendingRepository
    implements MembershipRequestSubmissionRepository {
  @override
  Future<void> submit(MembershipRequestModel request) {
    throw const DuplicatePendingMembershipRequestException();
  }
}

MembershipRequestModel _request() => MembershipRequestModel(
      requestId: 'user-1',
      organizationId: 'council-a',
      userId: 'user-1',
      fullName: 'QA User',
      civilId: '12345678',
      phone: '+96890000000',
      email: '',
      address: '',
      requestedRole: 'member',
      status: MembershipRequestStatus.pending,
      submittedAt: DateTime(2026, 9, 14),
    );

void main() {
  test('authenticated landing sends only users without memberships to join',
      () {
    expect(
      shouldOpenJoinCouncil(
        activeMembershipCount: 0,
        membershipsLoadFailed: false,
        isSystemOwner: false,
      ),
      isTrue,
    );
    expect(
      shouldOpenJoinCouncil(
        activeMembershipCount: 1,
        membershipsLoadFailed: false,
        isSystemOwner: false,
      ),
      isFalse,
    );
    expect(
      shouldOpenJoinCouncil(
        activeMembershipCount: 0,
        membershipsLoadFailed: true,
        isSystemOwner: false,
      ),
      isFalse,
    );
  });

  test('council search matches Arabic, English, and short names', () {
    final organization = <String, dynamic>{
      'organizationId': 'council-a',
      'officialNameArabic': 'مجلس الرحمات',
      'officialNameEnglish': 'Al Rahmat Council',
      'shortName': 'الرحمات',
    };

    expect(organizationMatchesJoinQuery(organization, 'مجلس الرحمات'), isTrue);
    expect(organizationMatchesJoinQuery(organization, 'Rahmat'), isTrue);
    expect(organizationMatchesJoinQuery(organization, 'الرحمات'), isTrue);
    expect(organizationMatchesJoinQuery(organization, 'Noor'), isFalse);
  });

  test('duplicate pending request is surfaced and not resubmitted as success',
      () async {
    final notifier =
        MembershipRequestSubmissionNotifier(_DuplicatePendingRepository());

    expect(await notifier.submit(_request()), isFalse);
    expect(
      notifier.state.failure,
      MembershipRequestSubmissionFailure.duplicatePending,
    );
    expect(notifier.state.isSubmitted, isFalse);
  });

  test('language switcher exists only in login and My Account screens', () {
    final login = File(
      'lib/presentation/screens/auth/login_screen.dart',
    ).readAsStringSync();
    final account = File(
      'lib/presentation/screens/member/my_account_screen.dart',
    ).readAsStringSync();
    final home = File(
      'lib/presentation/screens/member/member_home_screen.dart',
    ).readAsStringSync();
    final council = File(
      'lib/presentation/screens/council/council_dashboard_screen.dart',
    ).readAsStringSync();
    final system = File(
      'lib/presentation/screens/admin/admin_dashboard.dart',
    ).readAsStringSync();

    expect(login, contains('LanguageSwitcher'));
    expect(account, contains('LanguageSwitcher'));
    expect(home, isNot(contains('LanguageSwitcher')));
    expect(council, isNot(contains('LanguageSwitcher')));
    expect(system, isNot(contains('LanguageSwitcher')));
    expect(account, contains("pushNamed('joinRequest')"));
  });

  test('notification retry reuses one idempotency request id', () {
    final screen = File(
      'lib/presentation/screens/council/send_council_notification_screen.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/data/repositories/council_management_repository.dart',
    ).readAsStringSync();

    expect(screen, contains('final String _requestId = const Uuid().v4();'));
    expect(screen, contains('requestId: _requestId'));
    expect(repository, contains('required String requestId'));
    expect(repository, contains("'requestId': requestId"));
  });
}
