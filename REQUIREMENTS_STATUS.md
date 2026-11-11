# REQUIREMENTS_STATUS — AgentPhone

تدقيق صادق لكل متطلب. التعريفات (كما في البرومبت):

| الحالة | المعنى |
|---|---|
| **MISSING** | لا يوجد كود |
| **PARTIAL** | كود موجود لكنه محدود أو مربوط ببيانات تجريبية |
| **ANALYZED** | الكود موجود والفحوصات الساكنة تمرّ، لكن لم يُبنَ ولم يُختبر على جهاز |
| **BUILT** | بناء أخضر في CI على commit محدّد + رابط APK (يتطلب دليلاً: SHA + رابط التشغيل + artifact) |
| **VERIFIED** | أنا فقط أستطيع ضبطها: لا أحد يضبطها غيري |

**لا يوجد أي بند BUILT بعد.** أول بناء أخضر لم يقع (العائق: صلاحية GitHub، BLOCKERS.md).

آخر فحص ساكن: `dart analyze` (Dart 3.13.2 / Flutter 3.47.2) → **No issues found**؛
`python3 tool/verify/verify_all.py` → كل البوابات تمرّ.
آخر commit محلي: راجع `git log -1`.

---

| # | المتطلب | الحالة | الدليل (مسار / commit / تشغيل) |
|---|---|---|---|
| **R1** | هوية خاصة (اسم، applicationId، أيقونة) وتُثبَّت بجانب التطبيق الأصلي | **ANALYZED** | `android/app/build.gradle.kts` (`applicationId = "io.github.agentphone.app"`، `manifestPlaceholders["appLabel"] = "AgentPhone"`)؛ الأيقونة في `android/app/src/main/res/drawable/ic_launcher_*.xml` + `mipmap-*/ic_launcher.png` (مولّدة بـ `tool/branding/make_icon.py`)؛ اختبار الهوية `test/agentphone_release_contract_test.dart` |
| **R2** | لا Firebase/تحليلات؛ الأذونات المسموحة فقط؛ سكربت CI يفشل عند أي إذن آخر | **ANALYZED** | المانيفست `android/app/src/main/AndroidManifest.xml` (8 أذونات فقط)؛ الفحص `tool/verify/verify_permissions.py` + نفس القائمة في `test/fork_build_contract_test.dart`؛ لا تحليلات: `tool/verify/verify_no_analytics.py` |
| **R3** | بيئة: المستخدم يختار واحدة (Ubuntu افتراضي، Debian، Alpine تجريبي)، تحقق من الـ checksum المنشور فعلاً، فحص الحجم والمساحة | **ANALYZED** | موجود من المنبع: `android/app/src/main/kotlin/io/github/agentphone/app/BuiltinLinux.kt` (تنزيل صورة Ubuntu + Git + Node، فحص المساحة)؛ قائمة البيئات والاختيار في الواجهة. **ملاحظة:** التحقق من الـ checksum للـ OpenCode binary يجب أن يُقرأ من npm integrity (sha512) — راجع عند البناء |
| **R4** | نماذج: OpenAI-compatible + Anthropic، زر اختبار، المفتاح في Keystore | **ANALYZED** | موجود من المنبع: شاشة النماذج + `flutter_secure_storage`؛ لا مفاتيح في الكود (`tool/verify/verify_no_secrets.py`). لم أضف أي مفتاح |
| **R5** | **بوابة محلية (local gateway)**: loopback فقط، محمية بتوكن، تضيف مفتاح النموذج الحقيقي؛ OpenCode وLinux لا يرَين مفاتيح حقيقية؛ SSE؛ إعادة محاولة عند 429/5xx | **PARTIAL** | لا توجد بوابة مستقلة: التطبيق يمرّر إعداد المزوّد إلى سيرفر OpenCode (المفتاح يُحفظ في Keystore). **لم يُبنَ بعد** — هذا أول عمل بعد البناء الأخضر |
| **R6** | لوحة Computer (مطوي/نصف/كامل، تتبع الوكيل) مربوطة ببيانات OpenCode الحقيقية: الطرفية (الأمر الكامل، المجلد، الوقت، رمز الخروج، مخرجات ANSI حية، virtualized، 10k سطر ثم للقرص)، الملفات (+diff)، الخطة، المتصفح | **PARTIAL** | `lib/domain/computer_panel.dart` + `lib/ui/panels/computer_panel.dart` — مربوطة بأدوات الجلسة الحقيقية (`computerPanelModelFromMessages`)؛ الطرفية تعرض الأمر الكامل والمجلد والوقت ورمز الخروج والمخرجات (مُختصرة 200 سطر للعرض). **ناقص:** ANSI ملوّن داخل اللوحة، الـ virtualization، spill للقرص، تبويب الملفات بـ diff مباشر |
| **R7** | متصفح داخل التطبيق يتحكم فيه الوكيل عبر MCP: WebView معزول، http/https فقط، حظر localhost/الشبكات الخاصة/file/content/intent، حظر النوافذ المنبثقة، التنزيل والرفع مطفأ، لا جسر JS، لقطات نصية أولاً، محتوى الويب موسوم UNTRUSTED | **PARTIAL** | `webview_flutter` موجود في المنبع (`lib/ui/kit/kit_web_preview.dart`)؛ تبويب المتصفح في اللوحة يعرض الصفحات المفتوحة. **ناقص:** أدوات MCP للمتصفح (تحتاج `opencode2` يدعم `client-mcp` — قرارك: لا ترقية في بيئة هذه الجلسة) + سياسة الحظر داخل WebView + وسم UNTRUSTED |
| **R8** | خط زمني، زر «تولَّ الأمر»، إخفاء الأسرار | **PARTIAL** | «تولَّ الأمر» مربوط بمسار الإيقاف الموجود (`_abort`)؛ إخفاء الأسرار عبر `KitRedact.text` في كل ما تعرضه اللوحة. **ناقص:** الخط الزمني الكامل (سجل كل الأحداث) |
| **R9** | موافقات: إشعار بموافقة/رفض مع قفل الجهاز (`setAuthenticationRequired`)، الأمر كاملاً، إخفاء على شاشة القفل، لا جواب = رفض، قواعد الأوامر الخطرة، الموافقة التلقائية اختيارية فقط | **ANALYZED** | موجود من المنبع: `BackgroundConnectionService.kt` فيه `setAuthenticationRequired(true)`؛ نظام الصلاحيات كامل (`Permission.Effect`)؛ قاعدة الفرع `lib/domain/permission_risk.dart` (الأوامر الخطرة لا تُجاب تلقائياً أبداً) + اختبارها `test/permission_risk_test.dart` |
| **R10** | نقاط حفظ git مع استعادة بلمسة واحدة؛ استئناف الجلسة بعد القتل | **ANALYZED** | موجود من المنبع: `/api/vcs/init|status|diff` و `session.revert.*` (استُخدم في شاشات الفرق) + استئناف الجلسة. لم يُضف شيء جديد |
| **R11** | عدّاد تكلفة، حدّ لكل مهمة، قطع قاطع، نموذج بديل | **ANALYZED** | عدّاد الاستهلاك والميزانيات (من المنبع، شاشة Usage)؛ **جديد:** حدّ المهمة الواحدة + قطع قاطع (`lib/state/task_cost_limit.dart` + صف في شاشة الاستهلاك + الفحص في `session.usage.updated`). **ناقص:** النموذج البديل (fallback model) |
| **R12** | فريق AI: مخطط + N منفّذ + مراجع اختياري، لكل منهم نموذجه، كل منفّذ في worktree/فرع، تزامن ٢ (أقصى ٤)، تقدير تكلفة قبل التشغيل، إيقاف عام | **ANALYZED** | موجود من المنبع (محرك Rust + واجهة Team + worktrees + ساعة الإيقاف). لم يُضف منسّق جديد |
| **R13** | ثيمات Light/Dark/Sunset (design tokens)؛ عربي RTL + إنجليزي؛ الطرفية والكود LTR؛ حركات 150–250 مللي واحترام reduce motion | **ANALYZED** | موجود من المنبع: 32 ثيمة (Sunset ضمن `theme_packs_generated.dart`)، عربي كامل، `kit_bidi.dart` للـ LTR، حركات 220 مللي |
| **R14** | شاشة Health Check (قتل العمليات، قيود البطارية، نوع الخدمة صالح على Android 15) | **ANALYZED** | موجود من المنبع: `ServiceDiagnostics.kt` + شاشة التشخيص؛ نوع الخدمة `specialUse` (لا يخضع لحدّ 6 ساعات الخاص بـ `dataSync`) مع تبرير |
| **R15** | `allowBackup=false`، R8، غير debuggable، FLAG_SECURE + قفل بيومتري اختياريان، تصدير تشخيص بلا أسرار | **ANALYZED** | `allowBackup=false` + `isDebuggable = false` + `isMinifyEnabled = true` في build.gradle.kts؛ `local_auth` للقفل البيومتري؛ `KitRedact` للتصدير |
| **R16** | الاحتفاظ بإشعارات MIT وPRoot GPL و`THIRD_PARTY_NOTICES.md` وملاحظة «غير مرتبط» | **ANALYZED** | `LICENSE` + `NOTICE` + `THIRD_PARTY_NOTICES.md` (مع قسم PRoot/GPL ونص GPL v2)؛ ملاحظة «غير مرتبط» في `lib/ui/screens/about_screen.dart` |

---

## ملاحظات على التدقيق

- **لا يوجد أي بند BUILT.** البناء الأخضر لم يقع بعد؛ كل ما سبق ANALYZED (كود + فحص ساكن).
- الأرقام والحقائق في هذا الملف قابلة للتحقق بمسار الملف المذكور.
- لا توجد بيانات تجريبية معروضة كحقيقية.
