import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function escapeHtml(value: unknown) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  try {
    const body = await req.json();
    const requestId = String(body?.request_id ?? '').trim();
    const activationCode = String(body?.activation_code ?? '').trim().toUpperCase();
    const deviceUid = String(body?.device_uid ?? '').trim();
    const deviceProof = String(body?.device_proof ?? '').trim();
    if (!requestId || !activationCode || !deviceUid || !/^[A-Fa-f0-9]{64}$/.test(deviceProof)) {
      return json({ ok: false, error: 'invalid_request' }, 400);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const resendKey = Deno.env.get('RESEND_API_KEY') ?? '';
    const notifyEmail = Deno.env.get('CUSTOM_PLAN_NOTIFY_EMAIL') ?? 'albhtytymr6@gmail.com';
    const fromEmail = Deno.env.get('CUSTOM_PLAN_FROM_EMAIL') ?? 'THAMAN <onboarding@resend.dev>';
    if (!supabaseUrl || !serviceRole) return json({ ok: false, error: 'server_not_configured' }, 500);

    const admin = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: subscription, error: subError } = await admin
      .from('subscriptions')
      .select('id,business_id,activation_code')
      .ilike('activation_code', activationCode)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (subError || !subscription) return json({ ok: false, error: 'license_denied' }, 403);

    const { data: device, error: deviceError } = await admin
      .from('devices')
      .select('id,active,blocked,device_proof_hash')
      .eq('business_id', subscription.business_id)
      .eq('device_uid', deviceUid)
      .maybeSingle();
    if (deviceError || !device || device.active !== true || device.blocked === true) {
      return json({ ok: false, error: 'device_denied' }, 403);
    }
    const proofHash = await sha256Hex(deviceProof);
    if (!device.device_proof_hash || String(device.device_proof_hash).toLowerCase() !== proofHash) {
      return json({ ok: false, error: 'device_proof_mismatch' }, 403);
    }

    const { data: request, error: requestError } = await admin
      .from('subscription_requests')
      .select('id,business_id,current_plan_id,requested_duration_days,requested_device_limit,requested_budget,customer_note,contact_email,contact_phone,email_notified_at,created_at')
      .eq('id', requestId)
      .eq('business_id', subscription.business_id)
      .eq('request_type', 'custom')
      .maybeSingle();
    if (requestError || !request) return json({ ok: false, error: 'request_not_found' }, 404);
    if (request.email_notified_at) return json({ ok: true, already_sent: true, email_sent: true });

    const { data: business } = await admin
      .from('businesses')
      .select('account_no,name,owner_name,phone,email,city')
      .eq('id', subscription.business_id)
      .maybeSingle();
    const { data: plan } = request.current_plan_id
      ? await admin.from('plans').select('name').eq('id', request.current_plan_id).maybeSingle()
      : { data: null } as { data: null };

    if (!resendKey) {
      return json({ ok: true, email_sent: false, error: 'mail_not_configured' });
    }

    const ownerRaw = business?.owner_name || business?.name || 'مشترك THAMAN';
    const owner = escapeHtml(ownerRaw);
    const account = escapeHtml(business?.account_no || '—');
    const currentPlan = escapeHtml(plan?.name || '—');
    const budget = escapeHtml(request.requested_budget == null ? 'غير محددة' : String(request.requested_budget));
    const contactEmail = escapeHtml(request.contact_email || business?.email || '—');
    const contactPhone = escapeHtml(request.contact_phone || business?.phone || '—');
    const businessName = escapeHtml(business?.name || '—');
    const notes = escapeHtml(request.customer_note || 'لا توجد').replaceAll('\n', '<br>');

    const html = `
      <div dir="rtl" style="font-family:Arial,sans-serif;line-height:1.8;color:#14211e">
        <h2 style="color:#0f4b43">طلب باقة مخصصة جديد - THAMAN</h2>
        <p><b>المشترك:</b> ${owner}</p>
        <p><b>المتجر:</b> ${businessName}</p>
        <p><b>رقم الحساب:</b> ${account}</p>
        <p><b>الباقة الحالية:</b> ${currentPlan}</p>
        <p><b>المدة المطلوبة:</b> ${Number(request.requested_duration_days)} يوم</p>
        <p><b>عدد الأجهزة:</b> ${Number(request.requested_device_limit)}</p>
        <p><b>الميزانية المتوقعة:</b> ${budget}</p>
        <p><b>رقم التواصل:</b> ${contactPhone}</p>
        <p><b>البريد:</b> ${contactEmail}</p>
        <p><b>تفاصيل إضافية:</b><br>${notes}</p>
        <hr><p style="color:#73817d;font-size:12px">Request ID: ${escapeHtml(request.id)}</p>
      </div>`;

    const mailResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [notifyEmail],
        subject: `THAMAN - طلب باقة مخصصة من ${String(ownerRaw).replace(/[\r\n]/g, ' ')}`,
        html,
      }),
    });
    if (!mailResponse.ok) {
      const providerError = await mailResponse.text();
      console.error('Resend error', mailResponse.status, providerError);
      return json({ ok: true, email_sent: false, error: 'mail_provider_failed' });
    }

    await admin.from('subscription_requests').update({ email_notified_at: new Date().toISOString() }).eq('id', requestId);
    return json({ ok: true, email_sent: true });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: 'internal_error' }, 500);
  }
});
