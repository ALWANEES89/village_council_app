#!/usr/bin/env node
/**
 * diag_receipts_query.js — تشخيص استعلام الإيصالات قيد المراجعة.
 * يشغّل نفس استعلام streamPending() عبر Admin SDK على كل مجلس، ليكشف:
 *  - هل الفهرس المركّب (reviewStatus + submittedAt) منشور؟ (FAILED_PRECONDITION)
 *  - كم عدد الإيصالات pending فعلاً، وحقولها.
 * قراءة فقط — لا يكتب شيئًا. الاستخدام: node ./scripts/diag_receipts_query.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const FALLBACK_KEY = path.join(path.resolve(__dirname, '..'), 'local_keys', 'alrahmat-service-account.json');
const credPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS))
  ? process.env.GOOGLE_APPLICATION_CREDENTIALS : FALLBACK_KEY;
const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
initializeApp({ credential: cert(sa), projectId: sa.project_id });
const db = getFirestore();

async function main() {
  const orgs = await db.collection('organizations').get();
  console.log('عدد المجالس =', orgs.size);
  for (const org of orgs.docs) {
    const orgId = org.id;
    const col = db.collection('organizations').doc(orgId).collection('transactions');
    const total = (await col.count().get()).data().count;
    if (total === 0) continue;
    console.log(`\n=== ${orgId} (transactions=${total}) ===`);
    // نفس استعلام streamPending():
    try {
      const q = await col.where('reviewStatus', '==', 'pending')
        .orderBy('submittedAt', 'desc').get();
      console.log(`  ✅ الاستعلام (reviewStatus==pending + orderBy submittedAt desc) نجح. pending=${q.size}`);
      q.docs.slice(0, 5).forEach((d) => {
        const x = d.data();
        console.log(`     - ${d.id}: status=${JSON.stringify(x.status)} reviewStatus=${JSON.stringify(x.reviewStatus)} submittedAt=${x.submittedAt ? 'set' : 'MISSING'} org=${JSON.stringify(x.organizationId)}`);
      });
    } catch (e) {
      console.log('  ❌ فشل الاستعلام:', e.code || '', e.message);
      if (String(e.message).includes('index')) {
        console.log('     ⚠️ الفهرس المركّب غير منشور — هذا سبب "تظهر ثم تختفي".');
        const m = String(e.message).match(/https?:\/\/\S+/);
        if (m) console.log('     رابط إنشاء الفهرس:', m[0]);
      }
    }
    // توزيع reviewStatus لكل الإيصالات
    const all = await col.get();
    const dist = {};
    all.docs.forEach((d) => { const r = d.data().reviewStatus; dist[r] = (dist[r] || 0) + 1; });
    console.log('  توزيع reviewStatus =', JSON.stringify(dist));
  }
}
main().catch((e) => { console.error('ERR', e); process.exit(1); });
