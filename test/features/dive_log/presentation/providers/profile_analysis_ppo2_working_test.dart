import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/profile_analysis_provider.dart';
import 'package:submersion/features/divers/data/repositories/diver_repository.dart'
    as divers;
import 'package:submersion/features/divers/domain/entities/diver.dart'
    as domain;
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/settings/data/repositories/diver_settings_repository.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// The computer's own working ppO2 ceiling (Suunto Nautic /Summary), when the
/// dive carries one, drives that dive's oxygen-toxicity accounting instead of
/// the app's `ppO2MaxWorking` setting -- so its "time above the limit" matches
/// what the watch flagged.
late SharedPreferences _prefs;

class _FakeDiverRepository extends divers.DiverRepository {
  @override
  Future<domain.Diver?> getDiverById(String id) async => null;
  @override
  Future<domain.Diver?> getDefaultDiver() async => null;
  @override
  Future<String?> getActiveDiverIdFromSettings() async => null;
  @override
  Future<void> setActiveDiverIdInSettings(String? diverId) async {}
}

class _FakeDiverSettingsRepository extends DiverSettingsRepository {
  @override
  Future<AppSettings> getOrCreateSettingsForDiver(
    String diverId, {
    AppSettings? defaultSettings,
  }) async =>
      // Shipped defaults: ppO2MaxWorking 1.4 bar.
      const AppSettings(notificationsEnabled: false);

  @override
  Future<void> updateSettingsForDiver(
    String diverId,
    AppSettings settings,
  ) async {}
}

class _SettingsNotifier extends SettingsNotifier {
  _SettingsNotifier(Ref ref) : super(_FakeDiverSettingsRepository(), ref);
}

/// ~5 min at 60 m on air -> ppO2 ~1.47 bar, between the 1.4 default and a 1.6
/// watch ceiling.
List<DiveProfilePoint> _deepAirProfile() {
  final segments = <double>[0, 60, 60, 60, 60, 60, 60, 30, 0];
  return [
    for (var i = 0; i < segments.length; i++)
      DiveProfilePoint(timestamp: i * 60, depth: segments[i]),
  ];
}

Dive _dive({double? ppO2Working}) => Dive(
  id: 'nautic-ppo2',
  dateTime: DateTime.utc(2026, 1, 1),
  diveMode: DiveMode.oc,
  ppO2Working: ppO2Working,
  profile: _deepAirProfile(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        diverRepositoryProvider.overrideWithValue(_FakeDiverRepository()),
        settingsProvider.overrideWith((ref) => _SettingsNotifier(ref)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'with no dive ppO2 ceiling, the 1.4 default flags time above the limit',
    () {
      final analysis = container().read(diveProfileAnalysisProvider(_dive()));

      expect(analysis, isNotNull);
      expect(
        analysis!.o2Exposure.timeAboveWarning,
        greaterThan(0),
        reason: 'ppO2 ~1.47 sits above the 1.4 default',
      );
    },
  );

  test('the watch\'s 1.6 ceiling clears the same dive', () {
    final analysis = container().read(
      diveProfileAnalysisProvider(_dive(ppO2Working: 1.6)),
    );

    expect(analysis, isNotNull);
    expect(
      analysis!.o2Exposure.timeAboveWarning,
      0,
      reason: 'ppO2 ~1.47 is within the watch\'s 1.6 limit',
    );
  });
}
