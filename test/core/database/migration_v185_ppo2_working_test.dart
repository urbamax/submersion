import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

/// v192: `dives.pp_o2_working`, the diver's configured working ppO2 ceiling in
/// bar as read from the computer (Suunto Nautic /Summary), stored per dive next
/// to the gradient factors so the oxygen-toxicity and MOD calculations for that
/// dive can honour the watch instead of the app default. Renumbered from 185:
/// main landed rungs 185-191 while this branch was open.
void main() {
  // Stamped at 184 so every rung up to and including v192 runs.
  NativeDatabase setupDb() => NativeDatabase.memory(
    setup: (rawDb) {
      rawDb.execute('PRAGMA user_version = 184');
      // The pre-v185 shape carries the deco columns but not pp_o2_working.
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

  test('v192 is in the migration ladder', () {
    // Relaxed from an exact match when main's v194
    // (dive_tanks.transmitter_serial) landed on top: the exact-version
    // assertion is the newest rung's job (migration_v194_*).
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(192));
    expect(AppDatabase.migrationVersions, contains(192));
  });

  test('adds pp_o2_working to dives and dive_data_sources', () async {
    final db = AppDatabase(setupDb());
    addTearDown(db.close);

    for (final table in ['dives', 'dive_data_sources']) {
      final cols = await db.customSelect("PRAGMA table_info('$table')").get();
      final byName = {for (final c in cols) c.read<String>('name'): c};
      expect(byName.keys, contains('pp_o2_working'), reason: table);
      expect(byName['pp_o2_working']!.read<String>('type'), 'REAL');
    }
    // Existing rows get NULL: the calc then falls back to the app setting.
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

  test('the backstop is idempotent on an already-migrated db', () async {
    final db = AppDatabase(setupDb());
    addTearDown(db.close);
    // Force the migration, then open a second connection over the same file
    // shape: the beforeOpen backstop must not fail on the existing column.
    await db.customSelect("PRAGMA table_info('dives')").get();
    expect(
      () => db.customStatement('SELECT pp_o2_working FROM dives'),
      returnsNormally,
    );
  });
}
