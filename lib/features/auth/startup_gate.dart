import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/credential_hash.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../data/app_data_store.dart';
import 'access_screen.dart';
import 'first_run_activation_screen.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  final SubscriptionRepository repository = SubscriptionRepository();
  _StartupState state = _StartupState.loading;
  String? errorCode;
  bool requireOwnerSetup = true;
  Timer? _heartbeatTimer;
  Timer? _dataSyncTimer;
  bool _heartbeatBusy = false;
  bool _dataSyncBusy = false;

  static const _remoteLicenseCheckInterval = Duration(seconds: 45);
  static const _cloudDataSyncInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _dataSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed &&
        state == _StartupState.access) {
      unawaited(_backgroundValidate());
    }
  }

  Future<void> _boot() async {
    _heartbeatTimer?.cancel();
    _dataSyncTimer?.cancel();
    if (mounted) setState(() { state = _StartupState.loading; errorCode = null; });
    final completed = await repository.isFirstRunComplete();
    final ownerReady = AppDataStore.instance.hasOwnerAccount;
    if (!completed) {
      if (mounted) {
        setState(() {
          state = _StartupState.activation;
          // A license reset must not force an existing shop owner to recreate
          // credentials. Owner setup is required only when no owner exists yet.
          requireOwnerSetup = !ownerReady;
        });
      }
      return;
    }

    try {
      await repository.heartbeatStoredDevice();

      // V9.2.1 and older stored the owner only on the first device. Mirror that
      // account to Supabase once so future licensed devices can use the same
      // owner identity without repeating registration.
      final cloudOwner = await repository.ownerStatus();
      if (!cloudOwner.exists) {
        final localOwner = AppDataStore.instance.adminAccountByRole('owner');
        if (localOwner == null) {
          if (mounted) {
            setState(() {
              state = _StartupState.activation;
              requireOwnerSetup = true;
            });
          }
          return;
        }
        // A one-way local hash cannot be used as the owner's original
        // cloud password. Ask the owner to re-enter credentials once instead.
        if (CredentialHash.isHash(localOwner.password) ||
            CredentialHash.isHash(localOwner.pin)) {
          if (mounted) {
            setState(() {
              state = _StartupState.activation;
              requireOwnerSetup = true;
            });
          }
          return;
        }
        await repository.provisionOwner(
          displayName: localOwner.nameAr,
          phone: localOwner.phone,
          email: localOwner.email,
          password: localOwner.password,
          pin: localOwner.pin,
        );
      }

      if (mounted) {
        setState(() => state = _StartupState.access);
        _startHeartbeatTimer();
      }
      unawaited(AppDataStore.instance.syncFromCloudAfterValidation());
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      if (e.code == 'connection_failed') {
        // A previously verified shop can work through a short outage, but cannot
        // stay offline forever to bypass a later suspension/expiry.
        final offlineWindowValid = await repository.isOfflineWindowValid();
        if (!mounted) return;
        setState(() {
          state = offlineWindowValid ? _StartupState.access : _StartupState.blocked;
          errorCode = offlineWindowValid ? null : 'online_validation_required';
        });
        if (offlineWindowValid) _startHeartbeatTimer();
      } else if (_shouldReturnToActivation(e.code)) {
        // A definitive server denial invalidates the stored license binding.
        // Return to activation instead of trapping the customer on a dead-end
        // license screen. The local owner account and POS data stay intact.
        await repository.resetActivationForReentry();
        if (!mounted) return;
        setState(() {
          state = _StartupState.activation;
          requireOwnerSetup = !AppDataStore.instance.hasOwnerAccount;
          errorCode = e.code;
        });
      } else {
        setState(() { state = _StartupState.blocked; errorCode = e.code; });
      }
    }
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _dataSyncTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_remoteLicenseCheckInterval, (_) => _backgroundValidate());
    _dataSyncTimer = Timer.periodic(_cloudDataSyncInterval, (_) => _backgroundDataSync());
  }

  Future<void> _backgroundDataSync() async {
    if (_dataSyncBusy || state != _StartupState.access) return;
    _dataSyncBusy = true;
    try {
      await AppDataStore.instance.syncFromCloudAfterValidation();
    } finally {
      _dataSyncBusy = false;
    }
  }

  Future<void> _backgroundValidate() async {
    if (_heartbeatBusy || state != _StartupState.access) return;
    _heartbeatBusy = true;
    try {
      await repository.heartbeatStoredDevice();
      await AppDataStore.instance.syncFromCloudAfterValidation();
    } on SubscriptionLookupException catch (e) {
      if (!mounted) return;
      if (e.code == 'connection_failed') {
        final offlineWindowValid = await repository.isOfflineWindowValid();
        if (!mounted || offlineWindowValid) return;
        _heartbeatTimer?.cancel();
        _dataSyncTimer?.cancel();
        setState(() {
          state = _StartupState.blocked;
          errorCode = 'online_validation_required';
        });
        _returnToStartupGate();
        return;
      }

      if (_shouldReturnToActivation(e.code)) {
        await repository.resetActivationForReentry();
        if (!mounted) return;
        _heartbeatTimer?.cancel();
        _dataSyncTimer?.cancel();
        setState(() {
          state = _StartupState.activation;
          requireOwnerSetup = !AppDataStore.instance.hasOwnerAccount;
          errorCode = e.code;
        });
        _returnToStartupGate();
        return;
      }

      _heartbeatTimer?.cancel();
      _dataSyncTimer?.cancel();
      setState(() {
        state = _StartupState.blocked;
        errorCode = e.code;
      });
      _returnToStartupGate();
    } finally {
      _heartbeatBusy = false;
    }
  }

  void _returnToStartupGate() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
    });
  }

  bool _shouldReturnToActivation(String code) {
    if (code.startsWith('subscription_')) return true;
    return const {
      'activation_code_missing',
      'not_found',
      'business_suspended',
      'expired',
      'device_blocked',
      'device_not_registered',
      'device_unlinked',
      'license_denied',
    }.contains(code);
  }

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _StartupState.loading => const _StartupLoading(),
      _StartupState.activation => FirstRunActivationScreen(
          requireOwnerSetup: requireOwnerSetup,
          initialErrorCode: errorCode,
          onCompleted: _boot,
        ),
      _StartupState.blocked => _LicenseBlocked(errorCode: errorCode ?? 'license_denied', onRetry: _boot),
      _StartupState.access => const AccessScreen(),
    };
  }
}

