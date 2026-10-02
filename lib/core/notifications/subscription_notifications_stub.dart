class SubscriptionNotificationService {
  SubscriptionNotificationService._();
  static final SubscriptionNotificationService instance =
      SubscriptionNotificationService._();

  Future<void> initialize() async {}

  Future<void> syncSubscription({
    required String subscriptionId,
    required String businessName,
    required DateTime endsAt,
    required int warningDays,
    required int graceDays,
    required String status,
    required DateTime serverNow,
  }) async {}
}
