import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/anime/utils/host_health_mapping.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';

void main() {
  const view = HostHealthView(
    host: 'https://server.example/stream',
    successEwma: 0.82,
    latencyEwmaMs: 240.5,
    samples: 7,
    challenges: 1,
  );

  group('hostHealthFromView', () {
    test('copies every engine field onto the persisted row', () {
      final row = hostHealthFromView(view, updatedAt: 1234);
      expect(row.host, view.host);
      expect(row.successEwma, 0.82);
      expect(row.latencyEwmaMs, 240.5);
      expect(row.samples, 7);
      expect(row.challenges, 1);
      expect(row.updatedAt, 1234);
    });

    test('the row id is derived from the host so a put upserts', () {
      final a = hostHealthFromView(view, updatedAt: 1);
      final b = hostHealthFromView(view, updatedAt: 2);
      expect(a.id, b.id);
    });
  });

  group('hostHealthToView', () {
    test('round-trips back to the engine view without loss', () {
      final row = hostHealthFromView(view, updatedAt: 99);
      final back = hostHealthToView(row);
      expect(back, view);
    });
  });

  group('hostHealthsFromViews', () {
    test('maps a whole snapshot and stamps one timestamp', () {
      const other = HostHealthView(
        host: 'https://other.example',
        successEwma: 0.4,
        latencyEwmaMs: 900,
        samples: 3,
        challenges: 0,
      );
      final rows = hostHealthsFromViews([view, other], updatedAt: 555);
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.updatedAt == 555), isTrue);
      expect(rows.map((r) => r.host), containsAll([view.host, other.host]));
    });

    test('an empty snapshot maps to an empty list', () {
      expect(hostHealthsFromViews(const [], updatedAt: 1), isEmpty);
    });
  });

  group('rankHostsByHealth', () {
    test('orders by the engine score: success up, latency and challenges down',
        () {
      final healthy = hostHealthFromView(
        const HostHealthView(
          host: 'healthy',
          successEwma: 0.95,
          latencyEwmaMs: 120,
          samples: 10,
          challenges: 0,
        ),
        updatedAt: 1,
      );
      final slow = hostHealthFromView(
        const HostHealthView(
          host: 'slow',
          successEwma: 0.9,
          latencyEwmaMs: 2000,
          samples: 10,
          challenges: 0,
        ),
        updatedAt: 1,
      );
      final challenged = hostHealthFromView(
        const HostHealthView(
          host: 'challenged',
          successEwma: 0.95,
          latencyEwmaMs: 120,
          samples: 10,
          challenges: 5,
        ),
        updatedAt: 1,
      );
      final ranked = rankHostsByHealth([slow, challenged, healthy]);
      expect(ranked, ['healthy', 'challenged', 'slow']);
    });

    test('an empty store ranks to an empty list', () {
      expect(rankHostsByHealth(const []), isEmpty);
    });
  });
}