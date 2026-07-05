# BACKUP_AND_RECOVERY — النسخ الاحتياطي والاستعادة

> حماية بيانات منصّة متعددة المجالس. الهدف: استعادة موثوقة دون كسر العزل بين المجالس.

## 1. ما الذي يُنسخ احتياطياً؟
| العنصر | الأداة | الأولوية |
|---|---|---|
| Firestore (كل المجالس) | Managed Export / PITR | حرجة |
| Storage (الإيصالات/الصور) | GCS bucket backup | عالية |
| القواعد والفهارس والدوال | **Git** (الكود المصدري) | حرجة |
| إعدادات المشروع | توثيق يدوي | متوسطة |

## 2. Firestore — النسخ المُدار (Managed Export)
```bash
# تصدير كامل إلى GCS
gcloud firestore export gs://<BUCKET>/backups/$(date +%F) --project alrahmat-console

# تصدير مجموعات محدّدة (اختياري)
gcloud firestore export gs://<BUCKET>/backups/$(date +%F) \
  --collection-ids=organizations,users,platform_admins --project alrahmat-console
```
- **مجدول:** أنشئ جدولة يومية (Cloud Scheduler + Function، أو سياسة النسخ المُدارة في Console).
- **PITR (Point-in-Time Recovery):** فعّل الاستعادة الزمنية في Firestore (يحفظ حتى 7 أيام) لاستعادة دقيقة.

## 3. الاستعادة (Restore)
```bash
gcloud firestore import gs://<BUCKET>/backups/<DATE> --project alrahmat-console
```
> ⚠️ الاستيراد **يستبدل/يدمج** المستندات. اختبر على مشروع Staging أولاً. لا تستورد على الإنتاج دون خطة.

## 4. استعادة مجلس واحد فقط (Multi-Tenant)
- بما أن كل مجلس معزول تحت `organizations/{orgId}/`، يمكن تصدير/استيراد بياناته بانتقائية عبر مسار المجلس.
- **تحذير:** الاستيراد الانتقائي يجب ألا يمسّ مجالس أخرى؛ استخدم مساراً محدّداً وتحقّق قبل التنفيذ.
- بيانات مرتبطة خارج المجلس (`users`, `member_history`, `platform_admins`) قد تحتاج تنسيقاً — وثّق ذلك عند أي استعادة جزئية.

## 5. Storage
- فعّل **Object Versioning** على الـ bucket، أو انسخ دورياً إلى bucket نسخ احتياطي:
```bash
gsutil -m rsync -r gs://<APP_BUCKET> gs://<BACKUP_BUCKET>/$(date +%F)
```

## 6. الكود والبنية (الأهم للاستعادة السريعة)
- القواعد (`firestore.rules`, `storage.rules`)، الفهارس (`firestore.indexes.json`)، والدوال (`functions/`) **كلها في Git** — أعد نشرها فوراً عند الحاجة:
```bash
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```
- سجل الأحداث `audit_logs` نفسه دليل استرجاع لتسلسل العمليات عند التحقيق.

## 7. اختبار الاستعادة (إلزامي دورياً)
- [ ] كل ربع سنة: استعادة نسخة إلى Staging والتأكد من سلامة البيانات والعزل.
- [ ] التأكد أن القواعد المنشورة تحمي البيانات المستعادة.
- [ ] التأكد أن الدوال تعمل على البيانات المستعادة (سجل، إشعارات).

## 8. RPO / RTO (أهداف مقترحة)
- **RPO** (أقصى فقدان بيانات): ≤ 24 ساعة (نسخ يومي) أو ≤ دقائق (PITR).
- **RTO** (زمن الاستعادة): ساعات — نشر الكود من Git + استيراد أحدث نسخة.

## 9. قواعد إلزامية
- لا تحذف نسخاً احتياطية دون سياسة احتفاظ موثّقة.
- أي عملية استعادة على الإنتاج تُوثّق في `CHANGELOG.md`.
- لا تكسر عزل المجالس أثناء الاستعادة الجزئية.
