import 'dart:typed_data';

import 'package:libdivecomputer_plugin/libdivecomputer_plugin.dart' as pigeon;

import 'package:submersion/features/dive_computer/data/services/raw_log_import_service.dart';
import 'package:submersion/features/dive_computer/domain/entities/downloaded_dive.dart';
import 'package:submersion/features/dive_computer/domain/services/suunto_nautic_event_labels.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    show GasMix;
import 'package:submersion/features/universal_import/data/models/import_enums.dart';
import 'package:submersion/features/universal_import/data/models/import_options.dart';
import 'package:submersion/features/universal_import/data/models/import_payload.dart';
import 'package:submersion/features/universal_import/data/models/import_warning.dart';
import 'package:submersion/features/universal_import/data/parsers/import_parser.dart';

/// Parses a raw Suunto "Vaasa" generation (Nautic / Ocean) dive-log file —
/// the `SBEM0103` records a Bluetooth download stores — inside the universal
/// import wizard.
///
/// Runs the same native libdivecomputer parse a live download runs
/// ([RawLogImportService] → `parsedDiveToDownloaded`), then flattens each
/// [DownloadedDive] into the map keys `UddfEntityImporter` already reads, so
/// profile, tanks, gas, deco model and GPS all persist with no Nautic-specific
/// code downstream. The watch's own event wording is carried as a labelled
/// bookmark; the three events with a clean equivalent (deco stop, safety
/// stop, ceiling) also get their typed marker.
class RawDiveComputerParser implements ImportParser {
  const RawDiveComputerParser({RawDiveParseFn? parseFn}) : _parseFn = parseFn;

  final RawDiveParseFn? _parseFn;

  @override
  List<ImportFormat> get supportedFormats => const [
    ImportFormat.suuntoNauticRaw,
  ];

  @override
  Future<ImportPayload> parse(
    Uint8List fileBytes, {
    ImportOptions? options,
  }) async {
    final service = RawLogImportService(
      parseFn: _parseFn ?? pigeon.DiveComputerHostApi().parseRawDiveData,
    );

    final RawLogImportOutcome outcome;
    try {
      outcome = await service.parse(fileBytes);
    } catch (e) {
      return ImportPayload(
        entities: const {},
        warnings: [
          ImportWarning(
            severity: ImportWarningSeverity.error,
            message:
                'This build cannot read dive-computer data '
                '(the native component is unavailable): $e',
          ),
        ],
      );
    }

    if (outcome.dives.isEmpty) {
      return ImportPayload(
        entities: const {},
        warnings: [
          ImportWarning(
            severity: ImportWarningSeverity.error,
            message: outcome.warnings.isNotEmpty
                ? outcome.warnings.first
                : 'No dives could be read from that file.',
          ),
        ],
      );
    }

    final diveMaps = outcome.dives.map(_diveToMap).toList();

    return ImportPayload(
      entities: {ImportEntityType.dives: diveMaps},
      warnings: [
        if (outcome.divesFailed > 0)
          ImportWarning(
            severity: ImportWarningSeverity.warning,
            entityType: ImportEntityType.dives,
            message:
                '${outcome.divesFailed} record group(s) in the file could '
                'not be read as a dive.',
          ),
      ],
      metadata: {'sourceApp': 'Suunto', 'diveCount': outcome.dives.length},
    );
  }

