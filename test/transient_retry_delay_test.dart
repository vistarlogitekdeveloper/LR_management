import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/core/network/api_client.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  test(
    'transient retry waits ~1s then ~3s, long enough to outlast a Wi-Fi blip',
    () {
      expect(
        transientRetryDelay(1, random: _FixedRandom(0)),
        const Duration(seconds: 1),
      );
      expect(
        transientRetryDelay(2, random: _FixedRandom(0)),
        const Duration(seconds: 3),
      );
    },
  );

  test('jitter adds at most 25%', () {
    expect(
      transientRetryDelay(1, random: _FixedRandom(1)),
      const Duration(milliseconds: 1250),
    );
    expect(
      transientRetryDelay(2, random: _FixedRandom(1)),
      const Duration(milliseconds: 3750),
    );
  });
}
