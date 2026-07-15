# قاعدة البيانات

## المجموعات الرئيسية
- organizations
- memberships
- membership_requests
- roles
- settings
- financial_profile
- transactions
- bookings
- announcements
- events
- rentals
- rental_resources
- audit_logs
- platform_admins
- organizations/{organizationId}/financial_settings
- organizations/{organizationId}/subscription_plans
- organizations/{organizationId}/member_accounts
- organizations/{organizationId}/member_directory
- organizations/{organizationId}/charges
- organizations/{organizationId}/transactions
- organizations/{organizationId}/financial_notification_outbox

## قرار مالي V1
- جميع المبالغ الجديدة أعداد صحيحة بالبيسة (`*Baisa`).
- الإيصال الجماعي يوزع عبر `allocations` وتنفذ الموافقة خادميًا داخل Firestore transaction.
- `idempotencyKey`/معرّف المستند الثابت يمنع تكرار رسوم الاشتراك للفترة نفسها.
- مجموعتا `payments` و`transactions` القديمتان تبقيان للقراءة المتوافقة أثناء الترحيل.
- إشعارات الإيصالات المالية تُكتب أولًا داخل `financial_notification_outbox` في المعاملة المالية نفسها، ثم ينقلها trigger خادمي قابل لإعادة المحاولة إلى `users/{userId}/notifications/{notificationId}`. معرّف الإشعار ثابت لمنع التسليم المكرر.

## قاعدة التحديث
لا تضف حقولًا أو مجموعات هنا قبل التحقق من الكود وFirestore Rules.
