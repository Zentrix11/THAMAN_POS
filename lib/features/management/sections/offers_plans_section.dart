import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_controller.dart';
import '../../../core/app_strings.dart';
import '../../../core/subscription/subscription_repository.dart';
import '../../../core/widgets/surface_card.dart';

class OffersPlansSection extends StatefulWidget {
  const OffersPlansSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<OffersPlansSection> createState() => _OffersPlansSectionState();
}

class _OffersPlansSectionState extends State<OffersPlansSection> {
  final SubscriptionRepository _repository = SubscriptionRepository();
  AvailablePlansCatalog? _catalog;
  String? _error;
  bool _loading = true;
  String? _submittingPlanId;

  AppStrings get s => widget.s;
  bool get _canRequest => s.controller.role == UserRole.owner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _repository.fetchAvailablePlans();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      setState(() {
        _catalog = null;
        _error = e.code;
        _loading = false;
      });
    }
  }

  Future<void> _request(AvailableSubscriptionPlan plan) async {
    if (!_canRequest || _submittingPlanId != null) return;
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          scrollable: true,
          title: Text(plan.isCurrent ? s.text('طلب تجديد الاشتراك', 'Request renewal') : s.text('طلب تغيير الباقة', 'Request plan change')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.isCurrent
                      ? s.text('سيتم إرسال طلب تجديد باقة ${plan.name} إلى إدارة THAMAN للتواصل معك وإكمال التجديد.', 'A renewal request for ${plan.name} will be sent to THAMAN administration for follow-up.')
                      : s.text('سيتم إرسال طلب تغيير باقتك الحالية إلى ${plan.name}. لن تتغير الباقة تلقائيًا قبل تواصل إدارة THAMAN معك.', 'A request to change your current plan to ${plan.name} will be sent. Your plan will not change automatically before THAMAN contacts you.'),
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.55),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: s.text('ملاحظة للإدارة (اختياري)', 'Note to administration (optional)')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.send_rounded, size: 17), label: Text(s.text('إرسال الطلب', 'Send request'))),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      note.dispose();
      return;
    }
    setState(() => _submittingPlanId = plan.id);
    try {
      final result = await _repository.createSubscriptionRequest(plan: plan, customerNote: note.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.duplicate
            ? s.text('لديك طلب مفتوح مسبقًا لهذه الباقة. ستتواصل معك إدارة THAMAN.', 'You already have an open request for this plan. THAMAN will contact you.')
            : s.text('تم إرسال طلبك بنجاح. ستتواصل معك إدارة THAMAN لإكمال الإجراء.', 'Your request was sent successfully. THAMAN will contact you to complete the process.')),
      ));
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e.code)), backgroundColor: AppColors.danger));
    } finally {
      note.dispose();
      if (mounted) setState(() => _submittingPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SurfaceCard(child: SizedBox(height: 240, child: Center(child: CircularProgressIndicator())));
    }
    if (_error != null) {
      return SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.danger, size: 42),
            const SizedBox(height: 12),
            Text(_errorText(_error!), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(s.text('إعادة المحاولة', 'Retry'))),
          ]),
        ),
      );
    }
    final plans = _catalog?.plans ?? const <AvailableSubscriptionPlan>[];
    if (plans.isEmpty) {
      return SurfaceCard(child: Padding(padding: const EdgeInsets.all(28), child: Center(child: Text(s.text('لا توجد باقات أو عروض متاحة حاليًا.', 'No plans or offers are currently available.')))));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SurfaceCard(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [AppColors.primaryStrong, AppColors.primary])),
          child: Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.local_offer_rounded, color: Colors.white)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.text('اختر الباقة المناسبة لتجارتك', 'Choose the right plan for your business'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(s.text('الطلب يصل مباشرة إلى إدارة THAMAN، ولن يتم تغيير اشتراكك قبل التواصل معك.', 'Your request goes directly to THAMAN administration. Your subscription will not change until they contact you.'), style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 9.5, height: 1.45)),
            ])),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      if (!_canRequest)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.accent.withValues(alpha: .25))),
          child: Row(children: [const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 19), const SizedBox(width: 9), Expanded(child: Text(s.text('يمكن للمدير والمحاسب مشاهدة العروض، لكن إرسال طلب التجديد أو تغيير الباقة متاح لحساب المالك فقط.', 'Managers and accountants can view offers, but only the owner can submit renewal or plan-change requests.'), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)))]),
        ),
      LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1080 ? 3 : constraints.maxWidth >= 650 ? 2 : 1;
        final width = (constraints.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: plans.map((plan) => SizedBox(width: width, child: _PlanCard(plan: plan, loading: _submittingPlanId == plan.id, canRequest: _canRequest, s: s, onRequest: () => _request(plan)))).toList());
      }),
    ]);
  }

  String _errorText(String code) => switch (code) {
        'device_blocked' => s.text('هذا الجهاز محظور. تواصل مع إدارة THAMAN.', 'This device is blocked. Contact THAMAN administration.'),
        'device_unlinked' || 'device_not_registered' => s.text('هذا الجهاز غير مرتبط بالاشتراك. أعد التفعيل أو تواصل مع إدارة THAMAN.', 'This device is not linked to the subscription. Reactivate or contact THAMAN.'),
        'business_suspended' || 'subscription_suspended' => s.text('اشتراكك موقوف حاليًا. تواصل مع إدارة THAMAN.', 'Your subscription is currently suspended. Contact THAMAN administration.'),
        'subscription_expired' || 'expired' => s.text('اشتراكك منتهي. أرسل طلب تجديد بعد إعادة تفعيل الاشتراك أو تواصل مع إدارة THAMAN.', 'Your subscription has expired. Contact THAMAN administration.'),
        'server_not_configured' => s.text('اتصال THAMAN Cloud غير مضبوط في هذه النسخة.', 'THAMAN Cloud is not configured in this build.'),
        'catalog_server_error' => s.text('تعذر تحميل الباقات من قاعدة البيانات. طبّق SQL 014 ثم أعد المحاولة.', 'Could not load plans from the database. Apply SQL 014 and try again.'),
        'connection_failed' => s.text('تعذر الاتصال بالسيرفر. تحقق من الإنترنت وحاول مرة أخرى.', 'Could not connect to the server. Check your internet connection and try again.'),
        'plan_not_available' => s.text('هذه الباقة لم تعد متاحة.', 'This plan is no longer available.'),
        _ => s.text('تعذر تحميل الباقات أو إرسال الطلب. حاول مرة أخرى.', 'Could not load plans or send the request. Please try again.'),
      };
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.loading, required this.canRequest, required this.s, required this.onRequest});
  final AvailableSubscriptionPlan plan;
  final bool loading;
  final bool canRequest;
  final AppStrings s;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (plan.isOffer)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: AppColors.accentSoft,
            child: Row(children: [const Icon(Icons.local_fire_department_rounded, color: AppColors.accent, size: 17), const SizedBox(width: 7), Expanded(child: Text(plan.offerBadge.isEmpty ? s.text('عرض خاص', 'Special offer') : plan.offerBadge, style: const TextStyle(color: AppColors.accent, fontSize: 9.5, fontWeight: FontWeight.w900)))]),
          ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(plan.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            if (plan.isCurrent) ...[
              const SizedBox(height: 7),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(30)),
                  child: Text(s.text('باقتك الحالية', 'Current plan'), style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (plan.description.isNotEmpty) Text(plan.description, style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.5)) else Text(s.text('باقة THAMAN لإدارة أعمالك بكفاءة.', 'A THAMAN plan for efficient business management.'), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            const SizedBox(height: 16),
            if (plan.previousPrice != null && plan.previousPrice! > plan.price) Text(_money(plan.previousPrice!), style: const TextStyle(fontSize: 10.5, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(_money(plan.price), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: AppColors.primaryStrong)),
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(plan.billingCycle == 'yearly' ? s.text('/ سنويًا', '/ year') : s.text('/ شهريًا', '/ month'), style: const TextStyle(fontSize: 9, color: AppColors.muted))),
              ],
            ),
            const SizedBox(height: 14),
            _Feature(icon: Icons.devices_outlined, text: s.text('حتى ${plan.maxDevices} أجهزة', 'Up to ${plan.maxDevices} devices')),
            const SizedBox(height: 7),
            _Feature(icon: Icons.support_agent_rounded, text: s.text('طلبك يصل مباشرة لإدارة THAMAN', 'Request goes directly to THAMAN administration')),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: canRequest && !loading ? onRequest : null,
              icon: loading ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(plan.isCurrent ? Icons.autorenew_rounded : Icons.arrow_upward_rounded, size: 17),
              label: Text(plan.isCurrent ? s.text('طلب تجديد الباقة', 'Request renewal') : s.text('طلب هذه الباقة', 'Request this plan')),
            ),
          ]),
        ),
      ]),
    );
  }

  String _money(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 17, color: AppColors.primary), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)))]);
}
