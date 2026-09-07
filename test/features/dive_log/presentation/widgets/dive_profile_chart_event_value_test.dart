import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/constants/map_style.dart';
import 'package:submersion/core/constants/units.dart';
import 'package:submersion/core/deco/ascent_rate_calculator.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/profile_event.dart';
import 'package:submersion/features/dive_log/presentation/widgets/dive_profile_chart.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

/// issue #1523 — an ascent-rate event marker shows the actual rate at that
/// moment in the diver's depth unit ("· 14.0 m/min"), like the Suunto app.

class _Settings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _Settings([super.s = const AppSettings()]);
  @override
  Future<void> setMapStyle(MapStyle style) async =>
      state = state.copyWith(mapStyle: style);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<DiveProfilePoint> _profile() => List.generate(
  61,
  (i) => DiveProfilePoint(timestamp: i * 20, depth: i < 30 ? 30.0 : 4.0),
);

List<AscentRatePoint> _rates() => List.generate(61, (i) {
  final t = i * 20;
  // 14 m/min ascent right around t=600
  final rate = (t >= 580 && t <= 620) ? 14.0 : 0.0;
  return AscentRatePoint(
    timestamp: t,
    depth: 20,
    rateMetersPerMin: rate,
    category: rate > 10 ? AscentRateCategory.danger : AscentRateCategory.safe,
  );
});

Widget _chart(AppSettings settings) => ProviderScope(
  overrides: [settingsProvider.overrideWith((ref) => _Settings(settings))],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 500,
        height: 320,
        child: DiveProfileChart(
          profile: _profile(),
          ascentRates: _rates(),
          events: [
            ProfileEvent(
              id: 'e1',
              diveId: 'd1',
              timestamp: 600,
              eventType: ProfileEventType.ascentRateWarning,
              severity: EventSeverity.warning,
              description: 'Ascent rate alarm',
              createdAt: DateTime(2026),
            ),
          ],
        ),
      ),
    ),
  ),
);

String _label(WidgetTester tester) {
  final line = tester
      .widget<LineChart>(find.byType(LineChart).first)
      .data
      .extraLinesData
      .verticalLines
      .firstWhere((l) => l.dashArray != null);
  return line.label.labelResolver(line);
}

void main() {
  testWidgets('metric ascent-rate marker appends the rate in m/min', (
    tester,
  ) async {
    await tester.pumpWidget(_chart(const AppSettings()));
    await tester.pumpAndSettle();
    expect(_label(tester), 'Ascent rate alarm · 14.0 m/min');
  });

  testWidgets('the rate follows the diver\'s depth unit (ft)', (tester) async {
    await tester.pumpWidget(
      _chart(const AppSettings(depthUnit: DepthUnit.feet)),
    );
    await tester.pumpAndSettle();
    // 14 m/min ≈ 45.9 ft/min
    expect(_label(tester), startsWith('Ascent rate alarm · 4'));
    expect(_label(tester), endsWith(' ft/min'));
  });
}
