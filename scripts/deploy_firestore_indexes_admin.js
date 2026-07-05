#!/usr/bin/env node
/**
 * deploy_firestore_indexes_admin.js
 * ------------------------------------------------------------------------
 * نشر فهارس Firestore المركّبة (firestore.indexes.json) عبر Firestore Admin
 * REST API باستخدام Service Account — بدون `firebase login`.
 *
 * الاستخدام:  node ./scripts/deploy_firestore_indexes_admin.js
 *
 * يقرأ كل فهرس في الملف وينشئه إن لم يكن موجودًا. الفهرس الموجود مسبقًا
 * (ALREADY_EXISTS) يُتخطّى بأمان. إنشاء الفهرس عملية طويلة (LRO) قد تستغرق
 * دقائق حتى تصبح READY.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const EXPECTED_PROJECT_ID = 'alrahmat-console';
const PROJECT_ROOT = path.resolve(__dirname, '..');
const INDEXES_PATH = path.join(PROJECT_ROOT, 'firestore.indexes.json');
const FALLBACK_KEY = path.join(PROJECT_ROOT, 'local_keys', 'alrahmat-service-account.json');

function fail(m, e) { console.error('❌ ' + m + (e ? ' :: ' + (e.message || e) : '')); process.exit(1); }

async function main() {
  console.log('=== نشر فهارس Firestore عبر Service Account ===');
  if (!fs.existsSync(INDEXES_PATH)) fail('لا يوجد ملف فهارس: ' + INDEXES_PATH);
  const config = JSON.parse(fs.readFileSync(INDEXES_PATH, 'utf8'));
  const indexes = config.indexes || [];
  console.log('📄 عدد الفهارس في الملف = ' + indexes.length);

  const credPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS &&
    fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS))
    ? process.env.GOOGLE_APPLICATION_CREDENTIALS : FALLBACK_KEY;
  if (!fs.existsSync(credPath)) fail('لا يوجد ملف حساب خدمة: ' + credPath);
  const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
  if (sa.project_id !== EXPECTED_PROJECT_ID) fail('projectId غير متوقّع: ' + sa.project_id);

  const auth = new GoogleAuth({
    credentials: sa,
    scopes: ['https://www.googleapis.com/auth/datastore', 'https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const token = (await client.getAccessToken()).token;
  const headers = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
  const dbBase = `https://firestore.googleapis.com/v1/projects/${sa.project_id}/databases/(default)`;

  let created = 0, existed = 0, failed = 0;
  for (const idx of indexes) {
    const cg = idx.collectionGroup;
    const body = {
      queryScope: idx.queryScope || 'COLLECTION',
      fields: idx.fields
        .filter((f) => f.fieldPath !== '__name__')
        .map((f) => (f.order
          ? { fieldPath: f.fieldPath, order: f.order }
          : { fieldPath: f.fieldPath, arrayConfig: f.arrayConfig })),
    };
    const label = `${cg} [${body.queryScope}] {${idx.fields.map((f) => f.fieldPath + ':' + (f.order || f.arrayConfig)).join(', ')}}`;
    const url = `${dbBase}/collectionGroups/${cg}/indexes`;
    const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    const json = await res.json().catch(() => ({}));
    if (res.ok) {
      created++;
      console.log(`  ⏫ إنشاء: ${label}  → LRO ${json.name ? json.name.split('/').pop() : 'started'}`);
    } else if (res.status === 409 || (json.error && json.error.status === 'ALREADY_EXISTS')) {
      existed++;
      console.log(`  ✔️ موجود مسبقًا: ${label}`);
    } else {
      failed++;
      console.log(`  ❌ فشل: ${label}  (HTTP ${res.status}) ${JSON.stringify(json.error || json)}`);
    }
  }
  console.log(`\nالنتيجة: أُنشئ=${created} موجود=${existed} فشل=${failed}`);
  console.log('ℹ️ الفهارس الجديدة تحتاج دقائق حتى تصبح READY. تحقّق عبر:');
  console.log('   node ./scripts/diag_receipts_query.js');
  if (failed > 0) process.exit(2);
}
main().catch((e) => fail('خطأ غير متوقّع', e));
