import 'dart:typed_data';

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:libdivecomputer_plugin/libdivecomputer_plugin.dart' as pigeon;

import 'package:submersion/features/dive_computer/data/services/parsed_dive_mapper.dart';
import 'package:submersion/features/dive_computer/data/services/raw_log_file.dart';
import 'package:submersion/features/dive_computer/domain/entities/downloaded_dive.dart';
import 'package:submersion/features/universal_import/data/services/raw_profile_sanity_check.dart';

/// The Pigeon signature `DiveComputerHostApi.parseRawDiveData` exposes, kept
/// injectable so the service is unit-testable without the platform channel.
typedef RawDiveParseFn =
    Future<pigeon.ParsedDive> Function(
      String vendor,
      String product,
      int model,
      Uint8List data,
    );

/// Outcome of importing a raw dive-computer log file.
class RawLogImportOutcome {
  const RawLogImportOutcome({
    required this.dives,
    required this.recordsRead,
    required this.divesFailed,
    this.warnings = const [],
  });

  /// The dives recovered from the file, oldest first, ready to hand to
  /// `DiveImportService.importDives` exactly like a Bluetooth download.
  final List<DownloadedDive> dives;

  /// How many `SBEM0103` records the file held.
  final int recordsRead;

  /// Record groups that a parse could not turn into a plausible dive.
  final int divesFailed;

  final List<String> warnings;

  bool get isEmpty => dives.isEmpty;
}

/// Turns a picked raw dive-computer log file into [DownloadedDive]s.
///
/// The file is identified and split by [RawLogFileReader]; this service
/// groups the records into dives and runs each group through the native
/// libdivecomputer parser, reusing [parsedDiveToDownloaded] so a file import
/// and a Bluetooth download produce byte-identical dive records (same events
/// with their exact Suunto labels, same tank/gas linkage, same fingerprint).
class RawLogImportService {
  RawLogImportService({
    required RawDiveParseFn parseFn,
    RawLogFileReader reader = const RawLogFileReader(),
    bool trimTankPressureAtSurfacing = true,
  }) : _parseFn = parseFn,
       _reader = reader,
       _trimAtSurfacing = trimTankPressureAtSurfacing;

  final RawDiveParseFn _parseFn;
  final RawLogFileReader _reader;
  final bool _trimAtSurfacing;

  /// The most records that make up one dive. A Suunto Nautic dive is a
  /// profile record optionally followed by its `/Summary` record.
  static const _maxRecordsPerDive = 2;

  /// Parse [bytes] into dives. Throws [MissingPluginException] or a
  /// `PlatformException(code: 'UNSUPPORTED')` straight through so the caller
  /// can tell "the parser is unavailable" from "this file did not parse".
  Future<RawLogImportOutcome> parse(Uint8List bytes) async {
    final file = _reader.read(bytes);
    if (file == null) {
      return const RawLogImportOutcome(
        dives: [],
        recordsRead: 0,
        divesFailed: 0,
        warnings: ['This file is not a recognised Suunto Nautic / Ocean log.'],
      );
    }

    final warnings = <String>[
      if (file.leadingJunkBytes > 0)
        '${file.leadingJunkBytes} byte(s) before the first record were skipped.',
    ];

    final dives = <DownloadedDive>[];
    var failed = 0;

    // Greedy longest-match over the record list: at each position try the
    // widest group first (profile + Summary), fall back to the profile
    // alone, and only give up on a record when neither parses.
    var i = 0;
    while (i < file.records.length) {
      pigeon.ParsedDive? parsed;
      var consumed = 0;

      final maxGroup = (file.records.length - i)
          .clamp(1, _maxRecordsPerDive)
          .toInt();
      for (var group = maxGroup; group >= 1; group--) {
        final blob = _join(file.records.sublist(i, i + group));
        final candidate = await _tryParse(file, blob);
        if (candidate != null && RawProfileSanityCheck.accepts(candidate)) {
          parsed = candidate;
          consumed = group;
          break;
        }
      }

      if (parsed == null) {
        failed++;
        i += 1;
        continue;
      }

      dives.add(
        parsedDiveToDownloaded(parsed, trimAtSurfacing: _trimAtSurfacing),
      );
      i += consumed;
    }

    if (dives.isEmpty && failed > 0) {
      warnings.add(
        'The file was recognised but none of its $failed record group(s) '
        'parsed as a dive.',
      );
    }

    dives.sort((a, b) => a.startTime.compareTo(b.startTime));

    return RawLogImportOutcome(
      dives: dives,
      recordsRead: file.records.length,
      divesFailed: failed,
      warnings: warnings,
    );
  }

  Future<pigeon.ParsedDive?> _tryParse(RawLogFile file, Uint8List blob) async {
    try {
      return await _parseFn(file.vendor, file.product, file.model, blob);
    } on MissingPluginException {
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED' || e.code == 'channel-error') rethrow;
      return null;
    }
  }

  static Uint8List _join(List<Uint8List> parts) {
    if (parts.length == 1) return parts.first;
    final total = parts.fold<int>(0, (sum, p) => sum + p.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final p in parts) {
      out.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return out;
  }
}
