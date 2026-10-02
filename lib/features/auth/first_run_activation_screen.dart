import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/credential_hash.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/language_switch.dart';
import '../../data/app_data_store.dart';

class FirstRunActivationScreen extends StatefulWidget {
  const FirstRunActivationScreen({
    super.key,
    required this.onCompleted,
    this.requireOwnerSetup = true,
    this.initialErrorCode,
  });

  final VoidCallback onCompleted;
  final bool requireOwnerSetup;
  final String? initialErrorCode;

  @override
  State<FirstRunActivationScreen> createState() => _FirstRunActivationScreenState();
}

class _FirstRunActivationScreenState extends State<FirstRunActivationScreen> {
  static const String supportEmail = 'albhytytymr6@gmail.com';

  final SubscriptionRepository _repository = SubscriptionRepository();
  final activationCode = TextEditingController();
  final ownerName = TextEditingController();
  final ownerPhone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final pin = TextEditingController();

  int step = 0;
  bool busy = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;
  bool obscurePin = true;
  String? errorCode;
  SubscriptionSnapshot? subscription;

  @override
  void initState() {
    super.initState();
    errorCode = widget.initialErrorCode;
    _loadExistingCode();
  }

  Future<void> _loadExistingCode() async {
    final code = await _repository.loadActivationCode();
    if (!mounted || code.isEmpty) return;
    activationCode.text = code;
  }

