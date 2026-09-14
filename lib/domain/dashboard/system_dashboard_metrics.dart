class SystemDashboardSummary {
  const SystemDashboardSummary({
    required this.totalCouncils,
    required this.activeCouncils,
    required this.pendingActions,
    required this.countsByOrganization,
  });

  final int totalCouncils;
  final int activeCouncils;
  final int? pendingActions;
  final Map<String, Map<String, int>?> countsByOrganization;
}

SystemDashboardSummary buildSystemDashboardSummary({
  required List<Map<String, dynamic>> organizations,
  required Map<String, Map<String, int>?> countsByOrganization,
}) {
  final hasUnknownCounts =
      countsByOrganization.values.any((value) => value == null);
  final pendingActions = hasUnknownCounts
      ? null
      : countsByOrganization.values
          .whereType<Map<String, int>>()
          .fold<int>(0, (total, value) => total + (value['requests'] ?? 0));
  return SystemDashboardSummary(
    totalCouncils: organizations.length,
    activeCouncils:
        organizations.where((item) => item['status'] == 'active').length,
    pendingActions: pendingActions,
    countsByOrganization: Map.unmodifiable(countsByOrganization),
  );
}
