import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ThamanScrollBehavior extends MaterialScrollBehavior {
  const ThamanScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}
