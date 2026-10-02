import 'package:flutter_test/flutter_test.dart';
import 'package:thaman_pos/core/security/local_credential_hasher.dart';

void main() {
  test('credential hash is salted and verifiable', () {
    const secret = '5831';
    final first = LocalCredentialHasher.hash(secret);
    final second = LocalCredentialHasher.hash(secret);
    expect(first, isNot(secret));
    expect(first, isNot(second));
    expect(LocalCredentialHasher.verify(secret, first), isTrue);
    expect(LocalCredentialHasher.verify('0000', first), isFalse);
  });

  test('legacy plaintext remains verifiable only for migration', () {
    const legacy = 'old-password';
    expect(LocalCredentialHasher.needsUpgrade(legacy), isTrue);
    expect(LocalCredentialHasher.verify(legacy, legacy), isTrue);
  });
}
