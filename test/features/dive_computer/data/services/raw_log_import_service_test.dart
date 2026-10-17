import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer_plugin/libdivecomputer_plugin.dart' as pigeon;
import 'package:submersion/features/dive_computer/data/services/raw_log_import_service.dart';

Uint8List _record(String tail) =>
    Uint8List.fromList([...'SBEM0103'.codeUnits, ...tail.codeUnits]);

pigeon.ParsedDive _dive({
  required String fingerprint,
  int year = 2026,
  int month = 4,
  int day = 1,
  int hour = 10,
  double maxDepth = 18.0,
  int? gfLow,
}) => pigeon.ParsedDive(
  fingerprint: fingerprint,
  dateTimeYear: year,
  dateTimeMonth: month,
  dateTimeDay: day,
  dateTimeHour: hour,
  dateTimeMinute: 0,
  dateTimeSecond: 0,
  maxDepthMeters: maxDepth,
  avgDepthMeters: maxDepth / 2,
  durationSeconds: 2400,
  samples: [
    pigeon.ProfileSample(timeSeconds: 0, depthMeters: 0),
    pigeon.ProfileSample(timeSeconds: 60, depthMeters: maxDepth),
    pigeon.ProfileSample(timeSeconds: 2400, depthMeters: 0),
  ],
  tanks: const [],
  gasMixes: const [],
  events: const [],
  gfLow: gfLow,
);

void main() {
  test('empty / unrecognised file yields no dives and a warning', () async {
    final service = RawLogImportService(
      parseFn: (_, _, _, _) async => throw StateError('should not be called'),
    );
    final out = await service.parse(Uint8List.fromList('not a log'.codeUnits));
    expect(out.dives, isEmpty);
    expect(out.recordsRead, 0);
    expect(out.warnings, isNotEmpty);
  });

  test(
    'profile + Summary are grouped into one dive (widest match wins)',
    () async {
      final calls = <int>[];
      final service = RawLogImportService(
        parseFn: (vendor, product, model, data) async {
          calls.add(data.length);
          expect(vendor, 'Suunto');
          expect(product, 'Nautic');
          // The profile-only blob has no GF; the profile+Summary blob does.
          final hasSummary = String.fromCharCodes(data).contains('SUMMARY');
          return _dive(fingerprint: 'dive-1', gfLow: hasSummary ? 30 : null);
        },
      );

      final bytes = Uint8List.fromList([
        ..._record(' PROFILE'),
        ..._record(' SUMMARY'),
      ]);
      final out = await service.parse(bytes);

      expect(out.dives, hasLength(1));
      expect(
        out.dives.single.gfLow,
        30,
        reason: 'the profile+Summary blob won',
      );
      expect(out.recordsRead, 2);
      expect(out.divesFailed, 0);
    },
  );

  test('a two-dive file produces two dives, oldest first', () async {
    final service = RawLogImportService(
      parseFn: (vendor, product, model, data) async {
        final s = String.fromCharCodes(data);
        if (s.contains('P1')) return _dive(fingerprint: 'd1', day: 2);
        if (s.contains('P2')) return _dive(fingerprint: 'd2', day: 1);
        throw PlatformException(code: 'DATAFORMAT');
      },
    );

    final bytes = Uint8List.fromList([
      ..._record(' P1'),
      ..._record(' S1'),
      ..._record(' P2'),
      ..._record(' S2'),
    ]);
    final out = await service.parse(bytes);

    expect(out.dives.map((d) => d.fingerprint), ['d2', 'd1']);
    expect(
      out.dives.first.startTime.isBefore(out.dives.last.startTime),
      isTrue,
    );
  });

  test('a record that never parses is counted as failed, not fatal', () async {
    final service = RawLogImportService(
      parseFn: (_, _, _, _) async =>
          throw PlatformException(code: 'DATAFORMAT'),
    );
    final out = await service.parse(_record(' junk'));
    expect(out.dives, isEmpty);
    expect(out.divesFailed, 1);
    expect(out.warnings.any((w) => w.contains('none of its')), isTrue);
  });

  test('an implausible parse (no samples) is rejected', () async {
    final service = RawLogImportService(
      parseFn: (_, _, _, _) async => pigeon.ParsedDive(
        fingerprint: 'x',
        dateTimeYear: 2026,
        dateTimeMonth: 1,
        dateTimeDay: 1,
        dateTimeHour: 0,
        dateTimeMinute: 0,
        dateTimeSecond: 0,
        maxDepthMeters: 0,
        avgDepthMeters: 0,
        durationSeconds: 0,
        samples: const [],
        tanks: const [],
        gasMixes: const [],
        events: const [],
      ),
    );
    final out = await service.parse(_record(' looks-ok-parses-empty'));
    expect(out.dives, isEmpty);
    expect(out.divesFailed, 1);
  });

  test(
    'MissingPluginException propagates (parser unavailable != bad file)',
    () async {
      final service = RawLogImportService(
        parseFn: (_, _, _, _) async =>
            throw MissingPluginException('no channel'),
      );
      await expectLater(
        service.parse(_record(' profile')),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );
}
