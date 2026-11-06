import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:trackerone/features/diagnostics/application/diagnostics_controller.dart';

DiagnosticsSnapshot _snapshot({
  bool authenticated = true,
  bool offline = false,
  PermissionStatus location = PermissionStatus.granted,
  PermissionStatus background = PermissionStatus.granted,
  PermissionStatus notifications = PermissionStatus.granted,
  PermissionStatus? activityRecognition = PermissionStatus.granted,
  bool? batteryIgnored = true,
  bool trackingRunning = true,
  bool restReachable = true,
  bool socketConnected = true,
  ConnectivityResult network = ConnectivityResult.wifi,
}) {
  return DiagnosticsSnapshot(
    checkedAt: DateTime(2026, 11, 4),
    authenticated: authenticated,
    offline: offline,
    location: location,
    backgroundLocation: background,
    notifications: notifications,
    activityRecognition: activityRecognition,
    batteryOptimizationIgnored: batteryIgnored,
    trackingRunning: trackingRunning,
    trackingLogs: const [],
    restReachable: restReachable,
    socketConnected: socketConnected,
    network: network,
  );
}

void main() {
  group('DiagnosticsSnapshot.level', () {
    test('reports ok when everything is healthy', () {
      expect(_snapshot().level, DiagnosticsLevel.ok);
    });

    test('blocks reporting when location is denied', () {
      expect(
        _snapshot(location: PermissionStatus.denied).level,
        DiagnosticsLevel.error,
      );
    });

    test('treats limited location access as usable', () {
      expect(
        _snapshot(location: PermissionStatus.limited).level,
        DiagnosticsLevel.ok,
      );
    });

    test('warns when background location is missing', () {
      expect(
        _snapshot(background: PermissionStatus.denied).level,
        DiagnosticsLevel.warning,
      );
    });

    test('warns when notifications are missing', () {
      expect(
        _snapshot(notifications: PermissionStatus.denied).level,
        DiagnosticsLevel.warning,
      );
    });

    test('warns when battery optimization is restricted', () {
      expect(
        _snapshot(batteryIgnored: false).level,
        DiagnosticsLevel.warning,
      );
    });

    test('warns when reporting is stopped', () {
      expect(_snapshot(trackingRunning: false).level, DiagnosticsLevel.warning);
    });

    test('ignores missing motion permission when not applicable', () {
      expect(
        _snapshot(activityRecognition: null).level,
        DiagnosticsLevel.ok,
      );
    });

    test('errors when the server is unreachable online', () {
      expect(
        _snapshot(restReachable: false).level,
        DiagnosticsLevel.error,
      );
    });

    test('downgrades to warning when offline with cache', () {
      expect(
        _snapshot(restReachable: false, offline: true).level,
        DiagnosticsLevel.warning,
      );
    });

    test('warns when the session is not authenticated', () {
      expect(
        _snapshot(authenticated: false, restReachable: false).level,
        DiagnosticsLevel.warning,
      );
    });
  });

  group('PermissionStatusX', () {
    test('limited and provisional permissions count as granted', () {
      expect(PermissionStatus.granted.isGrantedOrLimited, isTrue);
      expect(PermissionStatus.limited.isGrantedOrLimited, isTrue);
      expect(PermissionStatus.provisional.isGrantedOrLimited, isTrue);
      expect(PermissionStatus.denied.isGrantedOrLimited, isFalse);
      expect(PermissionStatus.permanentlyDenied.isGrantedOrLimited, isFalse);
    });
  });
}
