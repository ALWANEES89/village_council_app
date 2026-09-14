// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Village Council';

  @override
  String get councilDashboard => 'Council Dashboard';

  @override
  String get currentCouncil => 'Current council';

  @override
  String get switchCouncil => 'Switch council';

  @override
  String get chooseCouncil => 'Choose a council';

  @override
  String get noCouncilSelected => 'No council selected';

  @override
  String get returnHome => 'Return home';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get member => 'Member';

  @override
  String get memberNumber => 'Member number';

  @override
  String get role => 'Role';

  @override
  String get status => 'Status';

  @override
  String get active => 'Active';

  @override
  String get pending => 'Pending review';

  @override
  String get approved => 'Approved';

  @override
  String get suspended => 'Suspended';

  @override
  String get rejected => 'Rejected';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get removed => 'Removed';

  @override
  String get resigned => 'Resigned';

  @override
  String get platformAdministrator => 'Platform administrator';

  @override
  String get councilOwnerRole => 'Council Owner';

  @override
  String get chairmanRole => 'Chairman';

  @override
  String get administrativeManagerRole => 'Administrative Manager';

  @override
  String get financialManagerRole => 'Financial Manager';

  @override
  String get financialReviewerRole => 'Financial Reviewer';

  @override
  String get memberRole => 'Member';

  @override
  String get selectLanguage => 'Choose language';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String get language => 'Language';

  @override
  String get members => 'Members';

  @override
  String get upcomingBookings => 'Upcoming bookings';

  @override
  String get receiptsPendingReview => 'Receipts pending review';

  @override
  String get outstandingSubscriptions => 'Outstanding subscriptions';

  @override
  String get statisticsUnavailable => 'Unavailable';

  @override
  String get dailyOperations => 'Daily Operations';

  @override
  String get dailyOperationsDescription =>
      'Bookings, members, subscriptions and communication';

  @override
  String get finance => 'Finance';

  @override
  String get financeDescription =>
      'Council fees, receipts and financial follow-up';

  @override
  String get councilManagement => 'Council Management';

  @override
  String get councilManagementDescription =>
      'Council information, permissions and settings';

  @override
  String get bookings => 'Bookings';

  @override
  String get membersManagement => 'Members';

  @override
  String get subscriptions => 'Subscriptions';

  @override
  String get notifications => 'Notifications';

  @override
  String get feesAndSubscriptions => 'Fees & Subscriptions';

  @override
  String get receipts => 'Receipts';

  @override
  String get paymentReview => 'Payment Review';

  @override
  String get financialReports => 'Financial Reports';

  @override
  String get councilInformation => 'Council Information';

  @override
  String get permissions => 'Permissions';

  @override
  String get councilSettings => 'Council Settings';

  @override
  String get activityLog => 'Activity Log';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get newBooking => 'New Booking';

  @override
  String get uploadReceipt => 'Upload Receipt';

  @override
  String get reviewReceipt => 'Review Receipt';

  @override
  String get manageMembers => 'Manage Members';

  @override
  String get recentActivity => 'Recent Activity';

  @override
  String get importantAlerts => 'Important Alerts';

  @override
  String get noRecentActivity => 'No recent activity for this council';

  @override
  String get noImportantAlerts => 'Everything is up to date';

  @override
  String get viewAllNotifications => 'View all notifications';

  @override
  String get pendingReceiptsAlert => 'Receipts need review';

  @override
  String get pendingBookingsAlert => 'Booking requests need review';

  @override
  String get overdueSubscriptionsAlert => 'Subscriptions are overdue';

  @override
  String itemsCount(int count) {
    return '$count items';
  }

  @override
  String get loading => 'Loading…';

  @override
  String get retry => 'Retry';

  @override
  String get couldNotLoad => 'Could not load data';

  @override
  String get couldNotSwitchCouncil => 'Could not switch council';

  @override
  String get searchCouncils => 'Search councils';

  @override
  String get serviceComingSoon => 'This service will be available soon';

  @override
  String get noAdditionalInformation => 'No additional information';

  @override
  String get membershipStatus => 'Membership status';

  @override
  String get fullPlatformAccess => 'Full platform administrator access';

  @override
  String get generalPaymentReceipt => 'General payment receipt';

  @override
  String get openNavigation => 'Open navigation';

  @override
  String get home => 'Home';

  @override
  String get close => 'Close';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get localTestEnvironment => 'Local test environment';

  @override
  String get systemAdministration => 'System Administration';

  @override
  String get systemAdministrationDescription =>
      'Manage councils, users, and platform settings';

  @override
  String get systemAccessDenied =>
      'Only the system owner can access System Administration';

  @override
  String get totalCouncils => 'Total Councils';

  @override
  String get activeCouncils => 'Active Councils';

  @override
  String get pendingActions => 'Pending Actions';

  @override
  String get pendingJoinRequests => 'Pending join requests';

  @override
  String get createCouncil => 'Create Council';

  @override
  String get manageCouncils => 'Manage Councils';

  @override
  String get councilsInSystem => 'Councils in the System';

  @override
  String get councilsInSystemDescription =>
      'View and manage councils registered on the platform';

  @override
  String get noCouncils => 'No councils are registered';

  @override
  String get systemHome => 'System Home';

  @override
  String get systemAlerts => 'System Alerts';

  @override
  String get noSystemAlerts => 'No system alerts require action';

  @override
  String get pendingActionsAlert => 'Join requests across councils need review';

  @override
  String get archived => 'Archived';

  @override
  String get inactive => 'Inactive';

  @override
  String get createdOn => 'Created on';

  @override
  String get openCouncil => 'Open Council';

  @override
  String get manage => 'Manage';

  @override
  String get couldNotOpenCouncil => 'Could not open this council';

  @override
  String get backToSystemAdministration => 'Back to System Administration';

  @override
  String get systemOwner => 'System Owner';

  @override
  String get profile => 'Profile';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get mainHome => 'Home';

  @override
  String welcomeUser(String name) {
    return 'Welcome, $name';
  }

  @override
  String get myAccount => 'My Account';

  @override
  String get payments => 'Payments';

  @override
  String get services => 'Services';

  @override
  String get upcomingBooking => 'Your upcoming booking';

  @override
  String get noUpcomingBooking => 'You have no upcoming booking';

  @override
  String get bookNow => 'Book now';

  @override
  String get viewDetails => 'View details';

  @override
  String get outstandingAmount => 'Outstanding amount';

  @override
  String get latestNotification => 'Latest notification';

  @override
  String get noNotifications => 'No notifications yet';

  @override
  String get markAllAsRead => 'Mark all as read';

  @override
  String get signInToViewNotifications => 'Sign in to view notifications';

  @override
  String get couldNotLoadNotifications =>
      'Could not load notifications. Try again.';

  @override
  String get couldNotUpdateNotification =>
      'Could not update the notification. Please try again.';

  @override
  String get councilDashboardDescription =>
      'Manage council operations and finances';

  @override
  String get accountSection => 'Account';

  @override
  String get personalInformation => 'Personal Information';

  @override
  String get securityAndPassword => 'Security & Password';

  @override
  String get notificationSettings => 'Notification Settings';

  @override
  String get councilsAndMemberships => 'Councils & Memberships';

  @override
  String get myCouncils => 'My Councils';

  @override
  String get membershipsAndRoles => 'Memberships & Roles';

  @override
  String get membershipDetails => 'Membership Details';

  @override
  String get myPaymentsAndReceipts => 'My Payments & Receipts';

  @override
  String get mySubscriptions => 'My Subscriptions';

  @override
  String get help => 'Help';

  @override
  String get contactUs => 'Contact Us';

  @override
  String get legal => 'Legal';

  @override
  String get aboutApp => 'About the App';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get signOut => 'Sign Out';

  @override
  String get basicMember => 'Member';

  @override
  String get noActiveMembership => 'No active membership is available';

  @override
  String get chooseCouncilForService => 'Choose a council to continue';

  @override
  String get bookingDate => 'Booking date';

  @override
  String get occasion => 'Occasion';

  @override
  String get membershipRole => 'Membership role';

  @override
  String get notAvailableYet => 'Not available yet';

  @override
  String get joinCouncil => 'Join a Council';

  @override
  String get councilBookings => 'Council Bookings';

  @override
  String get accessDenied => 'You do not have permission to access this page';

  @override
  String get approvedUpcomingBookings => 'Upcoming Confirmed Bookings';

  @override
  String get noUpcomingBookings => 'No upcoming bookings';

  @override
  String bookingNumber(String number) {
    return 'Booking #$number';
  }

  @override
  String get bookingStatus => 'Booking status';

  @override
  String additionalRequests(int count) {
    return 'Additional requests: $count';
  }

  @override
  String get sendNotification => 'Send Notification';

  @override
  String get confirmSendNotification => 'Confirm notification';

  @override
  String get sendToAllCouncilMembers =>
      'This notification will be sent only to active members of the current council.';

  @override
  String get send => 'Send';

  @override
  String notificationSentTo(int count) {
    return 'Notification sent to $count members';
  }

  @override
  String get couldNotSendNotification => 'Could not send the notification';

  @override
  String get serviceUnavailable =>
      'The service is unavailable in the current server version';

  @override
  String get notificationTitle => 'Notification title';

  @override
  String get notificationBody => 'Notification message';

  @override
  String get requiredField => 'This field is required';

  @override
  String get expenses => 'Expenses';

  @override
  String get addExpense => 'Add Expense';

  @override
  String get noExpenses => 'No expenses recorded';

  @override
  String get couldNotSaveExpense => 'Could not save the expense';

  @override
  String get expenseDescription => 'Expense description';

  @override
  String get amountOmr => 'Amount in OMR';

  @override
  String get invalidPositiveAmount =>
      'Enter a valid positive amount with up to three decimal places';

  @override
  String get expenseCategory => 'Expense category';

  @override
  String get expenseDate => 'Expense date';

  @override
  String get supplier => 'Supplier (optional)';

  @override
  String get invoiceNumber => 'Invoice number (optional)';

  @override
  String get notes => 'Notes';

  @override
  String get save => 'Save';

  @override
  String get expenseBills => 'Bills';

  @override
  String get expenseElectricity => 'Electricity';

  @override
  String get expenseWater => 'Water';

  @override
  String get expenseCommunications => 'Communications';

  @override
  String get expenseSupplies => 'Supplies';

  @override
  String get expenseMaintenance => 'Maintenance';

  @override
  String get expenseCleaning => 'Cleaning';

  @override
  String get expenseEquipment => 'Equipment';

  @override
  String get expenseHospitality => 'Hospitality';

  @override
  String get expenseOther => 'Other';

  @override
  String get thisMonth => 'This Month';

  @override
  String get previousMonth => 'Previous Month';

  @override
  String get thisYear => 'This Year';

  @override
  String get customPeriod => 'Custom Period';

  @override
  String get totalCollected => 'Total Collected';

  @override
  String get totalOutstanding => 'Total Outstanding';

  @override
  String get bookingRevenue => 'Booking Revenue';

  @override
  String get packageRevenue => 'Packages & Add-ons';

  @override
  String get totalExpenses => 'Total Expenses';

  @override
  String get netPosition => 'Net Position';

  @override
  String get membersPaid => 'Members Paid';

  @override
  String get membersUnpaid => 'Members Unpaid';

  @override
  String get membershipRevenue => 'Membership Revenue';

  @override
  String get expenseBreakdown => 'Expense Breakdown';

  @override
  String get reviewedBy => 'Reviewed by';

  @override
  String get bookedDate => 'Booked Date';

  @override
  String get bookedDateRequestWarning =>
      'This date already has a confirmed booking. You may still submit a request, which will be reviewed by the council administration.';

  @override
  String get continueAction => 'Continue';

  @override
  String get booked => 'Booked';

  @override
  String get expenseAttachment => 'Invoice or receipt attachment';

  @override
  String get optionalPdfOrImage => 'Optional — image or PDF up to 10 MB';

  @override
  String get edit => 'Edit';

  @override
  String get confirm => 'Confirm';

  @override
  String get cancelExpense => 'Cancel Expense';

  @override
  String get cancelExpenseConfirmation =>
      'The expense will remain in the audit trail but will be excluded from totals. Continue?';

  @override
  String get cancel => 'Cancel';

  @override
  String get transactionDetails => 'Transaction Details';

  @override
  String get noCurrentCouncil => 'No council is currently selected.';

  @override
  String get couldNotLoadTransaction => 'Could not load the transaction.';

  @override
  String get transactionNotFound => 'Transaction not found.';

  @override
  String get couldNotOpenReceipt =>
      'Could not open the receipt. Check your access and the file.';

  @override
  String get secureReceiptServiceUnavailable =>
      'Secure receipt access is unavailable in the current server version.';

  @override
  String get rejectionReason => 'Rejection reason';

  @override
  String get receiptAllocation => 'Receipt Allocation';

  @override
  String get openingReceipt => 'Opening receipt...';

  @override
  String get viewReceiptFile => 'View Receipt File';

  @override
  String get transactionPath => 'Transaction Path';

  @override
  String get receiptSubmittedStep => 'Receipt submitted';

  @override
  String get receiptReviewStep => 'Amount and allocation review';

  @override
  String get receiptRejectedStep => 'Receipt rejected';

  @override
  String get receiptAllocationApprovedStep => 'Allocation approved';

  @override
  String get loginSubtitle => 'Council subscriptions and services';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get password => 'Password';

  @override
  String get enterPhoneNumber => 'Enter your phone number';

  @override
  String get phoneMustBeEightDigits => 'The phone number must contain 8 digits';

  @override
  String get enterPassword => 'Enter your password';

  @override
  String get login => 'Sign in';

  @override
  String get loginInstructions =>
      'Enter your phone number and password to continue';

  @override
  String get createNewAccount => 'Create a new account';

  @override
  String get accountDataNotFound =>
      'Account details could not be found. Contact council administration.';

  @override
  String get invalidLoginCredentials =>
      'The phone number or password is incorrect';

  @override
  String get findAndJoinCouncil => 'Find and Join a Council';

  @override
  String get findCouncilDescription =>
      'Search the available councils and send a membership request.';

  @override
  String get searchByCouncilName => 'Search by council name';

  @override
  String get noMatchingCouncils => 'No councils match your search';

  @override
  String get noCouncilsAvailableToJoin =>
      'No councils are available to join right now';

  @override
  String get requestToJoin => 'Request to Join';

  @override
  String get joinAnotherCouncil => 'Join Another Council';

  @override
  String get joinRequestSent => 'Your membership request was sent';

  @override
  String get joinRequestPending => 'Pending';

  @override
  String get joinRequestApproved => 'Approved';

  @override
  String get joinRequestRejected => 'Rejected';

  @override
  String get joinRequestAlreadyPending =>
      'A membership request for this council is already pending';

  @override
  String get activeMembershipAlreadyExists =>
      'You already have an active membership in this council';

  @override
  String get couldNotSendJoinRequest =>
      'Could not send the membership request. Try again.';

  @override
  String get alreadyJoined => 'Joined';

  @override
  String get couldNotLoadAccount => 'Could not load your account. Try again.';

  @override
  String get couldNotFindUser => 'User details could not be found';

  @override
  String get couldNotLoadProfile => 'Could not load your profile. Try again.';

  @override
  String get couldNotLoadCouncils => 'Could not load the available councils';

  @override
  String get couldNotLoadJoinRequests =>
      'Could not load your membership requests';

  @override
  String get optionalJoinReason => 'Reason for joining (optional)';

  @override
  String get applicantDetails => 'Applicant details';

  @override
  String get civilId => 'Civil ID';

  @override
  String get phone => 'Phone';

  @override
  String get email => 'Email';

  @override
  String get address => 'Address';

  @override
  String get council => 'Council';

  @override
  String get sendRequest => 'Send Request';

  @override
  String get invalidJoinCode => 'The invitation code is invalid or expired';

  @override
  String get notificationAuthRequired =>
      'Your sign-in session has ended. Sign in and try again.';

  @override
  String get notificationPermissionDenied =>
      'You do not have permission to send notifications for the current council.';

  @override
  String get notificationRateLimited =>
      'Too many attempts. Wait a moment and try again.';

  @override
  String get notificationNetworkError =>
      'The notification service could not be reached. Check your connection and try again.';

  @override
  String get notificationInvalidData =>
      'The notification details are invalid. Review them and try again.';

  @override
  String get notificationAlreadySent => 'This notification was already sent.';

  @override
  String get notificationSecurityVerificationFailed =>
      'The secure session could not be verified. Try again; if the issue continues, contact support.';

  @override
  String get receiptReviewTitle => 'Receipt Review';

  @override
  String get noReceiptReviewPermission =>
      'You do not have permission to review this council\'s receipts.';

  @override
  String get receiptsLoadRetry => 'Could not load receipts. Try again.';

  @override
  String get noPendingReceipts => 'There are no receipts pending review.';

  @override
  String get receiptApprovedAndAllocated =>
      'The receipt was approved and allocated to the charges.';

  @override
  String get receiptApprovalFailed =>
      'Approval failed. A charge balance may have changed.';

  @override
  String get receiptApprovalUnavailable =>
      'Receipt approval is unavailable in the current server version.';

  @override
  String get receiptRejectionReason => 'Receipt rejection reason';

  @override
  String get receiptRejectionReasonHint => 'Enter a clear required reason';

  @override
  String get rejectReceipt => 'Reject Receipt';

  @override
  String get receiptRejectedWithoutPayment =>
      'The receipt was rejected without applying a payment.';

  @override
  String get receiptRejectionFailed =>
      'Could not reject the receipt. Try again.';

  @override
  String get receiptReviewUnavailable =>
      'Receipt review is unavailable in the current server version.';

  @override
  String get receiptOpenFailed =>
      'Could not open the receipt. Check your permission and the file.';

  @override
  String get receiptOpenUnavailable =>
      'Secure receipt access is unavailable in the current server version.';

  @override
  String membershipNumberValue(String value) {
    return 'Membership number: $value';
  }

  @override
  String submittedAtValue(String value) {
    return 'Submitted: $value';
  }

  @override
  String get payerEnteredAmount => 'Amount entered by payer';

  @override
  String get allocationTotal => 'Allocation total:';

  @override
  String get amountDifference => 'Difference:';

  @override
  String get amountMatchesAllocation => 'Amount matches the allocation';

  @override
  String get incompleteReceiptApprovalDisabled =>
      'Receipt details are incomplete — approval disabled';

  @override
  String get differenceApprovalDisabled => 'Amounts differ — approval disabled';

  @override
  String paidBeneficiariesCount(int count) {
    return 'Beneficiaries paid for ($count)';
  }

  @override
  String get balanceAtSubmission => 'Balance at submission:';

  @override
  String get openPdfFile => 'Open PDF';

  @override
  String get viewReceiptImage => 'View receipt image';

  @override
  String get reject => 'Reject';

  @override
  String get approve => 'Approve';
}
