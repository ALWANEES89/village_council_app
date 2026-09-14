import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/domain/dashboard/system_dashboard_metrics.dart';

void main() {
  test('builds system totals from real organization data', () {
    final summary = buildSystemDashboardSummary(
      organizations: const [
        {'id': 'org-a', 'status': 'active'},
        {'id': 'org-b', 'status': 'inactive'},
        {'id': 'org-c', 'status': 'active'},
      ],
      countsByOrganization: const {
        'org-a': {'members': 14, 'requests': 2},
        'org-b': {'members': 5, 'requests': 0},
        'org-c': {'members': 9, 'requests': 3},
      },
    );

    expect(summary.totalCouncils, 3);
    expect(summary.activeCouncils, 2);
    expect(summary.pendingActions, 5);
    expect(summary.countsByOrganization['org-a']?['members'], 14);
  });

  test('does not present a partial pending total as a complete value', () {
    final summary = buildSystemDashboardSummary(
      organizations: const [
        {'id': 'org-a', 'status': 'active'},
        {'id': 'org-b', 'status': 'active'},
      ],
      countsByOrganization: const {
        'org-a': {'members': 14, 'requests': 2},
        'org-b': null,
      },
    );

    expect(summary.totalCouncils, 2);
    expect(summary.activeCouncils, 2);
    expect(summary.pendingActions, isNull);
  });
}
