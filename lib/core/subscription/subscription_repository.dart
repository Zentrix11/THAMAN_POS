import 'dart:math';

import 'package:flutter/foundation.dart';
import '../security/secure_kv_store.dart';
import '../notifications/subscription_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionDeviceInfo {
  const SubscriptionDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.active,
    required this.blocked,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String platform;
  final String appVersion;
  final bool active;
  final bool blocked;
  final DateTime? lastSeenAt;

  factory SubscriptionDeviceInfo.fromMap(Map<String, dynamic> map) {
    return SubscriptionDeviceInfo(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? ''}',
      platform: '${map['platform'] ?? ''}',
      appVersion: '${map['app_version'] ?? ''}',
      active: map['active'] == true,
      blocked: map['blocked'] == true,
      lastSeenAt: _date(map['last_seen_at']),
    );
  }
}

class SubscriptionSnapshot {
  const SubscriptionSnapshot({
    required this.subscriptionId,
    required this.activationCode,
    required this.accountNo,
    required this.subscriberName,
    required this.businessName,
    required this.planName,
    required this.planCode,
    required this.billingCycle,
    required this.price,
    required this.status,
    required this.businessStatus,
    required this.startsAt,
    required this.endsAt,
    required this.autoRenew,
    required this.deviceLimit,
    required this.activeDeviceCount,
    required this.expiryWarningDays,
    required this.gracePeriodDays,
    required this.devices,
    this.serverTime,
    this.receivedAt,
  });

  final String subscriptionId;
  final String activationCode;
  final String accountNo;
  final String subscriberName;
  final String businessName;
  final String planName;
  final String planCode;
  final String billingCycle;
  final double price;
  final String status;
  final String businessStatus;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool autoRenew;
  final int deviceLimit;
  final int activeDeviceCount;
  final int expiryWarningDays;
  final int gracePeriodDays;
  final List<SubscriptionDeviceInfo> devices;
  final DateTime? serverTime;
  final DateTime? receivedAt;

  DateTime get estimatedServerNow {
    final server = serverTime;
    final received = receivedAt;
    if (server == null || received == null) return DateTime.now().toUtc();
    return server.toUtc().add(DateTime.now().toUtc().difference(received.toUtc()));
  }

  int get remainingDays {
    final diff = endsAt.toUtc().difference(estimatedServerNow);
    if (diff <= Duration.zero) return 0;
    return (diff.inMinutes / Duration.minutesPerDay).ceil();
  }

  Duration get remainingDuration {
    final diff = endsAt.toUtc().difference(estimatedServerNow);
    return diff.isNegative ? Duration.zero : diff;
  }

  int get remainingHoursPart => remainingDuration.inHours % 24;
  int get remainingMinutesPart => remainingDuration.inMinutes % 60;

  int get graceDaysRemaining {
    final now = estimatedServerNow;
    if (now.isBefore(endsAt.toUtc())) return gracePeriodDays;
    final graceEnd = endsAt.toUtc().add(Duration(days: gracePeriodDays));
    final diff = graceEnd.difference(now);
    if (diff <= Duration.zero) return 0;
    return (diff.inMinutes / Duration.minutesPerDay).ceil();
  }

  double get periodProgress {
    final total = endsAt.difference(startsAt).inMinutes;
    if (total <= 0) return 1;
    final elapsed = estimatedServerNow.difference(startsAt.toUtc()).inMinutes;
    return (elapsed / total).clamp(0.0, 1.0).toDouble();
  }

  bool get isNearExpiry => status == 'active' && remainingDays <= expiryWarningDays;

