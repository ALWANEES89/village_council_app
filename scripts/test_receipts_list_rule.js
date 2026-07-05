#!/usr/bin/env node
/**
 * test_receipts_list_rule.js — هل تسمح القواعد المنشورة للمالك الأعلى
 * باستعلام list على transactions (شاشة مراجعة الإيصالات)؟
 * يختبر method='list' بهوية المالك مع محاكاة platform_admins.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const ROOT = path.resolve(__dirname, '..');
const KEY = path.join(ROOT, 'local_keys', 'alrahmat-service-account.json');
const RULES = path.join(ROOT, 'firestore.rules');
const OWNER = '3PpbBzCACsh8PphpbN5Gp1keolF3';
const ORG = 'rahmat_general_council';
const DOCS = '/databases/(default)/documents';
const adminPath = `${DOCS}/platform_admins/${OWNER}`;

const ownerMocks = [
  { function: 'exists', args: [{ exactValue: adminPath }], result: { value: true } },
  { function: 'get', args: [{ exactValue: adminPath }],
    result: { value: { data: { status: 'active', role: 'system_owner', fullAccess: true } } } },
];

function tc(label, method, docPath, mocks) {
  return {
    expectation: 'ALLOW',
    request: { auth: { uid: OWNER, token: {} }, method, path: docPath, time: '2026-07-06T10:00:00.000Z' },
    functionMocks: mocks,
    __label: label,
  };
}

const cases = [
  tc('transactions.list (owner)', 'list', `${DOCS}/organizations/${ORG}/transactions/T1`, ownerMocks),
  tc('transactions.get  (owner)', 'get', `${DOCS}/organizations/${ORG}/transactions/T1`, ownerMocks),
];

async function main() {
  const sa = JSON.parse(fs.readFileSync(KEY, 'utf8'));
  const source = fs.readFileSync(RULES, 'utf8');
  const auth = new GoogleAuth({ credentials: sa,
    scopes: ['https://www.googleapis.com/auth/firebase', 'https://www.googleapis.com/auth/cloud-platform'] });
  const token = (await (await auth.getClient()).getAccessToken()).token;
  const res = await fetch(`https://firebaserules.googleapis.com/v1/projects/${sa.project_id}:test`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      source: { files: [{ name: 'firestore.rules', content: source }] },
      testSuite: { testCases: cases.map(({ __label, ...c }) => c) },
    }),
  });
  const json = await res.json();
  if (!res.ok) { console.error('HTTP', res.status, JSON.stringify(json, null, 2)); return; }
  (json.testResults || []).forEach((r, i) => {
    console.log(`[${cases[i].__label}] => ${r.state}  (متوقّع SUCCESS=مسموح)`);
    if (r.state !== 'SUCCESS' && r.debugMessages) console.log('   debug:', JSON.stringify(r.debugMessages));
  });
}
main().catch((e) => console.error('ERR', e));
