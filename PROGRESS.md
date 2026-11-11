# PROGRESS — AgentPhone

فرع من مشروع MIT: `Eslamasabry/opencode-mobile-next` (Flutter + Kotlin، تطبيق
`io.github.eslamasabry.opencode_mobile`). الهدف: نسخة باسم **AgentPhone**،
بدون Firebase، بأذونات أقل، وبـ «Computer panel».

**قاعدة ذهبية:** لا نبني ما هو موجود. نُعدّل، ونضيف الناقص فقط.

---

## (done) — تم إنجازه

**تدقيق وتحقق**
- التحقق من 30 «hint» على مواصفة OpenCode v2 (139 path) وعلى السيرفر المحلي v2.1.1 (119 path):
  27 hint صحيحة؛ 3 (`client-mcp`, `usage/limits`, `fs/watch`) تحتاج `opencode2` أحدث.
- قراءة `AndroidManifest.xml` + `build.gradle.kts` + `pubspec.yaml` + CI من المنبع.

**الهوية (Phase 0)**
- `applicationId` و`namespace` = `io.github.agentphone.app`، حزمة Kotlin = نفس المسار،
  حزمة Dart = `agentphone`، مخطط الروابط = `agentphone://`، اسم التطبيق = AgentPhone.
- أيقونة launcher جديدة مرسومة من الصفر (`tool/branding/make_icon.py`، بلا صور خارجية).
- `PRIVACY.md` و`README.md` جديدان للفرع، ونص «غير مرتبط» في شاشة About.

**بلا Firebase (Phase 0/1)**
- حذف حزم Dart الأربع، وحذف pluginَي Gradle، وحذف بيانات الـ metadata من المانيفست،
  وحذف محوّلات Firebase الثلاثة، وتوصيل `NoOpTelemetryAdapter` دائماً.
- نسخ Telemetry في كل اللغات تعكس الحقيقة: لا يُجمع ولا يُرسل شيء.
- `THIRD_PARTY_NOTICES.md` فيه إشعار PRoot (GPL) + نص GPL v2 كامل.

**الأذونات (قرار المستخدم 3)**
- المسموحة فقط: INTERNET, POST_NOTIFICATIONS, FOREGROUND_SERVICE (+ specialUse/dataSync),
  WAKE_LOCK, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, USE_BIOMETRIC.
- المحذوفة: CAMERA, REQUEST_INSTALL_PACKAGES, MANAGE_EXTERNAL_STORAGE,
  READ/WRITE_EXTERNAL_STORAGE, RECORD_AUDIO, SCHEDULE_EXACT_ALARM,
  RECEIVE_BOOT_COMPLETED, ACCESS_NETWORK_STATE, POST_PROMOTED_NOTIFICATIONS.
- الميزات المرتبطة أُطفئت داخل نموذج القدرات (`supportsVoice/CodePush/QrPairing = false`)
  وفي Kotlin (ماسح QR، المسجّل الصوتي، التخزين المشترك، تثبيت APK، المستقبِلات، الترقية).

**بلا Shorebird (قرار 1)**
- حذف `shorebird_code_push` و`shorebird.yaml`، والتصدير صار للـ stub دائماً.

**لوحة Computer (Phase 2)**
- `lib/domain/computer_panel.dart` + `lib/ui/panels/computer_panel.dart`:
  أربع تبويبات، ثلاث حالات، الأمر الكامل + المجلد + الوقت + رمز الخروج + المخرجات،
  الأوامر الخطيرة مُعلَّمة، كل نص يمرّ على `KitRedact`، وزر «تولَّ الأمر».
- تُفتح من الشريط العلوي للمحادثة.

**حدّ تكلفة المهمة (Phase 3)**
- `lib/state/task_cost_limit.dart`: حدّ بالدولار لكل ملف تعريف خادم، محفوظ على الجهاز فقط.
- `Usage screen` صف «حدّ المهمة الواحدة»؛ و`session.usage.updated` يقارن التكلفة الحية
  ويوقف الجري عند التجاوز (قطع قاطع).

**الأمان (Phase 1/3)**
- `lib/domain/permission_risk.dart`: sudo/rm -rf/تثبيت/تنزيل/force push/كتابة خارج
  المشروع ⇒ تُسأل دائماً، حتى مع الموافقة التلقائية.
- لا أسرار في المستودع (فحص آلي)، المفتاح خارج المستودع، البناء release بـ R8.

**البنية والتسليم**
- `.github/workflows/agentphone-android.yml`: analyze + test + format + البوابات +
  بناء APK موقّع arm64-v8a/x86_64 + Release مع SHA256SUMS.
- `tool/keystore/make_keystore.sh` (PKCS12 عبر openssl، بلا JDK) + `tool/release/push_and_build.sh`.
- `tool/verify/*`: 7 بوابات تفشل عند أي مخالفة.

**الفحص**
- `dart analyze` (Dart 3.13.2 + Flutter 3.47.2): **No issues found** على 3200+ ملف.
- كل بوابات `tool/verify/verify_all.py` تمرّ.

## (in progress) — قيد التنفيذ

- الرفع إلى GitHub والبناء: عائق تسجيل الدخول (BLOCKERS B1).
- `flutter test` لم يُشغَّل على الجوال (لا محرك اختبار لـ ARM64) — يعمل في CI.

## (next) — التالي

1. تفويض GitHub (أنت) ← `bash tool/release/push_and_build.sh`.
2. أول build أخضر ⇒ إصلاح أي اختبار فاشل (خطأ واحد لكل محاولة، 5 محاولات كحد أقصى).
3. `client-mcp` عند ترقية `opencode2` داخل بيئة التطبيق ⇒ تبويب المتصفح التفاعلي.
4. حدّ تكلفة لكل مهمة مع قطع قاطع (يحتاج بوابة LLM داخل التطبيق).

## (known issues) — مشاكل معروفة

- لا APK حتى الآن (لا يوجد رابط بناء أخضر).
- `flutter test` غير مُشغَّل محلياً ⇒ احتمال وجود اختبار واحد فاشل في أول build.
- حذف اختبار المنبع `test/scheduled_prompt_standard_test.dart` (كان يشير إلى `widgetbook/`
  غير الموجود في المستودع أصلاً) ومجلد iOS (التطبيق أندرويد فقط).

## (decisions) — قرارات

1. Flutter مستقر 3.47.2، بلا Shorebird. 2. حذف Firebase بالكامل.
3. 8 أذونات فقط. 4. التوقيع PKCS12 خارج المستودع. 5. لا ترقية لـ `opencode2` في بيئة هذه الجلسة.
6. البناء = GitHub Actions فقط. 7. `applicationId` مختلف عن الأصلي.
8. `dart format` يُفحص على الملفات التي يغيّرها الدفع فقط (المستودع الأصلي ليس بالصيغة الجديدة).
