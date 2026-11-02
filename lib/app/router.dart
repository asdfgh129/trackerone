import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/placeholder/placeholder_screen.dart';

/// 路由集中管理。后续接入会话状态后，在 [redirect] 中实现守卫：
/// 1. 无服务器档案 -> /server
/// 2. 需要登录但无 Token -> /login?redirect=...
/// 3. 推送冷启动意图在会话恢复后消费
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'server',
          builder: (context, state) => const PlaceholderScreen(
            title: '服务器配置',
            subtitle: '实现 docs/01-prd.md AUTH-01 ~ AUTH-03',
          ),
        ),
        GoRoute(
          path: 'login',
          builder: (context, state) => const PlaceholderScreen(
            title: '登录',
            subtitle: '实现 docs/01-prd.md AUTH-04 ~ AUTH-07',
          ),
        ),
        GoRoute(
          path: 'onboarding/permissions',
          builder: (context, state) => const PlaceholderScreen(
            title: '权限向导',
            subtitle: '实现 docs/02-ux-spec.md 3.4',
          ),
        ),
        GoRoute(
          path: 'device/:id',
          builder: (context, state) => PlaceholderScreen(
            title: '设备详情',
            subtitle: 'deviceId = ${state.pathParameters['id']}',
          ),
        ),
        GoRoute(
          path: 'device/:id/history',
          builder: (context, state) => PlaceholderScreen(
            title: '历史回放',
            subtitle: 'deviceId = ${state.pathParameters['id']}',
          ),
        ),
        GoRoute(
          path: 'event/:id',
          builder: (context, state) => PlaceholderScreen(
            title: '事件详情',
            subtitle: 'eventId = ${state.pathParameters['id']}',
          ),
        ),
        GoRoute(
          path: 'diagnostics',
          builder: (context, state) => const PlaceholderScreen(
            title: '诊断',
            subtitle: '实现 docs/05-tracking-engine.md 第 9 节',
          ),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => const PlaceholderScreen(
            title: '设置',
            subtitle: '实现 docs/01-prd.md SET-01 ~ SET-06',
          ),
        ),
      ],
    ),
  ],
);
