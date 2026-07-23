const admin = require("firebase-admin");

admin.initializeApp();

// سجل الأحداث الخادمي: مشغّلات تُنشئ audit_logs تلقائيًا عند العمليات الحسّاسة.
// تُصدَّر أدناه بعد تهيئة admin حتى تستخدم نفس التطبيق.
const auditTriggers = require("./audit");
for (const [name, handler] of Object.entries(auditTriggers)) {
  exports[name] = handler;
}

const financialFunctions = require("./financial");
for (const [name, handler] of Object.entries(financialFunctions)) {
  if (name !== "_test") exports[name] = handler;
}

const productionSecurity = require("./production_security");
for (const [name, handler] of Object.entries(productionSecurity)) {
  if (name !== "_test") exports[name] = handler;
}

const notificationFunctions = require("./notifications");
for (const [name, handler] of Object.entries(notificationFunctions)) {
  if (name !== "_test") exports[name] = handler;
}
