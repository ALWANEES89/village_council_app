#!/usr/bin/env node
/**
 * fix_member_role_fullaccess.js — إصلاح جذري لتلوّث دور "عضو" بصلاحية fullAccess.
 *
 * المشكلة: مستند دور roles/member كان يحوي "fullAccess"، فكان كل عضو يُقبَل
 * يرث صلاحيات مالك كاملة (approve() ينسخ صلاحيات الدور إلى permissionsSnapshot).
 *
 * هذا السكربت (idempotent):
 *   1) يزيل fullAccess من مستند دور member في المجلس المستهدف.
 *   2) يزامن كل عضو نشط roleId=member يحمل fullAccess موروثة (يزيلها فقط).
 * لا يمسّ الأدوار المميّزة (owner/chairman/adminManager/system_owner).
 *
 * الاستخدام:
 *   node ./scripts/fix_member_role_fullaccess.js [organizationId] [--apply]
 * بدون --apply = تشغيل تجريبي (dry-run) يعرض التغييرات فقط.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const ROOT = path.resolve(__dirname, '..');
const KEY = path.join(ROOT, 'local_keys', 'alrahmat-service-account.json');
const ORG = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2] : 'rahmat_general_council';
const APPLY = process.argv.includes('--apply');

const sa = JSON.parse(fs.readFileSync(KEY, 'utf8'));
initializeApp({ credential: cert(sa), projectId: sa.project_id });
const db = getFirestore();

const PRIVILEGED_ROLE_IDS = new Set([
  'system_owner', 'owner', 'council_owner', 'chairman', 'president',
  'council_chairman', 'council_president', 'adminManager', 'admin',
]);
const j = (v) => JSON.stringify(v);
const clean = (arr) =>
  [...new Set((arr || []).filter((p) => p !== 'fullAccess'))].sort();

async function main() {
  console.log(`=== إصلاح تلوّث دور "عضو" بـ fullAccess ===`);
  console.log(`projectId=${sa.project_id} org=${ORG} mode=${APPLY ? 'APPLY ✅' : 'DRY-RUN 🔍'}\n`);

  // 1) مستند دور member
  const roleRef = db.doc(`organizations/${ORG}/roles/member`);
  const roleSnap = await roleRef.get();
  if (!roleSnap.exists) {
    console.log('⚠️ لا يوجد مستند دور member — تخطّي إصلاح الدور.');
  } else {
    const before = roleSnap.get('permissions') || [];
    const after = clean(before);
    const changed = j([...before].sort()) !== j(after);
    console.log(`[1] roles/member`);
    console.log(`    before = ${j(before)}`);
    console.log(`    after  = ${j(after)}  ${changed ? '(سيتغيّر)' : '(لا تغيير)'}`);
    if (changed && APPLY) {
      await roleRef.update({
        permissions: after,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: 'data_repair_member_role_fullaccess',
      });
      console.log('    ✅ تم تحديث مستند الدور.');
    }
  }

  // 2) كل العضويات غير المميّزة التي تحمل fullAccess موروثة (أي حالة).
  // نشمل removed/suspended أيضًا لأن activate() لا يعيد بناء permissionsSnapshot،
  // فلو أُعيد تفعيل العضو لاستعاد الصلاحية الملوّثة.
  console.log(`\n[2] العضويات المتأثّرة (roleId غير مميّز + fullAccess، أي حالة):`);
  const members = await db
    .collection(`organizations/${ORG}/memberships`)
    .get();
  let fixed = 0;
  for (const doc of members.docs) {
    const d = doc.data();
    const roleId = d.roleId || 'member';
    const perms = d.permissionsSnapshot || [];
    if (PRIVILEGED_ROLE_IDS.has(roleId)) continue; // لا نمسّ الأدوار المميّزة
    if (!perms.includes('fullAccess')) continue;
    const after = clean(perms);
    console.log(`    - ${doc.id} (member#${d.memberNumber}) roleId=${roleId}`);
    console.log(`        before = ${j(perms)}`);
    console.log(`        after  = ${j(after)}`);
    if (APPLY) {
      await doc.ref.update({
        permissionsSnapshot: after,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: 'data_repair_member_role_fullaccess',
      });
      console.log('        ✅ تمت المزامنة.');
    }
    fixed++;
  }
  if (fixed === 0) console.log('    (لا عضويات متأثّرة)');

  console.log(`\n=== ${APPLY ? 'اكتمل التطبيق' : 'انتهى العرض التجريبي'} — عضويات متأثّرة=${fixed} ===`);
  if (!APPLY) console.log('لتطبيق التغييرات فعليًّا: أضِف --apply');
}
main().catch((e) => { console.error('❌', e); process.exit(1); });
