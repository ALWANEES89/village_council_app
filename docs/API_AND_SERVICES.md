# API_AND_SERVICES — الخدمات والمستودعات (طبقة الوصول للبيانات)

> لا يوجد REST API خارجي؛ "الـ API" هو Firebase SDK عبر طبقة Services/Repositories في `lib/data/`. كلها org-scoped ما لم يُذكر خلاف ذلك.

## 1. Services (`lib/data/services/`)
| الخدمة | المسؤولية |
|---|---|
| `AuthService` | تسجيل الدخول (هاتف+كلمة مرور)، `currentUser`, `updateFcmToken`، جلب العضو الحالي |
| `FirestoreService` | استعلامات عامة/إحصائيات، إنشاء معاملة إيصال org-scoped، تحديث حالة الدفع |
| `StorageService` | رفع الإيصالات/الصور إلى Storage (مسار org-scoped) |
| `NotificationService` | تهيئة FCM، أذونات، مزامنة التوكن |
| `OrganizationSeedService` | بذر المجلس الأول + الأدوار الافتراضية (DEC-007) |

## 2. Repositories (`lib/data/repositories/` + features)
| المستودع | المجموعة | ملاحظات |
|---|---|---|
| `UserRepository` | `users` | ملف الشخص + تفضيلات |
| `MembershipRepository` | `organizations/*/memberships` | collectionGroup مقيّد بـ `userId`؛ fallback per-org |
| `OrganizationRepository` | `organizations` | إنشاء/تعديل/أرشفة/إصلاح بنية؛ `update` يكتب `updatedBy` |
| `RoleRepository` | `organizations/*/roles` | `create/update` يكتبان `updatedBy`/`createdBy` |
| `PlatformAdminRepository` | `platform_admins` | فحص superAdmin، تفضيلات الإشعارات |
| `FinancialReceiptRepository` | `organizations/*/transactions` | اعتماد/رفض الإيصال (معاملة) |
| `MembershipRequestRepository` | `organizations/*/membership_requests` | تقديم/اعتماد/رفض/إلغاء |
| `MemberManagementRepository` | `organizations/*/memberships` + `member_history` | تغيير الدور/الحالة/النقل/الإزالة (يكتب `updatedBy`) |
| `BookingRepository` | `organizations/*/bookings` | إنشاء/بثّ الحجوزات |
| `NotificationRepository` | `users/*/notifications` | إشعارات داخلية + إخطار المراجعين |

## 3. المزوّدات (`lib/providers/app_providers.dart`)
- خدمات ومستودعات كـ `Provider`.
- `adminAccessProvider` (FutureProvider<AdminAccess>) — الصلاحيات المشتقّة.
- `organizationContextProvider` — المجلس المختار الحالي.
- `activeUserMembershipsProvider(uid)` — عضويات المستخدم النشطة (للاختيار).
- `authStateProvider` — حالة المصادقة.
- مزوّدات وحدة Audit في `lib/features/audit/providers/audit_providers.dart`.

## 4. توقيعات مهمّة تحمل الفاعل (Actor)
لضمان سجل تدقيق دقيق، هذه الدوال تمرّر/تكتب `actorUserId`:
- `RoleRepository.create/update({..., actorUserId})` → `updatedBy`/`createdBy`.
- `OrganizationRepository.update/setArchived({..., actorUserId})` → `updatedBy`.
- `MemberManagementRepository.changeRole/suspend/activate/remove(actorUserId)` → `updatedBy`/`removedBy`.
- `FinancialReceiptRepository.approve/reject(reviewedBy)` → `reviewedBy`.
- `MembershipRequestRepository.approve/reject(reviewedBy)` → `reviewedBy`.

## 5. مبادئ إلزامية للخدمات/المستودعات الجديدة
1. اعمل ضمن `organizationId` صريح (من `organizationContextProvider`).
2. مرّر `actorUserId` لأي عملية حسّاسة (لتغذية سجل التدقيق).
3. أي استعلام collectionGroup: قيّده بـ `where('userId', == currentUser)`.
4. لا تكتب audit من العميل (خادمي فقط).
5. حدّث هذا الملف عند إضافة خدمة/مستودع.
