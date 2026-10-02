import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaman_pos/core/security/secure_kv_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy bool values do not crash string migration', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'qa_legacy_bool': true,
    });
    final value = await SecureKvStore.instance.readBool('qa_legacy_bool');
    expect(value, isTrue);
  });

  test('legacy numeric values are safely converted', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'qa_legacy_number': 42,
    });
    final value = await SecureKvStore.instance.read('qa_legacy_number');
    expect(value, '42');
  });
}
