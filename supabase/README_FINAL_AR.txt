THAMAN FINAL DATABASE - SQL 001 TO 009

إذا أنشأت مشروع Supabase جديد من الصفر:
شغّل 001 ثم 002 ثم 003 ثم 004 ثم 005 ثم 006 ثم 007 ثم 008 ثم 009 بالترتيب.

إذا مشروعك الحالي عليه 001 إلى 008 بالفعل:
شغّل 009_final_device_proof_and_acl_hardening.sql فقط.

بعد نجاح 009 يمكنك تشغيل VERIFY_AFTER_009.sql. هذا ملف قراءة فقط، وكل نتيجة فيه يجب أن تكون passed = true.

مهم:
- لا تضع Secret key أو service_role داخل أي تطبيق Flutter.
- التطبيقات تستخدم فقط Project URL + Publishable key.
- بعد 009، النسخ القديمة التي تحاول استدعاء RPCs القديمة مباشرة لن تكون متوافقة؛ استخدم POS V9.5 النهائي.
- 009 يصلح كذلك مشكلة pgcrypto/gen_salt على المشاريع الجديدة ويضيف ربط الجهاز بـ device proof.
