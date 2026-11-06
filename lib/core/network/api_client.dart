import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/server_profile.dart';
import '../../features/auth/application/session_controller.dart';
import 'traccar_api.dart';

export '../../domain/entities/server_profile.dart';

/// 认证后的 REST 客户端。未登录时为 null。
final traccarApiProvider = Provider<TraccarApi?>((ref) {
  final session = ref.watch(sessionProvider).valueOrNull;
  final server = session?.server;
  final token = session?.token;
  if (server == null || token == null || token.isEmpty) return null;
  return TraccarApi(server: server, token: token);
});

/// 便于测试与诊断页展示；正式请求请使用 [traccarApiProvider]。
final serverApiProvider = Provider.family<TraccarApi, ServerProfile>(
  (ref, server) => TraccarApi(server: server),
);
