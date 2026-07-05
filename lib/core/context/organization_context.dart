import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/role_labels.dart';
import '../../data/models/membership_model.dart';
import '../../data/repositories/membership_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../../data/repositories/role_repository.dart';

class OrganizationContext {
  final Map<String, dynamic>? currentOrganization;
  final MembershipModel? currentMembership;
  final Map<String, dynamic>? currentRole;
  final List<String> permissions;
  final bool isPlatformAdmin;

  const OrganizationContext({
    this.currentOrganization,
    this.currentMembership,
    this.currentRole,
    this.permissions = const [],
    this.isPlatformAdmin = false,
  });

  static const empty = OrganizationContext();

  bool get hasOrganization =>
      currentOrganization != null &&
      (currentMembership != null || isPlatformAdmin);

  bool hasPermission(String permission) => permissions.contains(permission);
}

class OrganizationContextNotifier extends StateNotifier<OrganizationContext> {
  OrganizationContextNotifier({
    required OrganizationRepository organizationRepository,
    required MembershipRepository membershipRepository,
    required RoleRepository roleRepository,
  })  : _organizationRepository = organizationRepository,
        _membershipRepository = membershipRepository,
        _roleRepository = roleRepository,
        super(OrganizationContext.empty);

  final OrganizationRepository _organizationRepository;
  final MembershipRepository _membershipRepository;
  final RoleRepository _roleRepository;

  int _selectionVersion = 0;

  Map<String, dynamic>? get currentOrganization => state.currentOrganization;
  MembershipModel? get currentMembership => state.currentMembership;
  Map<String, dynamic>? get currentRole => state.currentRole;
  List<String> get permissions => state.permissions;

  Future<void> selectOrganization({
    required String organizationId,
    required String userId,
    String? membershipId,
  }) async {
    final selectionVersion = ++_selectionVersion;

    final organization = await _organizationRepository.getById(organizationId);
    if (selectionVersion != _selectionVersion) return;
    if (organization == null) {
      throw StateError('Organization $organizationId does not exist.');
    }

    final membership = await _membershipRepository.getById(
      organizationId: organizationId,
      membershipId: membershipId ?? userId,
    );
    if (selectionVersion != _selectionVersion) return;
    if (membership == null || membership.userId != userId) {
      throw StateError(
        'User $userId does not have a membership in $organizationId.',
      );
    }
    if (membership.organizationId != organizationId) {
      throw StateError('Membership organization does not match the selection.');
    }
    if (membership.status != MembershipStatus.active) {
      throw StateError('Only an active membership can select an organization.');
    }

    final role = await _roleRepository.getById(
      organizationId: organizationId,
      roleId: membership.roleId,
    );
    if (selectionVersion != _selectionVersion) return;
    // لا نفشل عند غياب مستند الدور (مثل roleId=system_owner للمالك الأعلى الذي
    // لا يملك مستند دور مبذور). نبني دورًا اصطناعيًا بالاسم العربي، والصلاحيات
    // تأتي من permissionsSnapshot (fullAccess للمالك) — حتى يفتح المالك مجلسه.
    final resolvedRole = role ??
        <String, dynamic>{
          'roleId': membership.roleId,
          'roleName': {
            'ar': roleLabelArabic(membership.roleId, role: membership.role),
          },
        };

    final permissions = membership.permissionsSnapshot.toSet().toList()..sort();

    debugPrint('[Council] open organizationId=$organizationId '
        'role=${membership.role} roleId=${membership.roleId} '
        'status=${membership.status.name} isPrimaryOwner=${membership.isPrimaryOwner} '
        'roleDocFound=${role != null} permissions=$permissions');

    state = OrganizationContext(
      currentOrganization: UnmodifiableMapView(organization),
      currentMembership: membership,
      currentRole: UnmodifiableMapView(resolvedRole),
      permissions: List.unmodifiable(permissions),
    );
  }

  Future<void> selectOrganizationAsSuperAdmin(String organizationId) async {
    final selectionVersion = ++_selectionVersion;
    final organization = await _organizationRepository.getById(organizationId);
    if (selectionVersion != _selectionVersion) return;
    if (organization == null) {
      throw StateError('Organization $organizationId does not exist.');
    }
    state = OrganizationContext(
      currentOrganization: UnmodifiableMapView(organization),
      currentRole: UnmodifiableMapView(const {
        'roleId': 'superAdmin',
        'roleName': {'ar': 'مشرف المنصة', 'en': 'Super Admin'},
      }),
      permissions: const ['fullAccess'],
      isPlatformAdmin: true,
    );
  }

  void clearOrganization() {
    _selectionVersion++;
    state = OrganizationContext.empty;
  }

  bool hasPermission(String permission) => state.hasPermission(permission);
}
