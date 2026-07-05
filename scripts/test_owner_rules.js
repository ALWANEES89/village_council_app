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
const FALLBACK_KEY = path.join(PROJECT_ROOT, 'local_keys', 'alrahmat-service-account.json');
const RULES_PATH = path.join(PROJECT_ROOT, 'firestore.rules');

const OWNER = '3PpbBzCACsh8PphpbN5Gp1keolF3';
const ORG = 'JDxPUEmnPN3tYMyGEVcp';
const TARGET = 'targetMemberUid';
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
  const credPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS &&
    fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS))
    ? process.env.GOOGLE_APPLICATION_CREDENTIALS : FALLBACK_KEY;
  const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'));
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
main().catch((e) => console.error('ERR', e));
