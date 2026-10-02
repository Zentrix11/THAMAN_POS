THAMAN POS V9.6 — 0.33.0+41
==========================
الجديد في صفحة الاشتراك/الباقات:
- عرض الباقة الحالية بوضوح.
- عرض الباقات والعروض العامة المنشورة من THAMAN Admin.
- عرض أي باقة مخصصة لهذا المشترك فقط.
- طلب تجديد أو تغيير باقة.
- طلب باقة مخصصة عبر نموذج: المدة، الأجهزة، الميزانية، بيانات التواصل والمتطلبات.
- الطلب يحفظ أولًا في Supabase، ثم يحاول إرسال نسخة إلى بريد الإدارة عبر Edge Function.

قبل تشغيل هذا الإصدار على Supabase:
نفّذ Migration 010 بعد Migration 009، ثم VERIFY_AFTER_010.sql.
للبريد راجع SETUP_CUSTOM_PLANS_AND_EMAIL_AR.txt و supabase/functions/custom-plan-request-email/README_AR.txt.
