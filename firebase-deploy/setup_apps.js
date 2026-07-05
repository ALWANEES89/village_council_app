const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const KEY_FILE      = 'C:\\Users\\alwan\\Downloads\\alrahmat-console-firebase-adminsdk-fbsvc-d7b2b0a8b7.json';
const PROJECT_ID    = 'alrahmat-console';
const PROJECT_DIR   = path.resolve(__dirname, '..');
const ANDROID_PKG   = 'com.alrahmat.village_council';
const IOS_BUNDLE    = 'com.alrahmat.villageCouncil';
const PROJECT_NUM   = '501018693703';
const STORAGE_BUCKET = 'alrahmat-console.firebasestorage.app';

function b64url(buf) {
  return buf.toString('base64').replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
}
async function getToken() {
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
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=` + jwt,
  });
  return (await r.json()).access_token;
}

async function api(url, method, token, body) {
  const r = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, data };
}

// ── انتظار اكتمال العملية الـ async ──────────────────
async function waitForOperation(operationName, token) {
  for (let i = 0; i < 10; i++) {
    await new Promise(r => setTimeout(r, 2000));
    const { ok, data } = await api(
      `https://firebase.googleapis.com/v1beta1/${operationName}`,
      'GET', token
    );
    if (ok && data.done) return data.response;
  }
  return null;
}

