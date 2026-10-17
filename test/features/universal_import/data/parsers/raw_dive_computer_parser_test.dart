import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer_plugin/libdivecomputer_plugin.dart' as pigeon;
import 'package:submersion/features/universal_import/data/models/import_enums.dart';
import 'package:submersion/features/universal_import/data/parsers/raw_dive_computer_parser.dart';

Uint8List _record(String tail) =>
    Uint8List.fromList([...'SBEM0103'.codeUnits, ...tail.codeUnits]);

pigeon.ParsedDive _dive() => pigeon.ParsedDive(
  fingerprint: 'fp-1',
  dateTimeYear: 2026,
  dateTimeMonth: 8,
  dateTimeDay: 20,
  dateTimeHour: 8,
  dateTimeMinute: 23,
  dateTimeSecond: 0,
  maxDepthMeters: 20,
  avgDepthMeters: 11,
  durationSeconds: 3420,
  minTemperatureCelsius: 20.4,
  samples: [
    pigeon.ProfileSample(timeSeconds: 0, depthMeters: 0),
    pigeon.ProfileSample(
      timeSeconds: 60,
      depthMeters: 20,
      temperatureCelsius: 20.4,
    ),
    pigeon.ProfileSample(timeSeconds: 3420, depthMeters: 0),
  ],
  tanks: [
    pigeon.TankInfo(
      index: 0,
      gasMixIndex: 0,
      volumeLiters: 12,
      startPressureBar: 210,
      endPressureBar: 80,
    ),
  ],
  gasMixes: [pigeon.GasMix(index: 0, o2Percent: 21, hePercent: 0)],
  events: [
    // The driver's t=0 initial-gas marker — must be dropped.
    pigeon.DiveEvent(timeSeconds: 0, type: 'gaschange', data: {'value': '0'}),
    pigeon.DiveEvent(timeSeconds: 600, type: 'ascent', data: {'value': '6149'}),
    pigeon.DiveEvent(timeSeconds: 1200, type: 'safetystop'),
  ],
  decoAlgorithm: 'buhlmann',
  gfLow: 85,
  gfHigh: 85,
);

void main() {
  test('supportedFormats is suuntoNauticRaw', () {
    expect(const RawDiveComputerParser().supportedFormats, [
      ImportFormat.suuntoNauticRaw,
    ]);
  });

  test(
    'a Nautic .bin becomes a dives payload with profile/tanks/events',
    () async {
      final parser = RawDiveComputerParser(
        parseFn: (_, _, _, _) async => _dive(),
      );
      final payload = await parser.parse(
        Uint8List.fromList([..._record(' P'), ..._record(' S')]),
      );

      final dives = payload.entities[ImportEntityType.dives]!;
      expect(dives, hasLength(1));
      final d = dives.single;
      expect(d['maxDepth'], 20);
      expect(d['diveComputerManufacturer'], 'Suunto');
      expect(d['diveComputerModel'], 'Nautic');
      expect(d['diveComputerSerial'], isNull);
      expect(d['sourceId'], 'fp-1');
      expect(d['decoAlgorithm'], 'buhlmann');
      expect((d['tanks'] as List), hasLength(1));
      expect((d['profile'] as List).length, 3);

      final events = (d['events'] as List).cast<Map<String, dynamic>>();
      // The safety stop gets both a typed marker and a labelled bookmark.
      expect(
        events.where((e) => e['eventType'] == 'safetyStopStart'),
        hasLength(1),
      );
      expect(events.where((e) => e['eventType'] == 'bookmark'), isNotEmpty);
      // The t=0 gaschange marker is dropped.
      expect(
        events.where((e) => (e['description'] as String?) == 'gaschange'),
        isEmpty,
      );
      expect(events.any((e) => e['timestamp'] == 0), isFalse);
    },
  );

  test('an unrecognised file is a clean error payload', () async {
    final parser = RawDiveComputerParser(
      parseFn: (_, _, _, _) async => _dive(),
    );
    final payload = await parser.parse(
      Uint8List.fromList('not a dive log'.codeUnits),
    );
    expect(payload.entities, isEmpty);
    expect(payload.warnings, isNotEmpty);
  });

  test('a missing native parser is reported, not thrown', () async {
    final parser = RawDiveComputerParser(
      parseFn: (_, _, _, _) async => throw MissingPluginException('no channel'),
    );
    final payload = await parser.parse(_record(' profile'));
    expect(payload.entities, isEmpty);
    expect(payload.warnings.first.message, contains('native component'));
  });
}
