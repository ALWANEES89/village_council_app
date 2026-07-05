#!/usr/bin/env node
/**
 * deploy_firestore_rules_admin.js
 * ------------------------------------------------------------------------
 * نشر قواعد Firestore (firestore.rules) إلى مشروع alrahmat-console باستخدام
 * حساب خدمة (Service Account) بدل `firebase login`.
 *
 * الاستخدام:
 *   node ./scripts/deploy_firestore_rules_admin.js
 *
 * مصدر بيانات الاعتماد (بالترتيب):
 *   1) متغيّر البيئة GOOGLE_APPLICATION_CREDENTIALS (مسار ملف service account).
 *   2) fallback: ./local_keys/alrahmat-service-account.json
 *
 * ما يفعله:
 *   - يقرأ firestore.rules من جذر المشروع.
 *   - يتحقق أن projectId في حساب الخدمة == alrahmat-console.
 *   - ينشئ ruleset جديدًا ثم يُصدره (release) إلى cloud.firestore.
 *   - يطبع تقرير نجاح/فشل واضح.
 *
 * يعتمد على firebaserules.googleapis.com REST API عبر google-auth-library.
 * يتطلب أن يملك حساب الخدمة دور: Firebase Rules Admin أو Editor.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const EXPECTED_PROJECT_ID = 'alrahmat-console';
const PROJECT_ROOT = path.resolve(__dirname, '..');
const RULES_PATH = path.join(PROJECT_ROOT, 'firestore.rules');
const FALLBACK_KEY = path.join(
  PROJECT_ROOT,
  'local_keys',
  'alrahmat-service-account.json',
);

function fail(message, error) {
  console.error('\n❌ فشل النشر: ' + message);
  if (error) console.error('   السبب: ' + (error.message || error));
  process.exit(1);
}

function resolveCredentialsPath() {
  const fromEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (fromEnv && fs.existsSync(fromEnv)) {
    console.log('🔑 بيانات الاعتماد: GOOGLE_APPLICATION_CREDENTIALS');
    return fromEnv;
  }
  if (fromEnv && !fs.existsSync(fromEnv)) {
    console.warn(
      '⚠️  GOOGLE_APPLICATION_CREDENTIALS يشير إلى ملف غير موجود: ' + fromEnv,
    );
  }
  if (fs.existsSync(FALLBACK_KEY)) {
    console.log('🔑 بيانات الاعتماد: ' + path.relative(PROJECT_ROOT, FALLBACK_KEY));
    return FALLBACK_KEY;
  }
  fail(
    'لم يتم العثور على بيانات اعتماد. اضبط GOOGLE_APPLICATION_CREDENTIALS ' +
      'أو ضع الملف في local_keys/alrahmat-service-account.json',
  );
}

async function main() {
  console.log('=== نشر قواعد Firestore عبر Service Account ===');

  if (!fs.existsSync(RULES_PATH)) {
    fail('ملف القواعد غير موجود: ' + RULES_PATH);
  }
  const rulesContent = fs.readFileSync(RULES_PATH, 'utf8');
  console.log(
    '📄 القواعد: firestore.rules (' + rulesContent.length + ' حرفًا)',
  );

  const credentialsPath = resolveCredentialsPath();
  let serviceAccount;
  try {
    serviceAccount = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
  } catch (error) {
    fail('تعذّر قراءة/تحليل ملف حساب الخدمة.', error);
  }

  const projectId = serviceAccount.project_id;
  console.log('🏷️  projectId (من حساب الخدمة) = ' + projectId);
  if (projectId !== EXPECTED_PROJECT_ID) {
    fail(
      'projectId لا يطابق المتوقّع (' +
        EXPECTED_PROJECT_ID +
        '). حساب الخدمة لمشروع مختلف — أوقفت النشر حمايةً لك.',
    );
  }

  const auth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: [
      'https://www.googleapis.com/auth/firebase',
      'https://www.googleapis.com/auth/cloud-platform',
    ],
  });
  let headers;
  try {
    const client = await auth.getClient();
    const token = (await client.getAccessToken()).token;
    if (!token) throw new Error('لم يتم الحصول على access token.');
    headers = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
  } catch (error) {
    fail('تعذّر المصادقة بحساب الخدمة.', error);
  }

  const base = 'https://firebaserules.googleapis.com/v1/projects/' + projectId;

  // 1) إنشاء ruleset جديد يحمل مصدر firestore.rules.
  console.log('⏫ إنشاء ruleset جديد ...');
  const createResponse = await fetch(base + '/rulesets', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      source: { files: [{ name: 'firestore.rules', content: rulesContent }] },
    }),
  });
  const createJson = await createResponse.json();
  if (!createResponse.ok) {
    fail(
      'إنشاء ruleset فشل (HTTP ' + createResponse.status + '). ' +
        'تأكد أن حساب الخدمة يملك دور Firebase Rules Admin.',
      new Error(JSON.stringify(createJson.error || createJson)),
    );
  }
  const rulesetName = createJson.name; // projects/<id>/rulesets/<uuid>
  console.log('✅ ruleset = ' + rulesetName);

  // 2) إصدار الـ ruleset إلى cloud.firestore (تحديث الإصدار إن وُجد، وإلا إنشاؤه).
  const releaseName = 'projects/' + projectId + '/releases/cloud.firestore';
  console.log('🚀 إصدار القواعد إلى cloud.firestore ...');
  let releaseResponse = await fetch(
    'https://firebaserules.googleapis.com/v1/' + releaseName,
    {
      method: 'PATCH',
      headers,
      body: JSON.stringify({
        release: { name: releaseName, rulesetName: rulesetName },
      }),
    },
  );
  // إن لم يكن الإصدار موجودًا بعد (404) ننشئه.
  if (releaseResponse.status === 404) {
    console.log('ℹ️  الإصدار غير موجود — يتم إنشاؤه لأول مرة ...');
    releaseResponse = await fetch(base + '/releases', {
      method: 'POST',
      headers,
      body: JSON.stringify({ name: releaseName, rulesetName: rulesetName }),
    });
  }
  const releaseJson = await releaseResponse.json();
  if (!releaseResponse.ok) {
    fail(
      'إصدار القواعد فشل (HTTP ' + releaseResponse.status + ').',
      new Error(JSON.stringify(releaseJson.error || releaseJson)),
    );
  }

  console.log('\n✅ تم نشر قواعد Firestore بنجاح إلى ' + projectId + '.');
  console.log('   الإصدار: cloud.firestore');
  console.log('   ruleset: ' + rulesetName);
  console.log('   وقت الإنشاء: ' + (releaseJson.createTime || releaseJson.updateTime || '-'));
}

main().catch((error) => fail('خطأ غير متوقّع.', error));
