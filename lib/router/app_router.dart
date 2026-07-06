import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_providers.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/otp_screen.dart';
import '../presentation/screens/auth/register_screen.dart';
import '../presentation/screens/member/member_dashboard.dart';
import '../presentation/screens/member/member_home_screen.dart';
import '../presentation/screens/member/profile_edit_screen.dart';
import '../presentation/screens/member/receipt_upload_screen.dart';
import '../presentation/screens/member/transaction_timeline_screen.dart';
import '../presentation/screens/member/council_booking_screen.dart';
import '../presentation/screens/member/receipt_history_screen.dart';
import '../presentation/screens/admin/admin_dashboard.dart';
import '../presentation/screens/admin/admin_review_screen.dart';
import '../presentation/screens/admin/create_organization_screen.dart';
import '../presentation/screens/admin/organizations_management_screen.dart';
import '../presentation/screens/admin/roles_management_screen.dart';
import '../presentation/screens/admin/financial_review_screen.dart';
import '../presentation/screens/organization/organization_selector_screen.dart';
import '../features/membership_request/presentation/join_request_screen.dart';
import '../presentation/screens/admin/membership_requests_review_screen.dart';
import '../presentation/screens/admin/booking_requests_review_screen.dart';
import '../presentation/screens/notifications/notifications_screen.dart';
import '../presentation/screens/notifications/notification_settings_screen.dart';
import '../features/member_management/presentation/member_list_screen.dart';
import '../features/member_management/presentation/member_details_screen.dart';
import '../features/member_management/presentation/member_permissions_screen.dart';
import '../features/audit/presentation/audit_logs_screen.dart';
import '../presentation/screens/council/council_dashboard_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen(authStateProvider, (_, __) => refreshNotifier.refresh());

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final isLoggedIn = ref.read(authStateProvider).value != null;
      final isOnLogin = state.matchedLocation.startsWith('/login');
      final isOnOtp = state.matchedLocation.startsWith('/otp');
      final isOnRegister = state.matchedLocation.startsWith('/register');
      final isQrDeepLink =
          state.uri.scheme == 'communityos' && state.uri.host == 'join';

      if (!isLoggedIn && isQrDeepLink) {
        return Uri(
          path: '/login',
          queryParameters: state.uri.queryParameters,
        ).toString();
      }
      if (!isLoggedIn && !isOnLogin && !isOnOtp && !isOnRegister) {
        return '/login';
      }
      if (isLoggedIn && isOnLogin) {
        return '/member-home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, state) {
          if (state.uri.scheme == 'communityos' && state.uri.host == 'join') {
            return Uri(
              path: '/join',
              queryParameters: state.uri.queryParameters,
            ).toString();
          }
          return '/login';
        },
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, state) => LoginScreen(
          organizationId: state.uri.queryParameters['organizationId'],
          joinCode: state.uri.queryParameters['joinCode'],
        ),
      ),
      GoRoute(
        path: '/otp',
        name: 'otp',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is String) return OtpScreen(phone: extra);
          final arguments = extra as Map<String, dynamic>;
          return OtpScreen(
            phone: arguments['phone'] as String,
            organizationId: arguments['organizationId'] as String?,
            joinCode: arguments['joinCode'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (_, state) => RegisterScreen(
          organizationId: state.uri.queryParameters['organizationId'],
          joinCode: state.uri.queryParameters['joinCode'],
        ),
      ),
      GoRoute(
        path: '/organizations',
        name: 'organizationSelector',
        builder: (_, __) => const OrganizationSelectorScreen(),
      ),
      GoRoute(
        path: '/join-request',
        name: 'joinRequest',
        builder: (_, state) => JoinRequestScreen(
          organizationId: state.uri.queryParameters['organizationId'],
          joinCode: state.uri.queryParameters['joinCode'],
        ),
      ),
      GoRoute(
        path: '/join',
        name: 'qrJoinRequest',
        builder: (_, state) => JoinRequestScreen(
          organizationId: state.uri.queryParameters['organizationId'],
          joinCode: state.uri.queryParameters['joinCode'],
        ),
      ),
      GoRoute(
        path: '/member-home',
        name: 'memberHome',
        builder: (_, __) => const MemberHomeScreen(),
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/notifications/settings',
        name: 'notificationSettings',
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        name: 'profileEdit',
        builder: (_, __) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (_, __) => const MemberDashboard(),
      ),
      GoRoute(
        path: '/council',
        name: 'councilDashboard',
        builder: (_, __) => const CouncilDashboardScreen(),
      ),
      GoRoute(
        path: '/upload-receipt',
        name: 'uploadReceipt',
        builder: (_, state) {
          final args = state.extra as Map<String, dynamic>;
          return ReceiptUploadScreen(
            paymentId: args['paymentId'] as String?,
            periodLabel: args['periodLabel'] as String,
            organizationId: args['organizationId'] as String?,
            membershipId: args['membershipId'] as String?,
            userId: args['userId'] as String?,
            amountDeclared: (args['amountDeclared'] as num?)?.toDouble(),
          );
        },
      ),
      GoRoute(
        path: '/rentals',
        name: 'rentalPlaceholder',
        builder: (_, state) => CouncilBookingScreen(
          arguments: state.extra as CouncilBookingArguments?,
        ),
      ),
      GoRoute(
        path: '/receipts/history',
        name: 'receiptHistory',
        builder: (_, __) => const ReceiptHistoryScreen(),
      ),
      GoRoute(
        path: '/transaction/:id',
        name: 'transactionTimeline',
        builder: (_, state) => TransactionTimelineScreen(
          transactionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/admin',
        name: 'adminDashboard',
        builder: (_, __) => const AdminDashboard(),
      ),
      GoRoute(
        path: '/admin/organizations/create',
        name: 'createOrganization',
        builder: (_, state) => CreateOrganizationScreen(
          organization: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
        path: '/admin/organizations',
        name: 'organizationsManagement',
        builder: (_, __) => const OrganizationsManagementScreen(),
      ),
      GoRoute(
        path: '/admin/roles',
        name: 'rolesManagement',
        builder: (_, __) => const RolesManagementScreen(),
      ),
      GoRoute(
        path: '/admin/review/:id',
        name: 'adminReview',
        builder: (_, state) => AdminReviewScreen(
          transactionId: state.pathParameters['id']!,
          organizationId: state.uri.queryParameters['organizationId'],
        ),
      ),
      GoRoute(
        path: '/admin/financial-review',
        name: 'financialReview',
        builder: (_, __) => const FinancialReviewScreen(),
      ),
      GoRoute(
        path: '/admin/membership-requests',
        name: 'membershipRequestsReview',
        builder: (_, __) => const MembershipRequestsReviewScreen(),
      ),
      GoRoute(
        path: '/admin/booking-requests',
        name: 'bookingRequestsReview',
        builder: (_, __) => const BookingRequestsReviewScreen(),
      ),
      GoRoute(
        path: '/admin/members',
        name: 'memberManagement',
        builder: (_, __) => const MemberListScreen(),
      ),
      GoRoute(
        path: '/admin/audit',
        name: 'auditLogs',
        builder: (_, __) => const AuditLogsScreen(),
      ),
      GoRoute(
        path: '/admin/members/:userId',
        name: 'memberDetails',
        builder: (_, state) => MemberDetailsScreen(
          organizationId: state.uri.queryParameters['organizationId'] ?? '',
          userId: state.pathParameters['userId']!,
        ),
      ),
      GoRoute(
        path: '/admin/members/:userId/permissions',
        name: 'memberPermissions',
        builder: (_, state) => MemberPermissionsScreen(
          organizationId: state.uri.queryParameters['organizationId'] ?? '',
          userId: state.pathParameters['userId']!,
        ),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('الصفحة غير موجودة: ${state.error}')),
    ),
  );
});
