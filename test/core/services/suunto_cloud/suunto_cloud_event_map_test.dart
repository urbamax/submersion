import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/suunto_cloud/suunto_cloud_event_map.dart';
import 'package:submersion/features/dive_computer/domain/services/suunto_nautic_event_labels.dart';

void main() {
  group('suuntoCloudEvent', () {
    test('maps a known event to a libdc type + native code', () {
      final e = suuntoCloudEvent('Alarm', 'Ascent Speed')!;
      expect(e.downloadedType, 'ascent');
      expect(e.nativeCode, (0x18 << 8) | 5);
    });

    test('the native code round-trips through suuntoNauticEventLabel', () {
      for (final entry in const [
        ('Alarm', 'Ascent Speed', 'Ascent rate alarm'),
        ('Alarm', 'Tank Pressure', 'Tank pressure alarm'),
        ('Warning', 'NoDecoTime', 'Low no-deco time'),
        ('State', 'Ndl exceeded', 'Decompression dive'),
        ('State', 'At Deco Stop', 'Deco stop reached'),
        ('State', 'At Safety Stop', 'Safety stop reached'),
        ('Notify', 'Gas Switch', 'Gas switch'),
        ('Ooam', 'Ceiling broken', 'Ceiling broken'),
      ]) {
        final mapped = suuntoCloudEvent(entry.$1, entry.$2);
        expect(mapped, isNotNull, reason: '${entry.$1}/${entry.$2}');
        expect(
          suuntoNauticEventLabel(mapped!.nativeCode),
          entry.$3,
          reason: '${entry.$1}/${entry.$2}',
        );
      }
    });

    test('returns null for an unmapped or deliberately-dropped event', () {
      expect(suuntoCloudEvent('Alarm', 'Battery'), isNull);
      expect(suuntoCloudEvent('State', 'Deco Stop Ahead'), isNull);
      expect(suuntoCloudEvent('Notify', 'Bearing set'), isNull);
      expect(suuntoCloudEvent('Nope', 'Ascent Speed'), isNull);
      expect(suuntoCloudEvent('Alarm', null), isNull);
    });
  });

  group('isSuuntoNauticFamily accepts the cloud display names', () {
    test('bare descriptor names', () {
      expect(isSuuntoNauticFamily('Suunto', 'Nautic'), isTrue);
      expect(isSuuntoNauticFamily('Suunto', 'Ocean'), isTrue);
    });

    test('Suunto Cloud resolved display names', () {
      expect(isSuuntoNauticFamily('Suunto', 'Suunto Nautic'), isTrue);
      expect(isSuuntoNauticFamily('Suunto', 'Suunto Nautic S'), isTrue);
      expect(isSuuntoNauticFamily('Suunto', 'Suunto Ocean'), isTrue);
    });

    test('still rejects other Suunto computers and other vendors', () {
      expect(isSuuntoNauticFamily('Suunto', 'EON Steel'), isFalse);
      expect(isSuuntoNauticFamily('Suunto', 'Suunto EON Steel'), isFalse);
      expect(isSuuntoNauticFamily('Shearwater', 'Nautic'), isFalse);
      expect(isSuuntoNauticFamily(null, null), isFalse);
    });
  });
}
