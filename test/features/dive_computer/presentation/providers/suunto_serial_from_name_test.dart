import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_computer/domain/entities/device_model.dart';
import 'package:submersion/features/dive_computer/presentation/providers/download_providers.dart';

DiscoveredDevice _device(String name) => DiscoveredDevice(
  id: 'id-1',
  name: name,
  connectionType: DeviceConnectionType.ble,
  address: 'AA:BB:CC:DD:EE:FF',
  discoveredAt: DateTime(2026, 9, 4),
);

void main() {
  group('suuntoSerialFromAdvertisedName', () {
    test('pulls the serial out of a Nautic advertised name', () {
      expect(
        suuntoSerialFromAdvertisedName(_device('Suunto Nautic 2604C3003306')),
        '2604C3003306',
      );
    });

    test('pulls the serial out of an Ocean advertised name', () {
      expect(
        suuntoSerialFromAdvertisedName(_device('Suunto Ocean 1234AB005678')),
        '1234AB005678',
      );
    });

    test('returns null when the device is null', () {
      expect(suuntoSerialFromAdvertisedName(null), isNull);
    });

    test('returns null for an unrelated Suunto BLE name', () {
      expect(
        suuntoSerialFromAdvertisedName(_device('Suunto EON Steel')),
        isNull,
      );
    });

    test('returns null when the name carries no serial', () {
      expect(suuntoSerialFromAdvertisedName(_device('Suunto Nautic')), isNull);
    });

    test('does not match another vendor that happens to end in digits', () {
      expect(
        suuntoSerialFromAdvertisedName(_device('Perdix 2 AI 330123')),
        isNull,
      );
    });
  });

  group('unpackSuuntoNauticFirmware', () {
    test('unpacks the packed int back to A.B.C for a Nautic', () {
      // 2.55.46 -> (2<<16)|(55<<8)|46 = 145198
      expect(
        unpackSuuntoNauticFirmware(
          _device('Suunto Nautic 2604C3003306'),
          '145198',
        ),
        '2.55.46',
      );
    });

    test('passes a non-numeric string through', () {
      expect(
        unpackSuuntoNauticFirmware(_device('Suunto Ocean 1234AB005678'), '3.1.0'),
        '3.1.0',
      );
    });

    test('leaves another vendor untouched', () {
      expect(
        unpackSuuntoNauticFirmware(_device('Perdix 2 AI 330123'), '92'),
        '92',
      );
    });

    test('null and out-of-range pass through', () {
      expect(
        unpackSuuntoNauticFirmware(_device('Suunto Nautic 2604C3003306'), null),
        isNull,
      );
      expect(
        unpackSuuntoNauticFirmware(
          _device('Suunto Nautic 2604C3003306'),
          '99999999',
        ),
        '99999999',
      );
    });
  });
}
