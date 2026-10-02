import 'package:flutter_test/flutter_test.dart';
import 'package:thaman_pos/core/subscription/subscription_repository.dart';

void main() {
  test('offline lease accepts a recent server validation', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    expect(
      SubscriptionRepository.offlineLeaseAllows(
        validatedAt: now.subtract(const Duration(hours: 12)),
        now: now,
        lastObservedAt: now.subtract(const Duration(minutes: 5)),
      ),
      isTrue,
    );
  });

  test('offline lease rejects expiry beyond three days', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    expect(
      SubscriptionRepository.offlineLeaseAllows(
        validatedAt: now.subtract(const Duration(days: 4)),
        now: now,
      ),
      isFalse,
    );
  });

  test('offline lease rejects meaningful local clock rollback', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    expect(
      SubscriptionRepository.offlineLeaseAllows(
        validatedAt: now.subtract(const Duration(hours: 1)),
        now: now,
        lastObservedAt: now.add(const Duration(hours: 2)),
      ),
      isFalse,
    );
  });

  test('offline lease rejects a future validation timestamp', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    expect(
      SubscriptionRepository.offlineLeaseAllows(
        validatedAt: now.add(const Duration(hours: 1)),
        now: now,
      ),
      isFalse,
    );
  });
}
