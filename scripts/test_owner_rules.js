#!/usr/bin/env node
/**
 * test_owner_rules.js — اختبار قطعي عبر TestRuleset API: هل تسمح القواعد
 * المنشورة للمالك الأعلى بكتابات "تغيير الصلاحية" الثلاث؟
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const RULES_PATH = path.join(PROJECT_ROOT, 'firestore.rules');
const EXPECTED_PROJECT_ID = 'demo-financial-prestaging';

const OWNER = 'qa-system-owner';
const ORG = 'qa-financial-council';
const TARGET = 'qa-target-member';
const DOCS = '/databases/(default)/documents';

const adminPath = `${DOCS}/platform_admins/${OWNER}`;
const orgPath = `${DOCS}/organizations/${ORG}`;

// محاكاة get() ترجع مستند platform_admins للمالك (Value محوّل إلى JSON بسيط).
const adminGet = { data: { status: 'active', role: 'system_owner', fullAccess: true } };

const ownerMocks = [
  { function: 'exists', args: [{ exactValue: adminPath }], result: { value: true } },
  { function: 'get', args: [{ exactValue: adminPath }], result: { value: adminGet } },
];
const notifMocks = [
  ...ownerMocks,
  { function: 'exists', args: [{ exactValue: orgPath }], result: { value: true } },
];

function tc(expectation, method, docPath, newData, oldData, functionMocks) {
  const request = {
    auth: { uid: OWNER, token: {} },
    method,
    path: docPath,
    time: '2026-07-05T18:00:00.000Z',
  };
  if (newData) request.resource = { data: newData };
  const out = { expectation, request, functionMocks };
  if (oldData) out.resource = { data: oldData };
  return out;
}

const testCases = [
  // 1) update العضوية الهدف (عضو عادي غير مالك)
  tc('ALLOW', 'update', `${DOCS}/organizations/${ORG}/memberships/${TARGET}`,
    { roleId: 'adminManager', role: 'member', userId: TARGET, organizationId: ORG,
      status: 'active', permissionsSnapshot: ['members.manage'] },
    { roleId: 'member', role: 'member', userId: TARGET, organizationId: ORG,
      status: 'active', permissionsSnapshot: [], isPrimaryOwner: false },
    ownerMocks),
  // 2) create member_history
  tc('ALLOW', 'create', `${DOCS}/member_history/HIST1`,
    { userId: TARGET, type: 'role', organizationId: ORG, previousRoleId: 'member',
      newRoleId: 'adminManager', actorUserId: OWNER }, null, ownerMocks),
  // 3) create notification للهدف
  tc('ALLOW', 'create', `${DOCS}/users/${TARGET}/notifications/membershipRoleChanged_${TARGET}`,
    { notificationId: `membershipRoleChanged_${TARGET}`, userId: TARGET,
      organizationId: ORG, status: 'unread', createdByUserId: OWNER,
      type: 'membershipRoleChanged' }, null, notifMocks),
];

async function main() {
  const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT;
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (projectId !== EXPECTED_PROJECT_ID || projectId === 'alrahmat-console') {
    throw new Error(`Refusing projectId=${projectId || 'missing'}. Expected ${EXPECTED_PROJECT_ID}.`);
  }
  if (process.env.ALLOW_REMOTE_RULESET_QA !== 'true') {
    throw new Error('Remote TestRuleset QA is disabled. Use Emulator tests for this round.');
  }
  if (!credPath || !fs.existsSync(credPath)) {
    throw new Error('An explicit demo-only GOOGLE_APPLICATION_CREDENTIALS path is required.');
  }
  const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
  if (sa.project_id !== EXPECTED_PROJECT_ID) {
    throw new Error(`Credential project mismatch: ${sa.project_id || 'missing'}.`);
  }
  const source = fs.readFileSync(RULES_PATH, 'utf8');

  const auth = new GoogleAuth({
    credentials: sa,
    scopes: ['https://www.googleapis.com/auth/firebase', 'https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const token = (await client.getAccessToken()).token;

  const res = await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${sa.project_id}:test`,
    {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: { files: [{ name: 'firestore.rules', content: source }] },
        testSuite: { testCases },
      }),
    },
  );
  const json = await res.json();
  if (!res.ok) { console.error('HTTP', res.status, JSON.stringify(json, null, 2)); return; }
  const labels = ['membership.update', 'member_history.create', 'notification.create'];
  (json.testResults || []).forEach((r, i) => {
    console.log(`\n[${labels[i]}] state=${r.state} (متوقّع ALLOW=SUCCESS)`);
    if (r.state !== 'SUCCESS') {
      if (r.debugMessages) console.log('  debug:', JSON.stringify(r.debugMessages));
      if (r.expressionReports) console.log('  reports:', JSON.stringify(r.expressionReports).slice(0, 500));
      if (r.errorPosition) console.log('  errorPos:', JSON.stringify(r.errorPosition));
    }
  });
}
main().catch((e) => {
  console.error('ERR', e.message);
  process.exitCode = 1;
});
