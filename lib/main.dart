import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/observability/crash_reporter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 只用于海外 / 开发包；未配置时自动降级，不阻断启动。
  final crashReporter = await CrashReporterFactory.create();
  installCrashHandlers(crashReporter);

  runApp(
    ProviderScope(
      overrides: [crashReporterProvider.overrideWithValue(crashReporter)],
      child: const TrackerOneApp(),
    ),
  );
}
