import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_computer/data/services/raw_log_file.dart';

Uint8List _sbemRecord(String tail) =>
    Uint8List.fromList([...'SBEM0103'.codeUnits, ...tail.codeUnits]);

/// A real Suunto Nautic dive log, exactly as a Bluetooth download stores it:
/// the decompressed profile record followed by the `/Summary` record.
/// Shared with the native `test_parse_raw_dive` fixture.
final _nauticDiveFixture = File(
  'packages/libdivecomputer_plugin/test/native/fixtures/suunto_nautic_dive.bin',
);

void main() {
  const reader = RawLogFileReader();

  test('returns null for bytes with no SBEM0103 magic', () {
    expect(reader.read(Uint8List.fromList('not a dive log'.codeUnits)), isNull);
    expect(reader.read(Uint8List(0)), isNull);
  });

  test('a single profile record is one record, Suunto/Nautic/0', () {
    final file = reader.read(_sbemRecord(' profile bytes'))!;
    expect(file.container, RawLogContainer.suuntoNauticSbem);
    expect(file.vendor, 'Suunto');
    expect(file.product, 'Nautic');
    expect(file.model, 0);
    expect(file.records, hasLength(1));
    expect(file.leadingJunkBytes, 0);
  });

  test('profile + Summary split into two records at the magic boundary', () {
    final bytes = Uint8List.fromList([
      ..._sbemRecord(' PROFILE'),
      ..._sbemRecord(' SUMMARY'),
    ]);
    final file = reader.read(bytes)!;
    expect(file.records, hasLength(2));
    expect(String.fromCharCodes(file.records[0]), 'SBEM0103 PROFILE');
    expect(String.fromCharCodes(file.records[1]), 'SBEM0103 SUMMARY');
  });

  test('a multi-dive file splits into every record in file order', () {
    final bytes = Uint8List.fromList([
      ..._sbemRecord(' P1'),
      ..._sbemRecord(' S1'),
      ..._sbemRecord(' P2'),
      ..._sbemRecord(' S2'),
    ]);
    final file = reader.read(bytes)!;
    expect(file.records.map(String.fromCharCodes), [
      'SBEM0103 P1',
      'SBEM0103 S1',
      'SBEM0103 P2',
      'SBEM0103 S2',
    ]);
  });

  test('a capture wrapper before the first record is reported, not fatal', () {
    final bytes = Uint8List.fromList([
      ...'PKLG-ish header'.codeUnits,
      ..._sbemRecord(' profile'),
    ]);
    final file = reader.read(bytes)!;
    expect(file.leadingJunkBytes, 'PKLG-ish header'.length);
    expect(file.records, hasLength(1));
    expect(String.fromCharCodes(file.records.single), 'SBEM0103 profile');
  });

  test('looksSupported mirrors read', () {
    expect(reader.looksSupported(_sbemRecord(' x')), isTrue);
    expect(reader.looksSupported(Uint8List.fromList([1, 2, 3])), isFalse);
  });

  test('golden: a real Nautic download splits into profile + /Summary', () {
    final bytes = _nauticDiveFixture.readAsBytesSync();
    final file = reader.read(bytes)!;

    expect(file.container, RawLogContainer.suuntoNauticSbem);
    expect(file.vendor, 'Suunto');
    expect(file.product, 'Nautic');
    expect(file.leadingJunkBytes, 0);
    expect(file.records, hasLength(2));

    // Every record opens with the SBEM0103 magic, and rejoining them
    // reproduces the original blob byte-for-byte (what the parser expects).
    for (final record in file.records) {
      expect(record.sublist(0, 8), kSbemMagic);
    }
    expect(file.records[0].length + file.records[1].length, bytes.length);
    // The /Summary record is the short one; a Nautic profile dwarfs it.
    expect(file.records[1].length, lessThan(file.records[0].length));
  });
}
