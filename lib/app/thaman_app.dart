import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_controller.dart';
import '../core/navigation/app_navigator.dart';
import '../features/auth/startup_gate.dart';
import 'app_scroll_behavior.dart';
import 'app_theme.dart';

class ThamanApp extends StatefulWidget {
  const ThamanApp({super.key});

  @override
  State<ThamanApp> createState() => _ThamanAppState();
}

class _ThamanAppState extends State<ThamanApp> {
  final AppController controller = AppController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final locale = Locale(controller.isArabic ? 'ar' : 'en');
          return MaterialApp(
            navigatorKey: thamanNavigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'THAMAN POS',
            theme: AppTheme.light,
            locale: locale,
            supportedLocales: const <Locale>[
              Locale('ar'),
              Locale('en'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            scrollBehavior: const ThamanScrollBehavior(),
            builder: (context, child) {
              final media = MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false);
              return MediaQuery(
                data: media,
                child: Directionality(
                  textDirection: controller.isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: const StartupGate(),
          );
        },
      ),
    );
  }
}
