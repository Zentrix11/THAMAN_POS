import 'security/local_credential_hasher.dart';

/// Backwards-compatible facade used throughout the V9.4 credential migration.
class CredentialHash {
  CredentialHash._();

  static bool isHash(String value) => LocalCredentialHasher.isHash(value);
  static bool needsUpgrade(String value) => LocalCredentialHasher.needsUpgrade(value);
  static String encode(String value) => LocalCredentialHasher.hash(value);
  static bool verify(String candidate, String stored) =>
      LocalCredentialHasher.verify(candidate, stored);
  static String upgraded(String candidate, String stored) =>
      verify(candidate, stored) && needsUpgrade(stored) ? encode(candidate) : stored;
}