enum _StartupState { loading, activation, blocked, access }

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: BrandPattern(
          borderRadius: BorderRadius.zero,
          child: Container(
            color: AppColors.background.withValues(alpha: .96),
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLogo(),
                SizedBox(height: 22),
                CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
}

class _LicenseBlocked extends StatelessWidget {
  const _LicenseBlocked({required this.errorCode, required this.onRetry});
  final String errorCode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final (title, text) = switch (errorCode) {
      'device_blocked' => (
          s.text('هذا الجهاز محظور', 'This device is blocked'),
          s.text('تم حظر هذا الجهاز من THAMAN Admin. تواصل مع إدارة THAMAN لفك الحظر ثم اضغط إعادة المحاولة.', 'This device was blocked in THAMAN Admin. Ask THAMAN administration to unblock it, then try again.'),
        ),
      'business_suspended' => (
          s.text('حساب المشترك موقوف', 'Subscriber account suspended'),
          s.text('تم إيقاف حساب هذا المتجر من THAMAN Admin.', 'This store account has been suspended in THAMAN Admin.'),
        ),
      'subscription_suspended' => (
          s.text('الاشتراك موقوف', 'Subscription suspended'),
          s.text('الاشتراك موقوف حاليًا. يجب تفعيله من THAMAN Admin.', 'The subscription is currently suspended and must be reactivated in THAMAN Admin.'),
        ),
      'subscription_expired' || 'expired' => (
          s.text('انتهى الاشتراك', 'Subscription expired'),
          s.text('يجب تجديد الاشتراك من THAMAN Admin قبل متابعة استخدام النظام.', 'Renew the subscription in THAMAN Admin before continuing to use the system.'),
        ),
      'subscription_pending' => (
          s.text('الاشتراك بانتظار التفعيل', 'Subscription pending'),
          s.text('الاشتراك لم يُفعّل بعد من THAMAN Admin.', 'The subscription has not been activated yet in THAMAN Admin.'),
        ),
      'not_found' => (
          s.text('الاشتراك غير موجود', 'Subscription not found'),
          s.text('لم يعد كود التفعيل مرتبطًا باشتراك موجود. تواصل مع إدارة THAMAN.', 'The activation code is no longer linked to an existing subscription. Contact THAMAN administration.'),
        ),
      'online_validation_required' => (
          s.text('يلزم اتصال للتحقق', 'Online verification required'),
          s.text('انتهت مدة العمل دون اتصال. وصّل الجهاز بالإنترنت واضغط إعادة المحاولة للتحقق من الاشتراك.', 'The offline-use window has ended. Connect to the internet and retry to verify the subscription.'),
        ),
      'secure_storage_unavailable' => (
          s.text('التخزين الآمن غير متاح', 'Secure storage unavailable'),
          s.text('لأمان الترخيص والبيانات لا يمكن تشغيل THAMAN بدون التخزين الآمن للنظام. أعد تشغيل الجهاز ثم حاول مرة أخرى.', 'For license and data protection, THAMAN cannot run without OS secure storage. Restart the device and try again.'),
        ),
      _ => (
          s.text('تعذر التحقق من صلاحية الوصول', 'License access could not be verified'),
          s.text('تحقق من حالة الاشتراك والجهاز في THAMAN Admin ثم حاول مرة أخرى.', 'Check the subscription and device status in THAMAN Admin, then try again.'),
        ),
    };

    return Scaffold(
      body: BrandPattern(
        borderRadius: BorderRadius.zero,
        child: Container(
          color: AppColors.background.withValues(alpha: .96),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: AppColors.border)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(),
                const SizedBox(height: 24),
                Container(width: 66, height: 66, decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: .08), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.gpp_bad_outlined, size: 32, color: AppColors.danger)),
                const SizedBox(height: 14),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6)),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(s.text('إعادة المحاولة', 'Try again'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
