# THAMAN POS V9.0 — Subscription Center readiness

- صفحة الاشتراك موجودة للمالك/المدير/المحاسب فقط.
- المدير والمحاسب عرض فقط؛ المالك يستطيع ربط كود التفعيل.
- لا توجد بيانات اشتراك وهمية.
- البيانات الحقيقية تأتي من نفس Supabase الخاص بـ THAMAN Admin.
- شغّل `supabase/migrations/004_pos_subscription_status.sql` بعد migrations 001/002/003 الخاصة بلوحة التحكم.
- مرر `THAMAN_SUPABASE_URL` و`THAMAN_SUPABASE_PUBLISHABLE_KEY` عبر `--dart-define` عند التشغيل/البناء.
- لا تستخدم `service_role` داخل التطبيق.
- لم يتم تنفيذ Flutter compile في بيئة الإنشاء هذه لأن Flutter SDK غير متوفر؛ شغّل `flutter pub get` ثم `flutter analyze` و`flutter run` على جهاز التطوير.
