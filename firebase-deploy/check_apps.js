const crypto = require('crypto');
const fs = require('fs');

const KEY_FILE = 'C:\\Users\\alwan\\Downloads\\alrahmat-console-firebase-adminsdk-fbsvc-d7b2b0a8b7.json';
const PROJECT_ID = 'alrahmat-console';

function b64url(buf) {
  return buf.toString('base64').replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
}

async function getToken() {
  const key = JSON.parse(fs.readFileSync(KEY_FILE, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
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
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  return (await r.json()).access_token;
}

async function get(url, token) {
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  return r.json();
}

async function main() {
  const token = await getToken();

  const project = await get(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}`, token);
  console.log('PROJECT_NUMBER=' + project.projectNumber);
  console.log('STORAGE_BUCKET=' + (project.resources?.storageBucket || ''));
  console.log('MESSAGING_SENDER_ID=' + (project.resources?.messagingSenderId || ''));

  const android = await get(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps`, token);
  const androidApps = android.apps || [];
  console.log('ANDROID_COUNT=' + androidApps.length);
  androidApps.forEach(a => console.log('ANDROID_APP=' + JSON.stringify({ appId: a.appId, packageName: a.packageName })));

  const ios = await get(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps`, token);
  const iosApps = ios.apps || [];
  console.log('IOS_COUNT=' + iosApps.length);
  iosApps.forEach(a => console.log('IOS_APP=' + JSON.stringify({ appId: a.appId, bundleId: a.bundleId })));

  // Web apps (for API key)
  const web = await get(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/webApps`, token);
  const webApps = web.apps || [];
  webApps.forEach(a => console.log('WEB_APP=' + JSON.stringify({ appId: a.appId, apiKey: a.apiKey })));

  // Get API key from project config
  const cfg = await get(`https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/webApps/${webApps[0]?.name?.split('/').pop()}/config`, token);
  if (cfg.apiKey) console.log('API_KEY=' + cfg.apiKey);
}

main().catch(console.error);
