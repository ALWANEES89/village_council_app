/**
 * bootstrap_system_owner.js — تثبيت المالك الأعلى (system_owner) لمرة واحدة.
 * ------------------------------------------------------------------------
 * يستخدم Firebase Admin SDK بصلاحية Service Account.
 * لا يُشغّل من التطبيق ولا يسمح للتطبيق بإنشاء system_owner من الواجهة.
 *
 * التشغيل:
 *   PowerShell:
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\serviceAccount.json"
 *
 *   معاينة:
 *   node .\scripts\bootstrap_system_owner.js --dry-run
 *
 *   تنفيذ:
 *   node .\scripts\bootstrap_system_owner.js
 *
 *   إذا ظهر تعارض في العضوية 001:
 *   node .\scripts\bootstrap_system_owner.js --confirm-transfer
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ── الثوابت ────────────────────────────────────────────────────────────────
const EXPECTED_PROJECT_ID = 'alrahmat-console';
const ORGANIZATION_ID = 'rahmat_general_council';
const OWNER_UID = '3PpbBzCACsh8PphpbN5Gp1keolF3';

const DRY_RUN = process.argv.includes('--dry-run');
const CONFIRM_TRANSFER =
  process.argv.includes('--confirm-transfer') ||
  process.env.CONFIRM_TRANSFER === '1' ||
  process.env.CONFIRM_TRANSFER === 'true';

function fail(message) {
  console.error(`\n❌ ${message}\n`);
  process.exit(1);
}

// ── تحميل Firebase Admin SDK بطريقة Modular ────────────────────────────────
let initializeApp;
let applicationDefault;
let getApps;
let getFirestore;
let FieldValue;

function requireFromFunctions(moduleName) {
  return require(path.join(
    __dirname,
    '..',
    'functions',
    'node_modules',
    ...moduleName.split('/')
  ));
}

try {
  ({ initializeApp, applicationDefault, getApps } = require('firebase-admin/app'));
  ({ getFirestore, FieldValue } = require('firebase-admin/firestore'));
} catch (_) {
  try {
    ({ initializeApp, applicationDefault, getApps } = requireFromFunctions('firebase-admin/app'));
    ({ getFirestore, FieldValue } = requireFromFunctions('firebase-admin/firestore'));
  } catch (__) {
    fail(
      'firebase-admin غير مثبّت أو غير قابل للتحميل.\n' +
        'شغّل من مجلد المشروع:\n' +
        'npm i firebase-admin --no-save'
    );
  }
}

// ── قراءة projectId من ملف Service Account أو البيئة ───────────────────────
function resolveProjectId() {
  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (credentialsPath && fs.existsSync(credentialsPath)) {
    try {
      const serviceAccount = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
      if (serviceAccount.project_id) return serviceAccount.project_id;
    } catch (error) {
      fail(
        'تعذّر قراءة ملف Service Account JSON.\n' +
          `المسار الحالي:\n${credentialsPath}\n\n` +
          `الخطأ:\n${error.message}`
      );
    }
  }

  return (
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    null
  );
}

function printableTimestamp() {
  return '[serverTimestamp]';
}

function printObject(title, data) {
  const safe = {};
  for (const [key, value] of Object.entries(data)) {
    if (key === 'createdAt' || key === 'updatedAt' || key.endsWith('At')) {
      safe[key] = printableTimestamp();
    } else {
      safe[key] = value;
    }
  }

  console.log(title);
  console.log(JSON.stringify(safe, null, 2));
}

async function main() {
  const projectId = resolveProjectId();

  if (!projectId) {
    fail(
      'تعذّر تحديد projectId.\n' +
        'تأكد أنك ضبطت GOOGLE_APPLICATION_CREDENTIALS على ملف Service Account الصحيح.'
    );
  }

  if (projectId !== EXPECTED_PROJECT_ID) {
    fail(
      `المشروع الحالي "${projectId}" لا يطابق المشروع المطلوب "${EXPECTED_PROJECT_ID}".\n` +
        'تم إيقاف التنفيذ لحماية البيانات.'
    );
  }

  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    fail(
      'المتغير GOOGLE_APPLICATION_CREDENTIALS غير مضبوط.\n' +
        'مثال PowerShell:\n' +
        '$env:GOOGLE_APPLICATION_CREDENTIALS="C:\\path\\to\\serviceAccount.json"'
    );
  }

  if (!fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
    fail(
      'ملف Service Account غير موجود في المسار المحدد:\n' +
        process.env.GOOGLE_APPLICATION_CREDENTIALS
    );
  }

  if (!getApps().length) {
    initializeApp({
      credential: applicationDefault(),
      projectId,
    });
  }

  const db = getFirestore();
  const now = FieldValue.serverTimestamp();

  console.log('──────────────────────────────────────────────');
  console.log(`المشروع        : ${projectId}`);
  console.log(`المجلس         : ${ORGANIZATION_ID}`);
  console.log(`مالك مستهدف    : ${OWNER_UID}`);
  console.log(`الوضع          : ${DRY_RUN ? 'DRY-RUN - معاينة فقط' : 'APPLY - كتابة فعلية'}`);
  console.log('──────────────────────────────────────────────\n');

  const organizationRef = db.collection('organizations').doc(ORGANIZATION_ID);

  const membershipRef = organizationRef
    .collection('memberships')
    .doc(OWNER_UID);

  const membershipsCol = organizationRef.collection('memberships');

  const platformAdminRef = db
    .collection('platform_admins')
    .doc(OWNER_UID);

  // 1) التأكد أن عضوية المالك موجودة
  const membershipSnap = await membershipRef.get();

  if (!membershipSnap.exists) {
    fail(
      `مستند العضوية غير موجود:\n` +
        `organizations/${ORGANIZATION_ID}/memberships/${OWNER_UID}\n\n` +
        'لا يمكن تثبيت المالك الأعلى قبل وجود عضويته.'
    );
  }

  const currentMembershipData = membershipSnap.data() || {};

  // 2) فحص تعارض رقم العضوية 001
  const [byMemberNumber, byMemberNo] = await Promise.all([
    membershipsCol.where('memberNumber', '==', '001').get(),
    membershipsCol.where('memberNo', '==', '001').get(),
  ]);

  const conflictIds = new Set();

  for (const doc of byMemberNumber.docs) {
    if (doc.id !== OWNER_UID) conflictIds.add(doc.id);
  }

  for (const doc of byMemberNo.docs) {
    if (doc.id !== OWNER_UID) conflictIds.add(doc.id);
  }

  const hasConflict = conflictIds.size > 0;

  if (hasConflict && !CONFIRM_TRANSFER) {
    console.log('⚠️  يوجد تعارض في رقم العضوية 001.');
    console.log(`UID المالك المطلوب : ${OWNER_UID}`);
    console.log(`UID يحمل 001 حاليًا : ${[...conflictIds].join(', ')}`);
    console.log('');
    console.log('لم يتم تنفيذ أي كتابة.');
    console.log('');
    console.log('إذا تريد نقل رقم العضوية 001 إلى المالك الأعلى شغّل:');
    console.log('node .\\scripts\\bootstrap_system_owner.js --confirm-transfer');
    process.exit(2);
  }

  // 3) تجهيز صلاحيات المالك الأعلى
  const permissionsSnapshot = [
    'fullAccess',
    'adminDashboard',
    'members.manage',
    'roles.manage',
    'receipts.review',
    'payments.manage',
    'settings.manage',
    'audit.view',
    'council.transfer',
    'members.suspend',
    'members.cancel',
  ];

  const platformAdminSnap = await platformAdminRef.get();
  const platformAdminExists = platformAdminSnap.exists;

  const platformAdminData = {
    uid: OWNER_UID,
    role: 'system_owner',
    status: 'active',
    fullAccess: true,
    updatedBy: 'bootstrap',
    updatedAt: now,
  };

  if (!platformAdminExists) {
    platformAdminData.createdAt = now;
    platformAdminData.createdBy = 'bootstrap';
  }

  const membershipData = {
    userId: OWNER_UID,
    memberNumber: '001',
    role: 'owner',
    roleId: 'system_owner',
    status: 'active',
    isPrimaryOwner: true,
    permissionsSnapshot,
    roleLabelArabic: 'المالك الأعلى',
    statusLabelArabic: 'نشط',
    updatedBy: 'bootstrap',
    updatedAt: now,
  };

  // نحافظ على بعض الحقول الموجودة إن كانت موجودة
  if (currentMembershipData.displayName && !membershipData.displayName) {
    membershipData.displayName = currentMembershipData.displayName;
  }

  if (currentMembershipData.fullName && !membershipData.fullName) {
    membershipData.fullName = currentMembershipData.fullName;
  }

  if (currentMembershipData.phone && !membershipData.phone) {
    membershipData.phone = currentMembershipData.phone;
  }

  // 4) Dry run
  if (DRY_RUN) {
    console.log('✅ DRY-RUN — لم يتم كتابة أي بيانات.\n');

    printObject(`سيتم إنشاء/تحديث: platform_admins/${OWNER_UID}`, platformAdminData);
    console.log('');
    printObject(
      `سيتم تحديث: organizations/${ORGANIZATION_ID}/memberships/${OWNER_UID}`,
      membershipData
    );

    if (hasConflict) {
      console.log('');
      console.log(`سيتم تفريغ رقم 001 من الحسابات التالية: ${[...conflictIds].join(', ')}`);
    }

    console.log('\nانتهت المعاينة بنجاح.');
    console.log('إذا كل شيء صحيح، شغّل:');
    console.log('node .\\scripts\\bootstrap_system_owner.js');

    if (hasConflict) {
      console.log('');
      console.log('وبسبب وجود تعارض 001، شغّل بدلًا من ذلك:');
      console.log('node .\\scripts\\bootstrap_system_owner.js --confirm-transfer');
    }

    return;
  }

  // 5) الكتابة الفعلية Batch
  const batch = db.batch();

  if (hasConflict && CONFIRM_TRANSFER) {
    for (const conflictId of conflictIds) {
      batch.set(
        membershipsCol.doc(conflictId),
        {
          memberNumber: '',
          memberNo: '',
          memberNumberRelinquishedAt: now,
          memberNumberRelinquishedBy: 'bootstrap',
        },
        { merge: true }
      );
    }
  }

  batch.set(platformAdminRef, platformAdminData, { merge: true });
  batch.set(membershipRef, membershipData, { merge: true });

  await batch.commit();

  console.log('✅ تم تثبيت المالك الأعلى بنجاح.\n');
  console.log('التقرير:');
  console.log(`projectId              : ${projectId}`);
  console.log(`organizationId         : ${ORGANIZATION_ID}`);
  console.log(`ownerUid               : ${OWNER_UID}`);
  console.log(`platform_admins        : ${platformAdminExists ? 'تم التحديث' : 'تم الإنشاء'}`);
  console.log('membership             : تم التحديث merge');
  console.log(`permissionsSnapshot    : ${JSON.stringify(permissionsSnapshot)}`);
  console.log(
    `تعارض memberNumber 001 : ${
      hasConflict ? `نعم — تم نقله من [${[...conflictIds].join(', ')}]` : 'لا'
    }`
  );

  console.log('\nالخطوة التالية:');
  console.log('flutter analyze');
  console.log('firebase deploy --only firestore:rules');
}

main().catch((error) => {
  console.error('\n❌ فشل السكربت:');
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});