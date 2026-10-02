import 'dart:async';
import '../../../core/time_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_controller.dart';
import '../../../core/app_strings.dart';
import '../../../core/subscription/subscription_repository.dart';
import '../../../core/widgets/surface_card.dart';

class SubscriptionSection extends StatefulWidget {
  const SubscriptionSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<SubscriptionSection> createState() => _SubscriptionSectionState();
}

class _SubscriptionSectionState extends State<SubscriptionSection> {
  final SubscriptionRepository _repository = SubscriptionRepository();
  String _activationCode = '';
  SubscriptionSnapshot? _snapshot;
  AvailablePlansCatalog? _catalog;
  String? _catalogError;
  String? _errorCode;
  bool _loading = true;
  bool _catalogLoading = false;
  bool _requestsLoading = false;
  String? _requestsError;
  List<OwnerCustomPlanRequestInfo> _customRequests = const [];
  Timer? _clockTimer;
  Timer? _requestSyncTimer;

  AppStrings get s => widget.s;
  bool get _isOwner => s.controller.role == UserRole.owner;

  @override
  void initState() {
    super.initState();
    _load();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _snapshot != null) setState(() {});
    });
    _requestSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _isOwner && _activationCode.isNotEmpty && !_requestsLoading) {
        _refreshCustomRequests(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _requestSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final code = await _repository.loadActivationCode();
    if (!mounted) return;
    setState(() {
      _activationCode = code;
      _loading = code.isNotEmpty;
      _errorCode = null;
    });
    if (code.isEmpty) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_activationCode.isEmpty) return;
    setState(() {
      _loading = true;
      _errorCode = null;
    });
    try {
      final snapshot = await _repository.fetch(_activationCode);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      await _refreshCatalog();
      if (_isOwner) await _refreshCustomRequests();
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _loading = false;
        _errorCode = e.code;
      });
    }
  }

  Future<void> _editActivationCode() async {
    final controller = TextEditingController(text: _activationCode);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          scrollable: true,
          title: Text(s.text('ربط كود التفعيل', 'Link activation code')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.text(
                    'أدخل كود التفعيل الصادر من THAMAN Admin. سيُستخدم لجلب بيانات الاشتراك الحقيقية من السيرفر.',
                    'Enter the activation code issued by THAMAN Admin. It will be used to load the real subscription from the server.',
                  ),
                  style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: s.text('كود التفعيل', 'Activation code'),
                    hintText: 'THM-XXXXXXXX',
                    prefixIcon: const Icon(Icons.key_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim().toUpperCase()),
              child: Text(s.text('حفظ وربط', 'Save & link')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    final normalized = result.trim().toUpperCase();
    setState(() {
      _activationCode = normalized;
      _snapshot = null;
      _errorCode = null;
      _loading = true;
    });
    try {
      final snapshot = await _repository.activateDevice(normalized);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      await _refreshCatalog();
      if (_isOwner) await _refreshCustomRequests();
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _loading = false;
        _errorCode = e.code;
      });
    }
  }

  Future<void> _refreshCatalog() async {
    if (_activationCode.isEmpty) return;
    if (mounted) setState(() { _catalogLoading = true; _catalogError = null; });
    try {
      final catalog = await _repository.fetchAvailablePlans();
      if (!mounted) return;
      setState(() { _catalog = catalog; _catalogLoading = false; _catalogError = null; });
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      setState(() { _catalogLoading = false; _catalogError = e.code; });
    }
  }

  Future<void> _refreshCustomRequests({bool silent = false}) async {
    if (!_isOwner || _activationCode.isEmpty) return;
    if (mounted && !silent) {
      setState(() { _requestsLoading = true; _requestsError = null; });
    }
    try {
      final requests = await _repository.fetchCustomPlanRequests();
      if (!mounted) return;
      setState(() {
        _customRequests = requests;
        if (!silent) _requestsLoading = false;
        _requestsError = null;
      });
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() { _requestsLoading = false; _requestsError = e.code; });
      }
    }
  }

  Future<void> _openCustomRequestChat(OwnerCustomPlanRequestInfo request) async {
    if (!_isOwner) return;
    try {
      await _repository.markCustomPlanRequestMessagesRead(request.id);
      await _refreshCustomRequests(silent: true);
    } catch (_) {}
    if (!mounted) return;

    final matching = _customRequests.where((e) => e.id == request.id).toList();
    var current = matching.isEmpty ? request : matching.first;
    final input = TextEditingController();
    bool sending = false;
    bool syncing = false;
    String? error;
    BuildContext? activeDialogContext;
    StateSetter? activeDialogSetState;

    Future<void> syncConversation() async {
      if (syncing) return;
      final dialogContext = activeDialogContext;
      final setDialogState = activeDialogSetState;
      if (dialogContext == null || setDialogState == null || !dialogContext.mounted) return;
      syncing = true;
      try {
        var updated = await _repository.fetchCustomPlanRequests();
        var matches = updated.where((e) => e.id == current.id).toList();
        if (matches.isEmpty) return;
        var latest = matches.first;
        if (latest.unreadOwnerCount > 0) {
          await _repository.markCustomPlanRequestMessagesRead(latest.id);
          updated = await _repository.fetchCustomPlanRequests();
          matches = updated.where((e) => e.id == current.id).toList();
          if (matches.isNotEmpty) latest = matches.first;
        }
        current = latest;
        if (mounted) setState(() => _customRequests = updated);
        if (dialogContext.mounted) setDialogState(() {});
      } catch (_) {
        // Keep the existing conversation visible during short network drops.
      } finally {
        syncing = false;
      }
    }

    final dialogFuture = showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: StatefulBuilder(
          builder: (dialogContext, setD) {
            activeDialogContext = dialogContext;
            activeDialogSetState = setD;
            return AlertDialog(
              scrollable: true,
              title: Row(children: [
                const Icon(Icons.forum_outlined, color: AppColors.primary),
                const SizedBox(width: 9),
                Expanded(child: Text(s.text('مراسلة إدارة THAMAN', 'Message THAMAN administration'))),
                _StatusPill(label: _requestStatusLabel(current.status), color: _requestStatusColor(current.status)),
              ]),
              content: SizedBox(
                width: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.border)),
                      child: Wrap(spacing: 14, runSpacing: 7, children: [
                        if (current.requestedDurationDays != null) Text(s.text('المدة: ${current.requestedDurationDays} يوم', 'Duration: ${current.requestedDurationDays} days'), style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w800)),
                        if (current.requestedDeviceLimit != null) Text(s.text('الأجهزة: ${current.requestedDeviceLimit}', 'Devices: ${current.requestedDeviceLimit}'), style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w800)),
                        if (current.requestedBudget != null) Text(s.text('الميزانية: ${current.requestedBudget!.toStringAsFixed(2)}', 'Budget: ${current.requestedBudget!.toStringAsFixed(2)}'), style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.sync_rounded, size: 14, color: AppColors.muted),
                      const SizedBox(width: 5),
                      Text(s.text('المحادثة تتحدث تلقائيًا كل عدة ثوانٍ', 'Conversation refreshes automatically every few seconds'), style: const TextStyle(fontSize: 8.5, color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      height: 320,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                      child: current.messages.isEmpty
                          ? Center(child: Text(s.text('ابدأ المحادثة مع الإدارة بخصوص طلبك.', 'Start a conversation with administration about your request.'), style: const TextStyle(fontSize: 9.5, color: AppColors.muted)))
                          : ListView.separated(
                              itemCount: current.messages.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final message = current.messages[index];
                                final mine = message.senderType == 'owner';
                                return Align(
                                  alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 430),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: mine ? AppColors.primary : Colors.white,
                                      borderRadius: BorderRadius.circular(13),
                                      border: mine ? null : Border.all(color: AppColors.border),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(mine ? s.text('أنت', 'You') : s.text('إدارة THAMAN', 'THAMAN Admin'), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: mine ? Colors.white70 : AppColors.muted)),
                                      const SizedBox(height: 3),
                                      Text(message.message, style: TextStyle(fontSize: 10, height: 1.45, color: mine ? Colors.white : AppColors.text)),
                                      const SizedBox(height: 4),
                                      Text(_formatDateTime(message.createdAt), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 7.5, color: mine ? Colors.white60 : AppColors.muted)),
                                    ]),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: input,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 4000,
                      decoration: InputDecoration(labelText: s.text('اكتب رسالتك', 'Write your message'), errorText: error),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: sending ? null : () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close'))),
                FilledButton.icon(
                  onPressed: sending ? null : () async {
                    final message = input.text.trim();
                    if (message.isEmpty) { setD(() => error = s.text('اكتب رسالة أولًا.', 'Write a message first.')); return; }
                    setD(() { sending = true; error = null; });
                    try {
                      await _repository.sendCustomPlanRequestMessage(requestId: current.id, message: message);
                      input.clear();
                      await syncConversation();
                      if (dialogContext.mounted) setD(() => sending = false);
                    } on SubscriptionLookupException catch (e) {
                      if (!dialogContext.mounted) return;
                      setD(() {
                        sending = false;
                        error = e.code == 'message_rate_limited'
                            ? s.text('أرسلت رسائل كثيرة بسرعة. انتظر دقيقة ثم حاول.', 'Too many messages were sent quickly. Wait a minute and try again.')
                            : s.text('تعذر إرسال الرسالة (${e.code}).', 'Could not send message (${e.code}).');
                      });
                    }
                  },
                  icon: sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 17),
                  label: Text(s.text('إرسال', 'Send')),
                ),
              ],
            );
          },
        ),
      ),
    );

    final liveTimer = Timer.periodic(const Duration(seconds: 4), (_) => syncConversation());
    await dialogFuture;
    liveTimer.cancel();
    activeDialogContext = null;
    activeDialogSetState = null;
    input.dispose();
    await _refreshCustomRequests(silent: true);
  }

  Future<void> _requestPlan(AvailableSubscriptionPlan plan) async {
    if (!_isOwner) return;
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          scrollable: true,
          title: Text(plan.isCurrent ? s.text('طلب تجديد الباقة', 'Request plan renewal') : s.text('طلب تغيير الباقة', 'Request plan change')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(plan.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text('${plan.price.toStringAsFixed(2)} • ${plan.maxDevices} ${s.text('أجهزة', 'devices')}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                const SizedBox(height: 14),
                TextField(controller: note, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: s.text('ملاحظة للإدارة (اختياري)', 'Note to administration (optional)'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('إرسال الطلب', 'Send request'))),
          ],
        ),
      ),
    );
    final customerNote = note.text.trim();
    note.dispose();
    if (confirmed != true) return;
    try {
      final result = await _repository.createSubscriptionRequest(plan: plan, customerNote: customerNote);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.duplicate
          ? s.text('هذا الطلب موجود مسبقًا لدى الإدارة.', 'This request is already pending with administration.')
          : s.text('تم إرسال طلبك إلى THAMAN Admin.', 'Your request was sent to THAMAN Admin.'))));
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تعذر إرسال الطلب (${e.code}).', 'Could not send request (${e.code}).'))));
    }
  }

  Future<void> _requestCustomPlan() async {
    if (!_isOwner) return;
    OwnerCloudProfile? profile;
    try { profile = await _repository.ownerStatus(); } catch (_) {}
    if (!mounted) return;

    final duration = TextEditingController(text: '365');
    final devices = TextEditingController(text: '${_snapshot?.deviceLimit ?? 1}');
    final budget = TextEditingController();
    final email = TextEditingController(text: profile?.email ?? '');
    final phone = TextEditingController(text: profile?.phone ?? '');
    final note = TextEditingController();

    final result = await showDialog<({int durationDays, int deviceLimit, double? budget, String email, String phone, String note})>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          scrollable: true,
          title: Row(children: [const Icon(Icons.tune_rounded, color: AppColors.primary), const SizedBox(width: 9), Expanded(child: Text(s.text('طلب باقة مخصصة', 'Request a custom plan')))]),
          content: SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: .15))),
                  child: Text(s.text('حدد احتياجك، وسيصل الطلب إلى لوحة THAMAN Admin وإلى بريد الإدارة للمراجعة والتواصل معك.', 'Tell us what you need. The request will reach THAMAN Admin and the administration email for review and follow-up.'), style: const TextStyle(fontSize: 10.5, height: 1.55, color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: TextField(controller: duration, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.text('المدة بالأيام *', 'Duration in days *'), helperText: s.text('مثال: 30، 90، 365', 'Example: 30, 90, 365'), prefixIcon: const Icon(Icons.calendar_month_outlined)))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: devices, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.text('عدد الأجهزة *', 'Number of devices *'), prefixIcon: const Icon(Icons.devices_outlined)))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: budget, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('الميزانية المتوقعة (اختياري)', 'Expected budget (optional)'), prefixIcon: const Icon(Icons.payments_outlined))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.text('رقم التواصل', 'Contact phone'), prefixIcon: const Icon(Icons.phone_outlined)))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: s.text('البريد الإلكتروني', 'Email'), prefixIcon: const Icon(Icons.email_outlined)))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: note, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: s.text('تفاصيل إضافية', 'Additional requirements'), hintText: s.text('مثلاً: احتياجات خاصة، عدد الفروع، ملاحظات...', 'For example: special needs, branches, notes...'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton.icon(
              onPressed: () {
                final d = int.tryParse(duration.text.trim());
                final count = int.tryParse(devices.text.trim());
                final amount = budget.text.trim().isEmpty ? null : double.tryParse(budget.text.trim());
                final mail = email.text.trim();
                if (d == null || d < 1 || d > 3650 || count == null || count < 1 || count > 500 || (amount != null && amount < 0) || (mail.isNotEmpty && !mail.contains('@'))) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('راجع المدة وعدد الأجهزة والميزانية والبريد.', 'Check duration, device count, budget and email.'))));
                  return;
                }
                Navigator.pop(context, (durationDays: d, deviceLimit: count, budget: amount, email: mail, phone: phone.text.trim(), note: note.text.trim()));
              },
              icon: const Icon(Icons.send_outlined, size: 17),
              label: Text(s.text('إرسال الطلب', 'Send request')),
            ),
          ],
        ),
      ),
    );

    duration.dispose(); devices.dispose(); budget.dispose(); email.dispose(); phone.dispose(); note.dispose();
    if (result == null) return;
    try {
      final sent = await _repository.createCustomPlanRequest(
        durationDays: result.durationDays,
        deviceLimit: result.deviceLimit,
        budget: result.budget,
        customerNote: result.note,
        contactEmail: result.email,
        contactPhone: result.phone,
      );
      if (!mounted) return;
      final message = sent.duplicate
          ? s.text('هذا الطلب المخصص موجود مسبقًا لدى الإدارة.', 'This custom request is already pending with administration.')
          : sent.emailSent
              ? s.text('تم إرسال طلب الباقة المخصصة إلى لوحة الإدارة والبريد.', 'The custom-plan request was sent to the admin console and email.')
              : s.text('تم حفظ الطلب في لوحة الإدارة. إرسال البريد يحتاج تفعيل خدمة البريد على Supabase.', 'The request was saved in the admin console. Email delivery requires enabling the mail service on Supabase.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refreshCustomRequests();
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تعذر إرسال الطلب (${e.code}).', 'Could not send request (${e.code}).'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingView();
    if (_activationCode.isEmpty) return _unlinkedView();
    if (_errorCode != null) return _errorView(_errorCode!);
    final snapshot = _snapshot;
    if (snapshot == null) return _errorView('invalid_response');
    return _subscriptionView(snapshot);
  }

  Widget _loadingView() {
    return SurfaceCard(
      child: SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(s.text('جاري تحديث بيانات الاشتراك...', 'Refreshing subscription details...'), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unlinkedView() {
    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(22)),
                  child: const Icon(Icons.workspace_premium_outlined, color: AppColors.primary, size: 34),
                ),
                const SizedBox(height: 16),
                Text(s.text('هذا الجهاز غير مربوط باشتراك بعد', 'This device is not linked to a subscription yet'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  _isOwner
                      ? s.text('اربط كود التفعيل الذي يصدر من THAMAN Admin حتى تظهر هنا الباقة والتواريخ والأجهزة الحقيقية.', 'Link the activation code issued by THAMAN Admin to show the real plan, dates and devices here.')
                      : s.text('يجب على المالك ربط كود التفعيل حتى تظهر بيانات الاشتراك الحقيقية.', 'The owner must link the activation code before real subscription details can be shown.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.55),
                ),
                if (_isOwner) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(onPressed: _editActivationCode, icon: const Icon(Icons.key_rounded, size: 18), label: Text(s.text('ربط كود التفعيل', 'Link activation code'))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(String errorCode) {
    final (title, description) = switch (errorCode) {
      'server_not_configured' => (
          s.text('ربط السيرفر غير مهيأ بعد', 'Server connection is not configured yet'),
          s.text('بيانات Supabase غير مضبوطة في نسخة THAMAN POS الحالية. لن يتم عرض أي بيانات وهمية.', 'Supabase connection values are not configured in this THAMAN POS build. No fake subscription data will be shown.'),
        ),
      'not_found' => (
          s.text('كود التفعيل غير موجود', 'Activation code not found'),
          s.text('تأكد من أن الكود هو نفسه الظاهر في THAMAN Admin وأن الاشتراك موجود في نفس مشروع Supabase.', 'Make sure the code matches THAMAN Admin and the subscription exists in the same Supabase project.'),
        ),
      'device_blocked' => (
          s.text('هذا الجهاز محظور', 'This device is blocked'),
          s.text('تم حظر هذا الجهاز من THAMAN Admin. يجب فك الحظر من لوحة الإدارة.', 'This device is blocked in THAMAN Admin. Unblock it from the admin console.'),
        ),
      'device_limit_reached' => (
          s.text('تم الوصول لحد الأجهزة', 'Device limit reached'),
          s.text('افصل جهازًا آخر من THAMAN Admin أو ارفع حد الأجهزة ثم حاول مرة أخرى.', 'Unlink another device in THAMAN Admin or increase the device limit, then try again.'),
        ),
      'business_suspended' || 'subscription_suspended' => (
          s.text('الوصول موقوف', 'Access suspended'),
          s.text('تم تعليق حساب المتجر أو الاشتراك من THAMAN Admin.', 'The store account or subscription is suspended in THAMAN Admin.'),
        ),
      'subscription_expired' || 'expired' => (
          s.text('الاشتراك منتهي', 'Subscription expired'),
          s.text('جدّد الاشتراك من THAMAN Admin ثم حاول مرة أخرى.', 'Renew the subscription in THAMAN Admin, then try again.'),
        ),
      'catalog_server_error' => (
          s.text('تعذر تحميل الباقات', 'Could not load plans'),
          s.text('تعذر تحميل الباقات من قاعدة البيانات. طبّق SQL 014 ثم أعد المحاولة.', 'Could not load plans from the database. Apply SQL 014 and try again.'),
        ),
      'connection_failed' => (
          s.text('تعذر الاتصال بالسيرفر', 'Could not reach the server'),
          s.text('تحقق من اتصال الإنترنت ثم حاول تحديث بيانات الاشتراك مرة أخرى.', 'Check the internet connection and try refreshing the subscription again.'),
        ),
      'activation_rate_limited' => (
          s.text('تم إيقاف محاولات التفعيل مؤقتًا', 'Activation temporarily rate-limited'),
          s.text('حدثت محاولات تفعيل خاطئة عدة مرات. انتظر 15 دقيقة ثم حاول من جديد.', 'Too many failed activation attempts. Wait 15 minutes and try again.'),
        ),
      'secure_storage_unavailable' => (
          s.text('التخزين الآمن غير متاح', 'Secure storage unavailable'),
          s.text('لن يخزن THAMAN بيانات حماية الجهاز في تخزين غير آمن. أصلح Secure Storage ثم أعد المحاولة.', 'THAMAN will not store device protection secrets in insecure storage. Fix secure storage and try again.'),
        ),
      _ => (
          s.text('تعذر تحميل الاشتراك', 'Could not load subscription'),
          s.text('حدث خطأ أثناء قراءة بيانات الاشتراك. حاول التحديث مرة أخرى.', 'An error occurred while reading the subscription. Try refreshing again.'),
        ),
    };

    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.cloud_off_outlined, color: AppColors.accent, size: 30)),
                const SizedBox(height: 14),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                Text(description, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.55)),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 17), label: Text(s.text('إعادة المحاولة', 'Try again'))),
                    if (_isOwner) OutlinedButton.icon(onPressed: _editActivationCode, icon: const Icon(Icons.key_outlined, size: 17), label: Text(s.text('تغيير كود التفعيل', 'Change activation code'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subscriptionView(SubscriptionSnapshot data) {
    final statusColor = _statusColor(data.status);
    final warning = _warningText(data);
    final width = MediaQuery.sizeOf(context).width;
    final detailWidth = width < 760
        ? (width - 72).clamp(220.0, 640.0).toDouble()
        : width < 1180
            ? 250.0
            : 290.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Container(
            padding: EdgeInsets.all(width < 650 ? 18 : 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFF0F4B43), Color(0xFF083A34)], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.text('الباقة الحالية', 'Current plan'), style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 9.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 5),
                          Text(data.planName.isEmpty ? s.text('بدون اسم', 'Unnamed plan') : data.planName, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                          const SizedBox(height: 7),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _StatusPill(label: _statusLabel(data.status), color: statusColor, darkBackground: true),
                            _StatusPill(label: _cycleLabel(data.billingCycle), color: AppColors.accent, darkBackground: true),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 210),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${data.remainingDuration.inDays}', style: const TextStyle(color: Colors.white, fontSize: 34, height: 1, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(s.text('يوم', 'days'), style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 9.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(_formatRemaining(s, data.remainingDuration), textAlign: TextAlign.end, style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 8.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: data.periodProgress,
                    backgroundColor: Colors.white.withValues(alpha: .16),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(_formatDate(data.startsAt), style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 8.8))),
                  Text(_formatDate(data.endsAt), style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 8.8)),
                ]),
              ],
            ),
          ),
        ),
        if (warning != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: .09), borderRadius: BorderRadius.circular(15), border: Border.all(color: statusColor.withValues(alpha: .22))),
            child: Row(children: [Icon(Icons.notifications_active_outlined, color: statusColor, size: 20), const SizedBox(width: 10), Expanded(child: Text(warning, style: TextStyle(color: statusColor, fontSize: 10, height: 1.45, fontWeight: FontWeight.w800)))]),
          ),
        ],
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(s.text('تفاصيل الاشتراك', 'Subscription details'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: Text(s.text('تحديث', 'Refresh'))),
                if (_isOwner) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(tooltip: s.text('تغيير كود التفعيل', 'Change activation code'), onPressed: _editActivationCode, icon: const Icon(Icons.key_outlined, size: 18)),
                ],
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailBox(width: detailWidth, icon: Icons.person_outline_rounded, label: s.text('اسم المشترك', 'Subscriber'), value: data.subscriberName),
                  _DetailBox(width: detailWidth, icon: Icons.storefront_outlined, label: s.text('اسم المتجر', 'Store'), value: data.businessName),
                  _DetailBox(width: detailWidth, icon: Icons.badge_outlined, label: s.text('رقم الحساب', 'Account number'), value: data.accountNo),
                  _DetailBox(width: detailWidth, icon: Icons.workspace_premium_outlined, label: s.text('الباقة', 'Plan'), value: data.planName),
                  _DetailBox(width: detailWidth, icon: Icons.calendar_month_outlined, label: s.text('تاريخ البداية', 'Start date'), value: _formatDate(data.startsAt)),
                  _DetailBox(width: detailWidth, icon: Icons.event_available_outlined, label: s.text('تاريخ الانتهاء', 'End date'), value: _formatDate(data.endsAt)),
                  _DetailBox(width: detailWidth, icon: Icons.hourglass_bottom_rounded, label: s.text('المدة المتبقية', 'Time remaining'), value: _formatRemaining(s, data.remainingDuration)),
                  _DetailBox(width: detailWidth, icon: Icons.devices_outlined, label: s.text('الأجهزة', 'Devices'), value: '${data.activeDeviceCount} / ${data.deviceLimit}'),
                  _DetailBox(width: detailWidth, icon: Icons.autorenew_rounded, label: s.text('التجديد التلقائي', 'Auto renewal'), value: data.autoRenew ? s.text('مفعّل', 'Enabled') : s.text('غير مفعّل', 'Disabled')),
                  _DetailBox(width: detailWidth, icon: Icons.payments_outlined, label: s.text('سعر الباقة', 'Plan price'), value: data.price.toStringAsFixed(2)),
                  _DetailBox(width: detailWidth, icon: Icons.shield_outlined, label: s.text('فترة السماح', 'Grace period'), value: s.text('${data.gracePeriodDays} يوم', '${data.gracePeriodDays} days')),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.key_rounded, color: AppColors.primary, size: 19)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('كود التفعيل', 'Activation code'), style: const TextStyle(fontSize: 8.5, color: AppColors.muted, fontWeight: FontWeight.w700)), const SizedBox(height: 3), SelectableText(data.activationCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .5))])),
                  IconButton.outlined(
                    tooltip: s.text('نسخ الكود', 'Copy code'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: data.activationCode));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تم نسخ كود التفعيل.', 'Activation code copied.'))));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 17),
                  ),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _plansCatalogCard(data),
        if (_isOwner) ...[
          const SizedBox(height: 14),
          _customRequestConversationsCard(),
        ],
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('الأجهزة المرتبطة', 'Linked devices'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(s.text('الأجهزة المسجلة على هذا الاشتراك كما هي في THAMAN Admin.', 'Devices registered to this subscription as stored in THAMAN Admin.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))])),
                _StatusPill(label: '${data.activeDeviceCount} / ${data.deviceLimit}', color: data.activeDeviceCount >= data.deviceLimit ? AppColors.warning : AppColors.success),
              ]),
              const SizedBox(height: 14),
              if (data.devices.isEmpty)
                Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)), child: Text(s.text('لا توجد أجهزة مسجلة على الاشتراك حتى الآن.', 'No devices are registered to this subscription yet.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)))
              else
                ...data.devices.map((device) => _DeviceTile(device: device, s: s)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _plansCatalogCard(SubscriptionSnapshot current) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.text('الباقات المتاحة', 'Available plans'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(s.text('شاهد باقتك الحالية والباقات والعروض المطروحة من THAMAN Admin.', 'View your current plan plus plans and offers published from THAMAN Admin.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)),
            ])),
            IconButton.outlined(onPressed: _catalogLoading ? null : _refreshCatalog, tooltip: s.text('تحديث الباقات', 'Refresh plans'), icon: _catalogLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 17)),
          ]),
          const SizedBox(height: 14),
          if (_catalogLoading && _catalog == null)
            const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
          else if (_catalogError != null && _catalog == null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Text(s.text('تعذر تحميل قائمة الباقات الآن. جرّب التحديث.', 'Could not load the plan catalog now. Try refreshing.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            )
          else if ((_catalog?.plans ?? const <AvailableSubscriptionPlan>[]).isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
              child: Text(s.text('لا توجد باقات مطروحة حاليًا.', 'No plans are currently published.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth >= 900 ? (constraints.maxWidth - 20) / 3 : constraints.maxWidth >= 570 ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _catalog!.plans.map((plan) {
                  final accent = plan.isCurrent ? AppColors.primary : (plan.isOffer ? AppColors.warning : AppColors.blue);
                  final cycle = plan.billingCycle == 'custom'
                      ? s.text('${plan.customDurationDays ?? current.endsAt.difference(current.startsAt).inDays} يوم', '${plan.customDurationDays ?? current.endsAt.difference(current.startsAt).inDays} days')
                      : _cycleLabel(plan.billingCycle);
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: plan.isCurrent ? .35 : .16), width: plan.isCurrent ? 1.4 : 1)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(plan.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
                          if (plan.isCurrent) _StatusPill(label: s.text('باقتك الحالية', 'Current'), color: AppColors.success),
                          if (!plan.isCurrent && plan.isOffer) _StatusPill(label: plan.offerBadge.isEmpty ? s.text('عرض', 'Offer') : plan.offerBadge, color: AppColors.warning),
                          if (!plan.isCurrent && plan.isCustom) _StatusPill(label: s.text('مخصصة لك', 'Custom for you'), color: AppColors.blue),
                        ]),
                        if (plan.description.isNotEmpty) ...[const SizedBox(height: 7), Text(plan.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.3, color: AppColors.muted, height: 1.45))],
                        const SizedBox(height: 12),
                        if (plan.previousPrice != null && plan.previousPrice! > plan.price) Text(plan.previousPrice!.toStringAsFixed(2), style: const TextStyle(fontSize: 9.5, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                        Text(plan.price.toStringAsFixed(2), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 10, runSpacing: 6, children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.schedule_outlined, size: 14, color: AppColors.muted), const SizedBox(width: 4), Text(cycle, style: const TextStyle(fontSize: 9, color: AppColors.muted))]),
                          Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.devices_outlined, size: 14, color: AppColors.muted), const SizedBox(width: 4), Text(s.text('${plan.maxDevices} أجهزة', '${plan.maxDevices} devices'), style: const TextStyle(fontSize: 9, color: AppColors.muted))]),
                        ]),
                        if (_isOwner) ...[
                          const SizedBox(height: 13),
                          OutlinedButton.icon(
                            onPressed: () => _requestPlan(plan),
                            icon: Icon(plan.isCurrent ? Icons.autorenew_rounded : Icons.send_outlined, size: 16),
                            label: Text(plan.isCurrent ? s.text('طلب تجديد', 'Request renewal') : s.text('طلب هذه الباقة', 'Request this plan')),
                          ),
                        ],
                      ]),
                    ),
                  );
                }).toList(),
              );
            }),
          if (_isOwner) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.primary.withValues(alpha: .14))),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.tune_rounded, color: AppColors.primary)),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.text('احتياجك مختلف؟', 'Need something different?'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(s.text('اطلب باقة مخصصة وحدد المدة وعدد الأجهزة والميزانية والتفاصيل.', 'Request a custom plan and specify duration, devices, budget and details.'), style: const TextStyle(fontSize: 8.8, color: AppColors.muted)),
                ])),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: _requestCustomPlan, icon: const Icon(Icons.send_outlined, size: 16), label: Text(s.text('طلب مخصص', 'Custom request'))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _customRequestConversationsCard() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.text('طلبات الباقة المخصصة والمراسلات', 'Custom-plan requests & messages'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(s.text('أي رد من إدارة THAMAN يظهر هنا ويمكنك متابعة المحادثة من نفس الطلب.', 'Replies from THAMAN administration appear here and you can continue the conversation on the same request.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)),
            ])),
            IconButton.outlined(onPressed: _requestsLoading ? null : _refreshCustomRequests, icon: _requestsLoading ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 17)),
          ]),
          const SizedBox(height: 12),
          if (_requestsError != null && _customRequests.isEmpty)
            Text(s.text('تعذر تحميل المراسلات الآن.', 'Could not load messages right now.'), style: const TextStyle(fontSize: 9.5, color: AppColors.muted))
          else if (_customRequests.isEmpty)
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)), child: Text(s.text('لا يوجد طلب باقة مخصصة حتى الآن.', 'No custom-plan request yet.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)))
          else
            ..._customRequests.map((request) {
              final last = request.messages.isEmpty ? null : request.messages.last;
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.tune_rounded, color: AppColors.primary)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(s.text('طلب باقة مخصصة', 'Custom-plan request'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900))),
                      _StatusPill(label: _requestStatusLabel(request.status), color: _requestStatusColor(request.status)),
                    ]),
                    const SizedBox(height: 4),
                    Text([
                      if (request.requestedDurationDays != null) s.text('${request.requestedDurationDays} يوم', '${request.requestedDurationDays} days'),
                      if (request.requestedDeviceLimit != null) s.text('${request.requestedDeviceLimit} أجهزة', '${request.requestedDeviceLimit} devices'),
                      _formatDateTime(request.createdAt),
                    ].join(' • '), style: const TextStyle(fontSize: 8.5, color: AppColors.muted)),
                    if (last != null) ...[const SizedBox(height: 5), Text(last.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.8, color: AppColors.text))],
                  ])),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openCustomRequestChat(request),
                    icon: Badge(isLabelVisible: request.unreadOwnerCount > 0, label: Text('${request.unreadOwnerCount}'), child: const Icon(Icons.forum_outlined, size: 16)),
                    label: Text(s.text('مراسلة', 'Message')),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }

  String _requestStatusLabel(String status) => switch (status) {
        'new' => s.text('جديد', 'New'),
        'contacting' => s.text('قيد التواصل', 'Contacting'),
        'completed' => s.text('مكتمل', 'Completed'),
        'rejected' => s.text('مرفوض', 'Rejected'),
        _ => status,
      };

  Color _requestStatusColor(String status) => switch (status) {
        'completed' => AppColors.success,
        'rejected' => AppColors.danger,
        'contacting' => AppColors.blue,
        _ => AppColors.warning,
      };

  String? _warningText(SubscriptionSnapshot data) {
    if (data.status == 'grace') {
      return s.text('انتهت مدة الاشتراك ودخلت فترة السماح. متبقي ${data.graceDaysRemaining} يوم قبل الإيقاف الكامل.', 'The subscription has ended and is in its grace period. ${data.graceDaysRemaining} days remain before full suspension.');
    }
    if (data.status == 'expired') return s.text('انتهى الاشتراك. يجب تجديد الباقة من THAMAN Admin لاستمرار الخدمة.', 'The subscription has expired. Renew it from THAMAN Admin to continue service.');
    if (data.status == 'suspended') return s.text('الاشتراك معلّق حاليًا من إدارة THAMAN.', 'This subscription is currently suspended by THAMAN administration.');
    if (data.status == 'pending') return s.text('الاشتراك بانتظار التفعيل.', 'This subscription is waiting for activation.');
    if (data.isNearExpiry) return s.text('اشتراكك يقترب من الانتهاء. المدة الفعلية المتبقية: ${_formatRemaining(s, data.remainingDuration)}.', 'Your subscription is nearing expiry. Actual time remaining: ${_formatRemaining(s, data.remainingDuration)}.');
    return null;
  }

  String _statusLabel(String status) => switch (status) {
        'active' => s.text('فعال', 'Active'),
        'trial' => s.text('تجريبي', 'Trial'),
        'grace' => s.text('فترة سماح', 'Grace period'),
        'suspended' => s.text('معلّق', 'Suspended'),
        'expired' => s.text('منتهي', 'Expired'),
        'pending' => s.text('بانتظار التفعيل', 'Pending'),
        _ => status,
      };

  String _cycleLabel(String cycle) => switch (cycle) {
        'monthly' => s.text('شهري', 'Monthly'),
        'yearly' => s.text('سنوي', 'Yearly'),
        'custom' => s.text('مخصص', 'Custom'),
        _ => cycle,
      };

  Color _statusColor(String status) => switch (status) {
        'active' => AppColors.success,
        'trial' => AppColors.blue,
        'grace' => AppColors.warning,
        'pending' => AppColors.warning,
        'suspended' || 'expired' => AppColors.danger,
        _ => AppColors.muted,
      };
}

