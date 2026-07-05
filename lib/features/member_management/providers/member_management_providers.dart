import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/membership_model.dart';
import '../../../providers/app_providers.dart';
import '../data/member_management_models.dart';
import '../data/member_management_repository.dart';

final memberManagementRepositoryProvider =
    Provider((ref) => MemberManagementRepository());

class MemberListState {
  final List<ManagedMember> members;
  final MemberListFilter filter;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;

  const MemberListState({
    this.members = const [],
    this.filter = const MemberListFilter(),
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.cursor,
  });

  MemberListState copyWith({
    List<ManagedMember>? members,
    MemberListFilter? filter,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    bool clearCursor = false,
  }) {
    return MemberListState(
      members: members ?? this.members,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
      cursor: clearCursor ? null : cursor ?? this.cursor,
    );
  }
}

class MemberListController extends StateNotifier<MemberListState> {
  MemberListController(this._repository, this._organizationId)
      : super(const MemberListState()) {
    load();
  }

  final MemberManagementRepository _repository;
  final String _organizationId;
  int _requestVersion = 0;

  Future<void> load() async {
    final version = ++_requestVersion;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearCursor: true,
    );
    try {
      final page = await _repository.getPage(
        organizationId: _organizationId,
        filter: state.filter,
      );
      if (version != _requestVersion) return;
      state = state.copyWith(
        members: page.members,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoading: false,
      );
    } catch (error) {
      if (version != _requestVersion) return;
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _repository.getPage(
        organizationId: _organizationId,
        filter: state.filter,
        startAfter: state.cursor,
      );
      final existingIds = state.members.map((member) => member.userId).toSet();
      state = state.copyWith(
        members: [
          ...state.members,
          ...page.members.where((member) => existingIds.add(member.userId)),
        ],
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingMore: false,
        error: error.toString(),
      );
    }
  }

  void setSearch(String search) {
    state = state.copyWith(filter: state.filter.copyWith(search: search));
    load();
  }

  void setStatus(MembershipStatus? status) {
    state = state.copyWith(
      filter: state.filter.copyWith(
        status: status,
        clearStatus: status == null,
      ),
    );
    load();
  }

  void setRole(String? roleId) {
    state = state.copyWith(
      filter: state.filter.copyWith(
        roleId: roleId,
        clearRole: roleId == null,
      ),
    );
    load();
  }

  void setSort(MemberSortField field, {required bool descending}) {
    state = state.copyWith(
      filter: state.filter.copyWith(
        sortField: field,
        descending: descending,
      ),
    );
    load();
  }
}

final memberListProvider = StateNotifierProvider.autoDispose
    .family<MemberListController, MemberListState, String>(
  (ref, organizationId) => MemberListController(
    ref.watch(memberManagementRepositoryProvider),
    organizationId,
  ),
);

typedef MemberLookup = ({String organizationId, String userId});

final managedMemberProvider =
    FutureProvider.autoDispose.family<ManagedMember?, MemberLookup>(
  (ref, lookup) => ref.watch(memberManagementRepositoryProvider).getById(
        organizationId: lookup.organizationId,
        userId: lookup.userId,
      ),
);

final memberHistoryProvider = StreamProvider.autoDispose
    .family<List<MemberHistoryEvent>, String>((ref, userId) {
  return ref.watch(memberManagementRepositoryProvider).historyStream(userId);
});

final organizationRolesProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, organizationId) {
  return ref.watch(roleRepositoryProvider).streamAll(organizationId);
});
