import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/auth_service.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/language_switch.dart';
import '../../data/app_data_store.dart';
import '../management/management_shell.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final pin = TextEditingController();
  final SubscriptionRepository repository = SubscriptionRepository();

  bool obscurePassword = true;
  bool obscurePin = true;
  bool loading = false;
  String selectedRole = 'owner';
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final compact = MediaQuery.sizeOf(context).width < 700;
    final ownerSelected = selectedRole == 'owner';

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: BrandPattern(
                borderRadius: BorderRadius.zero,
                child: Container(color: AppColors.background.withValues(alpha: .95)),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 28),
                child: Container(
                  width: (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 520.0).toDouble(),
                  padding: EdgeInsets.all(compact ? 22 : 30),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .98),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [BoxShadow(color: Color(0x12083A34), blurRadius: 50, offset: Offset(0, 22))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton.outlined(
                            tooltip: s.text('رجوع', 'Back'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(controller.isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
                          ),
                          const Spacer(),
                          const LanguageSwitch(),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Center(child: AppLogo()),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(30)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_user_outlined, size: 15, color: AppColors.primary),
                              const SizedBox(width: 7),
                              Text(s.text('وصول إداري محمي', 'Protected management access'), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(s.text('تسجيل دخول الإدارة', 'Management sign in'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                      const SizedBox(height: 7),
                      Text(
                        s.text(
                          ownerSelected
                              ? 'المالك يدخل بالبريد الإلكتروني وكلمة المرور ورمز PIN لطبقة حماية إضافية. الحساب مرتبط بالمشترك ويعمل على الأجهزة المفعّلة.'
                              : 'المدير والمحاسب يحتاجان البريد الإلكتروني وكلمة المرور ورمز الإدارة PIN.',
                          ownerSelected
                              ? 'The owner signs in with email, password and PIN for an additional security layer. The account works on activated devices.'
                              : 'Managers and accountants require email, password and the management PIN.',
                        ),
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.6),
                      ),
                      const SizedBox(height: 18),
                      Text(s.text('نوع الحساب الإداري', 'Management account type'), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _RoleChip(label: s.text('المالك', 'Owner'), icon: Icons.workspace_premium_outlined, selected: selectedRole == 'owner', onTap: () => _selectRole('owner')),
                          _RoleChip(label: s.text('المدير', 'Manager'), icon: Icons.manage_accounts_outlined, selected: selectedRole == 'manager', onTap: () => _selectRole('manager')),
                          _RoleChip(label: s.text('المحاسب', 'Accountant'), icon: Icons.account_balance_outlined, selected: selectedRole == 'accountant', onTap: () => _selectRole('accountant')),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: s.text('البريد الإلكتروني', 'Email address'), prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18)),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: password,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: s.text('كلمة المرور', 'Password'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                            icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                          ),
                        ),
                      ),
                      if (ownerSelected)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: loading ? null : _forgotPassword,
                            icon: const Icon(Icons.lock_reset_rounded, size: 17),
                            label: Text(s.text('نسيت كلمة المرور؟', 'Forgot password?')),
                          ),
                        ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: pin,
                        obscureText: obscurePin,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: s.text('رمز الإدارة PIN', 'Management PIN'),
                          prefixIcon: const Icon(Icons.password_rounded, size: 18),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscurePin = !obscurePin),
                            icon: Icon(obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF3CACA))),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 17, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Expanded(child: Text(error!, style: const TextStyle(fontSize: 9.5, color: AppColors.danger, height: 1.45))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: loading ? null : _submit,
                          icon: loading
                              ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.login_rounded, size: 18),
                          label: Text(s.text('الدخول إلى لوحة الإدارة', 'Enter management dashboard')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectRole(String role) {
    setState(() {
      selectedRole = role;
      error = null;
      email.clear();
      password.clear();
      pin.clear();
    });
  }

  Future<void> _submit() async {
    final controller = AppScope.of(context);
    setState(() {
      loading = true;
      error = null;
    });

    if (selectedRole == 'owner') {
      try {
        final profile = await repository.ownerLogin(email: email.text, password: password.text, pin: pin.text);
        var effectivePassword = password.text;
        if (profile.mustChangePassword) {
          final replacement = await _forceTemporaryPasswordChange(
            profile: profile,
            currentPassword: password.text,
          );
          if (replacement == null || !mounted) {
            if (mounted) setState(() => loading = false);
            return;
          }
          effectivePassword = replacement;
          password.text = replacement;
        }
        await AppDataStore.instance.upsertOwnerCache(
          name: profile.displayName,
          email: profile.email,
          phone: profile.phone,
          password: effectivePassword,
        );
        if (!mounted) return;
        controller.signIn(UserRole.owner, name: profile.displayName, management: true);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const ManagementShell()),
          (route) => route.isFirst,
        );
        return;
      } on SubscriptionLookupException catch (e) {
        // Owner credentials are authoritative in Supabase. Requiring an online
        // check at sign-in prevents an old cached password from bypassing a
        // password reset performed by THAMAN Admin.
        if (!mounted) return;
        setState(() => error = _loginError(controller.isArabic, e.code));
      } finally {
        if (mounted) setState(() => loading = false);
      }
      return;
    }

    final result = AuthService.managementLogin(
      email: email.text,
      password: password.text,
      pin: pin.text,
      arabic: controller.isArabic,
    );
    if (!result.success || result.role == null) {
      setState(() {
        loading = false;
        error = controller.isArabic ? result.messageAr : result.messageEn;
      });
      return;
    }
    final expectedRole = selectedRole == 'manager' ? UserRole.manager : UserRole.accountant;
    if (result.role != expectedRole) {
      setState(() {
        loading = false;
        error = controller.isArabic ? 'بيانات الدخول صحيحة لكن الحساب لا يطابق نوع الحساب الذي اخترته.' : 'The credentials are valid, but the account does not match the selected role.';
      });
      return;
    }
    controller.signIn(result.role!, name: result.name, management: true);
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const ManagementShell()),
          (route) => route.isFirst,
        );
      setState(() => loading = false);
    }
  }

  Future<String?> _forceTemporaryPasswordChange({
    required OwnerCloudProfile profile,
    required String currentPassword,
  }) async {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final nextPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    String? dialogError;
    bool saving = false;
    bool hideNext = true;
    bool hideConfirm = true;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(s.text('غيّر كلمة المرور المؤقتة', 'Change temporary password')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.text(
                    'تم تعيين كلمة مرور مؤقتة لهذا الحساب من THAMAN Admin. قبل الدخول، اختر كلمة مرور جديدة خاصة بك.',
                    'A temporary password was set for this account from THAMAN Admin. Choose your own new password before continuing.',
                  ),
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.55),
                ),
                if (profile.temporaryPasswordExpiresAt != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    s.text(
                      'صلاحية الكلمة المؤقتة حتى: ${profile.temporaryPasswordExpiresAt!.toLocal()}',
                      'Temporary password valid until: ${profile.temporaryPasswordExpiresAt!.toLocal()}',
                    ),
                    style: const TextStyle(fontSize: 9.5, color: AppColors.warning, fontWeight: FontWeight.w800),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: nextPassword,
                  obscureText: hideNext,
                  decoration: InputDecoration(
                    labelText: s.text('كلمة المرور الجديدة', 'New password'),
                    prefixIcon: const Icon(Icons.lock_reset_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setD(() => hideNext = !hideNext),
                      icon: Icon(hideNext ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassword,
                  obscureText: hideConfirm,
                  decoration: InputDecoration(
                    labelText: s.text('تأكيد كلمة المرور', 'Confirm password'),
                    prefixIcon: const Icon(Icons.verified_user_outlined),
                    suffixIcon: IconButton(
                      onPressed: () => setD(() => hideConfirm = !hideConfirm),
                      icon: Icon(hideConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(dialogError!, style: const TextStyle(color: AppColors.danger, fontSize: 9.5, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(s.text('إلغاء', 'Cancel')),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final next = nextPassword.text;
                      if (next.isEmpty) {
                        setD(() => dialogError = s.text('كلمة المرور لا يمكن أن تكون فارغة.', 'Password cannot be empty.'));
                        return;
                      }
                      if (next != confirmPassword.text) {
                        setD(() => dialogError = s.text('كلمتا المرور غير متطابقتين.', 'Passwords do not match.'));
                        return;
                      }
                      if (next == currentPassword) {
                        setD(() => dialogError = s.text('اختر كلمة مرور مختلفة عن الكلمة المؤقتة.', 'Choose a password different from the temporary password.'));
                        return;
                      }
                      setD(() { saving = true; dialogError = null; });
                      try {
                        await repository.changeOwnerPassword(
                          email: profile.email,
                          currentPassword: currentPassword,
                          newPassword: next,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext, next);
                      } on SubscriptionLookupException catch (e) {
                        setD(() {
                          saving = false;
                          dialogError = switch (e.code) {
                            'invalid_credentials' => s.text('تم تغيير كلمة المرور المؤقتة أو لم تعد صحيحة. سجّل الدخول بالكلمة الأحدث.', 'The temporary password was changed or is no longer valid. Sign in using the latest password.'),
                            'temporary_password_expired' => s.text('انتهت مهلة كلمة المرور المؤقتة. تواصل مع إدارة THAMAN لتعيين كلمة جديدة.', 'The temporary password expired. Contact THAMAN administration for a new one.'),
                            'password_same' => s.text('اختر كلمة مرور مختلفة عن الكلمة المؤقتة.', 'Choose a password different from the temporary password.'),
                            'password_weak' => s.text('اختر كلمة مرور غير فارغة. ننصح بكلمة طويلة ومميزة.', 'Choose a non-empty password. A long unique password is recommended.'),
                            'connection_failed' => s.text('يلزم الاتصال بالإنترنت لتغيير كلمة المرور المؤقتة.', 'An internet connection is required to change the temporary password.'),
                            _ => s.text('تعذر تغيير كلمة المرور الآن.', 'Could not change the password right now.'),
                          };
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 17),
              label: Text(s.text('حفظ والمتابعة', 'Save and continue')),
            ),
          ],
        ),
      ),
    );

    nextPassword.dispose();
    confirmPassword.dispose();
    return result;
  }

  String _loginError(bool ar, String code) => switch (code) {
        'invalid_credentials' => ar ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة.' : 'Incorrect email or password.',
        'temporary_password_expired' => ar ? 'انتهت صلاحية كلمة المرور المؤقتة. تواصل مع إدارة THAMAN لتعيين كلمة جديدة.' : 'The temporary password expired. Contact THAMAN administration for a new one.',
        'device_blocked' => ar ? 'هذا الجهاز محظور من إدارة THAMAN.' : 'This device is blocked by THAMAN administration.',
        'license_denied' || 'device_unlinked' || 'device_not_registered' => ar ? 'هذا الجهاز غير مربوط. أعد تفعيله بكود التفعيل.' : 'This device is not linked. Activate it again with the activation code.',
        'subscription_expired' => ar ? 'انتهى الاشتراك.' : 'The subscription has expired.',
        'subscription_suspended' || 'business_suspended' => ar ? 'الحساب أو الاشتراك موقوف.' : 'The account or subscription is suspended.',
        'server_not_configured' => ar ? 'نسخة التطبيق غير مربوطة بخادم THAMAN.' : 'This build is not connected to the THAMAN server.',
        'server_schema_outdated' || 'server_error' => ar
            ? 'تعذر إكمال تسجيل الدخول الآن. تحقق من الإنترنت وأعد المحاولة، وإن استمر الخطأ تواصل مع الدعم.'
            : 'Sign-in could not be completed right now. Check your internet connection and try again. If it continues, contact support.',
        'too_many_attempts' => ar ? 'محاولات كثيرة. انتظر ربع ساعة ثم حاول مجددًا.' : 'Too many attempts. Wait 15 minutes and try again.',
        'secure_storage_unavailable' => ar ? 'تعذر الوصول إلى التخزين الآمن على الجهاز. أعد تشغيل الجهاز ثم حاول مرة أخرى.' : 'Secure device storage is unavailable. Restart the device and try again.',
        'connection_failed' => ar ? 'تعذر الاتصال بالسيرفر. تحقق من الإنترنت ثم أعد المحاولة.' : 'Could not reach the server. Check your internet connection and try again.',
        _ => ar ? 'تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور ورمز PIN ثم حاول مرة أخرى.' : 'Could not sign in. Check the email, password and PIN, then try again.',
      };

  static const _supportEmail = 'albhtytymr6@gmail.com';

  Future<void> _showSupportContact(BuildContext hostContext, {String ownerEmail = ''}) async {
    final s = AppStrings(AppScope.of(context));
    await showDialog<void>(
      context: hostContext,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.support_agent_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(s.text('مراسلة الدعم', 'Contact support'))),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.text(
                  'تواصل مع دعم THAMAN عبر البريد التالي. انسخ العنوان وأرسل منه طلب استعادة كلمة المرور.',
                  'Contact THAMAN support using the email below. Copy the address and send your password-reset request from it.',
                ),
                style: const TextStyle(fontSize: 10.5, height: 1.55, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.alternate_email_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        _supportEmail,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: s.text('نسخ البريد', 'Copy email'),
                      onPressed: () async {
                        await Clipboard.setData(const ClipboardData(text: _supportEmail));
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(s.text('تم نسخ بريد الدعم.', 'Support email copied.'))),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              if (ownerEmail.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  s.text('بريد حسابك: ${ownerEmail.trim()}', 'Your account email: ${ownerEmail.trim()}'),
                  style: const TextStyle(fontSize: 9.2, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.text('إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final resetEmail = TextEditingController(text: email.text.trim());
    String? dialogError;
    bool sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Row(
            children: [
              const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(s.text('استعادة كلمة مرور المالك', 'Owner password recovery'))),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.text(
                    'إذا كان البريد مسجلًا لحساب مالك فعلي، نرسل إليه رابطًا آمنًا لتعيين كلمة مرور جديدة. ويمكنك بدلًا من ذلك مراسلة دعم THAMAN.',
                    'If the email belongs to a registered owner, a secure link will be sent so they can set a new password. You can also contact THAMAN support.',
                  ),
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: resetEmail,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: s.text('البريد الإلكتروني المسجل', 'Registered email'),
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    errorText: dialogError,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    s.text(
                      'لأسباب أمنية، ستظهر نفس رسالة النجاح سواء كان البريد موجودًا أم لا. رابط الاستعادة صالح لمدة محدودة ويعمل مرة واحدة.',
                      'For security, the same success message is shown whether the email exists or not. The reset link is time-limited and single-use.',
                    ),
                    style: const TextStyle(fontSize: 9.1, color: AppColors.muted, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: sending
                  ? null
                  : () => _showSupportContact(dialogContext, ownerEmail: resetEmail.text.trim()),
              icon: const Icon(Icons.support_agent_rounded, size: 17),
              label: Text(s.text('مراسلة الدعم', 'Contact support')),
            ),
            FilledButton.icon(
              onPressed: sending
                  ? null
                  : () async {
                      final value = resetEmail.text.trim();
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                        setD(() => dialogError = s.text('أدخل بريدًا إلكترونيًا صحيحًا.', 'Enter a valid email address.'));
                        return;
                      }
                      setD(() { sending = true; dialogError = null; });
                      try {
                        await repository.requestOwnerPasswordReset(email: value);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.text('إذا كان البريد مسجلًا، تم إرسال رابط الاستعادة إليه.', 'If the email is registered, a reset link has been sent.'))),
                        );
                      } on SubscriptionLookupException catch (e) {
                        if (!dialogContext.mounted) return;
                        setD(() {
                          sending = false;
                          dialogError = e.code == 'reset_service_unavailable'
                              ? s.text('خدمة إرسال رابط الاستعادة غير متاحة حاليًا. يمكنك مراسلة الدعم.', 'Password-reset email service is currently unavailable. You can contact support.')
                              : s.text('تعذر إرسال رابط الاستعادة الآن.', 'Could not send the reset link right now.');
                        });
                      }
                    },
              icon: sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.mark_email_read_outlined, size: 17),
              label: Text(s.text('إرسال رابط الاستعادة', 'Send reset link')),
            ),
          ],
        ),
      ),
    );
    resetEmail.dispose();
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: selected ? Colors.white : AppColors.primary),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: selected ? Colors.white : AppColors.text)),
          ]),
        ),
      );
}
