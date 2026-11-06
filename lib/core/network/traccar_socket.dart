import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/models.dart';
import '../../domain/entities/server_profile.dart';

/// Traccar WebSocket 推送的一帧数据。同一帧可能包含多个集合。
class TraccarSocketBatch {
  const TraccarSocketBatch({
    this.devices = const [],
    this.positions = const [],
    this.events = const [],
  });

  final List<Device> devices;
  final List<Position> positions;
  final List<DeviceEvent> events;

  bool get isEmpty =>
      devices.isEmpty && positions.isEmpty && events.isEmpty;
}

enum SocketStatus { disconnected, connecting, connected }

/// 全局单连接客户端，按用户/服务器隔离。
///
/// 断线重连：1s → 2s → 4s … → 30s，±20% 抖动。
class TraccarSocketClient {
  TraccarSocketClient({
    required this.server,
    required this.token,
    this.onUnauthorized,
  });

  final ServerProfile server;
  final String token;

  /// 服务端返回未授权帧或连接被 401 拒绝时回调，用于清理会话。
  final VoidCallback? onUnauthorized;

  final StreamController<TraccarSocketBatch> _batches =
      StreamController<TraccarSocketBatch>.broadcast();
  final StreamController<SocketStatus> _statuses =
      StreamController<SocketStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;
  SocketStatus _status = SocketStatus.disconnected;

  Stream<TraccarSocketBatch> get batches => _batches.stream;
  Stream<SocketStatus> get statuses => _statuses.stream;
  SocketStatus get status => _status;

  Uri get socketUri {
    final base = Uri.parse(server.apiBaseUrl);
    final basePath = base.path == '/' ? '' : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$basePath/api/socket',
      queryParameters: {'token': token},
    );
  }

  void connect() {
    if (_disposed || _status != SocketStatus.disconnected) return;
    _setStatus(SocketStatus.connecting);

    try {
      final channel = WebSocketChannel.connect(socketUri);
      _channel = channel;
      unawaited(
        channel.ready.then((_) {
          if (_disposed) return;
          _attempt = 0;
          _setStatus(SocketStatus.connected);
          _subscription = channel.stream.listen(
            _onData,
            onError: (Object error, StackTrace stack) {
              debugPrint('Traccar socket error: $error');
              _scheduleReconnect();
            },
            onDone: _scheduleReconnect,
            cancelOnError: true,
          );
        }).catchError((Object error, StackTrace stack) {
          debugPrint('Traccar socket connect failed: $error');
          _scheduleReconnect();
        }),
      );
    } catch (error) {
      debugPrint('Traccar socket create failed: $error');
      _scheduleReconnect();
    }
  }

  void _onData(Object? raw) {
    if (_disposed || raw == null) return;
    try {
      final decoded = raw is String ? jsonDecode(raw) : jsonDecode(utf8.decode(raw as List<int>));
      if (decoded is! Map) return;
      final map = decoded.cast<String, dynamic>();

      // Traccar 在未授权时可能推送纯文本或 {"error": "..."}。
      if (map['error'] is String) {
        final error = map['error'] as String;
        if (error.toLowerCase().contains('unauthorized')) {
          onUnauthorized?.call();
        }
        return;
      }

      final batch = TraccarSocketBatch(
        devices: _parseList(map['devices'], Device.fromJson),
        positions: _parseList(map['positions'], Position.fromJson),
        events: _parseList(map['events'], DeviceEvent.fromJson),
      );
      if (!batch.isEmpty) _batches.add(batch);
    } catch (error) {
      // 单帧解析失败只记录并丢弃，绝不断开连接。
      debugPrint('Traccar socket parse failed: $error');
    }
  }

  static List<T> _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (value is! List) return const [];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((item) => parse(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _setStatus(SocketStatus.disconnected);
    if (_reconnectTimer?.isActive ?? false) return;

    _attempt = _attempt.clamp(0, 5);
    final baseSeconds = 1 << _attempt;
    final jitter = 0.8 + Random().nextDouble() * 0.4;
    final delay = Duration(
      milliseconds: (baseSeconds * 1000 * jitter).round(),
    );
    if (baseSeconds < 30) _attempt++;

    debugPrint('Traccar socket reconnect in ${delay.inMilliseconds}ms');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_disposed) return;
      _setStatus(SocketStatus.disconnected);
      connect();
    });
  }

  void _setStatus(SocketStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    await _batches.close();
    await _statuses.close();
  }
}