class _DetailBox extends StatelessWidget {
  const _DetailBox({required this.width, required this.icon, required this.label, required this.value});
  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: AppColors.primary, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 8.3, color: AppColors.muted, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(value.isEmpty ? '—' : value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))])),
        ]),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.s});
  final SubscriptionDeviceInfo device;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final color = device.blocked ? AppColors.danger : (device.active ? AppColors.success : AppColors.muted);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)), child: Icon(_platformIcon(device.platform), color: color, size: 20)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(device.name.isEmpty ? s.text('جهاز THAMAN', 'THAMAN device') : device.name, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text([
            if (device.platform.isNotEmpty) device.platform,
            if (device.appVersion.isNotEmpty) 'v${device.appVersion}',
            if (device.lastSeenAt != null) '${s.text('آخر اتصال', 'Last seen')}: ${_formatDateTime(device.lastSeenAt!)}',
          ].join(' • '), style: const TextStyle(fontSize: 8.4, color: AppColors.muted)),
        ])),
        const SizedBox(width: 10),
        _StatusPill(label: device.blocked ? s.text('محظور', 'Blocked') : (device.active ? s.text('مرتبط', 'Linked') : s.text('مفصول', 'Unlinked')), color: color),
      ]),
    );
  }

  static IconData _platformIcon(String platform) {
    final value = platform.toLowerCase();
    if (value.contains('windows')) return Icons.desktop_windows_outlined;
    if (value.contains('android')) return Icons.android_rounded;
    if (value.contains('ios') || value.contains('iphone') || value.contains('ipad')) return Icons.phone_iphone_rounded;
    if (value.contains('mac')) return Icons.laptop_mac_outlined;
    if (value.contains('web')) return Icons.language_rounded;
    return Icons.devices_other_outlined;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color, this.darkBackground = false});
  final String label;
  final Color color;
  final bool darkBackground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: darkBackground ? Colors.white.withValues(alpha: .12) : color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: darkBackground ? Colors.white.withValues(alpha: .18) : color.withValues(alpha: .2)),
        ),
        child: Text(label, style: TextStyle(color: darkBackground ? Colors.white : color, fontSize: 8.7, fontWeight: FontWeight.w900)),
      );
}

String _formatRemaining(AppStrings s, Duration duration) {
  if (duration <= Duration.zero) return s.text('منتهي', 'Expired');
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  if (days > 0) return s.text('$days يوم، $hours ساعة، $minutes دقيقة', '$days days, $hours hours, $minutes minutes');
  if (hours > 0) return s.text('$hours ساعة، $minutes دقيقة', '$hours hours, $minutes minutes');
  return s.text('$minutes دقيقة', '$minutes minutes');
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatDateTime(DateTime value) => '${_formatDate(value)} ${formatHour12(value)}';
