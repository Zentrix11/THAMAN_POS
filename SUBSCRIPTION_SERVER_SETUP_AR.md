# ربط صفحة الاشتراك في THAMAN POS مع THAMAN Admin

هذه الصفحة لا تستخدم بيانات وهمية. حتى تعرض الاشتراك الحقيقي يجب أن يكون THAMAN Admin وTHAMAN POS على **نفس مشروع Supabase**.

## 1) قاعدة البيانات

نفّذ migrations لوحة THAMAN Admin بالترتيب:

1. `001_thaman_admin.sql`
2. `002_device_limits.sql`
3. `003_real_subscriptions_and_settings.sql`

ثم نفّذ من هذه الحزمة:

4. `supabase/migrations/004_pos_subscription_status.sql`

Migration 004 ينشئ دالة قراءة محدودة باسم `pos_subscription_status`. لا يعطي THAMAN POS صلاحيات إدارة جداول لوحة التحكم.

## 2) تشغيل THAMAN POS مع بيانات Supabase

مثال Windows Debug:

```bat
flutter run -d windows --dart-define=THAMAN_SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

مثال Windows Release:

```bat
flutter build windows --release --dart-define=THAMAN_SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

استخدم فقط **Publishable/Anon key** المخصص للعميل. لا تضع `service_role` داخل التطبيق.

## 3) ربط الاشتراك

- ادخل THAMAN POS كمالك.
- افتح **الاشتراك والباقة**.
- اضغط **ربط كود التفعيل**.
- أدخل الكود الموجود لنفس المشترك في THAMAN Admin.
- بعد نجاح الاتصال تظهر الباقة والتواريخ والأجهزة الحقيقية.

المدير والمحاسب يستطيعان رؤية الصفحة، لكن تعديل كود الربط محصور بالمالك.
