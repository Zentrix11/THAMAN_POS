import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../security/secure_kv_store.dart';

/// Native operating-system notifications for THAMAN subscription lifecycle.
///
/// Android/iOS/macOS/Windows can schedule the warning and expiry notifications
/// so they can appear while THAMAN is not in the foreground. Linux still gets
/// immediate notifications when THAMAN is open, because scheduled desktop
/// notifications are not consistently available across Linux environments.
class SubscriptionNotificationService {
  SubscriptionNotificationService._();
  static final SubscriptionNotificationService instance =
      SubscriptionNotificationService._();

  static const int _warningId = 9701;
  static const int _expiryId = 9702;
  static const int _graceEndId = 9703;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _initializing = false;

  final NotificationDetails _details = const NotificationDetails(
    android: AndroidNotificationDetails(
      'thaman_subscription_status',
      'THAMAN Subscription',
      channelDescription: 'Subscription expiry and renewal reminders',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
    windows: WindowsNotificationDetails(),
  );

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('thaman_notification');
      const darwin = DarwinInitializationSettings();
      const linux = LinuxInitializationSettings(
        defaultActionName: 'Open THAMAN',
      );
      const windows = WindowsInitializationSettings(
        appName: 'THAMAN POS',
        appUserModelId: 'Zentrix.THAMAN.POS',
        guid: '5d7ab2cb-6cce-44d7-b70b-9ef302c9d04f',
      );
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: linux,
        windows: windows,
      );
      await _plugin.initialize(settings);
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _initialized = true;
    } catch (_) {
      // Notifications must never prevent the POS from starting or validating
      // a subscription. The in-app warning remains available as a fallback.
      _initialized = false;
    } finally {
      _initializing = false;
    }
  }

  Future<void> syncSubscription({
    required String subscriptionId,
    required String businessName,
    required DateTime endsAt,
    required int warningDays,
    required int graceDays,
    required String status,
    required DateTime serverNow,
  }) async {
    await initialize();
    if (!_initialized || subscriptionId.trim().isEmpty) return;

    final end = endsAt.toUtc();
    final now = serverNow.toUtc();
    final label = businessName.trim().isEmpty ? 'اشتراك THAMAN' : businessName.trim();

    // Re-use stable ids. On platforms that support replacing pending
    // notifications this keeps renewals from accumulating duplicates.
    await _safeCancel(_warningId);
    await _safeCancel(_expiryId);
    await _safeCancel(_graceEndId);

    if (status == 'suspended' || status == 'expired') {
      if (!end.isAfter(now)) {
        await _showOnce(
          key: 'expiry::$subscriptionId::${end.toIso8601String()}',
          id: _expiryId,
          title: 'انتهى اشتراك THAMAN',
          body: 'انتهى اشتراك $label. تواصل مع الإدارة للتجديد.',
          payload: 'subscription:$subscriptionId',
        );
      }
      return;
    }

    final safeWarningDays = warningDays.clamp(0, 365);
    if (safeWarningDays > 0) {
      final warningAt = end.subtract(Duration(days: safeWarningDays));
      if (warningAt.isAfter(now.add(const Duration(minutes: 1)))) {
        await _safeSchedule(
          id: _warningId,
          title: 'اشتراك THAMAN يقترب من الانتهاء',
          body: 'بقي $safeWarningDays يوم على انتهاء اشتراك $label.',
          at: warningAt,
          payload: 'subscription:$subscriptionId',
        );
      } else if (end.isAfter(now)) {
        final remaining = end.difference(now);
        final days = remaining.inDays;
        final hours = remaining.inHours % 24;
        await _showOnce(
          key:
              'warning::$subscriptionId::${end.toIso8601String()}::$safeWarningDays',
          id: _warningId,
          title: 'اشتراك THAMAN يقترب من الانتهاء',
          body: days > 0
              ? 'متبقي $days يوم و$hours ساعة على اشتراك $label.'
              : 'متبقي $hours ساعة تقريبًا على اشتراك $label.',
          payload: 'subscription:$subscriptionId',
        );
      }
    }

    if (end.isAfter(now.add(const Duration(minutes: 1)))) {
      await _safeSchedule(
        id: _expiryId,
        title: 'انتهى اشتراك THAMAN',
        body: 'انتهت مدة اشتراك $label. افتح THAMAN لمراجعة حالة التجديد.',
        at: end,
        payload: 'subscription:$subscriptionId',
      );
    } else {
      await _showOnce(
        key: 'expiry::$subscriptionId::${end.toIso8601String()}',
        id: _expiryId,
        title: 'انتهى اشتراك THAMAN',
        body: 'انتهت مدة اشتراك $label. راجع الإدارة للتجديد.',
        payload: 'subscription:$subscriptionId',
      );
    }

    if (graceDays > 0) {
      final graceEnd = end.add(Duration(days: graceDays));
      if (graceEnd.isAfter(now.add(const Duration(minutes: 1)))) {
        await _safeSchedule(
          id: _graceEndId,
          title: 'تنتهي فترة السماح قريبًا',
          body: 'ستنتهي فترة السماح لاشتراك $label، وبعدها يتوقف الوصول.',
          at: graceEnd,
          payload: 'subscription:$subscriptionId',
        );
      } else if (!graceEnd.isAfter(now)) {
        await _showOnce(
          key: 'grace::$subscriptionId::${graceEnd.toIso8601String()}',
          id: _graceEndId,
          title: 'انتهت فترة السماح',
          body: 'انتهت فترة السماح لاشتراك $label.',
          payload: 'subscription:$subscriptionId',
        );
      }
    }
  }

  Future<void> _safeSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required String payload,
  }) async {
    // Linux desktop notification servers do not offer a portable scheduler.
    if (Platform.isLinux) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at.toUtc(), tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> _showOnce({
    required String key,
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    final storageKey = 'thaman_notification_once_v1__$key';
    final already = await SecureKvStore.instance.readBool(storageKey);
    if (already) return;
    try {
      await _plugin.show(id, title, body, _details, payload: payload);
      await SecureKvStore.instance.writeBool(storageKey, true);
    } catch (_) {}
  }

  Future<void> _safeCancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }
}
