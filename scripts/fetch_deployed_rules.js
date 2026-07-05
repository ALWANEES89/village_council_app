#!/usr/bin/env node
/**
 * fetch_deployed_rules.js
 * ------------------------------------------------------------------------
 * يجلب قواعد Firestore المنشورة فعليًّا من cloud.firestore ويقارنها بملف
 * firestore.rules المحلي — للتأكد ممّا إذا كان المنشور مطابقًا للملف.
 *
 * الاستخدام:  node ./scripts/fetch_deployed_rules.js
 * يكتب المنشور إلى: scripts/.deployed_firestore.rules
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const EXPECTED_PROJECT_ID = 'alrahmat-console';
const PROJECT_ROOT = path.resolve(__dirname, '..');
const RULES_PATH = path.join(PROJECT_ROOT, 'firestore.rules');
const FALLBACK_KEY = path.join(PROJECT_ROOT, 'local_keys', 'alrahmat-service-account.json');
const OUT_PATH = path.join(__dirname, '.deployed_firestore.rules');

function fail(m, e) { console.error('❌ ' + m + (e ? ' :: ' + (e.message || e) : '')); process.exit(1); }

async function main() {
  const credPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS &&
    fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS))
    ? process.env.GOOGLE_APPLICATION_CREDENTIALS : FALLBACK_KEY;
  if (!fs.existsSync(credPath)) fail('لا يوجد ملف حساب خدمة: ' + credPath);
  const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
  if (sa.project_id !== EXPECTED_PROJECT_ID) fail('projectId غير متوقّع: ' + sa.project_id);

  const auth = new GoogleAuth({
    credentials: sa,
    scopes: ['https://www.googleapis.com/auth/firebase', 'https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const token = (await client.getAccessToken()).token;
  const headers = { Authorization: 'Bearer ' + token };

  const releaseName = 'projects/' + sa.project_id + '/releases/cloud.firestore';
  const relRes = await fetch('https://firebaserules.googleapis.com/v1/' + releaseName, { headers });
  const rel = await relRes.json();
  if (!relRes.ok) fail('تعذّر قراءة الإصدار (HTTP ' + relRes.status + ')', new Error(JSON.stringify(rel.error || rel)));
  console.log('🚀 rulesetName المنشور = ' + rel.rulesetName);
  console.log('   updateTime = ' + (rel.updateTime || '-'));

  const rsRes = await fetch('https://firebaserules.googleapis.com/v1/' + rel.rulesetName, { headers });
  const rs = await rsRes.json();
  if (!rsRes.ok) fail('تعذّر قراءة الـ ruleset', new Error(JSON.stringify(rs.error || rs)));
  const files = (rs.source && rs.source.files) || [];
  const deployed = (files[0] && files[0].content) || '';
  fs.writeFileSync(OUT_PATH, deployed, 'utf8');
  console.log('   ruleset.createTime = ' + (rs.createTime || '-'));

  const local = fs.readFileSync(RULES_PATH, 'utf8');
  const norm = (s) => s.replace(/\r\n/g, '\n').trim();
  const same = norm(local) === norm(deployed);
  console.log('\n📄 محلي: ' + local.length + ' حرفًا | منشور: ' + deployed.length + ' حرفًا');
  console.log(same ? '✅ المنشور مطابق للملف المحلي.' : '⚠️  المنشور مختلف عن الملف المحلي!');

  const hasSysOwnerUpdate = /allow update:\s*if\s+isSystemOwner\(\)/.test(deployed);
  console.log('   المنشور يحتوي "allow update: if isSystemOwner()" ؟ ' + hasSysOwnerUpdate);
  const hasHistorySysOwner = /allow create:[\s\S]*?isSystemOwner\(\)[\s\S]*?member_history|member_history[\s\S]*?isSystemOwner/.test(deployed);
  console.log('   المنشور فيه isSystemOwner قرب member_history ؟ ' + hasHistorySysOwner);
  process.exit(same ? 0 : 2);
}
main().catch((e) => fail('خطأ غير متوقّع', e));
