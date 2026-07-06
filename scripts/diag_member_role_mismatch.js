#!/usr/bin/env node
/**
 * diag_member_role_mismatch.js — تشخيص عدم تطابق الدور المعروض مع الصلاحيات الفعلية.
 *
 * يطبع لكل عضو في المجلس: roleId + role + permissionsSnapshot، ويحسب:
 *   - displayLabel  : ما تعرضه الواجهة فعليًّا (roleLabelArabic → يعتمد roleId أولًا)
 *   - isReviewer    : هل يستقبل إشعارات طلبات الانضمام (يعتمد permissionsSnapshot)
 *   - MISMATCH      : عضو (member) في العرض لكنه فعليًّا مُراجِع/مدير في الصلاحيات
 *
 * الاستخدام:
 *   node ./scripts/diag_member_role_mismatch.js [organizationId]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const FALLBACK_KEY = path.join(PROJECT_ROOT, 'local_keys', 'alrahmat-service-account.json');
const orgId = process.argv[2] || 'rahmat_general_council';

const credPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS &&
  fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS))
  ? process.env.GOOGLE_APPLICATION_CREDENTIALS : FALLBACK_KEY;
const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
initializeApp({ credential: cert(sa), projectId: sa.project_id });
const db = getFirestore();

// نفس خريطة role_labels.dart (المفاتيح المهمّة).
const ROLE_LABELS = {
  system_owner: 'المالك الأعلى', owner: 'مالك المجلس', council_owner: 'مالك المجلس',
  chairman: 'رئيس المجلس', council_chairman: 'رئيس المجلس', council_president: 'رئيس المجلس',
  president: 'رئيس المجلس', adminManager: 'مدير إداري', admin: 'مدير إداري',
  financialManager: 'المدير المالي', financialReviewer: 'المراجع المالي',
  secretary: 'أمين السر', member: 'عضو', suspended: 'موقوف', superAdmin: 'مشرف المنصّة',
};
// نفس roleLabelArabic: roleId ثم role ثم fallback ثم 'عضو'.
function displayLabel(roleId, role, fallback) {
  if (roleId && ROLE_LABELS[roleId]) return ROLE_LABELS[roleId];
  if (role && ROLE_LABELS[role]) return ROLE_LABELS[role];
  if (fallback && fallback.trim()) return fallback;
  return 'عضو';
}
// الصلاحيات التي تجعل العضو "مُراجِع طلبات انضمام" (notifyOrganizationReviewers).
const REVIEWER_PERMS = ['members.approve', 'members.manage', 'membershipRequests.review'];
// أي صلاحية إدارية تدل على أنه ليس عضوًا عاديًا.
const ADMIN_PERMS = [
  'members.manage', 'members.approve', 'membershipRequests.review', 'roles.manage',
  'receipts.review', 'payments.approve', 'payments.reject', 'bookings.approve',
  'bookings.manage', 'settings.manage', 'organization.manage', 'audit.read',
  'notifications.send', 'fullAccess',
];
const j = (v) => JSON.stringify(v);

async function main() {
  console.log('=== تشخيص تطابق الدور/الصلاحيات ===');
  console.log('projectId =', sa.project_id, '| organizationId =', orgId, '\n');

  const snap = await db
    .collection('organizations').doc(orgId)
    .collection('memberships')
    .orderBy('joinedAt', 'desc')
    .get();

  console.log('عدد العضويات =', snap.size, '\n');
  let index = 0;
  const mismatches = [];
  for (const doc of snap.docs) {
    index++;
    const d = doc.data();
    const perms = Array.isArray(d.permissionsSnapshot) ? d.permissionsSnapshot : [];
    const label = displayLabel(d.roleId, d.role, '');
    const isReviewer = perms.includes('fullAccess') || perms.some((p) => REVIEWER_PERMS.includes(p));
    const adminPerms = perms.filter((p) => ADMIN_PERMS.includes(p));
    const displaysAsPlainMember = label === 'عضو';
    const mismatch = displaysAsPlainMember && adminPerms.length > 0;

    console.log(`#${index}  docId=${doc.id}`);
    console.log(`     userId               = ${j(d.userId)}`);
    console.log(`     path                 = organizations/${orgId}/memberships/${doc.id}`);
    console.log(`     roleId               = ${j(d.roleId)}`);
    console.log(`     role                 = ${j(d.role)}`);
    console.log(`     status               = ${j(d.status)}`);
    console.log(`     memberNumber         = ${j(d.memberNumber)}`);
    console.log(`     permissionsSnapshot  = ${j(perms)}`);
    console.log(`     → displayLabel(UI)   = ${label}`);
    console.log(`     → isReviewer(إشعارات) = ${isReviewer}`);
    console.log(`     → adminPerms         = ${j(adminPerms)}`);
    console.log(`     → MISMATCH           = ${mismatch ? '❗ نعم (يظهر عضو لكن صلاحياته إدارية)' : 'لا'}`);
    console.log('');
    if (mismatch) mismatches.push({ index, docId: doc.id, userId: d.userId, label, adminPerms });
  }

  console.log('=== الخلاصة ===');
  if (mismatches.length === 0) {
    console.log('لا يوجد عضو "يظهر عضو" بينما صلاحياته إدارية.');
  } else {
    console.log(`عدد الأعضاء غير المتطابقين = ${mismatches.length}`);
    for (const m of mismatches) {
      console.log(`  #${m.index} userId=${m.userId} label=${m.label} adminPerms=${j(m.adminPerms)}`);
    }
  }
}
main().catch((e) => { console.error('❌', e); process.exit(1); });
