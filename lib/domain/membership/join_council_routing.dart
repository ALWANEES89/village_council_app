bool shouldOpenJoinCouncil({
  required int activeMembershipCount,
  required bool membershipsLoadFailed,
  required bool isSystemOwner,
}) {
  return activeMembershipCount == 0 &&
      !membershipsLoadFailed &&
      !isSystemOwner;
}
