# INSTALLATION_GUIDE — دليل التثبيت وإعداد البيئة

> إعداد بيئة تطوير كاملة للمنصّة. للنشر راجع `DEPLOYMENT_GUIDE.md`.

## 1. المتطلبات
| الأداة | النسخة | التحقق |
|---|---|---|
| Flutter SDK | مستقرّة حديثة | `flutter --version` |
| Dart | مضمّنة مع Flutter | `dart --version` |
| Firebase CLI | ≥ 13 | `firebase --version` |
| Node.js | 20 (للدوال) | `node --version` |
| Java JDK | 17 (Android) | `java -version` |
| Android Studio / Xcode | للمنصّات | — |
| FlutterFire CLI | أحدث | `dart pub global activate flutterfire_cli` |

## 2. جلب المشروع
```bash
git clone <REPO_URL>
cd village_council_app
flutter pub get
```

## 3. ربط Firebase
> المشروع: `alrahmat-console`. الملفات المولّدة (`lib/firebase_options.dart`, `google-services.json`) موجودة. لإعادة التوليد:
```bash
firebase login
flutterfire configure --project alrahmat-console
```

## 4. اعتماديات Cloud Functions
```bash
cd functions && npm install && cd ..
```

## 5. التشغيل (Development)
```bash
flutter devices          # عرض الأجهزة/المحاكيات
flutter run              # تشغيل على جهاز مختار
flutter run -d chrome    # الويب
flutter run -d windows   # ويندوز
```

## 6. المحاكي (Firebase Emulator Suite)
```bash
firebase emulators:start --only firestore,functions,auth,storage
```
- لاختبار القواعد والدوال والمحاولات السلبية بأمان دون لمس الإنتاج.

## 7. التحقق من سلامة البيئة
```bash
flutter analyze                 # يجب: No issues found
node --check functions/index.js
node --check functions/audit.js
flutter test                    # اختبارات الوحدات
```

## 8. المنصّات المدعومة
Android · iPhone (iOS) · Huawei · Web · Windows. مجلدات المنصّات موجودة (`android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`).
- **Huawei:** لا خدمات Google؛ استخدم مسار FCM المتوافق/بديل الإشعارات عند اللزوم (راجع `NotificationService`).

## 9. أخطاء شائعة
| العرض | الحل |
|---|---|
| `No currently active project` | `firebase use alrahmat-console` |
| فشل بناء Android (Gradle/JDK) | تأكّد JDK 17 و`gradle.properties` |
| `firebase login` مطلوب لـ dry-run | سجّل الدخول أولاً |
| مشاكل ترميز عربي | تأكّد UTF-8 في الملفات |

## 10. البنية بعد التثبيت
راجع `DEVELOPER_GUIDE.md` (بنية المشروع) و`DATABASE_STRUCTURE.md` (قاعدة البيانات).
