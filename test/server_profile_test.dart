import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/entities/server_profile.dart';
import 'package:trackerone/domain/failures.dart';

void main() {
  group('ServerProfile.fromInput', () {
    test('derives report port 5055 from a bare host', () {
      final profile = ServerProfile.fromInput(
        'My server',
        'https://track.example.com',
      );

      expect(profile.name, 'My server');
      expect(profile.apiBaseUrl, 'https://track.example.com');
      expect(profile.reportUrl, 'https://track.example.com:5055');
      expect(profile.id, 'https://track.example.com');
    });

    test('adds https when the scheme is missing', () {
      final profile = ServerProfile.fromInput('', 'track.example.com');

      expect(profile.apiBaseUrl, 'https://track.example.com');
      expect(profile.name, 'track.example.com');
    });

    test('maps the web port 8082 to report port 5055', () {
      final profile = ServerProfile.fromInput(
        'Web',
        'http://192.168.1.10:8082',
      );

      expect(profile.apiBaseUrl, 'http://192.168.1.10:8082');
      expect(profile.reportUrl, 'http://192.168.1.10:5055');
    });

    test('keeps a custom port for both endpoints', () {
      final profile = ServerProfile.fromInput(
        'Custom',
        'https://track.example.com:8443',
      );

      expect(profile.reportUrl, 'https://track.example.com:8443');
    });

    test('keeps reverse proxy path and strips query / fragment', () {
      final profile = ServerProfile.fromInput(
        'Proxy',
        'https://example.com/traccar/?foo=bar#frag',
      );

      expect(profile.apiBaseUrl, 'https://example.com/traccar');
      expect(profile.reportUrl, 'https://example.com:5055');
    });

    test('accepts an explicit report url', () {
      final profile = ServerProfile.fromInput(
        'Explicit',
        'https://track.example.com',
        reportUrl: 'http://10.0.0.2:5055',
      );

      expect(profile.reportUrl, 'http://10.0.0.2:5055');
    });

    test('rejects invalid addresses', () {
      for (final input in ['not a server', '', 'ftp://example.com']) {
        expect(
          () => ServerProfile.fromInput('', input),
          throwsA(
            isA<AppFailure>()
                .having((e) => e.kind, 'kind', FailureKind.invalidRequest)
                .having((e) => e.messageKey, 'messageKey', isNotNull),
          ),
          reason: '输入「$input」应被拒绝',
        );
      }
    });
  });

  group('ServerProfile serialization', () {
    test('round trips through json', () {
      final profile = ServerProfile.fromInput(
        'Round trip',
        'https://track.example.com',
        allowSelfSigned: true,
      );

      final restored = ServerProfile.fromJson(profile.toJson());

      expect(restored, profile);
      expect(restored.name, 'Round trip');
      expect(restored.reportUrl, 'https://track.example.com:5055');
      expect(restored.allowSelfSigned, isTrue);
    });

    test('equality is based on the normalized address', () {
      final left = ServerProfile.fromInput(
        'A',
        'https://track.example.com',
      );
      final right = ServerProfile.fromInput(
        'B',
        'https://track.example.com/',
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });
  });
}
