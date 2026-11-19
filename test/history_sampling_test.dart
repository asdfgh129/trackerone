import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/entities/models.dart';
import 'package:trackerone/features/history/application/history_provider.dart';

Position _position(int index) => Position(
      id: index,
      deviceId: 1,
      latitude: 39.9 + index / 100000,
      longitude: 116.4 + index / 100000,
      fixTime: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
    );

void main() {
  group('samplePositions', () {
    test('点数未超上限时原样返回', () {
      final positions = [for (var i = 0; i < 100; i++) _position(i)];
      expect(samplePositions(positions, 1000), same(positions));
    });

    test('超上限时按步长抽稀并保留首尾点', () {
      final positions = [for (var i = 0; i < 5000; i++) _position(i)];
      final sampled = samplePositions(positions, 1000);

      expect(sampled.length, lessThanOrEqualTo(1001));
      expect(sampled.first, same(positions.first));
      expect(sampled.last, same(positions.last));
      // 抽稀后仍按时间升序
      for (var i = 1; i < sampled.length; i++) {
        expect(
          sampled[i].fixTime!.isAfter(sampled[i - 1].fixTime!),
          isTrue,
        );
      }
    });
  });

  group('HistoryQuery', () {
    test('今天从本地零点开始', () {
      final window = const HistoryQuery(
        deviceId: 1,
        range: HistoryRange.today,
      ).window;
      expect(window.from.hour, 0);
      expect(window.from.minute, 0);
      expect(window.to.isAfter(window.from), isTrue);
    });

    test('最近 7 天从 6 天前的零点开始', () {
      final window = const HistoryQuery(
        deviceId: 1,
        range: HistoryRange.last7Days,
      ).window;
      final days = window.to.difference(window.from).inDays;
      expect(days, inInclusiveRange(5, 7));
    });

    test('相同设备与范围视为同一查询', () {
      expect(
        const HistoryQuery(deviceId: 1, range: HistoryRange.today),
        const HistoryQuery(deviceId: 1, range: HistoryRange.today),
      );
    });
  });
}
