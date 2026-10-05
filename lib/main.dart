import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Config editable por el módulo Admin (SharedPreferences).
  await AppSettings.instance.init();
  runApp(const ProviderScope(child: IspApp()));
}
