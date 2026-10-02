import 'package:flutter/material.dart';
import 'app/thaman_app.dart';
import 'data/app_data_store.dart';
import 'core/notifications/subscription_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDataStore.instance.initialize();
  await SubscriptionNotificationService.instance.initialize();
  runApp(const ThamanApp());
}
