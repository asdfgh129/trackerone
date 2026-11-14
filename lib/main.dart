import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/observability/crash_reporter.dart';
import 'core/privacy/privacy_consent.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 合规：未同意隐私政策前不初始化任何第三方 SDK（含崩溃上报）。
  // Firebase 只在已同意后启动；首次同意的会话从下一次冷启动开始上报。
  final acceptedVersion =
      await const PrefsPrivacyConsentStore().readAcceptedVersion();
  final consented = acceptedVersion >= PrivacyConsentNotifier.policyVersion;
  final crashReporter = consented
      ? await CrashReporterFactory.create()
      : const NoopCrashReporter();
  installCrashHandlers(crashReporter);

  runApp(
    ProviderScope(
      overrides: [crashReporterProvider.overrideWithValue(crashReporter)],
      child: const TrackerOneApp(),
    ),
  );
}
