"use strict";

function effectiveMembershipPermissions(data = {}) {
  const permissions = Array.isArray(data.permissionsSnapshot) ? data.permissionsSnapshot : [];
  const isMemberRole = data.roleId === "member" || data.role === "member";
  return isMemberRole ? permissions.filter((permission) => permission !== "fullAccess") : permissions;
}

function hasAnyMembershipPermission(data, allowedPermissions) {
  const allowed = new Set(allowedPermissions);
  return effectiveMembershipPermissions(data).some((permission) => allowed.has(permission));
}

module.exports = {
  effectiveMembershipPermissions,
  hasAnyMembershipPermission,
};
