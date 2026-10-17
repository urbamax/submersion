import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_computer/domain/services/suunto_nautic_event_labels.dart';

int _code(int subGroup, int type) => (subGroup << 8) | type;

void main() {
  group('suuntoNauticEventLabel', () {
    test('decodes the reference dive 1787752091 events', () {
      // sub-groups: 0x18 Alarm, 0x19 Warning, 0x1A Notify, 0x1B State
      expect(suuntoNauticEventLabel(_code(0x1A, 11)), 'Gas switch');
      expect(suuntoNauticEventLabel(_code(0x19, 20)), 'Low no-deco time');
      expect(suuntoNauticEventLabel(_code(0x1B, 19)), 'Decompression dive');
      expect(suuntoNauticEventLabel(_code(0x18, 5)), 'Ascent rate alarm');
      expect(suuntoNauticEventLabel(_code(0x18, 3)), 'Tank pressure alarm');
      expect(suuntoNauticEventLabel(_code(0x1B, 35)), 'Deco stop reached');
      expect(suuntoNauticEventLabel(_code(0x1B, 37)), 'Safety stop reached');
    });

    test('distinguishes the two ppO2 alarms', () {
      expect(suuntoNauticEventLabel(_code(0x18, 1)), 'Low ppO2 alarm');
      expect(suuntoNauticEventLabel(_code(0x18, 2)), 'High ppO2 alarm');
      expect(suuntoNauticEventLabel(_code(0x19, 6)), 'High ppO2 warning');
    });

    test(
      'falls back to the sub-group name for an unknown alarm/warning type',
      () {
        expect(suuntoNauticEventLabel(_code(0x18, 99)), 'Alarm');
        expect(suuntoNauticEventLabel(_code(0x19, 99)), 'Warning');
      },
    );

    test('returns null for an unknown state/notify/ooam type', () {
      expect(suuntoNauticEventLabel(_code(0x1B, 99)), isNull);
      expect(suuntoNauticEventLabel(_code(0x1A, 99)), isNull);
      expect(suuntoNauticEventLabel(_code(0x1D, 99)), isNull);
    });

    test('returns null for a non-event-subgroup value', () {
      // a bare gas index (gas-switch event.value) or another computer's value
      expect(suuntoNauticEventLabel(0), isNull);
      expect(suuntoNauticEventLabel(2), isNull);
      expect(suuntoNauticEventLabel(null), isNull);
      expect(suuntoNauticEventLabel(-1), isNull);
    });

    test('ooam (end-of-dive reason) types', () {
      expect(suuntoNauticEventLabel(_code(0x1D, 2)), 'Ceiling broken');
      expect(suuntoNauticEventLabel(_code(0x1D, 4)), 'Max depth exceeded');
    });
  });

  group('isSuuntoNauticFamily', () {
    test('matches Suunto Nautic and Ocean only', () {
      expect(isSuuntoNauticFamily('Suunto', 'Nautic'), isTrue);
      expect(isSuuntoNauticFamily('Suunto', 'Ocean'), isTrue);
      expect(isSuuntoNauticFamily('Suunto', 'EON Steel'), isFalse);
      expect(isSuuntoNauticFamily('Shearwater', 'Nautic'), isFalse);
      expect(isSuuntoNauticFamily(null, null), isFalse);
    });
  });
}