// ── تسجيل تطبيق Android ──────────────────────────────
async function registerAndroid(token) {
  const { ok, data } = await api(
    `https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps`,
    'POST', token,
    { packageName: ANDROID_PKG, displayName: 'مجلس القرية Android' }
  );

  if (ok) {
    // operation async
    if (data.name && !data.appId) {
      const op = data.name.replace(/^projects\/[^/]+\//, '');
      const result = await waitForOperation(`projects/${PROJECT_ID}/${op}`, token);
      if (result?.appId) { console.log('   ✅ Android registered:', result.appId); return result.appId; }
    }
    if (data.appId) { console.log('   ✅ Android registered:', data.appId); return data.appId; }
  }

  if (data.error?.status === 'ALREADY_EXISTS') {
    const list = await api(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps`, 'GET', token);
    const app = list.data.apps?.find(a => a.packageName === ANDROID_PKG);
    if (app) { console.log('   ⏭️  Android exists:', app.appId); return app.appId; }
  }
  throw new Error(`Android registration: ${data.error?.message}`);
}

// ── تسجيل تطبيق iOS ──────────────────────────────────
async function registeriOS(token) {
  const { ok, data } = await api(
    `https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps`,
    'POST', token,
    { bundleId: IOS_BUNDLE, displayName: 'مجلس القرية iOS' }
  );

  if (ok) {
    if (data.name && !data.appId) {
      const op = data.name.replace(/^projects\/[^/]+\//, '');
      const result = await waitForOperation(`projects/${PROJECT_ID}/${op}`, token);
      if (result?.appId) { console.log('   ✅ iOS registered:', result.appId); return result.appId; }
    }
    if (data.appId) { console.log('   ✅ iOS registered:', data.appId); return data.appId; }
  }

  if (data.error?.status === 'ALREADY_EXISTS') {
    const list = await api(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps`, 'GET', token);
    const app = list.data.apps?.find(a => a.bundleId === IOS_BUNDLE);
    if (app) { console.log('   ⏭️  iOS exists:', app.appId); return app.appId; }
  }
  throw new Error(`iOS registration: ${data.error?.message}`);
}

// ── تحميل config ملف (base64) ─────────────────────────
async function downloadConfig(token, platform, appId) {
  await new Promise(r => setTimeout(r, 2000));
  const { ok, data } = await api(
    `https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/${platform}Apps/${appId}/config`,
    'GET', token
  );
  if (!ok) throw new Error(`${platform} config: ${data.error?.message}`);
  return Buffer.from(data.configFileContents, 'base64').toString('utf8');
}

// ── استخراج قيمة من google-services.json ─────────────
function extractAndroidApiKey(json) {
  try {
    return JSON.parse(json).client?.[0]?.api_key?.[0]?.current_key || '';
  } catch { return ''; }
}

// ── استخراج قيمة من plist ─────────────────────────────
function extractPlistValue(plist, key) {
  const m = plist.match(new RegExp(`<key>${key}<\\/key>\\s*<string>(.*?)<\\/string>`));
  return m?.[1] || '';
}

// ── توليد firebase_options.dart ───────────────────────
function buildFirebaseOptions(androidAppId, iosAppId, androidApiKey, iosApiKey, iosClientId) {
  return `// Generated by setup_apps.js
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '${androidApiKey}',
    appId: '${androidAppId}',
    messagingSenderId: '${PROJECT_NUM}',
    projectId: '${PROJECT_ID}',
    storageBucket: '${STORAGE_BUCKET}',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '${iosApiKey}',
    appId: '${iosAppId}',
    messagingSenderId: '${PROJECT_NUM}',
    projectId: '${PROJECT_ID}',
    storageBucket: '${STORAGE_BUCKET}',
    iosClientId: '${iosClientId}',
    iosBundleId: '${IOS_BUNDLE}',
  );
}
`;
}

// ── Main ──────────────────────────────────────────────
async function main() {
  console.log('🔐 Authenticating...');
  const token = await getToken();
  console.log('✅ Authenticated\n');

  console.log('📱 Registering apps...');
  const androidAppId = await registerAndroid(token);
  const iosAppId     = await registeriOS(token);

  console.log('\n📦 Downloading config files...');
  const androidJson = await downloadConfig(token, 'android', androidAppId);
  const iosPlist    = await downloadConfig(token, 'ios',     iosAppId);

  const androidApiKey = extractAndroidApiKey(androidJson);
  const iosApiKey     = extractPlistValue(iosPlist, 'API_KEY');
  const iosClientId   = extractPlistValue(iosPlist, 'CLIENT_ID');

  console.log('   Android API Key:', androidApiKey ? '✅' : '⚠️ empty');
  console.log('   iOS API Key:',     iosApiKey     ? '✅' : '⚠️ empty');

  // ── حفظ الملفات ──────────────────────────────────
  console.log('\n💾 Writing files...');

  const androidDir = path.join(PROJECT_DIR, 'android', 'app');
  fs.mkdirSync(androidDir, { recursive: true });
  fs.writeFileSync(path.join(androidDir, 'google-services.json'), androidJson);
  console.log('   ✅ android/app/google-services.json');

  const iosDir = path.join(PROJECT_DIR, 'ios', 'Runner');
  fs.mkdirSync(iosDir, { recursive: true });
  fs.writeFileSync(path.join(iosDir, 'GoogleService-Info.plist'), iosPlist);
  console.log('   ✅ ios/Runner/GoogleService-Info.plist');

  fs.writeFileSync(
    path.join(PROJECT_DIR, 'lib', 'firebase_options.dart'),
    buildFirebaseOptions(androidAppId, iosAppId, androidApiKey, iosApiKey, iosClientId)
  );
  console.log('   ✅ lib/firebase_options.dart');

  console.log('\n' + '═'.repeat(52));
  console.log('🎉 DONE! All Firebase files generated.');
  console.log('═'.repeat(52));
  console.log(`Android App ID   : ${androidAppId}`);
  console.log(`iOS App ID       : ${iosAppId}`);
  console.log(`Project ID       : ${PROJECT_ID}`);
  console.log(`Messaging Sender : ${PROJECT_NUM}`);
  console.log(`Storage Bucket   : ${STORAGE_BUCKET}`);
  console.log('═'.repeat(52));
  console.log('\n⚠️  Last step: enable Phone Auth in Firebase Console');
  console.log('   Authentication → Sign-in method → Phone → Enable');
}

main().catch(err => {
  console.error('\n❌ Error:', err.message);
  process.exit(1);
});
