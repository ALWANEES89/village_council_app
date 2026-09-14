const String fullAccessPermission = 'fullAccess';

/// يمنع أن يتحول دور العضو العادي إلى مالك فعلي بسبب قالب دور قديم أو تالف.
///
/// تبقى الصلاحيات الجزئية الممنوحة عمدًا للعضو كما هي؛ المحظور هنا هو
/// [fullAccess] فقط لأنه يتجاوز كل حدود الصلاحيات في التطبيق والقواعد.
List<String> sanitizePermissionsForRole(
  String roleId,
  Iterable<String> permissions,
) {
  final sanitized = permissions
      .where((permission) =>
          roleId != 'member' || permission != fullAccessPermission)
      .toSet()
      .toList()
    ..sort();
  return sanitized;
}

bool memberRoleHasSafePermissions(
  String roleId,
  Iterable<String> permissions,
) {
  return roleId != 'member' || !permissions.contains(fullAccessPermission);
}
