import 'package:submersion/core/constants/enums.dart';

/// One event reconstructed from a Suunto Nautic's own telemetry.
class SuuntoNauticDerivedEvent {
  const SuuntoNauticDerivedEvent({
    required this.timestampSeconds,
    required this.type,
    required this.description,
    this.value,
    this.depth,
  });

  final int timestampSeconds;
  final ProfileEventType type;

  /// The exact Suunto label, e.g. "Low no-deco time".
  final String description;

  /// Minutes remaining, for [ProfileEventType.lowNoDecoTime].
  final double? value;

  /// Depth in metres at the event.
  final double? depth;
}

/// Suunto Nautic default low-NDL warning threshold (the "Faible LND" the watch
/// raises), in seconds. Not carried in the dive data, so this is the factory
/// default.
const int kSuuntoNauticLowNdlThresholdSeconds = 5 * 60;

/// The Suunto Nautic shows two events that libdivecomputer's driver currently
/// drops (both map to `SAMPLE_EVENT_NONE`): "Faible LND" (low no-deco time)
/// and "Plongée avec décompression" (the dive became a decompression dive).
/// Reconstruct them from the watch's own per-sample NDL and ceiling, which the
/// driver DOES carry through (`DC_SAMPLE_DECO`). Each is emitted once, at its
/// first occurrence.
///
/// All lists are per-sample and index-aligned. [ndlSeconds] is null where the
/// computer reported no NDL; a value <= 0 means "in deco". [ceilings] is the
/// deco ceiling in metres (null or 0 when there is none).
List<SuuntoNauticDerivedEvent> deriveSuuntoNauticEvents({
  required List<int> timestamps,
  required List<double> depths,
  required List<int?> ndlSeconds,
  required List<double?> ceilings,
  int lowNdlThresholdSeconds = kSuuntoNauticLowNdlThresholdSeconds,
}) {
  final n = [
    timestamps.length,
    depths.length,
    ndlSeconds.length,
    ceilings.length,
  ].reduce((a, b) => a < b ? a : b);
  if (n == 0) return const [];

  final out = <SuuntoNauticDerivedEvent>[];
  var emittedLowNdl = false;
  var emittedDeco = false;

  for (var i = 0; i < n; i++) {
    final ndl = ndlSeconds[i];
    final ceiling = ceilings[i] ?? 0.0;
    final inDeco = ceiling > 0.0 || (ndl != null && ndl <= 0);

    if (!emittedDeco && inDeco) {
      emittedDeco = true;
      out.add(
        SuuntoNauticDerivedEvent(
          timestampSeconds: timestamps[i],
          type: ProfileEventType.decompressionDive,
          description: 'Decompression dive',
          depth: depths[i],
        ),
      );
    }

    if (!emittedLowNdl &&
        !inDeco &&
        ndl != null &&
        ndl > 0 &&
        ndl <= lowNdlThresholdSeconds) {
      emittedLowNdl = true;
      out.add(
        SuuntoNauticDerivedEvent(
          timestampSeconds: timestamps[i],
          type: ProfileEventType.lowNoDecoTime,
          description: 'Low no-deco time',
          value: (ndl / 60).roundToDouble(),
          depth: depths[i],
        ),
      );
    }

    if (emittedLowNdl && emittedDeco) break;
  }

  out.sort((a, b) => a.timestampSeconds.compareTo(b.timestampSeconds));
  return out;
}
