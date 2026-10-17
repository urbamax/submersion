import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/database/database.dart';

/// Schema v291: `dives.pp_o2_working` and `dive_data_sources.pp_o2_working`,
/// the computer's configured working ppO2 ceiling in bar (Suunto Nautic
/// /Summary), stored per dive so the oxygen-toxicity and MOD calculations can
/// honour the watch instead of the app default.
void main() {
  /// A v290 database whose dive tables lack the column.
  NativeDatabase setupDb() => NativeDatabase.memory(
    setup: (rawDb) {
      rawDb.execute('PRAGMA user_version = 290');
      rawDb.execute('''
        CREATE TABLE dives (
          id TEXT PRIMARY KEY,
          gradient_factor_low INTEGER,
          gradient_factor_high INTEGER,
          deco_algorithm TEXT,
          deco_conservatism INTEGER
        )
      ''');
      rawDb.execute('''
        CREATE TABLE dive_data_sources (
          id TEXT PRIMARY KEY,
          dive_id TEXT NOT NULL,
          gradient_factor_low INTEGER,
          gradient_factor_high INTEGER,
          imported_at INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      rawDb.execute("INSERT INTO dives (id) VALUES ('d1')");
    },
  );

  test('v291 is in the ladder and did not raise the floor', () {
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(291));
    expect(AppDatabase.migrationVersions, contains(291));
    expect(AppDatabase.minimumCompatibleSchemaVersion, isNot(291));
  });

  test('upgrading from v290 adds pp_o2_working to both tables', () async {
    final db = AppDatabase(setupDb());
    addTearDown(db.close);

    for (final table in ['dives', 'dive_data_sources']) {
      final cols = await db.customSelect("PRAGMA table_info('$table')").get();
      final byName = {for (final c in cols) c.read<String>('name'): c};
      expect(byName.keys, contains('pp_o2_working'), reason: table);
      expect(byName['pp_o2_working']!.read<String>('type'), 'REAL');
    }
    // Existing rows get NULL: the calculation then falls back to the app
    // setting.
    final row = await db
        .customSelect("SELECT pp_o2_working FROM dives WHERE id = 'd1'")
        .getSingle();
    expect(row.readNullable<double>('pp_o2_working'), isNull);
  });

  test('a value written after the migration round-trips', () async {
    final db = AppDatabase(setupDb());
    addTearDown(db.close);

    await db.customStatement(
      "UPDATE dives SET pp_o2_working = 1.4 WHERE id = 'd1'",
    );
    final row = await db
        .customSelect("SELECT pp_o2_working FROM dives WHERE id = 'd1'")
        .getSingle();
    expect(row.read<double>('pp_o2_working'), 1.4);
  });

  test('a database already at 291 without the columns gains them in '
      'beforeOpen', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute('PRAGMA user_version = 291');
          rawDb.execute('CREATE TABLE dives (id TEXT PRIMARY KEY)');
          rawDb.execute(
            'CREATE TABLE dive_data_sources (id TEXT PRIMARY KEY, '
            'dive_id TEXT NOT NULL, imported_at INTEGER NOT NULL, '
            'created_at INTEGER NOT NULL)',
          );
        },
      ),
    );
    addTearDown(db.close);

    for (final table in ['dives', 'dive_data_sources']) {
      final cols = await db.customSelect("PRAGMA table_info('$table')").get();
      expect(
        cols.map((c) => c.read<String>('name')),
        contains('pp_o2_working'),
        reason: table,
      );
    }
  });
}
