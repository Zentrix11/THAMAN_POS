import 'package:flutter_test/flutter_test.dart';
import 'package:thaman_pos/data/cloud_state_merge.dart';

void main() {
  test('concurrent invoice upserts from two devices are preserved', () {
    final baseline = <String, dynamic>{
      'invoices': <dynamic>[],
      'products': <dynamic>[],
    };
    final deviceA = <String, dynamic>{
      'invoices': <dynamic>[
        {'id': 'inv-a', 'total': 100}
      ],
      'products': <dynamic>[],
    };
    final deviceB = <String, dynamic>{
      'invoices': <dynamic>[
        {'id': 'inv-b', 'total': 200}
      ],
      'products': <dynamic>[],
    };

    final patchA = CloudStateMerge.diff(baseline, deviceA);
    final patchB = CloudStateMerge.diff(baseline, deviceB);
    final remoteAfterA = CloudStateMerge.apply(baseline, patchA);
    final merged = CloudStateMerge.apply(remoteAfterA, patchB);

    final ids = (merged['invoices'] as List)
        .map((e) => (e as Map<String, dynamic>)['id'])
        .toSet();
    expect(ids, containsAll(<String>{'inv-a', 'inv-b'}));
  });

  test('local-only serial metadata is not uploaded', () {
    final projected = CloudStateMerge.cloudProjection(<String, dynamic>{
      'invoiceSerial': 42,
      'sequenceEnds': {'invoice': 99},
      'invoices': <dynamic>[],
    });
    expect(projected.containsKey('invoiceSerial'), isFalse);
    expect(projected.containsKey('sequenceEnds'), isFalse);
  });
}
