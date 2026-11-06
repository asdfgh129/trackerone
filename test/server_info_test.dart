import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/network/traccar_api.dart';

void main() {
  group('ServerInfo', () {
    test('parses Traccar server id used by push aliases', () {
      final info = ServerInfo.fromJson({
        'id': 1,
        'version': '6.16.0',
        'coordinateFormat': 'dd',
      });

      expect(info.id, 1);
      expect(info.version, '6.16.0');
      expect(info.coordinateFormat, 'dd');
    });

    test('tolerates a missing id and numeric strings', () {
      expect(ServerInfo.fromJson({'version': '6.16'}).id, 0);
      expect(ServerInfo.fromJson({'id': '2', 'version': '6.16'}).id, 2);
    });
  });
}
