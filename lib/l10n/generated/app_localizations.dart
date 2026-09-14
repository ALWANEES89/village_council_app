import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Village Council'**
  String get appTitle;

  /// No description provided for @councilDashboard.
  ///
  /// In en, this message translates to:
  /// **'Council Dashboard'**
  String get councilDashboard;

  /// No description provided for @currentCouncil.
  ///
  /// In en, this message translates to:
  /// **'Current council'**
  String get currentCouncil;

  /// No description provided for @switchCouncil.
  ///
  /// In en, this message translates to:
  /// **'Switch council'**
  String get switchCouncil;

  /// No description provided for @chooseCouncil.
  ///
  /// In en, this message translates to:
  /// **'Choose a council'**
  String get chooseCouncil;

  /// No description provided for @noCouncilSelected.
  ///
  /// In en, this message translates to:
  /// **'No council selected'**
  String get noCouncilSelected;

  /// No description provided for @returnHome.
  ///
  /// In en, this message translates to:
  /// **'Return home'**
  String get returnHome;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @memberNumber.
  ///
  /// In en, this message translates to:
  /// **'Member number'**
  String get memberNumber;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get pending;

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @suspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspended;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @removed.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get removed;

  /// No description provided for @resigned.
  ///
  /// In en, this message translates to:
  /// **'Resigned'**
  String get resigned;

  /// No description provided for @platformAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Platform administrator'**
  String get platformAdministrator;

  /// No description provided for @councilOwnerRole.
  ///
  /// In en, this message translates to:
  /// **'Council Owner'**
  String get councilOwnerRole;

  /// No description provided for @chairmanRole.
  ///
  /// In en, this message translates to:
  /// **'Chairman'**
  String get chairmanRole;

  /// No description provided for @administrativeManagerRole.
  ///
  /// In en, this message translates to:
  /// **'Administrative Manager'**
  String get administrativeManagerRole;

  /// No description provided for @financialManagerRole.
  ///
  /// In en, this message translates to:
  /// **'Financial Manager'**
  String get financialManagerRole;

  /// No description provided for @financialReviewerRole.
  ///
  /// In en, this message translates to:
  /// **'Financial Reviewer'**
  String get financialReviewerRole;

  /// No description provided for @memberRole.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get memberRole;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get selectLanguage;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @upcomingBookings.
  ///
  /// In en, this message translates to:
  /// **'Upcoming bookings'**
  String get upcomingBookings;

  /// No description provided for @receiptsPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Receipts pending review'**
  String get receiptsPendingReview;

  /// No description provided for @outstandingSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Outstanding subscriptions'**
  String get outstandingSubscriptions;

  /// No description provided for @statisticsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get statisticsUnavailable;

  /// No description provided for @dailyOperations.
  ///
  /// In en, this message translates to:
  /// **'Daily Operations'**
  String get dailyOperations;

  /// No description provided for @dailyOperationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Bookings, members, subscriptions and communication'**
  String get dailyOperationsDescription;

  /// No description provided for @finance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get finance;

  /// No description provided for @financeDescription.
  ///
  /// In en, this message translates to:
  /// **'Council fees, receipts and financial follow-up'**
  String get financeDescription;

  /// No description provided for @councilManagement.
  ///
  /// In en, this message translates to:
  /// **'Council Management'**
  String get councilManagement;

  /// No description provided for @councilManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Council information, permissions and settings'**
  String get councilManagementDescription;

  /// No description provided for @bookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get bookings;

  /// No description provided for @membersManagement.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersManagement;

  /// No description provided for @subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @feesAndSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Fees & Subscriptions'**
  String get feesAndSubscriptions;

  /// No description provided for @receipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receipts;

  /// No description provided for @paymentReview.
  ///
  /// In en, this message translates to:
  /// **'Payment Review'**
  String get paymentReview;

  /// No description provided for @financialReports.
  ///
  /// In en, this message translates to:
  /// **'Financial Reports'**
  String get financialReports;

  /// No description provided for @councilInformation.
  ///
  /// In en, this message translates to:
  /// **'Council Information'**
  String get councilInformation;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @councilSettings.
  ///
  /// In en, this message translates to:
  /// **'Council Settings'**
  String get councilSettings;

  /// No description provided for @activityLog.
  ///
  /// In en, this message translates to:
  /// **'Activity Log'**
  String get activityLog;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @newBooking.
  ///
  /// In en, this message translates to:
  /// **'New Booking'**
  String get newBooking;

  /// No description provided for @uploadReceipt.
  ///
  /// In en, this message translates to:
  /// **'Upload Receipt'**
  String get uploadReceipt;

  /// No description provided for @reviewReceipt.
  ///
  /// In en, this message translates to:
  /// **'Review Receipt'**
  String get reviewReceipt;

  /// No description provided for @manageMembers.
  ///
  /// In en, this message translates to:
  /// **'Manage Members'**
  String get manageMembers;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @importantAlerts.
  ///
  /// In en, this message translates to:
  /// **'Important Alerts'**
  String get importantAlerts;

  /// No description provided for @noRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity for this council'**
  String get noRecentActivity;

  /// No description provided for @noImportantAlerts.
  ///
  /// In en, this message translates to:
  /// **'Everything is up to date'**
  String get noImportantAlerts;

  /// No description provided for @viewAllNotifications.
  ///
  /// In en, this message translates to:
  /// **'View all notifications'**
  String get viewAllNotifications;

  /// No description provided for @pendingReceiptsAlert.
  ///
  /// In en, this message translates to:
  /// **'Receipts need review'**
  String get pendingReceiptsAlert;

  /// No description provided for @pendingBookingsAlert.
  ///
  /// In en, this message translates to:
  /// **'Booking requests need review'**
  String get pendingBookingsAlert;

  /// No description provided for @overdueSubscriptionsAlert.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions are overdue'**
  String get overdueSubscriptionsAlert;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(int count);

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @couldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load data'**
  String get couldNotLoad;

  /// No description provided for @couldNotSwitchCouncil.
  ///
  /// In en, this message translates to:
  /// **'Could not switch council'**
  String get couldNotSwitchCouncil;

  /// No description provided for @searchCouncils.
  ///
  /// In en, this message translates to:
  /// **'Search councils'**
  String get searchCouncils;

  /// No description provided for @serviceComingSoon.
  ///
  /// In en, this message translates to:
  /// **'This service will be available soon'**
  String get serviceComingSoon;

  /// No description provided for @noAdditionalInformation.
  ///
  /// In en, this message translates to:
  /// **'No additional information'**
  String get noAdditionalInformation;

  /// No description provided for @membershipStatus.
  ///
  /// In en, this message translates to:
  /// **'Membership status'**
  String get membershipStatus;

  /// No description provided for @fullPlatformAccess.
  ///
  /// In en, this message translates to:
  /// **'Full platform administrator access'**
  String get fullPlatformAccess;

  /// No description provided for @generalPaymentReceipt.
  ///
  /// In en, this message translates to:
  /// **'General payment receipt'**
  String get generalPaymentReceipt;

  /// No description provided for @openNavigation.
  ///
  /// In en, this message translates to:
  /// **'Open navigation'**
  String get openNavigation;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @localTestEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Local test environment'**
  String get localTestEnvironment;

  /// No description provided for @systemAdministration.
  ///
  /// In en, this message translates to:
  /// **'System Administration'**
  String get systemAdministration;

  /// No description provided for @systemAdministrationDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage councils, users, and platform settings'**
  String get systemAdministrationDescription;

  /// No description provided for @systemAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Only the system owner can access System Administration'**
  String get systemAccessDenied;

  /// No description provided for @totalCouncils.
  ///
  /// In en, this message translates to:
  /// **'Total Councils'**
  String get totalCouncils;

  /// No description provided for @activeCouncils.
  ///
  /// In en, this message translates to:
  /// **'Active Councils'**
  String get activeCouncils;

  /// No description provided for @pendingActions.
  ///
  /// In en, this message translates to:
  /// **'Pending Actions'**
  String get pendingActions;

  /// No description provided for @pendingJoinRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending join requests'**
  String get pendingJoinRequests;

  /// No description provided for @createCouncil.
  ///
  /// In en, this message translates to:
  /// **'Create Council'**
  String get createCouncil;

  /// No description provided for @manageCouncils.
  ///
  /// In en, this message translates to:
  /// **'Manage Councils'**
  String get manageCouncils;

  /// No description provided for @councilsInSystem.
  ///
  /// In en, this message translates to:
  /// **'Councils in the System'**
  String get councilsInSystem;

  /// No description provided for @councilsInSystemDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage councils registered on the platform'**
  String get councilsInSystemDescription;

  /// No description provided for @noCouncils.
  ///
  /// In en, this message translates to:
  /// **'No councils are registered'**
  String get noCouncils;

  /// No description provided for @systemHome.
  ///
  /// In en, this message translates to:
  /// **'System Home'**
  String get systemHome;

  /// No description provided for @systemAlerts.
  ///
  /// In en, this message translates to:
  /// **'System Alerts'**
  String get systemAlerts;

  /// No description provided for @noSystemAlerts.
  ///
  /// In en, this message translates to:
  /// **'No system alerts require action'**
  String get noSystemAlerts;

  /// No description provided for @pendingActionsAlert.
  ///
  /// In en, this message translates to:
  /// **'Join requests across councils need review'**
  String get pendingActionsAlert;

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @createdOn.
  ///
  /// In en, this message translates to:
  /// **'Created on'**
  String get createdOn;

  /// No description provided for @openCouncil.
  ///
  /// In en, this message translates to:
  /// **'Open Council'**
  String get openCouncil;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @couldNotOpenCouncil.
  ///
  /// In en, this message translates to:
  /// **'Could not open this council'**
  String get couldNotOpenCouncil;

  /// No description provided for @backToSystemAdministration.
  ///
  /// In en, this message translates to:
  /// **'Back to System Administration'**
  String get backToSystemAdministration;

  /// No description provided for @systemOwner.
  ///
  /// In en, this message translates to:
  /// **'System Owner'**
  String get systemOwner;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @mainHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get mainHome;

  /// No description provided for @welcomeUser.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String welcomeUser(String name);

  /// No description provided for @myAccount.
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get myAccount;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @upcomingBooking.
  ///
  /// In en, this message translates to:
  /// **'Your upcoming booking'**
  String get upcomingBooking;

  /// No description provided for @noUpcomingBooking.
  ///
  /// In en, this message translates to:
  /// **'You have no upcoming booking'**
  String get noUpcomingBooking;

  /// No description provided for @bookNow.
  ///
  /// In en, this message translates to:
  /// **'Book now'**
  String get bookNow;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @outstandingAmount.
  ///
  /// In en, this message translates to:
  /// **'Outstanding amount'**
  String get outstandingAmount;

  /// No description provided for @latestNotification.
  ///
  /// In en, this message translates to:
  /// **'Latest notification'**
  String get latestNotification;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotifications;

  /// No description provided for @markAllAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllAsRead;

  /// No description provided for @signInToViewNotifications.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view notifications'**
  String get signInToViewNotifications;

  /// No description provided for @couldNotLoadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications. Try again.'**
  String get couldNotLoadNotifications;

  /// No description provided for @couldNotUpdateNotification.
  ///
  /// In en, this message translates to:
  /// **'Could not update the notification. Please try again.'**
  String get couldNotUpdateNotification;

  /// No description provided for @councilDashboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage council operations and finances'**
  String get councilDashboardDescription;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @personalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformation;

  /// No description provided for @securityAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Security & Password'**
  String get securityAndPassword;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// No description provided for @councilsAndMemberships.
  ///
  /// In en, this message translates to:
  /// **'Councils & Memberships'**
  String get councilsAndMemberships;

  /// No description provided for @myCouncils.
  ///
  /// In en, this message translates to:
  /// **'My Councils'**
  String get myCouncils;

  /// No description provided for @membershipsAndRoles.
  ///
  /// In en, this message translates to:
  /// **'Memberships & Roles'**
  String get membershipsAndRoles;

  /// No description provided for @membershipDetails.
  ///
  /// In en, this message translates to:
  /// **'Membership Details'**
  String get membershipDetails;

  /// No description provided for @myPaymentsAndReceipts.
  ///
  /// In en, this message translates to:
  /// **'My Payments & Receipts'**
  String get myPaymentsAndReceipts;

  /// No description provided for @mySubscriptions.
  ///
  /// In en, this message translates to:
  /// **'My Subscriptions'**
  String get mySubscriptions;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get contactUs;

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legal;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About the App'**
  String get aboutApp;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @basicMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get basicMember;

  /// No description provided for @noActiveMembership.
  ///
  /// In en, this message translates to:
  /// **'No active membership is available'**
  String get noActiveMembership;

  /// No description provided for @chooseCouncilForService.
  ///
  /// In en, this message translates to:
  /// **'Choose a council to continue'**
  String get chooseCouncilForService;

  /// No description provided for @bookingDate.
  ///
  /// In en, this message translates to:
  /// **'Booking date'**
  String get bookingDate;

  /// No description provided for @occasion.
  ///
  /// In en, this message translates to:
  /// **'Occasion'**
  String get occasion;

  /// No description provided for @membershipRole.
  ///
  /// In en, this message translates to:
  /// **'Membership role'**
  String get membershipRole;

  /// No description provided for @notAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get notAvailableYet;

  /// No description provided for @joinCouncil.
  ///
  /// In en, this message translates to:
  /// **'Join a Council'**
  String get joinCouncil;

  /// No description provided for @councilBookings.
  ///
  /// In en, this message translates to:
  /// **'Council Bookings'**
  String get councilBookings;

  /// No description provided for @accessDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to access this page'**
  String get accessDenied;

  /// No description provided for @approvedUpcomingBookings.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Confirmed Bookings'**
  String get approvedUpcomingBookings;

  /// No description provided for @noUpcomingBookings.
  ///
  /// In en, this message translates to:
  /// **'No upcoming bookings'**
  String get noUpcomingBookings;

  /// No description provided for @bookingNumber.
  ///
  /// In en, this message translates to:
  /// **'Booking #{number}'**
  String bookingNumber(String number);

  /// No description provided for @bookingStatus.
  ///
  /// In en, this message translates to:
  /// **'Booking status'**
  String get bookingStatus;

  /// No description provided for @additionalRequests.
  ///
  /// In en, this message translates to:
  /// **'Additional requests: {count}'**
  String additionalRequests(int count);

  /// No description provided for @sendNotification.
  ///
  /// In en, this message translates to:
  /// **'Send Notification'**
  String get sendNotification;

  /// No description provided for @confirmSendNotification.
  ///
  /// In en, this message translates to:
  /// **'Confirm notification'**
  String get confirmSendNotification;

  /// No description provided for @sendToAllCouncilMembers.
  ///
  /// In en, this message translates to:
  /// **'This notification will be sent only to active members of the current council.'**
  String get sendToAllCouncilMembers;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @notificationSentTo.
  ///
  /// In en, this message translates to:
  /// **'Notification sent to {count} members'**
  String notificationSentTo(int count);

  /// No description provided for @couldNotSendNotification.
  ///
  /// In en, this message translates to:
  /// **'Could not send the notification'**
  String get couldNotSendNotification;

  /// No description provided for @serviceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The service is unavailable in the current server version'**
  String get serviceUnavailable;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification title'**
  String get notificationTitle;

  /// No description provided for @notificationBody.
  ///
  /// In en, this message translates to:
  /// **'Notification message'**
  String get notificationBody;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get requiredField;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add Expense'**
  String get addExpense;

  /// No description provided for @noExpenses.
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded'**
  String get noExpenses;

  /// No description provided for @couldNotSaveExpense.
  ///
  /// In en, this message translates to:
  /// **'Could not save the expense'**
  String get couldNotSaveExpense;

  /// No description provided for @expenseDescription.
  ///
  /// In en, this message translates to:
  /// **'Expense description'**
  String get expenseDescription;

  /// No description provided for @amountOmr.
  ///
  /// In en, this message translates to:
  /// **'Amount in OMR'**
  String get amountOmr;

  /// No description provided for @invalidPositiveAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid positive amount with up to three decimal places'**
  String get invalidPositiveAmount;

  /// No description provided for @expenseCategory.
  ///
  /// In en, this message translates to:
  /// **'Expense category'**
  String get expenseCategory;

  /// No description provided for @expenseDate.
  ///
  /// In en, this message translates to:
  /// **'Expense date'**
  String get expenseDate;

  /// No description provided for @supplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier (optional)'**
  String get supplier;

  /// No description provided for @invoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice number (optional)'**
  String get invoiceNumber;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @expenseBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get expenseBills;

  /// No description provided for @expenseElectricity.
  ///
  /// In en, this message translates to:
  /// **'Electricity'**
  String get expenseElectricity;

  /// No description provided for @expenseWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get expenseWater;

  /// No description provided for @expenseCommunications.
  ///
  /// In en, this message translates to:
  /// **'Communications'**
  String get expenseCommunications;

  /// No description provided for @expenseSupplies.
  ///
  /// In en, this message translates to:
  /// **'Supplies'**
  String get expenseSupplies;

  /// No description provided for @expenseMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get expenseMaintenance;

  /// No description provided for @expenseCleaning.
  ///
  /// In en, this message translates to:
  /// **'Cleaning'**
  String get expenseCleaning;

  /// No description provided for @expenseEquipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get expenseEquipment;

  /// No description provided for @expenseHospitality.
  ///
  /// In en, this message translates to:
  /// **'Hospitality'**
  String get expenseHospitality;

  /// No description provided for @expenseOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get expenseOther;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous Month'**
  String get previousMonth;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get thisYear;

  /// No description provided for @customPeriod.
  ///
  /// In en, this message translates to:
  /// **'Custom Period'**
  String get customPeriod;

  /// No description provided for @totalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total Collected'**
  String get totalCollected;

  /// No description provided for @totalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total Outstanding'**
  String get totalOutstanding;

  /// No description provided for @bookingRevenue.
  ///
  /// In en, this message translates to:
  /// **'Booking Revenue'**
  String get bookingRevenue;

  /// No description provided for @packageRevenue.
  ///
  /// In en, this message translates to:
  /// **'Packages & Add-ons'**
  String get packageRevenue;

  /// No description provided for @totalExpenses.
  ///
  /// In en, this message translates to:
  /// **'Total Expenses'**
  String get totalExpenses;

  /// No description provided for @netPosition.
  ///
  /// In en, this message translates to:
  /// **'Net Position'**
  String get netPosition;

  /// No description provided for @membersPaid.
  ///
  /// In en, this message translates to:
  /// **'Members Paid'**
  String get membersPaid;

  /// No description provided for @membersUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Members Unpaid'**
  String get membersUnpaid;

  /// No description provided for @membershipRevenue.
  ///
  /// In en, this message translates to:
  /// **'Membership Revenue'**
  String get membershipRevenue;

  /// No description provided for @expenseBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Expense Breakdown'**
  String get expenseBreakdown;

  /// No description provided for @reviewedBy.
  ///
  /// In en, this message translates to:
  /// **'Reviewed by'**
  String get reviewedBy;

  /// No description provided for @bookedDate.
  ///
  /// In en, this message translates to:
  /// **'Booked Date'**
  String get bookedDate;

  /// No description provided for @bookedDateRequestWarning.
  ///
  /// In en, this message translates to:
  /// **'This date already has a confirmed booking. You may still submit a request, which will be reviewed by the council administration.'**
  String get bookedDateRequestWarning;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @booked.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get booked;

  /// No description provided for @expenseAttachment.
  ///
  /// In en, this message translates to:
  /// **'Invoice or receipt attachment'**
  String get expenseAttachment;

  /// No description provided for @optionalPdfOrImage.
  ///
  /// In en, this message translates to:
  /// **'Optional — image or PDF up to 10 MB'**
  String get optionalPdfOrImage;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @cancelExpense.
  ///
  /// In en, this message translates to:
  /// **'Cancel Expense'**
  String get cancelExpense;

  /// No description provided for @cancelExpenseConfirmation.
  ///
  /// In en, this message translates to:
  /// **'The expense will remain in the audit trail but will be excluded from totals. Continue?'**
  String get cancelExpenseConfirmation;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @transactionDetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get transactionDetails;

  /// No description provided for @noCurrentCouncil.
  ///
  /// In en, this message translates to:
  /// **'No council is currently selected.'**
  String get noCurrentCouncil;

  /// No description provided for @couldNotLoadTransaction.
  ///
  /// In en, this message translates to:
  /// **'Could not load the transaction.'**
  String get couldNotLoadTransaction;

  /// No description provided for @transactionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Transaction not found.'**
  String get transactionNotFound;

  /// No description provided for @couldNotOpenReceipt.
  ///
  /// In en, this message translates to:
  /// **'Could not open the receipt. Check your access and the file.'**
  String get couldNotOpenReceipt;

  /// No description provided for @secureReceiptServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Secure receipt access is unavailable in the current server version.'**
  String get secureReceiptServiceUnavailable;

  /// No description provided for @rejectionReason.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason'**
  String get rejectionReason;

  /// No description provided for @receiptAllocation.
  ///
  /// In en, this message translates to:
  /// **'Receipt Allocation'**
  String get receiptAllocation;

  /// No description provided for @openingReceipt.
  ///
  /// In en, this message translates to:
  /// **'Opening receipt...'**
  String get openingReceipt;

  /// No description provided for @viewReceiptFile.
  ///
  /// In en, this message translates to:
  /// **'View Receipt File'**
  String get viewReceiptFile;

  /// No description provided for @transactionPath.
  ///
  /// In en, this message translates to:
  /// **'Transaction Path'**
  String get transactionPath;

  /// No description provided for @receiptSubmittedStep.
  ///
  /// In en, this message translates to:
  /// **'Receipt submitted'**
  String get receiptSubmittedStep;

  /// No description provided for @receiptReviewStep.
  ///
  /// In en, this message translates to:
  /// **'Amount and allocation review'**
  String get receiptReviewStep;

  /// No description provided for @receiptRejectedStep.
  ///
  /// In en, this message translates to:
  /// **'Receipt rejected'**
  String get receiptRejectedStep;

  /// No description provided for @receiptAllocationApprovedStep.
  ///
  /// In en, this message translates to:
  /// **'Allocation approved'**
  String get receiptAllocationApprovedStep;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Council subscriptions and services'**
  String get loginSubtitle;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get enterPhoneNumber;

  /// No description provided for @phoneMustBeEightDigits.
  ///
  /// In en, this message translates to:
  /// **'The phone number must contain 8 digits'**
  String get phoneMustBeEightDigits;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterPassword;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get login;

  /// No description provided for @loginInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number and password to continue'**
  String get loginInstructions;

  /// No description provided for @createNewAccount.
  ///
  /// In en, this message translates to:
  /// **'Create a new account'**
  String get createNewAccount;

  /// No description provided for @accountDataNotFound.
  ///
  /// In en, this message translates to:
  /// **'Account details could not be found. Contact council administration.'**
  String get accountDataNotFound;

  /// No description provided for @invalidLoginCredentials.
  ///
  /// In en, this message translates to:
  /// **'The phone number or password is incorrect'**
  String get invalidLoginCredentials;

  /// No description provided for @findAndJoinCouncil.
  ///
  /// In en, this message translates to:
  /// **'Find and Join a Council'**
  String get findAndJoinCouncil;

  /// No description provided for @findCouncilDescription.
  ///
  /// In en, this message translates to:
  /// **'Search the available councils and send a membership request.'**
  String get findCouncilDescription;

  /// No description provided for @searchByCouncilName.
  ///
  /// In en, this message translates to:
  /// **'Search by council name'**
  String get searchByCouncilName;

  /// No description provided for @noMatchingCouncils.
  ///
  /// In en, this message translates to:
  /// **'No councils match your search'**
  String get noMatchingCouncils;

  /// No description provided for @noCouncilsAvailableToJoin.
  ///
  /// In en, this message translates to:
  /// **'No councils are available to join right now'**
  String get noCouncilsAvailableToJoin;

  /// No description provided for @requestToJoin.
  ///
  /// In en, this message translates to:
  /// **'Request to Join'**
  String get requestToJoin;

  /// No description provided for @joinAnotherCouncil.
  ///
  /// In en, this message translates to:
  /// **'Join Another Council'**
  String get joinAnotherCouncil;

  /// No description provided for @joinRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Your membership request was sent'**
  String get joinRequestSent;

  /// No description provided for @joinRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get joinRequestPending;

  /// No description provided for @joinRequestApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get joinRequestApproved;

  /// No description provided for @joinRequestRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get joinRequestRejected;

  /// No description provided for @joinRequestAlreadyPending.
  ///
  /// In en, this message translates to:
  /// **'A membership request for this council is already pending'**
  String get joinRequestAlreadyPending;

  /// No description provided for @activeMembershipAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'You already have an active membership in this council'**
  String get activeMembershipAlreadyExists;

  /// No description provided for @couldNotSendJoinRequest.
  ///
  /// In en, this message translates to:
  /// **'Could not send the membership request. Try again.'**
  String get couldNotSendJoinRequest;

  /// No description provided for @alreadyJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get alreadyJoined;

  /// No description provided for @couldNotLoadAccount.
  ///
  /// In en, this message translates to:
  /// **'Could not load your account. Try again.'**
  String get couldNotLoadAccount;

  /// No description provided for @couldNotFindUser.
  ///
  /// In en, this message translates to:
  /// **'User details could not be found'**
  String get couldNotFindUser;

  /// No description provided for @couldNotLoadProfile.
  ///
  /// In en, this message translates to:
  /// **'Could not load your profile. Try again.'**
  String get couldNotLoadProfile;

  /// No description provided for @couldNotLoadCouncils.
  ///
  /// In en, this message translates to:
  /// **'Could not load the available councils'**
  String get couldNotLoadCouncils;

  /// No description provided for @couldNotLoadJoinRequests.
  ///
  /// In en, this message translates to:
  /// **'Could not load your membership requests'**
  String get couldNotLoadJoinRequests;

  /// No description provided for @optionalJoinReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for joining (optional)'**
  String get optionalJoinReason;

  /// No description provided for @applicantDetails.
  ///
  /// In en, this message translates to:
  /// **'Applicant details'**
  String get applicantDetails;

  /// No description provided for @civilId.
  ///
  /// In en, this message translates to:
  /// **'Civil ID'**
  String get civilId;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @council.
  ///
  /// In en, this message translates to:
  /// **'Council'**
  String get council;

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send Request'**
  String get sendRequest;

  /// No description provided for @invalidJoinCode.
  ///
  /// In en, this message translates to:
  /// **'The invitation code is invalid or expired'**
  String get invalidJoinCode;

  /// No description provided for @notificationAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in session has ended. Sign in and try again.'**
  String get notificationAuthRequired;

  /// No description provided for @notificationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to send notifications for the current council.'**
  String get notificationPermissionDenied;

  /// No description provided for @notificationRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a moment and try again.'**
  String get notificationRateLimited;

  /// No description provided for @notificationNetworkError.
  ///
  /// In en, this message translates to:
  /// **'The notification service could not be reached. Check your connection and try again.'**
  String get notificationNetworkError;

  /// No description provided for @notificationInvalidData.
  ///
  /// In en, this message translates to:
  /// **'The notification details are invalid. Review them and try again.'**
  String get notificationInvalidData;

  /// No description provided for @notificationAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'This notification was already sent.'**
  String get notificationAlreadySent;

  /// No description provided for @notificationSecurityVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'The secure session could not be verified. Try again; if the issue continues, contact support.'**
  String get notificationSecurityVerificationFailed;

  /// No description provided for @receiptReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt Review'**
  String get receiptReviewTitle;

  /// No description provided for @noReceiptReviewPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to review this council\'s receipts.'**
  String get noReceiptReviewPermission;

  /// No description provided for @receiptsLoadRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load receipts. Try again.'**
  String get receiptsLoadRetry;

  /// No description provided for @noPendingReceipts.
  ///
  /// In en, this message translates to:
  /// **'There are no receipts pending review.'**
  String get noPendingReceipts;

  /// No description provided for @receiptApprovedAndAllocated.
  ///
  /// In en, this message translates to:
  /// **'The receipt was approved and allocated to the charges.'**
  String get receiptApprovedAndAllocated;

  /// No description provided for @receiptApprovalFailed.
  ///
  /// In en, this message translates to:
  /// **'Approval failed. A charge balance may have changed.'**
  String get receiptApprovalFailed;

  /// No description provided for @receiptApprovalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Receipt approval is unavailable in the current server version.'**
  String get receiptApprovalUnavailable;

  /// No description provided for @receiptRejectionReason.
  ///
  /// In en, this message translates to:
  /// **'Receipt rejection reason'**
  String get receiptRejectionReason;

  /// No description provided for @receiptRejectionReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a clear required reason'**
  String get receiptRejectionReasonHint;

  /// No description provided for @rejectReceipt.
  ///
  /// In en, this message translates to:
  /// **'Reject Receipt'**
  String get rejectReceipt;

  /// No description provided for @receiptRejectedWithoutPayment.
  ///
  /// In en, this message translates to:
  /// **'The receipt was rejected without applying a payment.'**
  String get receiptRejectedWithoutPayment;

  /// No description provided for @receiptRejectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reject the receipt. Try again.'**
  String get receiptRejectionFailed;

  /// No description provided for @receiptReviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Receipt review is unavailable in the current server version.'**
  String get receiptReviewUnavailable;

  /// No description provided for @receiptOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the receipt. Check your permission and the file.'**
  String get receiptOpenFailed;

  /// No description provided for @receiptOpenUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Secure receipt access is unavailable in the current server version.'**
  String get receiptOpenUnavailable;

  /// No description provided for @membershipNumberValue.
  ///
  /// In en, this message translates to:
  /// **'Membership number: {value}'**
  String membershipNumberValue(String value);

  /// No description provided for @submittedAtValue.
  ///
  /// In en, this message translates to:
  /// **'Submitted: {value}'**
  String submittedAtValue(String value);

  /// No description provided for @payerEnteredAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount entered by payer'**
  String get payerEnteredAmount;

  /// No description provided for @allocationTotal.
  ///
  /// In en, this message translates to:
  /// **'Allocation total:'**
  String get allocationTotal;

  /// No description provided for @amountDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference:'**
  String get amountDifference;

  /// No description provided for @amountMatchesAllocation.
  ///
  /// In en, this message translates to:
  /// **'Amount matches the allocation'**
  String get amountMatchesAllocation;

  /// No description provided for @incompleteReceiptApprovalDisabled.
  ///
  /// In en, this message translates to:
  /// **'Receipt details are incomplete — approval disabled'**
  String get incompleteReceiptApprovalDisabled;

  /// No description provided for @differenceApprovalDisabled.
  ///
  /// In en, this message translates to:
  /// **'Amounts differ — approval disabled'**
  String get differenceApprovalDisabled;

  /// No description provided for @paidBeneficiariesCount.
  ///
  /// In en, this message translates to:
  /// **'Beneficiaries paid for ({count})'**
  String paidBeneficiariesCount(int count);

  /// No description provided for @balanceAtSubmission.
  ///
  /// In en, this message translates to:
  /// **'Balance at submission:'**
  String get balanceAtSubmission;

  /// No description provided for @openPdfFile.
  ///
  /// In en, this message translates to:
  /// **'Open PDF'**
  String get openPdfFile;

  /// No description provided for @viewReceiptImage.
  ///
  /// In en, this message translates to:
  /// **'View receipt image'**
  String get viewReceiptImage;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