  factory SubscriptionSnapshot.fromMap(Map<String, dynamic> map) {
    final rawDevices = (map['devices'] as List?) ?? const <dynamic>[];
    return SubscriptionSnapshot(
      subscriptionId: '${map['subscription_id'] ?? ''}',
      activationCode: '${map['activation_code'] ?? ''}',
      accountNo: '${map['account_no'] ?? ''}',
      subscriberName: '${map['subscriber_name'] ?? ''}',
      businessName: '${map['business_name'] ?? ''}',
      planName: '${map['plan_name'] ?? ''}',
      planCode: '${map['plan_code'] ?? ''}',
      billingCycle: '${map['billing_cycle'] ?? ''}',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      status: '${map['effective_status'] ?? map['subscription_status'] ?? ''}',
      businessStatus: '${map['business_status'] ?? ''}',
      startsAt: _date(map['starts_at']) ?? DateTime.now(),
      endsAt: _date(map['ends_at']) ?? DateTime.now(),
      autoRenew: map['auto_renew'] == true,
      deviceLimit: (map['device_limit'] as num?)?.toInt() ?? 1,
      activeDeviceCount: (map['active_device_count'] as num?)?.toInt() ?? 0,
      expiryWarningDays: (map['expiry_warning_days'] as num?)?.toInt() ?? 14,
      gracePeriodDays: (map['grace_period_days'] as num?)?.toInt() ?? 0,
      devices: rawDevices
          .whereType<Map>()
          .map((item) => SubscriptionDeviceInfo.fromMap(item.cast<String, dynamic>()))
          .toList(),
      serverTime: _date(map['server_time']),
      receivedAt: DateTime.now().toUtc(),
    );
  }
}


class AvailableSubscriptionPlan {
  const AvailableSubscriptionPlan({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.billingCycle,
    required this.price,
    required this.maxDevices,
    required this.isOffer,
    required this.offerBadge,
    this.previousPrice,
    required this.displayOrder,
    required this.isCurrent,
    this.isCustom = false,
    this.customDurationDays,
  });

  final String id;
  final String name;
  final String code;
  final String description;
  final String billingCycle;
  final double price;
  final int maxDevices;
  final bool isOffer;
  final String offerBadge;
  final double? previousPrice;
  final int displayOrder;
  final bool isCurrent;
  final bool isCustom;
  final int? customDurationDays;

  factory AvailableSubscriptionPlan.fromMap(Map<String, dynamic> map) => AvailableSubscriptionPlan(
        id: '${map['id'] ?? ''}',
        name: '${map['name'] ?? ''}',
        code: '${map['code'] ?? ''}',
        description: '${map['description'] ?? ''}',
        billingCycle: '${map['billing_cycle'] ?? 'monthly'}',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        maxDevices: (map['max_devices'] as num?)?.toInt() ?? 1,
        isOffer: map['is_offer'] == true,
        offerBadge: '${map['offer_badge'] ?? ''}',
        previousPrice: map['previous_price'] == null ? null : (map['previous_price'] as num?)?.toDouble(),
        displayOrder: (map['display_order'] as num?)?.toInt() ?? 0,
        isCurrent: map['is_current'] == true,
        isCustom: map['is_custom'] == true,
        customDurationDays: map['custom_duration_days'] == null ? null : (map['custom_duration_days'] as num?)?.toInt(),
      );
}

class AvailablePlansCatalog {
  const AvailablePlansCatalog({required this.currentPlanId, required this.subscriptionId, required this.plans});
  final String currentPlanId;
  final String subscriptionId;
  final List<AvailableSubscriptionPlan> plans;

  factory AvailablePlansCatalog.fromMap(Map<String, dynamic> map) {
    final raw = (map['plans'] as List?) ?? const <dynamic>[];
    return AvailablePlansCatalog(
      currentPlanId: '${map['current_plan_id'] ?? ''}',
      subscriptionId: '${map['subscription_id'] ?? ''}',
      plans: raw.whereType<Map>().map((e) => AvailableSubscriptionPlan.fromMap(e.cast<String, dynamic>())).toList(),
    );
  }
}

class SubscriptionRequestResult {
  const SubscriptionRequestResult({required this.requestId, required this.requestType, required this.duplicate});
  final String requestId;
  final String requestType;
  final bool duplicate;
}

class CustomPlanRequestResult {
  const CustomPlanRequestResult({required this.requestId, required this.duplicate, required this.emailSent});
  final String requestId;
  final bool duplicate;
  final bool emailSent;
}


class SubscriptionRequestMessageInfo {
  const SubscriptionRequestMessageInfo({
    required this.id,
    required this.senderType,
    required this.message,
    required this.readByOwner,
    required this.readByAdmin,
    required this.createdAt,
  });

