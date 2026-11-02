import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/build_config.dart';

/// 崩溃上报抽象。
///
/// 中国大陆生产环境不能依赖 Crashlytics（需要 GMS），
/// 因此默认 [NoopCrashReporter]，后续接腾讯 Bugly 时新增实现即可。
abstract interface class CrashReporter {
  Future<void> initialize();
  void recordFlutterError(FlutterErrorDetails details);
  void recordError(Object error, StackTrace? stack, {bool fatal = false});
  Future<void> log(String message);
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> initialize() async {}

  @override
  void recordFlutterError(FlutterErrorDetails details) {}

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) {}

  @override
  Future<void> log(String message) async {}
}

/// 海外 / 开发环境使用。
class FirebaseCrashReporter implements CrashReporter {
  const FirebaseCrashReporter();

  @override
  Future<void> initialize() async {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    if (kDebugMode) return;
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) {
    if (kDebugMode) return;
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  }

  @override
  Future<void> log(String message) =>
      FirebaseCrashlytics.instance.log(message);
}

/// 默认实现，测试或未配置时使用。
final crashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
);

abstract final class CrashReporterFactory {
  /// 根据构建配置创建实现。
  ///
  /// 关键点：Firebase 未配置（缺 google-services.json / GoogleService-Info.plist）
  /// 时不能阻断启动，失败直接降级为 [NoopCrashReporter]。
  static Future<CrashReporter> create() async {
    if (BuildConfig.crashReporter != 'firebase') {
      return const NoopCrashReporter();
    }
    try {
      await Firebase.initializeApp();
      const reporter = FirebaseCrashReporter();
      await reporter.initialize();
      return reporter;
    } catch (error) {
      debugPrint('Firebase 初始化失败，崩溃上报降级为 noop: $error');
      return const NoopCrashReporter();
    }
  }
}

/// 安装全局错误处理。必须在 `runApp` 之前调用。
void installCrashHandlers(CrashReporter reporter) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reporter.recordFlutterError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.recordError(error, stack, fatal: true);
    return true;
  };
}
