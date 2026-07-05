# ROADMAP — خارطة الطريق

> تُحدَّث **كل جلسة**. الحالات: ✅ Completed · 🔵 In Progress · ⚪ Planned · ❌ Cancelled. كل بند يحمل تاريخ الإنجاز ورقم الإصدار المرتبط. الإصدار الحالي غير المنشور: **Unreleased (2026-07-03)**.

## ✅ Completed
| البند | التاريخ | الإصدار |
|---|---|---|
| بنية Multi-Organization (models, repositories, screens) | 2026-07 | Unreleased |
| إصلاح تصعيد صلاحيات العضوية (roles.manage) — DEC-004 | 2026-07-03 | Unreleased |
| إغلاق تسريب العضويات بين المجالس (list/collectionGroup) — DEC-005 | 2026-07-03 | Unreleased |
| سلامة سجل الأحداث (actor spoofing) — audit/member_history | 2026-07-03 | Unreleased |
| سجل أحداث خادمي (8 Cloud Functions triggers) — DEC-003 | 2026-07-03 | Unreleased |
| إزالة كتابة audit من العميل + قفل append-only | 2026-07-03 | Unreleased |
| توثيق الفاعل (updatedBy/createdBy) في الأدوار/المجلس/البذر — DEC-008 | 2026-07-03 | Unreleased |
| شاشة Audit Viewer (للقراءة فقط، معزولة، فلاتر) | 2026-07-03 | Unreleased |
| التوثيق الرسمي الكامل في docs/ (23 ملفاً) | 2026-07-03 | Unreleased |
| اعتماد الدستور + الحوكمة Documentation-First — DEC-011 | 2026-07-03 | Unreleased |
| إصلاح رفض رفع الإيصال (Storage unauthorized) — ملكية = auth.uid | 2026-07-03 | Unreleased |
| إصلاح بنية storage.rules (نقل الدوال داخل match) لتصريف/نشر سليم | 2026-07-03 | Unreleased |
| المالك الأعلى System Owner + حماية المالك + نقل رئاسة المجلس (DEC-012) | 2026-07-03 | Unreleased |
| خدمة صلاحيات مركزية + محرّر صلاحيات + إصلاح اللوحة الذهبية + لون المالك | 2026-07-03 | Unreleased |

## 🔵 In Progress
| البند | ملاحظات |
|---|---|
| تجهيز الحزمة للنشر على Staging | بانتظار اجتياز PRE_DEPLOY_TEST_CHECKLIST |

## ⚪ Planned
| البند | القرار المرتبط | الأولوية |
|---|---|---|
| تقاعد بذر المجلس الأول الثابت → إنشاء يقوده superAdmin | DEC-007 | عالية (قبل توسّع إنتاجي) |
| تقاعد النظام القديم `members`/`isAdmin` (TASK-005 Phase 8) | DEC-006 | عالية |
| مهمة مزامنة snapshots عند تغيير صلاحيات دور (Reconciliation) | TASK-005.2 | عالية |
| ترحيل superAdmin إلى Custom Claims (أداء) | DEC-002 | متوسطة |
| توطين كامل ar/en | — | متوسطة |
| تقييد قراءة platform_admins/roles + حماية PII العضوية | FIREBASE_SECURITY §7 | متوسطة |
| النسخ الاحتياطي المجدول + PITR | BACKUP_AND_RECOVERY | متوسطة |
| تصدير سجل الأحداث (CSV/PDF) + pagination | — | منخفضة |
| شاشات إعدادات المجلس/البنك من الواجهة (مع updatedBy) | — | منخفضة |
| دعم Huawei للإشعارات (بديل FCM) | — | متوسطة |

## ❌ Cancelled
| البند | السبب | التاريخ |
|---|---|---|
| — | — | — |

## ملاحظات الحوكمة
- أي مهمة جديدة تُضاف هنا فور بدئها، وتُنقل بين الحالات مع التاريخ/الإصدار.
- عند إكمال مهمة: حدّث الكود + الوثائق + هذا الملف + `CHANGELOG.md` + `SYSTEM_DECISIONS.md` (إن لزم).