  final String id;
  final String senderType;
  final String message;
  final bool readByOwner;
  final bool readByAdmin;
  final DateTime createdAt;

  factory SubscriptionRequestMessageInfo.fromMap(Map<String, dynamic> map) =>
      SubscriptionRequestMessageInfo(
        id: '${map['id'] ?? ''}',
        senderType: '${map['sender_type'] ?? ''}',
        message: '${map['message'] ?? ''}',
        readByOwner: map['read_by_owner'] == true,
        readByAdmin: map['read_by_admin'] == true,
        createdAt: _date(map['created_at']) ?? DateTime.now(),
      );
}

class OwnerCustomPlanRequestInfo {
  const OwnerCustomPlanRequestInfo({
    required this.id,
    required this.status,
    required this.requestType,
    required this.customerNote,
    required this.adminNote,
    required this.createdAt,
    required this.unreadOwnerCount,
    required this.messages,
    this.requestedDurationDays,
    this.requestedDeviceLimit,
    this.requestedBudget,
  });

  final String id;
  final String status;
  final String requestType;
  final String customerNote;
  final String adminNote;
  final DateTime createdAt;
  final int unreadOwnerCount;
  final int? requestedDurationDays;
  final int? requestedDeviceLimit;
  final double? requestedBudget;
  final List<SubscriptionRequestMessageInfo> messages;

