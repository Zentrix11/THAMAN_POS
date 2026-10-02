import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 verifier for local/offline credentials.
/// Legacy plaintext values are accepted only long enough to migrate them.
class LocalCredentialHasher {
  LocalCredentialHasher._();

  static const String _prefix = 'thm-pbkdf2-v1';
  static const int _iterations = 120000;
  static const int _saltLength = 16;
  static const int _derivedLength = 32;

  static bool isHash(String value) => value.startsWith('$_prefix\$');

  /// True for a legacy plaintext credential that should be migrated to PBKDF2.
  static bool needsUpgrade(String value) => value.isNotEmpty && !isHash(value);

  static String hash(String secret) {
    if (secret.isEmpty) return '';
    if (isHash(secret)) return secret;
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
    final derived = _pbkdf2(
      secret: secret,
      salt: salt,
      iterations: _iterations,
      outputLength: _derivedLength,
    );
    return '$_prefix\$$_iterations\$${base64UrlEncode(salt)}\$${base64UrlEncode(derived)}';
  }

  static bool verify(String candidate, String stored) {
    if (candidate.isEmpty || stored.isEmpty) return false;
    if (!isHash(stored)) {
      return _constantTimeEquals(utf8.encode(candidate), utf8.encode(stored));
    }
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _prefix) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1000 || iterations > 1000000) {
      return false;
    }
    try {
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      final actual = _pbkdf2(
        secret: candidate,
        salt: Uint8List.fromList(salt),
        iterations: iterations,
        outputLength: expected.length,
      );
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static Uint8List _pbkdf2({
    required String secret,
    required Uint8List salt,
    required int iterations,
    required int outputLength,
  }) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    const hashLength = 32;
    final blockCount = (outputLength / hashLength).ceil();
    final output = BytesBuilder(copy: false);

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final blockInput = BytesBuilder(copy: false)
        ..add(salt)
        ..add([
          (blockIndex >> 24) & 0xff,
          (blockIndex >> 16) & 0xff,
          (blockIndex >> 8) & 0xff,
          blockIndex & 0xff,
        ]);
      var u = Uint8List.fromList(hmac.convert(blockInput.toBytes()).bytes);
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }
    final bytes = output.toBytes();
    return Uint8List.fromList(bytes.sublist(0, outputLength));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
