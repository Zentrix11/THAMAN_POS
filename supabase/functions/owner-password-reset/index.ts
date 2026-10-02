import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const enc = new TextEncoder();

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function html(body: string, status = 200) {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
  });
}

function page(content: string) {
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>THAMAN - استعادة كلمة المرور</title><style>
  *{box-sizing:border-box}body{margin:0;background:#f4f7f6;font-family:Segoe UI,Tahoma,Arial,sans-serif;color:#102522;min-height:100vh;display:grid;place-items:center;padding:24px}.card{width:min(520px,100%);background:#fff;border:1px solid #dfe8e5;border-radius:24px;padding:30px;box-shadow:0 18px 50px rgba(15,91,80,.08)}.brand{font-weight:900;letter-spacing:2px;color:#0f5b50;font-size:18px}.sub{color:#71807c;line-height:1.8;font-size:14px}h1{font-size:26px;margin:22px 0 8px}label{display:block;font-weight:800;font-size:13px;margin:14px 0 7px}.field{position:relative}.field input{width:100%;padding:14px 46px 14px 14px;border:1px solid #cad8d4;border-radius:12px;font-size:15px;outline:none}.field input:focus{border-color:#0f5b50;box-shadow:0 0 0 3px rgba(15,91,80,.08)}.eye{position:absolute;right:8px;top:50%;transform:translateY(-50%);border:0;background:transparent;cursor:pointer;font-size:18px}.btn{width:100%;margin-top:20px;padding:14px;border:0;border-radius:12px;background:#0f5b50;color:white;font-size:15px;font-weight:900;cursor:pointer}.note{margin-top:14px;padding:12px;border-radius:12px;background:#edf6f3;color:#46635b;font-size:12px;line-height:1.7}.error{background:#fff0f0;color:#b42318}.ok{font-size:17px;line-height:1.9;text-align:center}.support{display:block;margin-top:18px;text-align:center;color:#0f5b50;text-decoration:none;font-weight:800}</style></head><body><div class="card"><div class="brand">THAMAN</div>${content}</div></body></html>`;
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function sendResetEmail(to: string, link: string) {
  const resendKey = Deno.env.get('RESEND_API_KEY') ?? '';
  const fromEmail = Deno.env.get('THAMAN_RESET_FROM_EMAIL') ?? '';
  if (!resendKey || !fromEmail) throw new Error('email_not_configured');

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: fromEmail,
      to: [to],
      subject: 'THAMAN - استعادة كلمة المرور',
      html: `<div dir="rtl" style="font-family:Arial,sans-serif"><h2>استعادة كلمة مرور THAMAN</h2><p>وصلنا طلب لتعيين كلمة مرور جديدة لحساب المالك.</p><p><a href="${link}" style="display:inline-block;padding:12px 18px;background:#0f5b50;color:#fff;text-decoration:none;border-radius:10px">تعيين كلمة مرور جديدة</a></p><p>الرابط صالح لمدة 30 دقيقة ويعمل مرة واحدة فقط. إذا لم تطلب هذا التغيير فتجاهل الرسالة.</p></div>`,
    }),
  });
  if (!response.ok) throw new Error('email_send_failed');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey) return json({ ok: false, error: 'server_not_configured' }, 503);
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const token = url.searchParams.get('token') ?? '';
    if (!token) return html(page('<h1>رابط غير صالح</h1><p class="sub">اطلب رابط استعادة جديدًا من تطبيق THAMAN.</p>'), 400);
    return html(page(`<h1>كلمة مرور جديدة</h1><p class="sub">أدخل كلمة المرور الجديدة للحساب. يمكنك إظهارها قبل الحفظ للتأكد منها.</p><form method="post"><input type="hidden" name="token" value="${token.replaceAll('&','&amp;').replaceAll('"','&quot;')}"><label>كلمة المرور الجديدة</label><div class="field"><input id="p1" name="password" type="password" required><button class="eye" type="button" onclick="toggle('p1',this)">👁</button></div><label>تأكيد كلمة المرور</label><div class="field"><input id="p2" name="confirm" type="password" required><button class="eye" type="button" onclick="toggle('p2',this)">👁</button></div><button class="btn" type="submit">حفظ كلمة المرور</button><div class="note">نصيحة: استخدم كلمة مرور طويلة وفريدة. النظام لا يفرض نمطًا معقدًا عليك.</div></form><script>function toggle(id,b){const e=document.getElementById(id);e.type=e.type==='password'?'text':'password';b.textContent=e.type==='password'?'👁':'🙈'}</script>`));
  }

  const contentType = req.headers.get('content-type') ?? '';
  if (req.method === 'POST' && contentType.includes('application/x-www-form-urlencoded')) {
    const form = await req.formData();
    const token = String(form.get('token') ?? '');
    const password = String(form.get('password') ?? '');
    const confirm = String(form.get('confirm') ?? '');
    if (!token || !password || password !== confirm) {
      return html(page('<h1>تعذر الحفظ</h1><p class="sub error">تحقق من كلمة المرور والتأكيد ثم اطلب رابطًا جديدًا إذا لزم.</p>'), 400);
    }
    const tokenHash = await sha256(token);
    const { data: reset } = await admin.from('pos_owner_password_resets').select('id').eq('token_hash', tokenHash).is('used_at', null).gt('expires_at', new Date().toISOString()).maybeSingle();
    if (!reset) return html(page('<h1>انتهت صلاحية الرابط</h1><p class="sub error">الرابط غير صالح أو تم استخدامه سابقًا. اطلب رابط استعادة جديدًا.</p>'), 410);
    const { data, error } = await admin.rpc('owner_password_reset_complete_v1', { p_request_id: reset.id, p_new_password: password });
    if (error || data !== true) return html(page('<h1>تعذر تغيير كلمة المرور</h1><p class="sub error">اطلب رابطًا جديدًا وحاول مرة أخرى.</p>'), 500);
    return html(page('<div class="ok"><h1>تم تغيير كلمة المرور</h1><p>يمكنك الآن العودة إلى THAMAN وتسجيل الدخول بكلمة المرور الجديدة.</p></div>'));
  }

  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  let payload: Record<string, unknown> = {};
  try { payload = await req.json(); } catch (_) { return json({ ok: true }); }
  const email = String(payload.email ?? '').trim().toLowerCase();
  if (!email || !email.includes('@')) return json({ ok: true });

  // Enumeration-safe: return the same response when no account exists.
  const { data: owner } = await admin.from('pos_owner_accounts').select('id,email').eq('email', email).eq('active', true).maybeSingle();
  if (!owner) return json({ ok: true });

  const token = randomToken();
  const tokenHash = await sha256(token);
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();

  await admin.from('pos_owner_password_resets').delete().eq('owner_id', owner.id).is('used_at', null);
  const { error: insertError } = await admin.from('pos_owner_password_resets').insert({
    owner_id: owner.id,
    token_hash: tokenHash,
    expires_at: expiresAt,
    request_ip: req.headers.get('x-forwarded-for'),
    user_agent: req.headers.get('user-agent'),
  });
  if (insertError) return json({ ok: false, error: 'reset_request_failed' }, 500);

  const resetLink = `${supabaseUrl}/functions/v1/owner-password-reset?token=${encodeURIComponent(token)}`;
  try {
    await sendResetEmail(owner.email, resetLink);
  } catch (e) {
    console.error('owner-password-reset email failed', e);
    return json({ ok: false, error: 'email_not_configured' }, 503);
  }
  return json({ ok: true });
});