  Map<String, dynamic> _diveToMap(DownloadedDive dive) {
    final fingerprint = dive.fingerprint;
    final map = <String, dynamic>{
      'dateTime': dive.startTime,
      'maxDepth': dive.maxDepth,
      if (dive.avgDepth != null) 'avgDepth': dive.avgDepth,
      'runtime': Duration(seconds: dive.durationSeconds),
      if (dive.minTemperature != null) 'waterTemp': dive.minTemperature,
      if (dive.minTemperature != null) 'minTemperature': dive.minTemperature,
      if (dive.maxTemperature != null) 'maxTemperature': dive.maxTemperature,
      // Split the way the descriptor and the Bluetooth download path name it,
      // so a file import and a download register one computer, not two. The
      // .bin carries no serial (no /Info record), so it is deliberately left
      // null: attaching a wrong or truncated one is worse than none.
      'diveComputerManufacturer': 'Suunto',
      'diveComputerModel': 'Nautic',
      if (fingerprint != null && fingerprint.isNotEmpty) ...{
        'sourceId': fingerprint,
        'sourceUuid': fingerprint,
      },
      'diveMode': dive.diveMode.code,
    };

    if (dive.decoAlgorithm != null) map['decoAlgorithm'] = dive.decoAlgorithm;
    if (dive.gfLow != null) map['gradientFactorLow'] = dive.gfLow;
    if (dive.gfHigh != null) map['gradientFactorHigh'] = dive.gfHigh;
    if (dive.ppO2Working != null) map['ppO2Working'] = dive.ppO2Working;

    final entry = _validFix(dive.entryLatitude, dive.entryLongitude);
    if (entry != null) {
      map['latitude'] = entry.$1;
      map['longitude'] = entry.$2;
    }
    final exit = _validFix(dive.exitLatitude, dive.exitLongitude);
    if (exit != null) {
      map['exitLatitude'] = exit.$1;
      map['exitLongitude'] = exit.$2;
    }

    if (dive.tanks.isNotEmpty) {
      map['tanks'] = [
        for (final t in dive.tanks)
          <String, dynamic>{
            'order': t.index,
            if (t.startPressure != null) 'startPressure': t.startPressure,
            if (t.endPressure != null) 'endPressure': t.endPressure,
            if (t.volumeLiters != null) 'volume': t.volumeLiters,
            'gasMix': GasMix(o2: t.o2Percent, he: t.hePercent),
          },
      ];
    }

    if (dive.gasSwitches.isNotEmpty) {
      map['gasSwitches'] = [
        for (final s in dive.gasSwitches)
          <String, dynamic>{
            'timestamp': s.timeSeconds,
            'tankIndex': s.toTankIndex,
            'depth': s.depth,
          },
      ];
    }

    if (dive.profile.isNotEmpty) {
      map['profile'] = [for (final s in dive.profile) _sampleToMap(s)];
    }

    final events = _eventsToMaps(dive.events);
    if (events.isNotEmpty) map['events'] = events;

    return map;
  }

  Map<String, dynamic> _sampleToMap(ProfileSample s) {
    final point = <String, dynamic>{
      'timestamp': s.timeSeconds,
      'depth': s.depth,
    };
    if (s.temperature != null) point['temperature'] = s.temperature;
    if (s.heartRate != null) point['heartRate'] = s.heartRate;
    if (s.cns != null) point['cns'] = s.cns;
    if (s.ndl != null) point['ndl'] = s.ndl;
    if (s.tts != null) point['tts'] = s.tts;
    if (s.ceiling != null && s.ceiling! > 0) point['ceiling'] = s.ceiling;
    if (s.ppo2 != null) point['ppO2'] = s.ppo2;
    if (s.setpoint != null) point['setpoint'] = s.setpoint;

    final pressures = <Map<String, dynamic>>[
      if (s.tankPressures != null)
        for (var i = 0; i < s.tankPressures!.length; i++)
          if (s.tankPressures![i] != null)
            {'tankIndex': i, 'pressure': s.tankPressures![i]}
          else if (s.pressure != null)
            {'tankIndex': s.tankIndex ?? 0, 'pressure': s.pressure},
    ];
    if (pressures.isNotEmpty) point['allTankPressures'] = pressures;
    return point;
  }

  /// Every watch event becomes a bookmark carrying its exact Suunto wording,
  /// so nothing is lost or renamed. Deco / safety-stop / ceiling additionally
  /// get their typed marker, which renders better than a plain bookmark.
  List<Map<String, dynamic>> _eventsToMaps(List<DownloadedEvent> events) {
    final out = <Map<String, dynamic>>[];
    for (final e in events) {
      // The Nautic driver emits a bare SAMPLE_EVENT_GASCHANGE at t=0 just to
      // announce the starting gas (value 0, no Suunto sub-group code). Real
      // gas switches are carried by `gasSwitches`, so drop the event: a
      // "gaschange" marker on the first sample is noise, not a switch.
      if (e.type == 'gaschange' || e.type == 'gaschange2') continue;
      final label = suuntoNauticEventLabel(e.value) ?? e.type;
      switch (e.type) {
        case 'safetystop':
          out.add({'eventType': 'safetyStopStart', 'timestamp': e.timeSeconds});
        case 'deco':
          out.add({'eventType': 'decoStopStart', 'timestamp': e.timeSeconds});
        case 'ceiling':
          out.add({'eventType': 'decoViolation', 'timestamp': e.timeSeconds});
      }
      out.add({
        'eventType': 'bookmark',
        'timestamp': e.timeSeconds,
        'description': label,
      });
    }
    return out;
  }

  (double, double)? _validFix(double? lat, double? lon) {
    if (lat == null || lon == null) return null;
    if (lat == 0.0 && lon == 0.0) return null;
    if (lat == -1.0 && lon == -1.0) return null;
    return (lat, lon);
  }
}
