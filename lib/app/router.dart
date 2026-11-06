import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/push/push_gateway.dart';
import '../core/push/push_service.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/devices/presentation/device_detail_screen.dart';
import '../features/devices/presentation/devices_screen.dart';
import '../features/diagnostics/presentation/battery_guide_screen.dart';
import '../features/diagnostics/presentation/diagnostics_screen.dart';
import '../features/events/presentation/event_detail_screen.dart';
import '../features/events/presentation/events_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/map/presentation/map_screen.dart';
import '../features/onboarding/presentation/permissions_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/push/application/push_registration_controller.dart';
import '../features/server/application/server_profiles_controller.dart';
import '../features/server/presentation/server_setup_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tracking/application/tracking_controller.dart';
import '../features/tracking/presentation/tracking_screen.dart';
import 'shell.dart';

/// 路由负责三件事：
/// 1. 启动时等待服务器档案与会话恢复；
/// 2. 无服务器 → /server，未登录 → /login?from=...；
/// 3. 登录后把登录页/启动页重定向回主框架。
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/home/map',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final profiles = ref.read(serverProfilesProvider);
      final session = ref.read(sessionProvider);

      if (profiles.isLoading || session.isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final server = profiles.valueOrNull?.active;
      final authenticated =
          session.valueOrNull?.isAuthenticated ?? false;

      if (server == null) {
        return location == '/server' ? null : '/server';
      }

      if (!authenticated) {
        if (location == '/login') return null;
        if (location == '/server') return null;
        if (location == '/splash') return '/login';
        return '/login?from=${Uri.encodeComponent(state.uri.toString())}';
      }

      // 已登录时不再停留在登录/启动页；/server 仍允许从设置进入。
      if (location == '/login' || location == '/splash') {
        return '/home/map';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/server',
        builder: (context, state) => const ServerSetupScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          from: state.uri.queryParameters['from'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/devices',
                builder: (context, state) => const DevicesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/events',
                builder: (context, state) => const EventsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/tracking',
                builder: (context, state) => const TrackingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/device/:id',
        builder: (context, state) => DeviceDetailScreen(
          deviceId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/device/:id/history',
        builder: (context, state) => HistoryScreen(
          deviceId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/event/:id',
        builder: (context, state) => EventDetailScreen(
          eventId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsScreen(),
      ),
      GoRoute(
        path: '/diagnostics/battery',
        builder: (context, state) => const BatteryGuideScreen(),
      ),
      GoRoute(
        path: '/onboarding/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
    ],
  );

  // 推送点击直达事件；未登录时先缓存，登录完成后再跳转。
  final push = ref.watch(pushServiceProvider);
  int? pendingEventId;

  void handlePush(PushMessage message) {
    final session = ref.read(sessionProvider).valueOrNull;
    final authenticated = session?.isAuthenticated ?? false;

    if (message.isCommand && authenticated) {
      // 远程指令：让 SDK 立即上报一次位置。
      unawaited(ref.read(trackingProvider.notifier).requestPosition());
    }

    final eventId = message.eventId;
    if (eventId == null) return;
    if (!authenticated) {
      pendingEventId = eventId;
      return;
    }
    if (router.state.uri.path == '/event/$eventId') return;
    router.push('/event/$eventId');
  }

  Future<void> consumeInitialMessage() async {
    final message = await push.takeInitialMessage();
    if (message != null) handlePush(message);
  }

  final pushSubscription = push.messages.listen((message) {
    // 前台展示不打断当前页面；只有点击通知或远程指令才处理。
    if (message.opened || message.isCommand) handlePush(message);
  });
  ref.onDispose(() => unawaited(pushSubscription.cancel()));

  // 推送 SDK 初始化完成后再读取冷启动通知，否则会拿到空值。
  ref.listen(
    pushRegistrationProvider,
    (_, next) {
      if (next is AsyncData) unawaited(consumeInitialMessage());
    },
    fireImmediately: true,
  );

  ref.listen(sessionProvider, (_, next) {
    router.refresh();
    if (next.valueOrNull?.isAuthenticated != true) return;
    final eventId = pendingEventId;
    if (eventId == null) return;
    pendingEventId = null;
    if (router.state.uri.path != '/event/$eventId') {
      router.push('/event/$eventId');
    }
  });
  ref.listen(serverProfilesProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});
