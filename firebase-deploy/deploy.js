const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PROJECT_ID  = 'alrahmat-console';
const KEY_FILE    = 'C:\\Users\\alwan\\Downloads\\alrahmat-console-firebase-adminsdk-fbsvc-d7b2b0a8b7.json';
const PROJECT_DIR = path.resolve(__dirname, '..');

// ── JWT من Service Account ────────────────────────────
function b64url(buf) {
  return buf.toString('base64').replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
}
async function getAccessToken() {
  const key = JSON.parse(fs.readFileSync(KEY_FILE, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(Buffer.from(JSON.stringify({ alg:'RS256', typ:'JWT' })));
  const p = b64url(Buffer.from(JSON.stringify({
    iss: key.client_email, sub: key.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
  })));
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(`${h}.${p}`);
  const jwt = `${h}.${p}.${b64url(sign.sign(key.private_key))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Auth: ${data.error_description}`);
  return data.access_token;
}

async function api(url, method, token, body) {
  const res = await fetch(url, {
    method,
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

// ── إنشاء Firestore Database إذا لم يوجد ─────────────
async function ensureFirestoreDatabase(token) {
  const check = await api(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)`,
    'GET', token
  );
  if (check.ok) {
    console.log('   Firestore database already exists');
    return true;
  }

  console.log('   Creating Firestore database...');
  const create = await api(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases?databaseId=(default)`,
    'POST', token,
    { type: 'FIRESTORE_NATIVE', locationId: 'me-central1' }
  );

  if (create.ok || create.data.error?.status === 'ALREADY_EXISTS') {
    console.log('   ✅ Firestore database created (me-central1)');
    // انتظر لحظة لينتهي الإنشاء
    await new Promise(r => setTimeout(r, 5000));
    return true;
  }

  console.error(`   ❌ Could not create database: ${create.data.error?.message}`);
  return false;
}

// ── نشر قواعد الأمان (Firestore أو Storage) ─────────
async function deployRules(token, rulesFile, releaseId) {
  const content = fs.readFileSync(path.join(PROJECT_DIR, rulesFile), 'utf8');

  // إنشاء ruleset
  const { ok, data } = await api(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/rulesets`,
    'POST', token,
    { source: { files: [{ content, name: rulesFile }] } }
  );
  if (!ok) return { success: false, reason: `Ruleset: ${data.error?.message}` };
  const rulesetName = data.name;

  const releaseName = `projects/${PROJECT_ID}/releases/${releaseId}`;

  // تحديث release موجود — التنسيق الصحيح: UpdateReleaseRequest في الـ body
  const patch = await api(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases/${releaseId}`,
    'PATCH', token,
    { release: { name: releaseName, rulesetName }, updateMask: 'rulesetName' }
  );
  if (patch.ok) return { success: true };

  // إنشاء release جديد إذا لم يوجد (404)
  if (patch.status === 404 || patch.data.error?.status === 'NOT_FOUND') {
    const post = await api(
      `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases`,
      'POST', token,
      { name: releaseName, rulesetName }
    );
    if (post.ok) return { success: true };
    return { success: false, reason: post.data.error?.message };
  }

  return { success: false, reason: patch.data.error?.message };
}

// ── اكتشاف Storage Bucket ─────────────────────────────
async function getStorageBucket(token) {
  const { ok, data } = await api(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases`,
    'GET', token
  );
  if (ok && data.releases) {
    const sr = data.releases.find(r => r.name.includes('/releases/firebase.storage/'));
    if (sr) {
      const parts = sr.name.split('/releases/firebase.storage/');
      if (parts[1]) return parts[1];
    }
  }
  return `${PROJECT_ID}.firebasestorage.app`;
}

// ── Composite Indexes ─────────────────────────────────
async function deployIndexes(token) {
  const config = JSON.parse(
    fs.readFileSync(path.join(PROJECT_DIR, 'firestore.indexes.json'), 'utf8')
  );
  let created = 0, existed = 0, failed = 0;

  for (const index of config.indexes) {
    const col = index.collectionGroup;
    const { ok, data } = await api(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/collectionGroups/${col}/indexes`,
      'POST', token,
      { queryScope: index.queryScope, fields: index.fields }
    );
    const label = index.fields.map(f => `${f.fieldPath}:${f.order[0]}`).join('+');
    if (ok) {
      console.log(`   ✅ ${col} [${label}]`);
      created++;
    } else if (data.error?.status === 'ALREADY_EXISTS') {
      console.log(`   ⏭️  ${col} [${label}] (already exists)`);
      existed++;
    } else {
      console.error(`   ❌ ${col} [${label}] — ${data.error?.message}`);
      failed++;
    }
  }
  return { created, existed, failed };
}

// ── Main ──────────────────────────────────────────────
async function main() {
  console.log('🔐 Authenticating...');
  const token = await getAccessToken();
  console.log('✅ Authenticated\n');

  const results = {};

  // 1. Firestore Database + Rules
  console.log('📋 Setting up Firestore...');
  const fsReady = await ensureFirestoreDatabase(token);
  if (!fsReady) {
    results.firestoreRules = '❌ Database creation failed';
    console.log(`   ${results.firestoreRules}`);
  } else {
    const r = await deployRules(token, 'firestore.rules', 'cloud.firestore');
    results.firestoreRules = r.success ? '✅ Rules deployed' : `❌ ${r.reason}`;
    console.log(`   ${results.firestoreRules}`);
  }

  // 2. Storage Rules
  console.log('\n📦 Deploying Storage rules...');
  const bucket = await getStorageBucket(token);
  console.log(`   Bucket: ${bucket}`);
  const sr = await deployRules(token, 'storage.rules', `firebase.storage/${bucket}`);
  results.storageRules = sr.success ? '✅ Deployed' : `❌ ${sr.reason}`;
  console.log(`   ${results.storageRules}`);

  // 3. Firestore Indexes
  console.log('\n🗂️  Creating Firestore composite indexes...');
  const ix = await deployIndexes(token);
  results.indexes = `✅ ${ix.created} created, ${ix.existed} existed, ${ix.failed} failed`;

  // ── Summary ──
  console.log('\n' + '═'.repeat(50));
  console.log('📊 DEPLOYMENT SUMMARY');
  console.log('═'.repeat(50));
  console.log(`Firestore Rules : ${results.firestoreRules}`);
  console.log(`Storage Rules   : ${results.storageRules}`);
  console.log(`Indexes         : ${results.indexes}`);
  console.log('═'.repeat(50));

  console.log('\n⏳ Indexes take 2-5 minutes to build in Firebase Console.');
}

main().catch(err => {
  console.error('\n❌ Fatal error:', err.message);
  process.exit(1);
});
