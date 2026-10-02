import 'package:flutter/material.dart';

/// Shared navigator key used by cross-cutting UI services (for example the
/// print-preview flow) without forcing every print call site to pass context.
final GlobalKey<NavigatorState> thamanNavigatorKey = GlobalKey<NavigatorState>();
