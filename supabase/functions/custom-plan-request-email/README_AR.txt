إعداد إرسال طلبات الباقة المخصصة إلى البريد
============================================

الطلب يُحفظ دائمًا أولًا داخل جدول subscription_requests في Supabase.
إرسال البريد يتم من Edge Function حتى لا نضع أي مفتاح بريد سري داخل تطبيق Flutter.

البريد المستلم الافتراضي في الكود:
albhtytymr6@gmail.com

المطلوب مرة واحدة فقط:
1) أنشئ مفتاح API من Resend.
2) من Supabase CLI داخل المشروع نفّذ:
   supabase secrets set RESEND_API_KEY=YOUR_RESEND_KEY
   supabase secrets set CUSTOM_PLAN_NOTIFY_EMAIL=albhtytymr6@gmail.com
   supabase secrets set CUSTOM_PLAN_FROM_EMAIL="THAMAN <you@your-verified-domain.com>"
3) انشر الدالة:
   supabase functions deploy custom-plan-request-email --no-verify-jwt

مهم: SUPABASE_SERVICE_ROLE_KEY متوفر تلقائيًا داخل بيئة Edge Functions ولا يوضع داخل Flutter.
إذا لم تفعّل Resend، سيظل الطلب يصل إلى لوحة THAMAN Admin ولن يضيع، لكن البريد لن يُرسل.
