#!/usr/bin/env node
/**
 * inspect_owner_access.js  —  تشخيص صلاحية المالك الأعلى فعليًّا على الخادم.
 * يقرأ platform_admins/{uid} + عضويات المستخدم، ويحاكي شرط isSystemOwner()
 * كما في القواعد، لمعرفة سبب رفض تغيير الصلاحية.
 *
 * الاستخدام:
 *   node ./scripts/inspect_owner_access.js <uid> [organizationId] [targetUid]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const FALLBACK_KEY = path.join(PROJECT_ROOT, 'local_keys', 'alrahmat-service-account.json');

const uid = process.argv[2] || '3PpbBzCACsh8PphpbN5Gp1keolF3';
const orgId = process.argv[3] || null;
const targetUid = process.argv[4] || null;

const credPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS &&
  fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS))
  ? process.env.GOOGLE_APPLICATION_CREDENTIALS : FALLBACK_KEY;
const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
initializeApp({ credential: cert(sa), projectId: sa.project_id });
const db = getFirestore();

function j(v) { return JSON.stringify(v); }

async function main() {
  console.log('=== تشخيص وصول المالك الأعلى ===');
  console.log('projectId =', sa.project_id);
  console.log('uid       =', j(uid), '(length=' + uid.length + ')');

  // 1) platform_admins/{uid}
  const adminSnap = await db.doc('platform_admins/' + uid).get();
  console.log('\n[platform_admins/' + uid + ']');
  console.log('  exists   =', adminSnap.exists);
  const a = adminSnap.data() || {};
  console.log('  data     =', j(a));
  const roleVal = a.role;
  const statusVal = a.status;
  const fullAccessVal = a.fullAccess;
  console.log('  role     =', j(roleVal), '(type ' + typeof roleVal + ')');
  console.log('  status   =', j(statusVal), '(type ' + typeof statusVal + ')');
  console.log('  fullAccess =', j(fullAccessVal), '(type ' + typeof fullAccessVal + ')');

  // محاكاة isSystemOwner() من القواعد بالضبط:
  const rulesIsSystemOwner =
    adminSnap.exists &&
    statusVal === 'active' &&
    (roleVal === 'system_owner' ||
      (roleVal === 'superAdmin' && fullAccessVal === true));
  console.log('\n>>> isSystemOwner() (كما في القواعد) =', rulesIsSystemOwner);
  if (!rulesIsSystemOwner) {
    console.log('    ⚠️ سبب الرفض المحتمل:');
    if (!adminSnap.exists) console.log('       - المستند غير موجود على هذا المسار/المشروع.');
    if (statusVal !== 'active') console.log('       - status ليست "active" بالضبط (القيمة: ' + j(statusVal) + ').');
    if (roleVal !== 'system_owner' && roleVal !== 'superAdmin')
      console.log('       - role ليست system_owner/superAdmin (القيمة: ' + j(roleVal) + ').');
  }

  // 2) عضويات المستخدم عبر كل المجالس (لماذا تظهر الأزرار؟)
  console.log('\n[عضويات المستخدم عبر المجالس]');
  const cg = await db.collectionGroup('memberships').get();
  let mine = 0;
  for (const d of cg.docs) {
    const data = d.data();
    if (d.id === uid || data.userId === uid) {
      mine++;
      console.log('  path=' + d.ref.path);
      console.log('     roleId=' + j(data.roleId) + ' role=' + j(data.role) +
        ' status=' + j(data.status) + ' isPrimaryOwner=' + j(data.isPrimaryOwner));
      console.log('     permissionsSnapshot=' + j(data.permissionsSnapshot || []));
    }
  }
  if (mine === 0) console.log('  (لا عضويات — الأزرار تظهر فقط عبر isSuperAdmin)');

  // 3) العضوية الهدف إن حُدّدت
  if (orgId && targetUid) {
    const tSnap = await db.doc('organizations/' + orgId + '/memberships/' + targetUid).get();
    console.log('\n[العضوية الهدف organizations/' + orgId + '/memberships/' + targetUid + ']');
    console.log('  exists =', tSnap.exists, ' data=', j(tSnap.data() || {}));
  }

}
main().catch((e) => { console.error('❌', e); process.exit(1); });