  @override
  void dispose() {
    for (final controller in [activationCode, ownerName, ownerPhone, email, password, confirmPassword, pin]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _activate() async {
    if (busy) return;
    final code = activationCode.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => errorCode = 'activation_code_missing');
      return;
    }
    setState(() {
      busy = true;
      errorCode = null;
    });
    try {
      final snapshot = await _repository.activateDevice(code);
      if (!mounted) return;

      // The owner is a business-level cloud identity. A second licensed device
      // must never ask the same owner to create the account again.
      final cloudOwner = await _repository.ownerStatus();
      if (cloudOwner.exists) {
        await _repository.markFirstRunComplete();
        if (mounted) widget.onCompleted();
        return;
      }

      // Upgrade path for shops created before cloud-owner sync existed: mirror
      // the existing local owner once, without asking the customer to re-enter
      // all data.
      final localOwner = AppDataStore.instance.adminAccountByRole('owner');
      if (localOwner != null &&
          !widget.requireOwnerSetup &&
          !CredentialHash.isHash(localOwner.password) &&
          !CredentialHash.isHash(localOwner.pin)) {
        await _repository.provisionOwner(
          displayName: localOwner.nameAr,
          phone: localOwner.phone,
          email: localOwner.email,
          password: localOwner.password,
          pin: localOwner.pin,
        );
        await _repository.markFirstRunComplete();
        if (mounted) widget.onCompleted();
        return;
      }

      ownerName.text = snapshot.subscriberName.trim();
      setState(() {
        subscription = snapshot;
        step = 1;
      });
    } on SubscriptionLookupException catch (e) {
      if (mounted) setState(() => errorCode = e.code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _createOwner() async {
    if (busy) return;
    final normalizedEmail = email.text.trim().toLowerCase();
    final pwd = password.text;
    final confirm = confirmPassword.text;
    final managementPin = pin.text.trim();

    if (ownerName.text.trim().isEmpty) {
      setState(() => errorCode = 'owner_name_missing');
      return;
    }
    if (ownerPhone.text.trim().isEmpty) {
      setState(() => errorCode = 'phone_missing');
      return;
    }
    if (!_looksLikeEmail(normalizedEmail)) {
      setState(() => errorCode = 'email_invalid');
      return;
    }
    if (pwd.isEmpty) {
      setState(() => errorCode = 'password_short');
      return;
    }
    if (pwd != confirm) {
      setState(() => errorCode = 'password_mismatch');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(managementPin)) {
      setState(() => errorCode = 'pin_invalid');
      return;
    }

    setState(() {
      busy = true;
      errorCode = null;
    });
    try {
      await _repository.provisionOwner(
        displayName: ownerName.text.trim(),
        phone: ownerPhone.text.trim(),
        email: normalizedEmail,
        password: pwd,
        pin: managementPin,
      );
      await AppDataStore.instance.provisionOwnerAccount(
        name: ownerName.text.trim(),
        phone: ownerPhone.text.trim(),
        email: normalizedEmail,
        password: pwd,
        pin: managementPin,
      );
      await _repository.markFirstRunComplete();
      if (mounted) widget.onCompleted();
    } on SubscriptionLookupException catch (e) {
      if (mounted) setState(() => errorCode = e.code);
    } catch (_) {
      if (mounted) setState(() => errorCode = 'owner_setup_failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      body: SafeArea(
        child: BrandPattern(
          borderRadius: BorderRadius.zero,
          child: Container(
            color: AppColors.background.withValues(alpha: .96),
            alignment: Alignment.center,
            padding: EdgeInsets.all(compact ? 14 : 28),
            child: SingleChildScrollView(
              child: Container(
                width: (MediaQuery.sizeOf(context).width - 28).clamp(0.0, 720.0).toDouble(),
                padding: EdgeInsets.all(compact ? 20 : 30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Color(0x12083A34), blurRadius: 55, offset: Offset(0, 22))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const AppLogo(),
                        const Spacer(),
                        const LanguageSwitch(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _ProgressHeader(step: step, s: s),
                    const SizedBox(height: 24),
                    if (step == 0) _activationStep(s) else _ownerStep(s),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _activationStep(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('فعّل THAMAN POS', 'Activate THAMAN POS'), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: AppColors.text)),
        const SizedBox(height: 7),
        Text(
          s.text(
            'أدخل كود التفعيل الذي استلمته من إدارة THAMAN. إذا كان حساب المالك موجودًا مسبقًا سيتم ربط الجهاز والانتقال مباشرة لتسجيل الدخول بدون إعادة البيانات.',
            'Enter the activation code issued by THAMAN. If the owner account already exists, this device will be linked and you will go directly to sign in without re-entering owner details.',
          ),
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withValues(alpha: .12))),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(s.text('التفعيل الأول يحتاج اتصال إنترنت. بعد التفعيل يحتفظ النظام بهوية الجهاز محليًا.', 'First activation requires internet. After activation, the app keeps this installation identity locally.'), style: const TextStyle(fontSize: 9.2, color: AppColors.primary, fontWeight: FontWeight.w700, height: 1.45))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: activationCode,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() => errorCode = null),
          decoration: InputDecoration(
            labelText: s.text('كود التفعيل', 'Activation code'),
            hintText: 'THM-ABCD-1234',
            prefixIcon: const Icon(Icons.key_rounded),
          ),
        ),
        if (errorCode != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(
            message: _errorMessage(s, errorCode!),
            supportLabel: _requiresSupport(errorCode!)
                ? s.text('للمساعدة تواصل مع إدارة THAMAN', 'For assistance, contact THAMAN administration')
                : null,
            supportEmail: _requiresSupport(errorCode!) ? supportEmail : null,
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy ? null : _activate,
          icon: busy
              ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.rocket_launch_outlined, size: 18),
          label: Text(s.text('تحقق وفعّل هذا الجهاز', 'Verify & activate this device')),
        ),
      ],
    );
  }

  Widget _ownerStep(AppStrings s) {
    final data = subscription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('أنشئ حساب المالك', 'Create the owner account'), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: AppColors.text)),
        const SizedBox(height: 7),
        Text(
          s.text(
            'تم قبول كود التفعيل وربط الجهاز. الآن أنشئ بيانات الدخول التي ستستخدمها لإدارة هذا المتجر.',
            'The activation code was accepted and this device is linked. Now create the credentials you will use to manage this store.',
          ),
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
        ),
        if (data != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _MiniActivationInfo(icon: Icons.person_outline_rounded, text: data.subscriberName),
                _MiniActivationInfo(icon: Icons.storefront_outlined, text: data.businessName),
                _MiniActivationInfo(icon: Icons.workspace_premium_outlined, text: data.planName),
                _MiniActivationInfo(icon: Icons.devices_outlined, text: '${data.activeDeviceCount} / ${data.deviceLimit}'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: ownerName,
          decoration: InputDecoration(labelText: s.text('اسم المالك', 'Owner name'), prefixIcon: const Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ownerPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: s.text('رقم الجوال', 'Mobile number'), prefixIcon: const Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(labelText: s.text('البريد الإلكتروني', 'Email address'), prefixIcon: const Icon(Icons.mail_outline_rounded)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: password,
          obscureText: obscurePassword,
          decoration: InputDecoration(
            labelText: s.text('كلمة المرور (8 أحرف على الأقل)', 'Password (at least 8 characters)'),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(onPressed: () => setState(() => obscurePassword = !obscurePassword), icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: confirmPassword,
          obscureText: obscureConfirm,
          decoration: InputDecoration(
            labelText: s.text('تأكيد كلمة المرور', 'Confirm password'),
            prefixIcon: const Icon(Icons.lock_reset_rounded),
            suffixIcon: IconButton(onPressed: () => setState(() => obscureConfirm = !obscureConfirm), icon: Icon(obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: pin,
          obscureText: obscurePin,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: InputDecoration(
            labelText: s.text('رمز الإدارة PIN (4 أرقام)', 'Management PIN (4 digits)'),
            prefixIcon: const Icon(Icons.password_rounded),
            suffixIcon: IconButton(onPressed: () => setState(() => obscurePin = !obscurePin), icon: Icon(obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
          ),
        ),
        if (errorCode != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(
            message: _errorMessage(s, errorCode!),
            supportLabel: _requiresSupport(errorCode!)
                ? s.text('للمساعدة تواصل مع إدارة THAMAN', 'For assistance, contact THAMAN administration')
                : null,
            supportEmail: _requiresSupport(errorCode!) ? supportEmail : null,
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            OutlinedButton.icon(onPressed: busy ? null : () => setState(() { step = 0; errorCode = null; }), icon: const Icon(Icons.arrow_back_rounded, size: 17), label: Text(s.text('رجوع', 'Back'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _createOwner,
                icon: busy
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(s.text('إنشاء الحساب وبدء THAMAN', 'Create account & start THAMAN')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _requiresSupport(String code) {
    if (code.startsWith('subscription_')) return true;
    return const {
      'not_found',
      'business_suspended',
      'expired',
      'device_blocked',
      'device_limit_reached',
      'device_registered_elsewhere',
      'device_not_registered',
      'device_unlinked',
      'license_denied',
    }.contains(code);
  }

  String _errorMessage(AppStrings s, String code) => switch (code) {
        'server_not_configured' => s.text('هذه النسخة غير مربوطة بسيرفر THAMAN. ابنِ التطبيق مع بيانات Supabase أولًا.', 'This build is not connected to the THAMAN server. Build it with the Supabase values first.'),
        'activation_code_missing' => s.text('أدخل كود التفعيل.', 'Enter the activation code.'),
        'not_found' => s.text('كود التفعيل غير صحيح، أو تم حذف/إلغاء الاشتراك المرتبط به.', 'The activation code is invalid, or its subscription was deleted/cancelled.'),
        'business_suspended' => s.text('حساب المشترك موقوف من إدارة THAMAN. تواصل مع الإدارة لإعادة التفعيل.', 'This subscriber account is suspended by THAMAN. Contact administration to reactivate it.'),
        'subscription_suspended' => s.text('الاشتراك موقوف أو ملغى من إدارة THAMAN. تواصل مع الإدارة لإعادة التفعيل.', 'The subscription is suspended or cancelled by THAMAN. Contact administration to reactivate it.'),
        'subscription_pending' => s.text('الاشتراك بانتظار التفعيل من إدارة THAMAN.', 'The subscription is still pending activation by THAMAN.'),
        'subscription_expired' || 'expired' => s.text('الاشتراك منتهي. تواصل مع إدارة THAMAN للتجديد وإعادة التفعيل.', 'The subscription has expired. Contact THAMAN administration to renew and reactivate it.'),
        'device_limit_reached' => s.text('تم الوصول للحد الأقصى للأجهزة. افصل جهازًا من THAMAN Admin أو ارفع الحد.', 'The device limit has been reached. Unlink a device in THAMAN Admin or increase the limit.'),
        'device_blocked' => s.text('هذا الجهاز محظور من إدارة THAMAN ولا يمكن تفعيله حتى يتم فك الحظر.', 'This device is blocked by THAMAN administration and cannot be activated until it is unblocked.'),
        'device_registered_elsewhere' => s.text('هذا الجهاز مرتبط بمشترك آخر. تواصل مع إدارة THAMAN لمراجعة ربط الجهاز.', 'This device is linked to another subscriber. Contact THAMAN administration to review the device binding.'),
        'connection_failed' => s.text('تعذر الاتصال بالسيرفر. تحقق من الإنترنت وحاول مرة أخرى.', 'Could not reach the server. Check your internet connection and try again.'),
        'activation_rate_limited' => s.text('تم إدخال أكواد تفعيل خاطئة عدة مرات. انتظر 15 دقيقة ثم حاول مجددًا.', 'Too many failed activation attempts. Wait 15 minutes and try again.'),
        'secure_storage_unavailable' => s.text('تعذر الوصول إلى التخزين الآمن في هذا الجهاز، لذلك أوقف THAMAN التفعيل لحماية الترخيص. أعد تشغيل الجهاز أو أصلح Secure Storage ثم حاول مجددًا.', 'Secure storage is unavailable on this device, so THAMAN stopped activation to protect the license. Restart the device or fix secure storage and try again.'),
        'owner_name_missing' => s.text('أدخل اسم المالك.', 'Enter the owner name.'),
        'phone_missing' => s.text('أدخل رقم جوال المالك.', 'Enter the owner mobile number.'),
        'email_invalid' => s.text('أدخل بريدًا إلكترونيًا صحيحًا.', 'Enter a valid email address.'),
        'email_already_used' => s.text('هذا البريد مستخدم لحساب مالك آخر.', 'This email is already used by another owner account.'),
        'owner_already_exists' => s.text('حساب المالك موجود مسبقًا. ارجع وأعد إدخال كود التفعيل للانتقال إلى تسجيل الدخول.', 'The owner account already exists. Go back and enter the activation code again to continue to sign in.'),
        'password_short' => s.text('أدخل كلمة مرور. ننصح بكلمة طويلة ومميزة.', 'Enter a password. A long unique password is recommended.'),
        'password_mismatch' => s.text('كلمتا المرور غير متطابقتين.', 'The passwords do not match.'),
        'pin_invalid' => s.text('رمز الإدارة يجب أن يكون 4 أرقام.', 'The management PIN must be exactly 4 digits.'),
        'owner_setup_failed' => s.text('تعذر إنشاء حساب المالك. حاول مرة أخرى.', 'Could not create the owner account. Try again.'),
        'device_not_registered' => s.text('تم حذف تسجيل هذا الجهاز. أدخل كود تفعيل صالح لربطه من جديد.', 'This device registration was removed. Enter a valid activation code to link it again.'),
        'device_unlinked' => s.text('تم فصل هذا الجهاز من إدارة THAMAN. أدخل كود تفعيل صالح لربطه من جديد.', 'This device was unlinked by THAMAN administration. Enter a valid activation code to link it again.'),
        _ => s.text('تعذر إكمال التفعيل. تحقق من البيانات وحاول مرة أخرى.', 'Activation could not be completed. Check the details and try again.'),
      };
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.s});
  final int step;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    Widget item(int index, String title, IconData icon) {
      final active = index <= step;
      return Expanded(
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: active ? AppColors.primary : AppColors.surfaceAlt, shape: BoxShape.circle, border: Border.all(color: active ? AppColors.primary : AppColors.border)),
              child: Icon(icon, size: 17, color: active ? Colors.white : AppColors.muted),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(title, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: active ? AppColors.text : AppColors.muted))),
          ],
        ),
      );
    }

    return Row(
      children: [
        item(0, s.text('تفعيل الاشتراك', 'Activate subscription'), Icons.vpn_key_outlined),
        Container(width: 26, height: 1, color: AppColors.border),
        item(1, s.text('حساب المالك', 'Owner account'), Icons.admin_panel_settings_outlined),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.supportLabel, this.supportEmail});

  final String message;
  final String? supportLabel;
  final String? supportEmail;

  @override
  Widget build(BuildContext context) {
    final hasSupport = (supportEmail ?? '').trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2CACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 9.4, height: 1.45, color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (hasSupport) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: const Color(0xFFF2CACA)),
            const SizedBox(height: 9),
            Text(
              supportLabel ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: AppColors.text, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            SelectableText(
              supportEmail!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w900),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniActivationInfo extends StatelessWidget {
  const _MiniActivationInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(text.isEmpty ? '—' : text, style: const TextStyle(fontSize: 9.4, color: AppColors.text, fontWeight: FontWeight.w800)),
        ],
      );
}
