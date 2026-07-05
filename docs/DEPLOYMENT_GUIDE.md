# DEPLOYMENT_GUIDE — دليل النشر

> **قاعدة ذهبية:** انشر **Functions + Firestore Rules معاً**، وأصدر نسخة تطبيق محدّثة، لأن القواعد الجديدة تمنع كتابة `audit_logs` من العميل فيجب أن تكون الدوال حيّة أولاً. **لا تنشر على الإنتاج قبل اجتياز `PRE_DEPLOY_TEST_CHECKLIST.md`.**

## 0. المتطلبات
- Firebase CLI (`firebase --version`).
- صلاحية على المشروع `alrahmat-console`.
- Flutter SDK للبناء.

## 1. المصادقة واختيار المشروع
```bash
firebase login
firebase use alrahmat-console
```

## 2. تثبيت اعتماديات الدوال (أول مرة / عند تغييرها)
```bash
cd functions && npm install && cd ..
```

## 3. التحقق قبل النشر
```bash
# تحليل التطبيق
flutter analyze

# فحص صياغة الدوال
node --check functions/index.js
node --check functions/audit.js

# فحص القواعد بدون نشر (compile في السحابة)
firebase deploy --only firestore:rules --dry-run
```

## 4. النشر (الترتيب مهم)
```bash
# 1) الدوال أولاً (حتى يعمل السجل الخادمي قبل إغلاق كتابة العميل)
firebase deploy --only functions

# 2) القواعد (تُغلق كتابة audit_logs من العميل + إصلاحات التصعيد/العزل)
firebase deploy --only firestore:rules

# 3) الفهارس (إن تغيّرت)
firebase deploy --only firestore:indexes

# 4) قواعد التخزين (إن تغيّرت)
firebase deploy --only storage

# — أو معاً —
firebase deploy --only functions,firestore:rules,firestore:indexes,storage
```

## 5. بناء التطبيق
```bash
flutter build apk --release        # Android APK
# أو
flutter build appbundle --release  # Google Play
# أو المنصّة المستهدفة (ios/web/...)
```
> يجب إصدار النسخة التي **أزالت كتابة audit_logs من العميل وتمرّر actorUserId** قبل/مع نشر القواعد.

## 6. النطاقات (Scopes) المتاحة للنشر
| Scope | ما يُنشر |
|---|---|
| `functions` | كل Cloud Functions |
| `firestore:rules` | `firestore.rules` |
| `firestore:indexes` | `firestore.indexes.json` |
| `storage` | `storage.rules` |

## 7. التراجع (Rollback)
- **القواعد:** Firebase Console → Firestore → Rules → History → استعادة نسخة سابقة.
- **الدوال:** أعد نشر الإصدار السابق من الكود (`git`), أو احذف دالة معطوبة: `firebase functions:delete <name>`.
- **بيانات:** راجع `BACKUP_AND_RECOVERY.md`.

## 8. بعد النشر
اتبع `POST_DEPLOY_CHECKLIST.md` مباشرة.

## 9. ملاحظات Multi-Tenant
- القواعد والدوال **عامة معلّمة بالمسار**؛ نشرها مرة واحدة يخدم كل المجالس.
- لا حاجة لنشر خاص عند إضافة مجلس جديد (بيانات فقط).