  factory OwnerCustomPlanRequestInfo.fromMap(Map<String, dynamic> map) {
    final rawMessages = (map['messages'] as List?) ?? const <dynamic>[];
    return OwnerCustomPlanRequestInfo(
      id: '${map['id'] ?? ''}',
      status: '${map['status'] ?? 'new'}',
      requestType: '${map['request_type'] ?? 'custom'}',
      customerNote: '${map['customer_note'] ?? ''}',
      adminNote: '${map['admin_note'] ?? ''}',
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      unreadOwnerCount: (map['unread_owner_count'] as num?)?.toInt() ?? 0,
      requestedDurationDays: (map['requested_duration_days'] as num?)?.toInt(),
      requestedDeviceLimit: (map['requested_device_limit'] as num?)?.toInt(),
      requestedBudget: (map['requested_budget'] as num?)?.toDouble(),
      messages: rawMessages
          .whereType<Map>()
          .map((e) => SubscriptionRequestMessageInfo.fromMap(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class OwnerCloudProfile {
  const OwnerCloudProfile({
    required this.exists,
    this.ownerId = '',
    this.businessId = '',
    this.displayName = '',
    this.phone = '',
    this.email = '',
    this.active = true,
    this.mustChangePassword = false,
    this.temporaryPasswordExpiresAt,
    this.lastLoginAt,
  });

  final bool exists;
  final String ownerId;
  final String businessId;
  final String displayName;
  final String phone;
  final String email;
  final bool active;
  final bool mustChangePassword;
  final DateTime? temporaryPasswordExpiresAt;
  final DateTime? lastLoginAt;

  factory OwnerCloudProfile.fromMap(Map<String, dynamic> map) => OwnerCloudProfile(
        exists: map['owner_exists'] == true || '${map['owner_id'] ?? ''}'.isNotEmpty,
        ownerId: '${map['owner_id'] ?? ''}',
        businessId: '${map['business_id'] ?? ''}',
        displayName: '${map['display_name'] ?? ''}',
        phone: '${map['phone'] ?? ''}',
        email: '${map['email'] ?? ''}',
        active: map['active'] != false,
        mustChangePassword: map['must_change_password'] == true,
        temporaryPasswordExpiresAt: _date(map['temporary_password_expires_at']),
        lastLoginAt: _date(map['last_login_at']),
      );
}

class CloudStoreState {
  const CloudStoreState({
    required this.exists,
    required this.revision,
    required this.snapshot,
  });

  final bool exists;
  final int revision;
  final Map<String, dynamic> snapshot;
}

class CloudStorePushResult {
  const CloudStorePushResult({
    required this.saved,
    required this.revision,
  });

  final bool saved;
  final int revision;
}

class SequenceBlock {
  const SequenceBlock({
    required this.kind,
    required this.start,
    required this.end,
  });

  final String kind;
  final int start;
  final int end;
}

class SubscriptionRepository {
  static const _activationCodeKey = 'thaman_pos_subscription_activation_code';
  static const _activationCompleteKey = 'thaman_pos_first_run_activation_complete_v1';
  static const _deviceUidKey = 'thaman_pos_installation_device_uid_v1';
  static const _deviceProofKey = 'thaman_pos_installation_device_proof_v1';
  static const _lastValidatedAtKey = 'thaman_pos_license_last_validated_at_v1';
  static const _lastObservedLocalAtKey = 'thaman_pos_license_last_local_clock_v1';

  static const supabaseUrl = String.fromEnvironment('THAMAN_SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('THAMAN_SUPABASE_PUBLISHABLE_KEY');
  static const appVersion = '0.37.0';
  static const offlineAccessWindow = Duration(hours: 24);
  static const clockRollbackTolerance = Duration(minutes: 5);

  bool get isConfigured => supabaseUrl.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  SupabaseClient _client() {
    if (!isConfigured) {
      throw const SubscriptionLookupException('server_not_configured');
    }
    return SupabaseClient(supabaseUrl.trim(), publishableKey.trim());
  }

  SecureKvStore get _secure => SecureKvStore.instance;

  Future<String> loadActivationCode() async =>
      ((await _secure.read(_activationCodeKey)) ?? '').trim().toUpperCase();

  Future<void> saveActivationCode(String code) async {
    final normalized = code.trim().toUpperCase();
    await _secure.write(_activationCodeKey, normalized.isEmpty ? null : normalized);
  }

  /// Clears only the server-license binding after a definitive online denial.
  /// The installation identity and locally-created owner account are preserved,
  /// so a shop can enter a valid activation code again without recreating users.
  Future<void> resetActivationForReentry() async {
    await _secure.delete(_activationCodeKey);
    await _secure.delete(_lastValidatedAtKey);
  }

  Future<bool> isFirstRunComplete() async {
    final complete = await _secure.readBool(_activationCompleteKey);
    final code = ((await _secure.read(_activationCodeKey)) ?? '').trim();
    final uid = ((await _secure.read(_deviceUidKey)) ?? '').trim();
    if (complete && code.isNotEmpty && uid.isNotEmpty) {
      // Existing V9.4 installations receive a proof automatically; the server
      // binds it to the registered device on the next validated heartbeat.
      await deviceProof();
      return true;
    }
    return false;
  }

  Future<void> markFirstRunComplete() =>
      _secure.writeBool(_activationCompleteKey, true);

  Future<String> deviceUid() async {
    final existing = ((await _secure.read(_deviceUidKey)) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    final uid = 'THM-${platformLabel.toUpperCase()}-$token';
    await _secure.write(_deviceUidKey, uid);
    return uid;
  }

  Future<String> deviceProof() async {
    try {
      final existing = ((await _secure.readStrict(_deviceProofKey)) ?? '').trim();
      if (RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(existing)) return existing;
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final proof = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      await _secure.writeStrict(_deviceProofKey, proof);
      return proof;
    } on SecureStorageUnavailableException {
      throw const SubscriptionLookupException('secure_storage_unavailable');
    }
  }

  String get platformLabel {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Windows',
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
  }

  Future<String> deviceName() async {
    final uid = await deviceUid();
    final suffix = uid.length > 6 ? uid.substring(uid.length - 6) : uid;
    return 'THAMAN $platformLabel • $suffix';
  }

  Future<SubscriptionSnapshot> activateDevice(String activationCode) async {
    final normalized = activationCode.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const SubscriptionLookupException('activation_code_missing');
    }
    try {
      final uid = await deviceUid();
      final response = await _client().rpc(
        'pos_activate_device_v4',
        params: {
          'p_activation_code': normalized,
          'p_device_uid': uid,
          'p_device_proof': await deviceProof(),
          'p_device_name': await deviceName(),
          'p_platform': platformLabel,
          'p_app_version': appVersion,
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'activation_failed'}');
      }
      await saveActivationCode(normalized);
      await _setLastValidatedFromResponse(map);
      return await fetch(normalized);
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<String> heartbeatStoredDevice() async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_device_heartbeat_v3',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_app_version': appVersion,
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'license_denied'}');
      }
      await _setLastValidatedFromResponse(map);
      return '${map['effective_status'] ?? 'active'}';
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<DateTime?> lastValidatedAt() async =>
      _date(await _secure.read(_lastValidatedAtKey));

  Future<bool> isOfflineWindowValid() async {
    final last = await lastValidatedAt();
    if (last == null) return false;

    final now = DateTime.now().toUtc();
    final validated = last.toUtc();
    final observed = _date(await _secure.read(_lastObservedLocalAtKey))?.toUtc();

    final valid = offlineLeaseAllows(
      validatedAt: validated,
      now: now,
      lastObservedAt: observed,
    );
    if (valid) {
      await _secure.write(_lastObservedLocalAtKey, now.toIso8601String());
    }
    return valid;
  }

  static bool offlineLeaseAllows({
    required DateTime validatedAt,
    required DateTime now,
    DateTime? lastObservedAt,
  }) {
    final current = now.toUtc();
    final validated = validatedAt.toUtc();
    if (current.add(clockRollbackTolerance).isBefore(validated)) return false;
    if (current.difference(validated) > offlineAccessWindow) return false;
    if (lastObservedAt != null &&
        current.add(clockRollbackTolerance).isBefore(lastObservedAt.toUtc())) {
      return false;
    }
    return true;
  }

  Future<void> _setLastValidatedFromResponse(Map<String, dynamic> response) async {
    final serverTime = DateTime.tryParse('${response['server_time'] ?? ''}')?.toUtc();
    // Never create/extend an offline lease from the user-controlled local clock.
    if (serverTime == null) return;
    await _secure.write(_lastValidatedAtKey, serverTime.toIso8601String());
    await _secure.write(
      _lastObservedLocalAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<OwnerCloudProfile> ownerStatus() async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_owner_status_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) throw SubscriptionLookupException('${map['error'] ?? 'owner_status_failed'}');
      return OwnerCloudProfile.fromMap(map);
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<OwnerCloudProfile> provisionOwner({
    required String displayName,
    required String phone,
    required String email,
    required String password,
    required String pin,
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_provision_owner_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_display_name': displayName.trim(),
          'p_phone': phone.trim(),
          'p_email': email.trim().toLowerCase(),
          'p_password': password,
          'p_pin': pin.trim(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) throw SubscriptionLookupException('${map['error'] ?? 'owner_setup_failed'}');
      return await ownerStatus();
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<OwnerCloudProfile> ownerLogin({
    required String email,
    required String password,
    required String pin,
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_owner_login_v3',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_email': email.trim().toLowerCase(),
          'p_password': password,
          'p_pin': pin.trim(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) throw SubscriptionLookupException('${map['error'] ?? 'invalid_credentials'}');
      return OwnerCloudProfile.fromMap({...map, 'owner_exists': true});
    } on SubscriptionLookupException {
      rethrow;
    } on PostgrestException catch (e) {
      // Do not disguise database/RPC deployment problems as an internet error.
      // PGRST202/42883 = missing RPC signature/function, 42P01 = missing relation,
      // 42501 = privilege mismatch. All indicate that the server schema needs
      // the matching THAMAN migration rather than asking the user to check Wi-Fi.
      final code = e.code;
      if (code == 'PGRST202' ||
          code == '42883' ||
          code == '42P01' ||
          code == '42501') {
        throw const SubscriptionLookupException('server_schema_outdated');
      }
      throw const SubscriptionLookupException('server_error');
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<void> requestOwnerPasswordReset({required String email}) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) throw const SubscriptionLookupException('email_required');
    try {
      final response = await _client().functions.invoke(
        'owner-password-reset',
        body: {'email': normalized},
      );
      if (response.status < 200 || response.status >= 300) {
        throw const SubscriptionLookupException('reset_service_unavailable');
      }
      final data = response.data;
      if (data is Map && data['ok'] == false) {
        throw SubscriptionLookupException('${data['error'] ?? 'reset_service_unavailable'}');
      }
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('reset_service_unavailable');
    }
  }

  Future<void> changeOwnerPassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_change_owner_password_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_email': email.trim().toLowerCase(),
          'p_current_password': currentPassword,
          'p_new_password': newPassword,
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) throw SubscriptionLookupException('${map['error'] ?? 'password_change_failed'}');
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<AvailablePlansCatalog> fetchAvailablePlans() async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    final uid = await deviceUid();
    final proof = await deviceProof();
    final params = {
      'p_activation_code': code,
      'p_device_uid': uid,
      'p_device_proof': proof,
    };
    try {
      dynamic response;
      try {
        response = await _client().rpc('pos_available_plans_v3', params: params);
      } on PostgrestException catch (e) {
        // Upgrade-safe fallback: RC2 prefers SQL 014 / v3, while an installation
        // that has not applied 014 yet can still use the hardened v2 endpoint.
        final missing = e.code == 'PGRST202' ||
            e.message.contains('pos_available_plans_v3') ||
            e.message.toLowerCase().contains('function');
        if (!missing) {
          throw SubscriptionLookupException(
            e.message.toLowerCase().contains('failed to fetch') ? 'connection_failed' : 'catalog_server_error',
          );
        }
        response = await _client().rpc('pos_available_plans_v2', params: params);
      }
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'catalog_failed'}');
      }
      return AvailablePlansCatalog.fromMap(map);
    } on SubscriptionLookupException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('failed to fetch') ||
          e.message.toLowerCase().contains('network')) {
        throw const SubscriptionLookupException('connection_failed');
      }
      throw const SubscriptionLookupException('catalog_server_error');
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<SubscriptionRequestResult> createSubscriptionRequest({
    required AvailableSubscriptionPlan plan,
    String customerNote = '',
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    final requestType = plan.isCurrent ? 'renewal' : 'change_plan';
    try {
      final response = await _client().rpc(
        'pos_create_subscription_request_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_request_type': requestType,
          'p_requested_plan_id': plan.id,
          'p_customer_note': customerNote.trim(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) throw SubscriptionLookupException('${map['error'] ?? 'request_failed'}');
      return SubscriptionRequestResult(
        requestId: '${map['request_id'] ?? ''}',
        requestType: '${map['request_type'] ?? requestType}',
        duplicate: map['duplicate'] == true,
      );
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }


  Future<CustomPlanRequestResult> createCustomPlanRequest({
    required int durationDays,
    required int deviceLimit,
    double? budget,
    String customerNote = '',
    String contactEmail = '',
    String contactPhone = '',
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    final uid = await deviceUid();
    final proof = await deviceProof();
    try {
      final response = await _client().rpc(
        'pos_create_custom_plan_request_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': uid,
          'p_device_proof': proof,
          'p_duration_days': durationDays,
          'p_device_limit': deviceLimit,
          'p_budget': budget,
          'p_customer_note': customerNote.trim(),
          'p_contact_email': contactEmail.trim().toLowerCase(),
          'p_contact_phone': contactPhone.trim(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) throw SubscriptionLookupException('${map['error'] ?? 'request_failed'}');
      final requestId = '${map['request_id'] ?? ''}';
      var emailSent = false;
      if (requestId.isNotEmpty) {
        try {
          final mail = await _client().functions.invoke(
            'custom-plan-request-email',
            body: {
              'request_id': requestId,
              'activation_code': code,
              'device_uid': uid,
              'device_proof': proof,
            },
          );
          final data = mail.data;
          if (data is Map) {
            emailSent = data['email_sent'] == true || data['already_sent'] == true;
          }
        } catch (_) {
          // The request is already safely stored in Supabase. Email delivery is
          // best-effort so a temporary mail-provider issue never loses it.
        }
      }
      return CustomPlanRequestResult(
        requestId: requestId,
        duplicate: map['duplicate'] == true,
        emailSent: emailSent,
      );
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<List<OwnerCustomPlanRequestInfo>> fetchCustomPlanRequests() async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_list_custom_plan_requests_v1',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'request_list_failed'}');
      }
      final raw = (map['requests'] as List?) ?? const <dynamic>[];
      return raw
          .whereType<Map>()
          .map((e) => OwnerCustomPlanRequestInfo.fromMap(e.cast<String, dynamic>()))
          .toList();
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<void> sendCustomPlanRequestMessage({
    required String requestId,
    required String message,
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_send_subscription_request_message_v1',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_request_id': requestId,
          'p_message': message.trim(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'message_send_failed'}');
      }
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<void> markCustomPlanRequestMessagesRead(String requestId) async {
    final code = await loadActivationCode();
    if (code.isEmpty) return;
    try {
      final response = await _client().rpc(
        'pos_mark_subscription_request_messages_read_v1',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_request_id': requestId,
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'message_read_failed'}');
      }
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<CloudStoreState> pullStoreState() async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_pull_store_state_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'sync_pull_failed'}');
      }
      final raw = map['snapshot'];
      return CloudStoreState(
        exists: map['exists'] == true,
        revision: (map['revision'] as num?)?.toInt() ?? 0,
        snapshot: raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
      );
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<CloudStorePushResult> pushStoreState(
    Map<String, dynamic> snapshot, {
    required int expectedRevision,
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_push_store_state_v3',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_expected_revision': expectedRevision,
          'p_snapshot': snapshot,
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        if ('${map['error'] ?? ''}' == 'sync_conflict') {
          return CloudStorePushResult(
            saved: false,
            revision: (map['revision'] as num?)?.toInt() ?? expectedRevision,
          );
        }
        throw SubscriptionLookupException('${map['error'] ?? 'sync_push_failed'}');
      }
      return CloudStorePushResult(
        saved: true,
        revision: (map['revision'] as num?)?.toInt() ?? expectedRevision,
      );
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<SequenceBlock> reserveSequenceBlock(
    String kind, {
    int blockSize = 100,
    int observedMinimum = 0,
  }) async {
    final code = await loadActivationCode();
    if (code.isEmpty) throw const SubscriptionLookupException('activation_code_missing');
    try {
      final response = await _client().rpc(
        'pos_reserve_sequence_block_v2',
        params: {
          'p_activation_code': code,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
          'p_kind': kind,
          'p_block_size': blockSize,
          'p_observed_minimum': observedMinimum,
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'sequence_reserve_failed'}');
      }
      return SequenceBlock(
        kind: '${map['kind'] ?? kind}',
        start: (map['start'] as num?)?.toInt() ?? 0,
        end: (map['end'] as num?)?.toInt() ?? 0,
      );
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  Future<SubscriptionSnapshot> fetch(String activationCode) async {
    final normalized = activationCode.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const SubscriptionLookupException('activation_code_missing');
    }

    try {
      final response = await _client().rpc(
        'pos_subscription_status_v3',
        params: {
          'p_activation_code': normalized,
          'p_device_uid': await deviceUid(),
          'p_device_proof': await deviceProof(),
        },
      );
      final map = _responseMap(response);
      if (map['ok'] != true) {
        throw SubscriptionLookupException('${map['error'] ?? 'not_found'}');
      }
      final snapshot = SubscriptionSnapshot.fromMap(map);
      await SubscriptionNotificationService.instance.syncSubscription(
        subscriptionId: snapshot.subscriptionId,
        businessName: snapshot.businessName,
        endsAt: snapshot.endsAt,
        warningDays: snapshot.expiryWarningDays,
        graceDays: snapshot.gracePeriodDays,
        status: snapshot.status,
        serverNow: snapshot.estimatedServerNow,
      );
      return snapshot;
    } on SubscriptionLookupException {
      rethrow;
    } catch (_) {
      throw const SubscriptionLookupException('connection_failed');
    }
  }

  static Map<String, dynamic> _responseMap(dynamic response) {
    if (response is! Map) {
      throw const SubscriptionLookupException('invalid_response');
    }
    return Map<String, dynamic>.from(response);
  }
}

class SubscriptionLookupException implements Exception {
  const SubscriptionLookupException(this.code);
  final String code;

  @override
  String toString() => code;
}

DateTime? _date(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse('$raw')?.toLocal();
}
