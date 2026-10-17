import 'dart:typed_data';

/// A raw dive-computer log/dump file picked for import.
///
/// This is the offline counterpart of a Bluetooth download: instead of the
/// native layer streaming a dive's bytes off the watch, the diver hands us a
/// file that already holds them. The file is split into one blob per dive,
/// each of which is fed to `DiveComputerHostApi.parseRawDiveData` exactly as
/// the reparse path feeds a stored `rawData` blob.
///
/// Only the Suunto "Vaasa" generation (Nautic / Nautic S / Ocean) is
/// recognised today. Their logs are `SBEM0103` records: a decompressed
/// profile stream, optionally followed by the `/Summary` record (gradient
/// factors, gas mixes, ppO2 ceiling), which is the exact byte layout
/// libdivecomputer's `suunto_nautic` driver stores per dive. A classic
/// flat memory image from another computer is a separate container kind and
/// is not handled yet.
enum RawLogContainer {
  /// One or more Suunto Nautic/Ocean dive logs as decompressed `SBEM0103`
  /// records. Each dive is a profile record optionally followed by its
  /// `/Summary` record.
  suuntoNauticSbem,
}

/// The `SBEM0103` magic that opens every decompressed Suunto Nautic record
/// (profile and `/Summary` alike).
final Uint8List kSbemMagic = Uint8List.fromList('SBEM0103'.codeUnits);

/// Result of identifying and splitting a raw log file.
class RawLogFile {
  const RawLogFile({
    required this.container,
    required this.vendor,
    required this.product,
    required this.model,
    required this.records,
    this.leadingJunkBytes = 0,
  });

  /// Which on-disk layout this file is.
  final RawLogContainer container;

  /// libdivecomputer descriptor vendor for [records], e.g. `Suunto`.
  final String vendor;

  /// libdivecomputer descriptor product, e.g. `Nautic`. The Nautic and Ocean
  /// descriptors share one parser, so `Nautic` is passed for both and the
  /// exact unit is refined later from the parsed data / device info.
  final String product;

  /// libdivecomputer model number, or 0 to let the native layer resolve the
  /// descriptor by vendor + product name.
  final int model;

  /// The `SBEM0103` records in file order. A dive is one profile record,
  /// usually followed by its `/Summary` record; [RawLogImportService] decides
  /// how to group them.
  final List<Uint8List> records;

  /// Bytes skipped before the first recognised record (a capture wrapper,
  /// a stray header). Non-zero is worth surfacing as a warning.
  final int leadingJunkBytes;
}

/// Identifies a picked file and splits it into raw records, without touching
/// the native parser. Grouping records into dives and parsing them is
/// [RawLogImportService]'s job.
class RawLogFileReader {
  const RawLogFileReader();

  /// Returns the parsed structure of [bytes], or null when the file is not a
  /// recognised raw dive-computer log.
  RawLogFile? read(Uint8List bytes) {
    final firstMagic = _indexOf(bytes, kSbemMagic, 0);
    if (firstMagic < 0) return null;

    // Every SBEM0103 boundary starts a new record. The profile record's
    // header carries its own length, but splitting on the magic is enough:
    // rejoining consecutive records reproduces the original contiguous blob
    // the driver would have stored, and the parser stops at the profile
    // length regardless of what follows.
    final offsets = _allIndexesOf(bytes, kSbemMagic, firstMagic);
    final records = <Uint8List>[];
    for (var i = 0; i < offsets.length; i++) {
      final start = offsets[i];
      final end = i + 1 < offsets.length ? offsets[i + 1] : bytes.length;
      records.add(Uint8List.sublistView(bytes, start, end));
    }

    return RawLogFile(
      container: RawLogContainer.suuntoNauticSbem,
      vendor: 'Suunto',
      product: 'Nautic',
      model: 0,
      records: records,
      leadingJunkBytes: firstMagic,
    );
  }

  /// True when [bytes] looks like a raw dive-computer log we can import.
  bool looksSupported(Uint8List bytes) => read(bytes) != null;

  static int _indexOf(Uint8List haystack, Uint8List needle, int from) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    final last = haystack.length - needle.length;
    for (var i = from < 0 ? 0 : from; i <= last; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  static List<int> _allIndexesOf(
    Uint8List haystack,
    Uint8List needle,
    int from,
  ) {
    final out = <int>[];
    var i = _indexOf(haystack, needle, from);
    while (i >= 0) {
      out.add(i);
      i = _indexOf(haystack, needle, i + needle.length);
    }
    return out;
  }
}
