import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/dive_computer/domain/services/suunto_nautic_derived_events.dart';

void main() {
  group('deriveSuuntoNauticEvents', () {
    test('emits a low-no-deco-time event when NDL crosses the threshold', () {
      final events = deriveSuuntoNauticEvents(
        timestamps: [0, 60, 120, 180],
        depths: [5, 20, 30, 30],
        ndlSeconds: [3600, 1200, 300, 240], // hits 5 min at t=120
        ceilings: [null, null, null, null],
      );
      expect(events, hasLength(1));
      expect(events.single.type, ProfileEventType.lowNoDecoTime);
      expect(events.single.timestampSeconds, 120);
      expect(events.single.value, 5.0);
      expect(events.single.depth, 30);
      expect(events.single.description, 'Low no-deco time');
    });

    test('emits low NDL then decompression dive as NDL runs down', () {
      final events = deriveSuuntoNauticEvents(
        timestamps: [0, 60, 120, 180],
        depths: [5, 30, 35, 35],
        ndlSeconds: [3600, 240, 0, 0], // low NDL at t=60, deco at t=120
        ceilings: [null, null, 3.0, 3.0],
      );
      expect(events.map((e) => e.type), [
        ProfileEventType.lowNoDecoTime,
        ProfileEventType.decompressionDive,
      ]);
      expect(events[0].timestampSeconds, 60);
      expect(events[1].timestampSeconds, 120);
    });

    test('a straight run to deco emits only the decompression-dive event', () {
      final events = deriveSuuntoNauticEvents(
        timestamps: [0, 60, 120],
        depths: [5, 30, 35],
        ndlSeconds: [3600, 600, 0], // jumps past the 5-min threshold
        ceilings: [null, null, 3.0],
      );
      expect(events.map((e) => e.type), [ProfileEventType.decompressionDive]);
      expect(events.single.timestampSeconds, 120);
    });

    test('a deco onset signalled by NDL <= 0 also counts', () {
      final events = deriveSuuntoNauticEvents(
        timestamps: [0, 60],
        depths: [30, 35],
        ndlSeconds: [600, -1],
        ceilings: [null, null],
      );
      expect(
        events.any((e) => e.type == ProfileEventType.decompressionDive),
        isTrue,
      );
    });

    test('each event fires once', () {
      final events = deriveSuuntoNauticEvents(
        timestamps: [0, 60, 120, 180, 240],
        depths: [30, 30, 30, 30, 30],
        ndlSeconds: [200, 180, 60, 120, 90],
        ceilings: [null, null, null, null, null],
      );
      expect(
        events.where((e) => e.type == ProfileEventType.lowNoDecoTime),
        hasLength(1),
      );
      expect(events.single.timestampSeconds, 0);
    });

    test('no events on a clean no-deco dive', () {
      final events = deriveSuuntoNauticEvents(
        timestamps: [0, 60, 120],
        depths: [5, 18, 18],
        ndlSeconds: [3600, 3000, 2400],
        ceilings: [null, null, null],
      );
      expect(events, isEmpty);
    });

    test('tolerates ragged / empty input', () {
      expect(
        deriveSuuntoNauticEvents(
          timestamps: const [],
          depths: const [],
          ndlSeconds: const [],
          ceilings: const [],
        ),
        isEmpty,
      );
    });
  });
}
