import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException();
}

/// Secure storage wrapper used for licensing/device identity.
///
/// General values keep a compatibility fallback for older installations.
/// High-value secrets (device proof / local DB key) use the strict methods and
/// are never persisted to SharedPreferences.
class SecureKvStore {
  SecureKvStore._();
  static final SecureKvStore instance = SecureKvStore._();

  static const _fallbackPrefix = 'secure_fallback_v1__';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> read(String key) async {
    try {
      final secureValue = await _storage.read(key: key);
      if (secureValue != null) return secureValue;

      final prefs = await SharedPreferences.getInstance();
      final legacyValue = prefs.get(key);
      if (legacyValue != null) {
        final converted = _convertToString(legacyValue);
        if (converted != null) {
          try {
            await _storage.write(key: key, value: converted);
            await prefs.remove(key);
            await prefs.remove('$_fallbackPrefix$key');
          } catch (_) {
            await prefs.setString('$_fallbackPrefix$key', converted);
            await prefs.remove(key);
          }
          return converted;
        }
      }

      return _convertToString(prefs.get('$_fallbackPrefix$key'));
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return _convertToString(
        prefs.get('$_fallbackPrefix$key') ?? prefs.get(key),
      );
    }
  }

  Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('$_fallbackPrefix$key');
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove('$_fallbackPrefix$key');
        await prefs.remove(key);
      } else {
        await prefs.setString('$_fallbackPrefix$key', value);
        await prefs.remove(key);
      }
    }
  }

  /// Reads a secret from OS-backed secure storage only.
  ///
  /// Legacy fallback values are migrated into secure storage once. If the OS
  /// secure store is unavailable, this method fails closed instead of writing
  /// the secret to SharedPreferences.
  Future<String?> readStrict(String key) async {
    try {
      final secureValue = await _storage.read(key: key);
      if (secureValue != null) return secureValue;

      final prefs = await SharedPreferences.getInstance();
      final legacy = _convertToString(
        prefs.get(key) ?? prefs.get('$_fallbackPrefix$key'),
      );
      if (legacy == null) return null;

      await _storage.write(key: key, value: legacy);
      await prefs.remove(key);
      await prefs.remove('$_fallbackPrefix$key');
      return legacy;
    } catch (_) {
      throw const SecureStorageUnavailableException();
    }
  }

  Future<void> writeStrict(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('$_fallbackPrefix$key');
    } catch (_) {
      throw const SecureStorageUnavailableException();
    }
  }

  Future<bool> readBool(String key) async {
    final value = await read(key);
    if (value == null) return false;
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  Future<void> writeBool(String key, bool value) =>
      write(key, value ? '1' : '0');

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await prefs.remove('$_fallbackPrefix$key');
  }

  static String? _convertToString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is bool) return value ? '1' : '0';
    if (value is num) return value.toString();
    if (value is List<String>) return value.join(',');
    return value.toString();
  }
}
