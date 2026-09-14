"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { _test } = require("./council_management");

test("financial report keeps integer baisa totals and separates income from expenses", () => {
  const report = _test.buildFinancialReport({
    transactions: [{
      id: "t1",
      data: {
        reviewStatus: "approved",
        amountDeclaredBaisa: 25000,
        reviewedBy: "reviewer",
        allocations: [
          { chargeId: "subscription", amountAllocatedBaisa: 10000 },
          { chargeId: "booking", amountAllocatedBaisa: 12000 },
          { chargeId: "addon", amountAllocatedBaisa: 3000 },
        ],
      },
    }],
    charges: [
      { id: "subscription", data: { membershipId: "m1", chargeType: "subscription", amountDueBaisa: 10000, amountPaidBaisa: 10000, balanceBaisa: 0, status: "paid" } },
      { id: "booking", data: { membershipId: "m2", chargeType: "booking", sourceId: "b1", amountDueBaisa: 12000, amountPaidBaisa: 12000, balanceBaisa: 0, status: "paid" } },
      { id: "addon", data: { membershipId: "m3", chargeType: "package", amountDueBaisa: 5000, amountPaidBaisa: 3000, balanceBaisa: 2000, status: "partial" } },
      { id: "legacy", data: { membershipId: "m4", chargeType: "other", amountDue: 5, amountPaid: 2, status: "unpaid" } },
    ],
    bookings: [{ id: "b1", data: { status: "approved", bookingCategory: "regular", approvedBy: "reviewer" } }],
    expenses: [
      { id: "e1", data: { category: "maintenance", amountBaisa: 4500, status: "posted" } },
      { id: "e2", data: { category: "other", amountBaisa: 9900, status: "cancelled" } },
    ],
  });

  assert.equal(report.totalCollectedBaisa, 25000);
  assert.equal(report.totalExpensesBaisa, 4500);
  assert.equal(report.netBalanceBaisa, 20500);
  assert.equal(report.revenueByCategory.subscription, 10000);
  assert.equal(report.revenueByCategory.bookingRegular, 12000);
  assert.equal(report.revenueByCategory.packageAddOn, 3000);
  assert.equal(report.membersPaidCount, 2);
  assert.equal(report.membersUnpaidCount, 2);
  assert.equal(report.totalOutstandingBaisa, 5000);
  assert.equal(report.expenseCount, 1);
  for (const value of [report.totalCollectedBaisa, report.totalExpensesBaisa, report.netBalanceBaisa]) {
    assert.equal(Number.isSafeInteger(value), true);
  }
});

test("expense and council notification permissions stay capability based", () => {
  const financialManager = { platformOwner: false, membership: { roleId: "financialManager" } };
  const financialReviewer = { platformOwner: false, membership: { roleId: "financialReviewer" } };
  const notifier = { platformOwner: false, membership: { permissionsSnapshot: ["notifications.send"] } };
  const announcementManager = { platformOwner: false, membership: { permissionsSnapshot: ["announcements.manage"] } };
  const plainMember = { platformOwner: false, membership: { roleId: "member", permissionsSnapshot: [] } };

  assert.equal(_test.canManageExpenses(financialManager), true);
  assert.equal(_test.canManageExpenses(financialReviewer), false);
  assert.equal(_test.canSendNotifications(notifier), true);
  assert.equal(_test.canSendNotifications(announcementManager), true);
  assert.equal(_test.canSendNotifications(plainMember), false);
  assert.equal(_test.canViewFinancialReports(financialReviewer), true);
});
