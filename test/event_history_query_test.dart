import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/features/events/application/events_provider.dart';

void main() {
  test('默认 24 小时、上限 300 条', () {
    const query = EventHistoryQuery();
    expect(query.range, EventRange.last24Hours);
    expect(query.range.duration, const Duration(hours: 24));
    expect(query.limit, 300);
  });

  test('范围决定时间窗口长度', () {
    expect(EventRange.last7Days.duration, const Duration(days: 7));
    expect(EventRange.last30Days.duration, const Duration(days: 30));
  });

  test('范围或上限不同的查询不相等', () {
    expect(
      const EventHistoryQuery(range: EventRange.last7Days),
      isNot(const EventHistoryQuery()),
    );
    expect(
      const EventHistoryQuery(limit: 100),
      isNot(const EventHistoryQuery()),
    );
  });
}
