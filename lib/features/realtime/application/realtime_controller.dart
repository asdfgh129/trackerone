import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/build_config.dart';
import '../../../core/dev/simulated_data.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/traccar_api.dart';
import '../../../core/network/traccar_socket.dart';
import '../../../core/storage/realtime_cache.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/failures.dart';
import '../../auth/application/session_controller.dart';

class RealtimeState {
  const RealtimeState({
    this.devices = const {},
    this.positions = const {},
    this.events = const [],
    this.connected = false,
    this.loading = false,
    this.error,
  });

  final Map<int, Device> devices;

  /// deviceId → 最新位置。
  final Map<int, Position> positions;

  /// 最近的实时事件，按时间倒序。
  final List<DeviceEvent> events;

  final bool connected;
  final bool loading;
  final String? error;

  bool get isEmpty => devices.isEmpty && positions.isEmpty && events.isEmpty;

  Position? positionFor(int deviceId) => positions[deviceId];

  RealtimeState copyWith({
    Map<int, Device>? devices,
    Map<int, Position>? positions,
    List<DeviceEvent>? events,
    bool? connected,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return RealtimeState(
      devices: devices ?? this.devices,
      positions: positions ?? this.positions,
      events: events ?? this.events,
      connected: connected ?? this.connected,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 设备/位置/事件的实时聚合。
///
/// 首屏用 REST 快照，增量来自 WebSocket；断线由 [TraccarSocketClient] 自动重连。
class RealtimeController extends AsyncNotifier<RealtimeState> {
  static const _batchWindow = Duration(milliseconds: 50);

  TraccarSocketClient? _socket;
  String? _serverId;
  RealtimeCache? _cache;

  Timer? _batchTimer;
  TraccarSocketBatch? _pendingBatch;

  @override
  Future<RealtimeState> build() async {
    final session = ref.watch(sessionProvider);
    final current = session.valueOrNull;
    if (current == null || !current.isAuthenticated) {
      return const RealtimeState();
    }

    final server = current.server!;
    final token = current.token!;
    final api = ref.watch(traccarApiProvider);
    if (api == null) return const RealtimeState();

    _serverId = server.id;
    final cache = ref.watch(realtimeCacheProvider);
    _cache = cache;
    final cached = await cache.load(server.id);

    final socket = TraccarSocketClient(
      server: server,
      token: token,
      onUnauthorized: () {
        unawaited(ref.read(sessionProvider.notifier).invalidate());
      },
    );
    _socket = socket;

    final statusSubscription = socket.statuses.listen((status) {
      _update(connected: status == SocketStatus.connected);
    });
    final batchSubscription = socket.batches.listen(_onBatch);

    ref.onDispose(() {
      _batchTimer?.cancel();
      _batchTimer = null;
      _pendingBatch = null;
      unawaited(statusSubscription.cancel());
      unawaited(batchSubscription.cancel());
      unawaited(socket.dispose());
    });

    final initial = await _loadSnapshot(api, cached: cached);
    socket.connect();
    return initial;
  }

  Future<RealtimeState> _loadSnapshot(
    TraccarApi api, {
    CachedRealtime? cached,
  }) async {
    try {
      final results = await Future.wait<Object>([
        api.getDevices(),
        api.getLatestPositions(),
      ]);
      final simulated = BuildConfig.simulateDevices > 0
          ? buildSimulatedData(BuildConfig.simulateDevices)
          : null;
      final devices = <Device>[
        ...(results[0] as List<Device>),
        ...?simulated?.devices,
      ];
      final positions = <Position>[
        ...(results[1] as List<Position>),
        ...?simulated?.positions,
      ];
      final serverId = _serverId;
      if (serverId != null && simulated == null) {
        unawaited(
          _cache?.saveSnapshot(
            serverId: serverId,
            devices: devices,
            positions: positions,
          ),
        );
      }
      return RealtimeState(
        devices: {for (final device in devices) device.id: device},
        positions: {for (final position in positions) position.deviceId: position},
        events: cached?.events ?? state.valueOrNull?.events ?? const [],
        loading: false,
      );
    } on AppFailure catch (failure) {
      if (failure.isUnauthorized) {
        unawaited(ref.read(sessionProvider.notifier).invalidate());
      }
      return _fallback(cached, failure.message);
    } catch (error) {
      return _fallback(cached, error.toString());
    }
  }

  RealtimeState _fallback(CachedRealtime? cached, String message) {
    if (cached != null && !cached.isEmpty) {
      return RealtimeState(
        devices: {for (final device in cached.devices) device.id: device},
        positions: {
          for (final position in cached.positions)
            position.deviceId: position,
        },
        events: cached.events,
        loading: false,
        error: message,
      );
    }
    return RealtimeState(error: message);
  }

  /// WebSocket 到达的帧先累积 50ms 再统一合并，避免高并发设备下
  /// 每帧都触发一次整页重建（PRD 要求 500/1000 设备 ≥30fps）。
  void _onBatch(TraccarSocketBatch batch) {
    final pending = _pendingBatch;
    _pendingBatch = TraccarSocketBatch(
      devices: [...?pending?.devices, ...batch.devices],
      positions: [...?pending?.positions, ...batch.positions],
      events: [...?pending?.events, ...batch.events],
    );
    _batchTimer ??= Timer(_batchWindow, _flushBatches);
  }

  void _flushBatches() {
    _batchTimer = null;
    final batch = _pendingBatch;
    _pendingBatch = null;
    if (batch == null || batch.isEmpty) return;

    final current = state.valueOrNull ?? const RealtimeState();
    final devices = {...current.devices};
    final positions = {...current.positions};

    for (final device in batch.devices) {
      devices[device.id] = device;
    }
    for (final position in batch.positions) {
      final previous = positions[position.deviceId];
      if (previous == null || _isNewer(position, previous)) {
        positions[position.deviceId] = position;
      }
    }

    final events = [...current.events];
    for (final event in batch.events) {
      if (!events.any((item) => item.id == event.id)) {
        events.insert(0, event);
      }
    }

    state = AsyncData(
      current.copyWith(
        devices: devices,
        positions: positions,
        events: events.take(200).toList(growable: false),
        clearError: true,
      ),
    );

    final serverId = _serverId;
    if (serverId != null) {
      unawaited(
        _cache?.upsertBatch(
          serverId: serverId,
          devices: batch.devices,
          positions: batch.positions,
          events: batch.events,
        ),
      );
    }
  }

  static bool _isNewer(Position left, Position right) {
    if (left.id != 0 && right.id != 0) return left.id > right.id;
    final leftTime = left.fixTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightTime = right.fixTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return leftTime.isAfter(rightTime);
  }

  void _update({bool? connected, String? error}) {
    final current = state.valueOrNull ?? const RealtimeState();
    state = AsyncData(
      current.copyWith(
        connected: connected,
        error: error,
        clearError: error == null,
      ),
    );
  }

  Future<void> refresh() async {
    final api = ref.read(traccarApiProvider);
    if (api == null) return;
    final previous = state.valueOrNull;
    state = const AsyncLoading<RealtimeState>();
    final snapshot = await _loadSnapshot(
      api,
      cached: previous == null
          ? null
          : CachedRealtime(
              devices: previous.devices.values.toList(growable: false),
              positions: previous.positions.values.toList(growable: false),
              events: previous.events,
              updatedAt: DateTime.now(),
            ),
    );
    // 拉取快照期间 WebSocket 可能仍保持连接，不能用默认的 false 覆盖。
    state = AsyncData(
      snapshot.copyWith(
        connected: _socket?.status == SocketStatus.connected,
      ),
    );
    _socket?.connect();
  }
}

final realtimeProvider =
    AsyncNotifierProvider<RealtimeController, RealtimeState>(
  RealtimeController.new,
);
