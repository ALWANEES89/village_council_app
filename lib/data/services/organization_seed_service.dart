import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/organization_model.dart';

class OrganizationSeedService {
  OrganizationSeedService._({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static final instance = OrganizationSeedService._();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  StreamSubscription<User?>? _authSubscription;
  Future<void>? _pendingSeed;

  void start() {
    _authSubscription ??= _auth.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(ensureSeeded().catchError((_) {}));
      }
    });
    if (_auth.currentUser != null) {
      unawaited(ensureSeeded().catchError((_) {}));
    }
  }

  Future<void> ensureSeeded() {
    final running = _pendingSeed;
    if (running != null) return running;
    final operation = _ensureSeeded();
    _pendingSeed = operation;
    return operation.whenComplete(() => _pendingSeed = null);
  }

  Future<void> _ensureSeeded() async {
    final actorUid = _auth.currentUser?.uid;
    if (actorUid == null) return;

    const organization = OrganizationModel.production;
    final organizationReference =
        _firestore.collection('organizations').doc(organization.organizationId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(organizationReference);
      if (existing.exists) return;

      // توثيق منشئ البذرة الأولى (أول أدمن مسجّل) حتى تُنسب أحداث الإنشاء في
      // سجل الأحداث الخادمي إلى فاعل بدل unknown.
      transaction.set(organizationReference, {
        ...organization.toFirestore(),
        'createdBy': actorUid,
      });
      transaction.set(
        organizationReference.collection('financial_profile').doc('banking'),
        {...bankingDefaults(), 'updatedBy': actorUid},
      );
      transaction.set(
        organizationReference.collection('settings').doc('organization'),
        {...organizationSettingsDefaults(), 'updatedBy': actorUid},
      );
      transaction.set(
        organizationReference.collection('settings').doc('location_maps'),
        {...locationDefaults(), 'updatedBy': actorUid},
      );

      for (final entry in defaultRoles.entries) {
        transaction.set(
          organizationReference.collection('roles').doc(entry.key),
          {...entry.value, 'createdBy': actorUid, 'updatedBy': actorUid},
        );
      }
    });

    await _bootstrapChairman(organizationReference);
  }

  Future<void> _bootstrapChairman(
    DocumentReference<Map<String, dynamic>> organizationReference,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final currentLegacyMember =
        await _firestore.collection('members').doc(currentUser.uid).get();
    if (currentLegacyMember.data()?['isAdmin'] != true) return;

    final memberships = organizationReference.collection('memberships');
    final existingChairman =
        await memberships.where('roleId', isEqualTo: 'chairman').limit(1).get();
    if (existingChairman.docs.isNotEmpty) return;

    final legacyAdmins = await _firestore
        .collection('members')
        .where('isAdmin', isEqualTo: true)
        .limit(1)
        .get();
    final chairmanUserId = legacyAdmins.docs.isEmpty
        ? currentUser.uid
        : legacyAdmins.docs.first.id;
    final membershipReference = memberships.doc(chairmanUserId);

    await _firestore.runTransaction((transaction) async {
      final membership = await transaction.get(membershipReference);
      if (membership.exists) return;
      final now = FieldValue.serverTimestamp();
      transaction.set(membershipReference, {
        'userId': chairmanUserId,
        'organizationId': OrganizationModel.productionOrganizationId,
        'memberNumber': '001',
        'roleId': 'chairman',
        'status': 'active',
        'joinedAt': now,
        'approvedBy': currentUser.uid,
        'approvedAt': now,
        'isPrimary': true,
        'permissionsSnapshot': ['fullAccess'],
        'joinedReason': 'organizationBootstrap',
        'invitedBy': currentUser.uid,
        'leftReason': null,
      });
    });
  }

  Map<String, dynamic> bankingDefaults() => {
        'bankName': '',
        'accountName': '',
        'accountNumber': '',
        'iban': '',
        'swiftCode': '',
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> organizationSettingsDefaults() => {
        'locale': 'ar',
        'timezone': 'Asia/Muscat',
        'currency': 'OMR',
        'countryCode': 'OM',
        'navigationEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> locationDefaults() => {
        'latitude': null,
        'longitude': null,
        'googleMapsUrl': '',
        'appleMapsUrl': '',
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, Map<String, dynamic>> get defaultRoles => {
        'chairman': _role(
          'chairman',
          'رئيس المجلس',
          'Chairman',
          const ['fullAccess'],
          color: '#D4A017',
          icon: 'workspace_premium',
          priority: 100,
        ),
        'adminManager': _role(
          'adminManager',
          'مدير إداري',
          'Administrative Manager',
          const [
            'members.manage',
            'members.read',
            'members.approve',
            'membershipRequests.review',
            'organization.manage',
            'settings.manage',
            'bookings.read',
            'bookings.approve',
            'bookings.reject',
            'bookings.manage',
          ],
          color: '#6A1BFF',
          icon: 'admin_panel_settings',
          priority: 80,
        ),
        'financialManager': _role(
          'financialManager',
          'المدير المالي',
          'Financial Manager',
          const [
            'payments.manage',
            'transactions.review',
            'reports.view',
            'receipts.review',
            'payments.approve',
            'payments.reject',
            'payments.read',
          ],
          color: '#148A45',
          icon: 'account_balance_wallet',
          priority: 70,
        ),
        'financialReviewer': _role(
          'financialReviewer',
          'المراجع المالي',
          'Financial Reviewer',
          const [
            'transactions.review',
            'reports.view',
            'receipts.review',
            'payments.approve',
            'payments.reject',
            'payments.read',
          ],
          color: '#2878B5',
          icon: 'fact_check',
          priority: 60,
        ),
        'secretary': _role(
          'secretary',
          'أمين السر',
          'Secretary',
          const [
            'membershipRequests.review',
            'announcements.manage',
            'notifications.send',
            'audit.read',
          ],
          color: '#A45A12',
          icon: 'edit_note',
          priority: 50,
        ),
        'member': _role(
          'member',
          'عضو',
          'Member',
          const [
            'profile.read',
            'payments.read',
            'rentals.create',
            'bookings.read',
            'bookings.create',
          ],
          color: '#707070',
          icon: 'person',
          priority: 10,
        ),
      };

  Map<String, dynamic> _role(
    String roleId,
    String arabicName,
    String englishName,
    List<String> permissions, {
    required String color,
    required String icon,
    required int priority,
  }) {
    return {
      'roleId': roleId,
      'arabicName': arabicName,
      'englishName': englishName,
      'roleName': {'ar': arabicName, 'en': englishName},
      'description': {
        'ar': 'دور نظامي: $arabicName',
        'en': 'System role: $englishName',
      },
      'permissions': permissions,
      'systemRole': true,
      'isSystemRole': true,
      'color': color,
      'icon': icon,
      'priority': priority,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
