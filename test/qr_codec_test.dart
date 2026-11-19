import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/failures.dart';
import 'package:trackerone/features/server/presentation/qr_scanner_screen.dart';

Matcher _rejects(String key) => throwsA(
      isA<AppFailure>()
          .having((e) => e.kind, 'kind', FailureKind.invalidRequest)
          .having((e) => e.messageKey, 'messageKey', key),
    );

void main() {
  group('ServerProfileCodec', () {
    test('接受裸地址', () {
      final profile = ServerProfileCodec.parse('https://track.example.com');
      expect(profile.apiBaseUrl, 'https://track.example.com');
      expect(profile.reportUrl, 'https://track.example.com:5055');
    });

    test('接受 JSON 二维码', () {
      final profile = ServerProfileCodec.parse(
        '{"name":"公司","url":"https://track.example.com",'
        '"reportUrl":"http://10.0.0.2:5055"}',
      );
      expect(profile.name, '公司');
      expect(profile.reportUrl, 'http://10.0.0.2:5055');
    });

    test('接受 trackerone 深链', () {
      final profile = ServerProfileCodec.parse(
        'trackerone://server?url=https://track.example.com&name=车队',
      );
      expect(profile.apiBaseUrl, 'https://track.example.com');
      expect(profile.name, '车队');
    });

    test('空内容给出可本地化的错误', () {
      expect(() => ServerProfileCodec.parse('   '), _rejects('qrEmpty'));
    });

    test('非法 JSON 给出可本地化的错误', () {
      expect(() => ServerProfileCodec.parse('{oops}'), _rejects('qrMalformed'));
    });

    test('缺少地址给出可本地化的错误', () {
      expect(
        () => ServerProfileCodec.parse('{"name":"x"}'),
        _rejects('qrMissingUrl'),
      );
      expect(
        () => ServerProfileCodec.parse('trackerone://server?name=x'),
        _rejects('qrMissingUrl'),
      );
    });
  });
}
