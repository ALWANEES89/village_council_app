# وثائق المشروع — مجلس الرحمات (منصّة Multi-Tenant)

> **قرار المشروع النهائي:** منصّة SaaS متعددة المؤسسات (Multi-Tenant) تدير عشرات/مئات المجالس عبر Firebase Project واحد مع عزل كامل. راجع `SYSTEM_DECISIONS.md` (DEC-001).

## الفهرس
| الوثيقة | المحتوى |
|---|---|
| [PROJECT_ARCHITECTURE.md](PROJECT_ARCHITECTURE.md) | الهيكل المعماري الكامل + المبادئ الإلزامية |
| [MULTI_TENANT_ARCHITECTURE.md](MULTI_TENANT_ARCHITECTURE.md) | تعدّد المؤسسات وآليات عزل المجالس |
| [DATABASE_STRUCTURE.md](DATABASE_STRUCTURE.md) | كل Collections و Subcollections والحقول |
| [FIREBASE_SECURITY.md](FIREBASE_SECURITY.md) | المصادقة + التخزين + أفضل الممارسات |
| [FIRESTORE_RULES.md](FIRESTORE_RULES.md) | شرح قواعد الأمان ودوالها |
| [ROLES_AND_PERMISSIONS.md](ROLES_AND_PERMISSIONS.md) | نظام الأدوار والصلاحيات |
| [AUDIT_LOGS.md](AUDIT_LOGS.md) | سجل الأحداث الخادمي |
| [CLOUD_FUNCTIONS.md](CLOUD_FUNCTIONS.md) | الدوال الخادمية |
| [ORGANIZATION_BOOTSTRAP.md](ORGANIZATION_BOOTSTRAP.md) | إنشاء مجلس جديد |
| [API_AND_SERVICES.md](API_AND_SERVICES.md) | الخدمات والمستودعات |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | خطوات النشر |
| [PRE_DEPLOY_TEST_CHECKLIST.md](PRE_DEPLOY_TEST_CHECKLIST.md) | اختبار ما قبل النشر |
| [POST_DEPLOY_CHECKLIST.md](POST_DEPLOY_CHECKLIST.md) | تحقّق ما بعد النشر |
| [BACKUP_AND_RECOVERY.md](BACKUP_AND_RECOVERY.md) | النسخ الاحتياطي والاستعادة |
| [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) | دليل المطوّر + Workflow إضافة ميزة |
| [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) | تثبيت وإعداد بيئة التطوير |
| [USER_MANUAL.md](USER_MANUAL.md) | دليل المستخدم (العضو) |
| [ADMIN_MANUAL.md](ADMIN_MANUAL.md) | دليل المشرف |
| [CLIENT_IMPLEMENTATION_GUIDE.md](CLIENT_IMPLEMENTATION_GUIDE.md) | دليل تهيئة/تسليم مجلس للعميل |
| [ROADMAP.md](ROADMAP.md) | خارطة الطريق (تُحدَّث كل جلسة) |
| [SYSTEM_DECISIONS.md](SYSTEM_DECISIONS.md) | **مرجع القرارات المعمارية (إلزامي)** |
| [CHANGELOG.md](CHANGELOG.md) | سجل التغييرات |

> وثائق ترحيل سابقة: `TASK-005*_*.md` (بنية الهوية/الأجهزة/محرك الصلاحيات).

## الدستور والحوكمة (Documentation-First)
هذا المشروع **منصّة مؤسسية Multi-Tenant SaaS**. `docs/` هو **المرجع الرسمي الوحيد** — تُحدَّث الوثائق ولا تُنشأ من جديد. أي تعديل في الكود ينعكس تلقائياً: **الكود → الوثائق → ROADMAP → CHANGELOG → SYSTEM_DECISIONS (إن لزم)**. راجع `SYSTEM_DECISIONS.md` (DEC-011).

## المبادئ الإلزامية (ملخّص)
1. منصّة Multi-Tenant · 2. لا Hardcoded Organization (استثناء انتقالي: DEC-007) · 3. عزل بـ `organizationId` · 4. القواعد تعتمد `organizationId` · 5. الدوال ضمن نطاق المجلس · 6. Audit معزول لكل مجلس · 7. الصلاحيات للمجلس الحالي فقط · 8. الميزات الجديدة تعمل لعشرات المجالس دون تعديل كود · 9. Scalability/الأداء/الأمان من البداية · 10. توافق مستقبلي.

## تعريف "الميزة المكتملة"
لا تُعتبر مكتملة إلا بعد: تحديث الوثائق · تحديث `SYSTEM_DECISIONS` إن أثّرت على المعمارية · مراجعة Rules · مراجعة Cloud Functions · مراجعة Audit Logs · التأكد من عدم كسر Multi-Tenant.
